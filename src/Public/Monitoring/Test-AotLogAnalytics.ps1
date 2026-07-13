function Test-AotLogAnalytics {
    <#
    .SYNOPSIS
        Validates Log Analytics workspaces for health, retention and ingestion.

    .DESCRIPTION
        Flags workspaces whose retention is below a floor or that have received no
        recent heartbeat data (stale ingestion). Requires Az.OperationalInsights;
        the ingestion check additionally needs Az.OperationalInsights query rights.

    .PARAMETER MinRetentionDays
        Minimum acceptable retention. Workspaces below this are flagged.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Test-AotLogAnalytics -MinRetentionDays 90
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$MinRetentionDays = 30,
        [string[]]$SubscriptionId
    )

    if (-not (Get-Command Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue)) {
        throw 'Az.OperationalInsights is required for Test-AotLogAnalytics.'
    }

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'LogAnalytics' -Fetch {
        param($sub)
        foreach ($w in (Get-AzOperationalInsightsWorkspace)) {
            # Best-effort heartbeat freshness probe, done inside the sweep so it
            # parallelises with the rest; errors are carried, not thrown.
            $hb = $null; $hbError = $null
            try {
                $q = 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated)'
                $res = Invoke-AzOperationalInsightsQuery -WorkspaceId $w.CustomerId -Query $q -ErrorAction Stop
                $hb = $res.Results.LastHeartbeat
            }
            catch { $hbError = $_.Exception.Message }
            [pscustomobject]@{ Workspace = $w; LastHeartbeat = $hb; HeartbeatError = $hbError }
        }
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($item in $entry.Items) {
            $w = $item.Workspace
            if ($item.HeartbeatError) {
                Write-AotLog -Level Verbose -Operation 'LogAnalytics' `
                    -Message "Heartbeat query skipped for '$(Get-AotMember $w 'Name')': $($item.HeartbeatError)"
            }

            # Workspace shapes vary across Az.OperationalInsights versions.
            $retention = (Get-AotMember $w 'RetentionInDays') ?? (Get-AotMember $w 'retentionInDays')
            $provState = Get-AotMember $w 'ProvisioningState'

            $issues = @()
            if ($null -ne $retention -and $retention -lt $MinRetentionDays) { $issues += "RetentionBelow${MinRetentionDays}d" }
            if ($provState -and $provState -ne 'Succeeded') { $issues += "ProvisioningState:$provState" }

            $lastHeartbeat = $item.LastHeartbeat
            if ($lastHeartbeat -and ([datetime]$lastHeartbeat -lt (Get-Date).AddHours(-24))) {
                $issues += 'NoHeartbeat24h'
            }

            New-AotFinding -Category 'Monitoring' -Type 'LogAnalyticsWorkspace' `
                -Name (Get-AotMember $w 'Name') -ResourceId (Get-AotMember $w 'ResourceId') `
                -ResourceGroup (Get-AotMember $w 'ResourceGroupName') -Location (Get-AotMember $w 'Location') `
                -Severity ($issues ? 'Medium' : 'Informational') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    RetentionInDays = $retention
                    Sku             = (Get-AotMember $w 'Sku')
                    Issues          = $issues
                    LastHeartbeat   = $lastHeartbeat
                }
        }
    }
}

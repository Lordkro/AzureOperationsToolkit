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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'LogAnalytics' -Message "Workspaces for '$($sub.Name)'"

        $workspaces = Invoke-AotOperation -Operation "LogAnalytics:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzOperationalInsightsWorkspace
        }

        foreach ($w in $workspaces) {
            # Workspace shapes vary across Az.OperationalInsights versions.
            $retention = (Get-AotMember $w 'RetentionInDays') ?? (Get-AotMember $w 'retentionInDays')
            $provState = Get-AotMember $w 'ProvisioningState'

            $issues = @()
            if ($null -ne $retention -and $retention -lt $MinRetentionDays) { $issues += "RetentionBelow${MinRetentionDays}d" }
            if ($provState -and $provState -ne 'Succeeded') { $issues += "ProvisioningState:$provState" }

            # Best-effort heartbeat freshness check.
            $lastHeartbeat = $null
            try {
                $q = 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated)'
                $res = Invoke-AzOperationalInsightsQuery -WorkspaceId $w.CustomerId -Query $q -ErrorAction Stop
                $lastHeartbeat = $res.Results.LastHeartbeat
                if ($lastHeartbeat -and ([datetime]$lastHeartbeat -lt (Get-Date).AddHours(-24))) {
                    $issues += 'NoHeartbeat24h'
                }
            }
            catch {
                Write-AotLog -Level Verbose -Operation 'LogAnalytics' `
                    -Message "Heartbeat query skipped for '$($w.Name)': $($_.Exception.Message)"
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

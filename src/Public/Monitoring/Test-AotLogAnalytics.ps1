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

        $workspaces = Invoke-AotOperation -Operation "LogAnalytics:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzOperationalInsightsWorkspace
        }

        foreach ($w in $workspaces) {
            $issues = @()
            if ($w.RetentionInDays -lt $MinRetentionDays) { $issues += "RetentionBelow${MinRetentionDays}d" }
            if ($w.ProvisioningState -ne 'Succeeded')      { $issues += "ProvisioningState:$($w.ProvisioningState)" }

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
                -Name $w.Name -ResourceId $w.ResourceId `
                -ResourceGroup $w.ResourceGroupName -Location $w.Location `
                -Severity ($issues ? 'Medium' : 'Informational') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    RetentionInDays = $w.RetentionInDays
                    Sku             = $w.Sku
                    Issues          = $issues
                    LastHeartbeat   = $lastHeartbeat
                }
        }
    }
}

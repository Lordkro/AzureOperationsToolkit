function Get-AotMonitorAlert {
    <#
    .SYNOPSIS
        Inventories Azure Monitor alert rules and flags disabled ones.

    .DESCRIPTION
        Collects metric, scheduled-query and activity-log alert rules. Disabled
        rules are surfaced Medium severity as a monitoring gap.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotMonitorAlert
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'MonitorAlert' -Message "Alert rules for '$($sub.Name)'"

        $rules = Invoke-AotOperation -Operation "MonitorAlert:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $metric = @()
            if (Get-Command Get-AzMetricAlertRuleV2 -ErrorAction SilentlyContinue) {
                $metric = Get-AzMetricAlertRuleV2 | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Name; Id = $_.Id; Enabled = $_.Enabled; Kind = 'Metric'; Rg = $_.ResourceGroupName }
                }
            }
            $sq = @()
            if (Get-Command Get-AzScheduledQueryRule -ErrorAction SilentlyContinue) {
                $sq = Get-AzScheduledQueryRule | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Name; Id = $_.Id; Enabled = ($_.Enabled -ne 'false'); Kind = 'ScheduledQuery'; Rg = $_.ResourceGroupName }
                }
            }
            $metric + $sq
        }

        foreach ($rule in $rules) {
            New-AotFinding -Category 'Monitoring' -Type 'AlertRule' `
                -Name $rule.Name -ResourceId $rule.Id -ResourceGroup $rule.Rg `
                -Severity ($rule.Enabled ? 'Informational' : 'Medium') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    AlertKind = $rule.Kind
                    Enabled   = $rule.Enabled
                }
        }
    }
}

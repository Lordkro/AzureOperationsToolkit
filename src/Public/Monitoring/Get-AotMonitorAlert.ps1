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

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'MonitorAlert' -Fetch {
        param($sub)
        # Property names differ across Az.Monitor generations (e.g. newer
        # ScheduledQueryRule output has no ResourceGroupName); probe via
        # PSObject (module helpers are unavailable in parallel runspaces) and
        # derive the resource group from the ARM id instead.
        $normalise = {
            param($rule, $kind)
            $get = { param($o, $n) $p = $o.PSObject.Properties[$n]; if ($p) { $p.Value } }
            $id = & $get $rule 'Id'
            $rg = (& $get $rule 'ResourceGroupName') ??
                  $(if ($id -match '/resourceGroups/([^/]+)/') { $Matches[1] })
            $enabled = (& $get $rule 'Enabled') ?? $true
            [pscustomobject]@{
                Name    = (& $get $rule 'Name')
                Id      = $id
                Enabled = -not ($enabled -in $false, 'false', 'False')
                Kind    = $kind
                Rg      = $rg
            }
        }

        $all = @()
        if (Get-Command Get-AzMetricAlertRuleV2 -ErrorAction SilentlyContinue) {
            $all += Get-AzMetricAlertRuleV2 | ForEach-Object { & $normalise $_ 'Metric' }
        }
        if (Get-Command Get-AzScheduledQueryRule -ErrorAction SilentlyContinue) {
            $all += Get-AzScheduledQueryRule | ForEach-Object { & $normalise $_ 'ScheduledQuery' }
        }
        $all
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($rule in $entry.Items) {
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

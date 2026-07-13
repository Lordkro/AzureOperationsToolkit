function Get-AotDefenderStatus {
    <#
    .SYNOPSIS
        Reports Microsoft Defender for Cloud plan coverage per subscription.

    .DESCRIPTION
        Flags any Defender plan still on the Free tier as a gap. Requires
        Az.Security.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotDefenderStatus
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    if (-not (Get-Command Get-AzSecurityPricing -ErrorAction SilentlyContinue)) {
        throw 'Az.Security is required for Get-AotDefenderStatus.'
    }

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    # Fast path: one tenant-wide Resource Graph query instead of one ARM call
    # per subscription.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            $rows = Invoke-AotGraphQuery -Operation 'DefenderStatus:graph' -SubscriptionId @($subs.Id) -Query (
                "securityresources | where type == 'microsoft.security/pricings' " +
                '| project id, name, subscriptionId, pricingTier = tostring(properties.pricingTier), subPlan = tostring(properties.subPlan)'
            )
            foreach ($row in $rows) {
                $isGap = $row.pricingTier -eq 'Free'
                New-AotFinding -Category 'Security' -Type 'DefenderPlan' `
                    -Name $row.name -ResourceId $row.id `
                    -Severity ($isGap ? 'High' : 'Informational') `
                    -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        PricingTier = $row.pricingTier
                        IsGap       = $isGap
                        SubPlan     = $row.subPlan
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'DefenderStatus' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'DefenderStatus' -Fetch {
        param($sub)
        Get-AzSecurityPricing
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($p in $entry.Items) {
            $isGap = $p.PricingTier -eq 'Free'
            New-AotFinding -Category 'Security' -Type 'DefenderPlan' `
                -Name $p.Name -ResourceId $p.Id `
                -Severity ($isGap ? 'High' : 'Informational') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    PricingTier = $p.PricingTier
                    IsGap       = $isGap
                    SubPlan     = $p.SubPlan
                }
        }
    }
}

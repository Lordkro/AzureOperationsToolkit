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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'DefenderStatus' -Message "Defender plans for '$($sub.Name)'"

        $plans = Invoke-AotOperation -Operation "DefenderStatus:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzSecurityPricing
        }

        foreach ($p in $plans) {
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

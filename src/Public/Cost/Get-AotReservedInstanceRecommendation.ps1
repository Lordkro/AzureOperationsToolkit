function Get-AotReservedInstanceRecommendation {
    <#
    .SYNOPSIS
        Surfaces Azure Advisor reserved-instance (cost) recommendations.

    .DESCRIPTION
        Pulls Cost category recommendations from Azure Advisor, which include
        reservation purchase suggestions and their projected savings. Requires
        Az.Advisor.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotReservedInstanceRecommendation
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    if (-not (Get-Command Get-AzAdvisorRecommendation -ErrorAction SilentlyContinue)) {
        throw 'Az.Advisor is required for Get-AotReservedInstanceRecommendation.'
    }

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'RiRecommendation' -Message "Advisor cost recs for '$($sub.Name)'"

        $recs = Invoke-AotOperation -Operation "RiRecommendation:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzAdvisorRecommendation -Category Cost
        }

        foreach ($r in $recs) {
            $props = (Get-AotMember $r 'ExtendedProperty') ?? @{}
            $solution = Get-AotMember $r 'ShortDescriptionSolution'
            New-AotFinding -Category 'Cost' -Type 'ReservedInstanceRecommendation' `
                -Name ($solution ?? $r.Name) -ResourceId (Get-AotMember $r 'ResourceId') `
                -Severity 'Low' -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    Problem          = (Get-AotMember $r 'ShortDescriptionProblem')
                    Solution         = $solution
                    Impact           = (Get-AotMember $r 'Impact')
                    AnnualSavings    = $props['annualSavingsAmount']
                    SavingsCurrency  = $props['savingsCurrency']
                    Term             = $props['term']
                    LookbackPeriod   = $props['lookbackPeriod']
                }
        }
    }
}

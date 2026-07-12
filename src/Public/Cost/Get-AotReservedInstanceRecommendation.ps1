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

        $recs = Invoke-AotOperation -Operation "RiRecommendation:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $advisorCmd = Get-Command Get-AzAdvisorRecommendation
            if ($advisorCmd.Parameters.ContainsKey('Filter')) {
                # Az.Advisor 3.x (autorest): subscription-wide category filtering
                # is only available through -Filter; bare -Category resolves no
                # parameter set.
                Get-AzAdvisorRecommendation -Filter "Category eq 'Cost'"
            }
            else {
                # Az.Advisor 2.x
                Get-AzAdvisorRecommendation -Category Cost
            }
        }

        foreach ($r in $recs) {
            # ExtendedProperty is a hashtable in Az.Advisor 2.x and a typed
            # object in 3.x; read keys through whichever shape arrived.
            $props = (Get-AotMember $r 'ExtendedProperty') ?? @{}
            $readProp = {
                param($key)
                if ($props -is [System.Collections.IDictionary]) { $props[$key] }
                else { Get-AotMember $props $key }
            }

            $solution = Get-AotMember $r 'ShortDescriptionSolution'
            New-AotFinding -Category 'Cost' -Type 'ReservedInstanceRecommendation' `
                -Name ($solution ?? (Get-AotMember $r 'Name')) `
                -ResourceId ((Get-AotMember $r 'ResourceId') ?? (Get-AotMember $r 'Id')) `
                -Severity 'Low' -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    Problem          = (Get-AotMember $r 'ShortDescriptionProblem')
                    Solution         = $solution
                    Impact           = (Get-AotMember $r 'Impact')
                    AnnualSavings    = (& $readProp 'annualSavingsAmount')
                    SavingsCurrency  = (& $readProp 'savingsCurrency')
                    Term             = (& $readProp 'term')
                    LookbackPeriod   = (& $readProp 'lookbackPeriod')
                }
        }
    }
}

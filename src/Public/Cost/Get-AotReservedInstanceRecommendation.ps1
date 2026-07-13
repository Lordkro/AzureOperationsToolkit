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

    # Fast path: one tenant-wide Resource Graph query over Advisor resources.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            $rows = Invoke-AotGraphQuery -Operation 'RiRecommendation:graph' -SubscriptionId @($subs.Id) -Query (
                "advisorresources | where type == 'microsoft.advisor/recommendations' and properties.category == 'Cost' " +
                '| project id, subscriptionId, impact = tostring(properties.impact), ' +
                'problem = tostring(properties.shortDescription.problem), solution = tostring(properties.shortDescription.solution), ' +
                'extended = properties.extendedProperties'
            )
            foreach ($row in $rows) {
                $ext = Get-AotMember $row 'extended'
                New-AotFinding -Category 'Cost' -Type 'ReservedInstanceRecommendation' `
                    -Name ($row.solution ?? $row.id) -ResourceId $row.id `
                    -Severity 'Low' -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        Problem         = $row.problem
                        Solution        = $row.solution
                        Impact          = $row.impact
                        AnnualSavings   = (Get-AotMember $ext 'annualSavingsAmount')
                        SavingsCurrency = (Get-AotMember $ext 'savingsCurrency')
                        Term            = (Get-AotMember $ext 'term')
                        LookbackPeriod  = (Get-AotMember $ext 'lookbackPeriod')
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'RiRecommendation' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'RiRecommendation' -Fetch {
        param($sub)
        $advisorCmd = Get-Command Get-AzAdvisorRecommendation
        if ($advisorCmd.Parameters.ContainsKey('Filter')) {
            # Az.Advisor 3.x (autorest): subscription-wide category filtering
            # is only available through -Filter; bare -Category resolves no
            # parameter set.
            Get-AzAdvisorRecommendation -Filter "Category eq 'Cost'" -SubscriptionId $sub.Id
        }
        else {
            # Az.Advisor 2.x
            Get-AzAdvisorRecommendation -Category Cost
        }
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($r in $entry.Items) {
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

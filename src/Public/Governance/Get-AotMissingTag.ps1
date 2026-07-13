function Get-AotMissingTag {
    <#
    .SYNOPSIS
        Finds resources missing one or more required tags.

    .DESCRIPTION
        Checks every resource against a required tag-key list and reports the
        specific keys that are absent. Run parallel per resource for large estates.

    .PARAMETER RequiredTag
        Tag keys that must be present (e.g. Owner, CostCenter, Environment).

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotMissingTag -RequiredTag Owner, CostCenter, Environment
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredTag,

        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'MissingTag' -Fetch {
        param($sub)
        Get-AzResource
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($r in $entry.Items) {
            $present = Get-AotTagKey -Tags $r.Tags
            $missing = $RequiredTag | Where-Object { $_ -notin $present }
            if (-not $missing) { continue }

            New-AotFinding -Category 'Governance' -Type 'MissingTag' `
                -Name $r.Name -ResourceId $r.ResourceId `
                -ResourceGroup $r.ResourceGroupName -Location $r.Location -Severity 'Low' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ResourceType = $r.ResourceType
                    MissingTags  = @($missing)
                    PresentTags  = $present
                }
        }
    }
}

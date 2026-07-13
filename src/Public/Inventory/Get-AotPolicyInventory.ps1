function Get-AotPolicyInventory {
    <#
    .SYNOPSIS
        Inventories policy assignments across subscriptions.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotPolicyInventory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'PolicyInventory' -Fetch {
        param($sub)
        Get-AzPolicyAssignment
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($p in $entry.Items) {
            # Older Az nested details under .Properties; newer Az flattens them.
            $props = (Get-AotMember $p 'Properties') ?? $p
            New-AotFinding -Category 'Inventory' -Type 'PolicyAssignment' `
                -Name ((Get-AotMember $props 'DisplayName') ?? $p.Name) `
                -ResourceId (Get-AotMember $p 'ResourceId') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    PolicyDefinitionId = (Get-AotMember $props 'PolicyDefinitionId')
                    EnforcementMode    = (Get-AotMember $props 'EnforcementMode')
                    Scope              = (Get-AotMember $props 'Scope')
                    Description        = (Get-AotMember $props 'Description')
                }
        }
    }
}

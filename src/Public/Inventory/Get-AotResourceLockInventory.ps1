function Get-AotResourceLockInventory {
    <#
    .SYNOPSIS
        Inventories resource locks (CanNotDelete / ReadOnly) across subscriptions.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotResourceLockInventory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'LockInventory' -Fetch {
        param($sub)
        Get-AzResourceLock
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($l in $entry.Items) {
            New-AotFinding -Category 'Inventory' -Type 'ResourceLock' `
                -Name $l.Name -ResourceId $l.ResourceId `
                -ResourceGroup $l.ResourceGroupName `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    LockLevel = ((Get-AotMember $l.Properties 'level') ?? (Get-AotMember $l.Properties 'Level'))
                    Notes     = ((Get-AotMember $l.Properties 'notes') ?? (Get-AotMember $l.Properties 'Notes'))
                    LockedResource = $l.ResourceId
                }
        }
    }
}

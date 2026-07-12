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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'LockInventory' -Message "Resource locks for '$($sub.Name)'"

        $locks = Invoke-AotOperation -Operation "LockInventory:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzResourceLock
        }

        foreach ($l in $locks) {
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

function Get-AotUnattachedDisk {
    <#
    .SYNOPSIS
        Finds managed disks not attached to any VM (billed but unused).

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotUnattachedDisk | Sort-Object { $_.Detail.DiskSizeGB } -Descending
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'UnattachedDisk' -Message "Disks for '$($sub.Name)'"

        $disks = Invoke-AotOperation -Operation "UnattachedDisk:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' -and -not $_.ManagedBy }
        }

        foreach ($d in $disks) {
            New-AotFinding -Category 'Cost' -Type 'UnattachedDisk' `
                -Name $d.Name -ResourceId $d.Id `
                -ResourceGroup $d.ResourceGroupName -Location $d.Location -Severity 'Low' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    DiskSizeGB = $d.DiskSizeGB
                    Sku        = $d.Sku.Name
                    DiskState  = $d.DiskState
                    TimeCreated = $d.TimeCreated
                    Recommendation = 'Snapshot then delete if no longer required.'
                }
        }
    }
}

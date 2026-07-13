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

    # Fast path: one tenant-wide Resource Graph query over disks.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            $rows = Invoke-AotGraphQuery -Operation 'UnattachedDisk:graph' -SubscriptionId @($subs.Id) -Query (
                "resources | where type == 'microsoft.compute/disks' " +
                "| where tostring(properties.diskState) == 'Unattached' and isempty(tostring(managedBy)) " +
                '| project id, name, subscriptionId, resourceGroup, location, ' +
                'diskSizeGB = toint(properties.diskSizeGB), skuName = tostring(sku.name), timeCreated = tostring(properties.timeCreated)'
            )
            foreach ($row in $rows) {
                New-AotFinding -Category 'Cost' -Type 'UnattachedDisk' `
                    -Name $row.name -ResourceId $row.id `
                    -ResourceGroup $row.resourceGroup -Location $row.location -Severity 'Low' `
                    -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        DiskSizeGB     = $row.diskSizeGB
                        Sku            = $row.skuName
                        DiskState      = 'Unattached'
                        TimeCreated    = $row.timeCreated
                        Recommendation = 'Snapshot then delete if no longer required.'
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'UnattachedDisk' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'UnattachedDisk' -Fetch {
        param($sub)
        Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' -and -not $_.ManagedBy }
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($d in $entry.Items) {
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

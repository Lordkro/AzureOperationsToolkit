function Get-AotResourceGroupInventory {
    <#
    .SYNOPSIS
        Inventories resource groups and their resource counts.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotResourceGroupInventory -SubscriptionId $sub
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    # Fast path: resource containers + resource counts in one tenant-wide query.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            $rows = Invoke-AotGraphQuery -Operation 'RgInventory:graph' -SubscriptionId @($subs.Id) -Query (
                "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' " +
                '| project id, name, subscriptionId, location, tags, provisioningState = tostring(properties.provisioningState) ' +
                '| join kind=leftouter (resources | summarize resourceCount = count() by subscriptionId, resourceGroup) ' +
                'on subscriptionId, $left.name == $right.resourceGroup'
            )
            foreach ($row in $rows) {
                New-AotFinding -Category 'Inventory' -Type 'ResourceGroup' `
                    -Name $row.name -ResourceId $row.id `
                    -ResourceGroup $row.name -Location $row.location `
                    -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        ResourceCount     = ((Get-AotMember $row 'resourceCount') ?? 0)
                        ProvisioningState = $row.provisioningState
                        TagCount          = (Get-AotTagKey -Tags (Get-AotMember $row 'tags')).Count
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'RgInventory' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'RgInventory' -Fetch {
        param($sub)
        $groups    = Get-AzResourceGroup
        $resources = Get-AzResource
        [pscustomobject]@{ Groups = @($groups); Resources = @($resources) }
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        $data = $entry.Items | Select-Object -First 1
        if (-not $data) { continue }

        $countByRg = $data.Resources | Group-Object ResourceGroupName -AsHashTable -AsString

        foreach ($rg in $data.Groups) {
            $count = if ($countByRg -and $countByRg.ContainsKey($rg.ResourceGroupName)) {
                @($countByRg[$rg.ResourceGroupName]).Count
            } else { 0 }

            New-AotFinding -Category 'Inventory' -Type 'ResourceGroup' `
                -Name $rg.ResourceGroupName -ResourceId $rg.ResourceId `
                -ResourceGroup $rg.ResourceGroupName -Location $rg.Location `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ResourceCount = $count
                    ProvisioningState = $rg.ProvisioningState
                    TagCount = (Get-AotTagKey -Tags $rg.Tags).Count
                }
        }
    }
}

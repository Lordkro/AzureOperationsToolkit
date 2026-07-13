function Get-AotIdlePublicIp {
    <#
    .SYNOPSIS
        Finds public IP addresses not associated with any resource.

    .DESCRIPTION
        Standard-SKU static IPs bill even when unassociated. Any public IP with no
        IpConfiguration is reported; static Standard IPs are flagged higher.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotIdlePublicIp
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    # Fast path: one tenant-wide Resource Graph query over public IPs.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            $rows = Invoke-AotGraphQuery -Operation 'IdlePublicIp:graph' -SubscriptionId @($subs.Id) -Query (
                "resources | where type == 'microsoft.network/publicipaddresses' " +
                '| where isnull(properties.ipConfiguration) and isnull(properties.natGateway) ' +
                '| project id, name, subscriptionId, resourceGroup, location, skuName = tostring(sku.name), ' +
                'allocationMethod = tostring(properties.publicIPAllocationMethod), ipAddress = tostring(properties.ipAddress)'
            )
            foreach ($row in $rows) {
                $billable = $row.skuName -eq 'Standard' -and $row.allocationMethod -eq 'Static'
                New-AotFinding -Category 'Cost' -Type 'IdlePublicIp' `
                    -Name $row.name -ResourceId $row.id `
                    -ResourceGroup $row.resourceGroup -Location $row.location `
                    -Severity ($billable ? 'Low' : 'Informational') `
                    -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        Sku              = $row.skuName
                        AllocationMethod = $row.allocationMethod
                        IpAddress        = $row.ipAddress
                        Billable         = $billable
                        Recommendation   = 'Delete if not reserved for imminent use.'
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'IdlePublicIp' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'IdlePublicIp' -Fetch {
        param($sub)
        Get-AzPublicIpAddress | Where-Object { -not $_.IpConfiguration -and -not $_.NatGateway }
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($ip in $entry.Items) {
            $billable = $ip.Sku.Name -eq 'Standard' -and $ip.PublicIpAllocationMethod -eq 'Static'
            New-AotFinding -Category 'Cost' -Type 'IdlePublicIp' `
                -Name $ip.Name -ResourceId $ip.Id `
                -ResourceGroup $ip.ResourceGroupName -Location $ip.Location `
                -Severity ($billable ? 'Low' : 'Informational') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    Sku              = $ip.Sku.Name
                    AllocationMethod = $ip.PublicIpAllocationMethod
                    IpAddress        = $ip.IpAddress
                    Billable         = $billable
                    Recommendation   = 'Delete if not reserved for imminent use.'
                }
        }
    }
}

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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'IdlePublicIp' -Message "Public IPs for '$($sub.Name)'"

        $ips = Invoke-AotOperation -Operation "IdlePublicIp:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzPublicIpAddress | Where-Object { -not $_.IpConfiguration -and -not $_.NatGateway }
        }

        foreach ($ip in $ips) {
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

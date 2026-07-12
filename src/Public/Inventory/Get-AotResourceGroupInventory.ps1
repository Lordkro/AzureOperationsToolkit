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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'RgInventory' -Message "Resource groups for '$($sub.Name)'"

        $data = Invoke-AotOperation -Operation "RgInventory:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $groups    = Get-AzResourceGroup
            $resources = Get-AzResource
            [pscustomobject]@{ Groups = $groups; Resources = $resources }
        }

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
                    TagCount = @($rg.Tags.Keys).Count
                }
        }
    }
}

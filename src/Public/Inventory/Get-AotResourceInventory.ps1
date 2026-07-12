function Get-AotResourceInventory {
    <#
    .SYNOPSIS
        Inventories all Azure resources across the requested subscriptions.

    .DESCRIPTION
        Uses Azure Resource Graph when available (fast, paged) and falls back to
        Get-AzResource per subscription. Emits normalised Aot.Finding objects.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotResourceInventory | Export-AotCsvReport -Path .\resources.csv
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    begin {
        $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId
        $useGraph = $null -ne (Get-Command Search-AzGraph -ErrorAction SilentlyContinue)
    }

    process {
        foreach ($sub in $subs) {
            Write-AotLog -Level Information -Operation 'ResourceInventory' `
                -Message "Collecting resources for '$($sub.Name)'"

            $resources = Invoke-AotOperation -Operation "ResourceInventory:$($sub.Id)" -SkipOnError -ScriptBlock {
                if ($useGraph) {
                    $query = 'Resources | project id, name, type, location, resourceGroup, tags, sku, kind'
                    $result = Search-AzGraph -Query $query -Subscription $sub.Id -First 1000
                    # Depending on Az.ResourceGraph version the rows come back
                    # directly or wrapped in a response object with a Data property.
                    if ($result -and $result.PSObject.Properties['Data']) { $result.Data } else { $result }
                }
                else {
                    Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
                    Get-AzResource
                }
            }

            foreach ($r in $resources) {
                # Az (Get-AzResource) and Resource Graph return differently-named
                # and sometimes-absent properties; probe everything safely under
                # StrictMode.
                $tagKeys = Get-AotTagKey -Tags (Get-AotMember $r 'Tags')

                New-AotFinding -Category 'Inventory' -Type 'Resource' `
                    -Name (Get-AotMember $r 'Name') `
                    -ResourceId ((Get-AotMember $r 'ResourceId') ?? (Get-AotMember $r 'Id')) `
                    -ResourceGroup ((Get-AotMember $r 'ResourceGroupName') ?? (Get-AotMember $r 'ResourceGroup')) `
                    -Location (Get-AotMember $r 'Location') `
                    -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                    -Detail @{
                        ResourceType = ((Get-AotMember $r 'ResourceType') ?? (Get-AotMember $r 'Type'))
                        Sku          = (Get-AotMember $r 'Sku')
                        Kind         = (Get-AotMember $r 'Kind')
                        TagCount     = $tagKeys.Count
                    }
            }
        }
    }
}

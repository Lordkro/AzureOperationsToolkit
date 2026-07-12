function Get-AotEmptyResourceGroup {
    <#
    .SYNOPSIS
        Finds resource groups that contain no resources.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotEmptyResourceGroup
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'EmptyRg' -Message "Empty resource groups for '$($sub.Name)'"

        $data = Invoke-AotOperation -Operation "EmptyRg:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $groups    = Get-AzResourceGroup
            $resources = Get-AzResource
            [pscustomobject]@{ Groups = $groups; Resources = $resources }
        }

        $nonEmpty = $data.Resources | Group-Object ResourceGroupName -AsHashTable -AsString

        foreach ($rg in $data.Groups) {
            if ($nonEmpty -and $nonEmpty.ContainsKey($rg.ResourceGroupName)) { continue }

            New-AotFinding -Category 'Cost' -Type 'EmptyResourceGroup' `
                -Name $rg.ResourceGroupName -ResourceId $rg.ResourceId `
                -ResourceGroup $rg.ResourceGroupName -Location $rg.Location -Severity 'Informational' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ProvisioningState = $rg.ProvisioningState
                    TagCount = @($rg.Tags.Keys).Count
                    Recommendation = 'Delete if not a placeholder for pending deployment.'
                }
        }
    }
}

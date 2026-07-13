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

    # Fast path: resource groups with no resources, one tenant-wide query.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            # ARG does not support the leftanti join flavor; emulate it with
            # leftouter + isnull.
            $rows = Invoke-AotGraphQuery -Operation 'EmptyRg:graph' -SubscriptionId @($subs.Id) -Query (
                "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' " +
                '| project id, name, subscriptionId, location, tags, provisioningState = tostring(properties.provisioningState) ' +
                '| join kind=leftouter (resources | summarize n = count() by subscriptionId, resourceGroup) ' +
                'on subscriptionId, $left.name == $right.resourceGroup ' +
                '| where isnull(n) | project-away n, subscriptionId1, resourceGroup'
            )
            foreach ($row in $rows) {
                New-AotFinding -Category 'Cost' -Type 'EmptyResourceGroup' `
                    -Name $row.name -ResourceId $row.id `
                    -ResourceGroup $row.name -Location $row.location -Severity 'Informational' `
                    -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        ProvisioningState = $row.provisioningState
                        TagCount          = (Get-AotTagKey -Tags (Get-AotMember $row 'tags')).Count
                        Recommendation    = 'Delete if not a placeholder for pending deployment.'
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'EmptyRg' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'EmptyRg' -Fetch {
        param($sub)
        $groups    = Get-AzResourceGroup
        $resources = Get-AzResource
        [pscustomobject]@{ Groups = @($groups); Resources = @($resources) }
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        $data = $entry.Items | Select-Object -First 1
        if (-not $data) { continue }

        $nonEmpty = $data.Resources | Group-Object ResourceGroupName -AsHashTable -AsString

        foreach ($rg in $data.Groups) {
            if ($nonEmpty -and $nonEmpty.ContainsKey($rg.ResourceGroupName)) { continue }

            New-AotFinding -Category 'Cost' -Type 'EmptyResourceGroup' `
                -Name $rg.ResourceGroupName -ResourceId $rg.ResourceId `
                -ResourceGroup $rg.ResourceGroupName -Location $rg.Location -Severity 'Informational' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ProvisioningState = $rg.ProvisioningState
                    TagCount = (Get-AotTagKey -Tags $rg.Tags).Count
                    Recommendation = 'Delete if not a placeholder for pending deployment.'
                }
        }
    }
}

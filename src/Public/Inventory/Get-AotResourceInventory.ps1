function Get-AotResourceInventory {
    <#
    .SYNOPSIS
        Inventories all Azure resources across the requested subscriptions.

    .DESCRIPTION
        Uses Azure Resource Graph when available: one batched, paged query for
        every subscription at once — the fastest possible sweep on large
        tenants. Falls back to a parallel per-subscription Get-AzResource sweep
        when Az.ResourceGraph is not installed. Emits normalised Aot.Finding
        objects either way.

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

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId
    $useGraph = $null -ne (Get-Command Search-AzGraph -ErrorAction SilentlyContinue)

    $emit = {
        param($r, $subId, $subName)
        $tagKeys = Get-AotTagKey -Tags (Get-AotMember $r 'Tags')
        New-AotFinding -Category 'Inventory' -Type 'Resource' `
            -Name (Get-AotMember $r 'Name') `
            -ResourceId ((Get-AotMember $r 'ResourceId') ?? (Get-AotMember $r 'Id')) `
            -ResourceGroup ((Get-AotMember $r 'ResourceGroupName') ?? (Get-AotMember $r 'ResourceGroup')) `
            -Location (Get-AotMember $r 'Location') `
            -SubscriptionId $subId -SubscriptionName $subName `
            -Detail @{
                ResourceType = ((Get-AotMember $r 'ResourceType') ?? (Get-AotMember $r 'Type'))
                Sku          = (Get-AotMember $r 'Sku')
                Kind         = (Get-AotMember $r 'Kind')
                TagCount     = $tagKeys.Count
            }
    }

    if ($useGraph) {
        # One tenant-wide query, paged with SkipToken — no per-subscription
        # round trips at all.
        $subIds = @($subs.Id)
        $subName = @{}
        foreach ($s in $subs) { $subName[$s.Id] = $s.Name }

        Write-AotLog -Level Information -Operation 'ResourceInventory' `
            -Message "Batched Resource Graph query across $($subIds.Count) subscription(s)"

        try {
            $rows = Invoke-AotGraphQuery -Operation 'ResourceInventory:graph' -SubscriptionId $subIds -Query (
                'resources | project id, name, type, location, resourceGroup, tags, sku, kind, subscriptionId'
            )
            foreach ($r in $rows) {
                $subId = Get-AotMember $r 'SubscriptionId'
                & $emit $r $subId ($subName[[string]$subId])
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'ResourceInventory' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    # Fallback: parallel per-subscription sweep with Get-AzResource.
    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'ResourceInventory' -Fetch {
        param($sub)
        Get-AzResource
    }

    foreach ($entry in $sweep) {
        foreach ($r in $entry.Items) {
            & $emit $r $entry.Subscription.Id $entry.Subscription.Name
        }
    }
}

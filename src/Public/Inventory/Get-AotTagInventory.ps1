function Get-AotTagInventory {
    <#
    .SYNOPSIS
        Aggregates tag usage (keys and values) across subscriptions.

    .DESCRIPTION
        Summarises how many resources carry each tag key and the distinct values
        seen, useful for spotting inconsistent or free-text tagging.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotTagInventory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'TagInventory' -Fetch {
        param($sub)
        Get-AzResource
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription

        $tally = @{}   # key -> @{ Count = int; Values = hashset }
        foreach ($r in $entry.Items) {
            if (-not $r.Tags) { continue }
            foreach ($key in $r.Tags.Keys) {
                if (-not $tally.ContainsKey($key)) {
                    $tally[$key] = @{ Count = 0; Values = [System.Collections.Generic.HashSet[string]]::new() }
                }
                $tally[$key].Count++
                [void]$tally[$key].Values.Add([string]$r.Tags[$key])
            }
        }

        foreach ($key in $tally.Keys) {
            New-AotFinding -Category 'Inventory' -Type 'TagKey' `
                -Name $key -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ResourceCount    = $tally[$key].Count
                    DistinctValues   = $tally[$key].Values.Count
                    SampleValues     = @($tally[$key].Values) | Select-Object -First 10
                }
        }
    }
}

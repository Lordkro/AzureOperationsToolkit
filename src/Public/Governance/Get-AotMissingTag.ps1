function Get-AotMissingTag {
    <#
    .SYNOPSIS
        Finds resources missing one or more required tags.

    .DESCRIPTION
        Checks every resource against a required tag-key list and reports the
        specific keys that are absent. Run parallel per resource for large estates.

    .PARAMETER RequiredTag
        Tag keys that must be present (e.g. Owner, CostCenter, Environment).

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotMissingTag -RequiredTag Owner, CostCenter, Environment
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredTag,

        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'MissingTag' -Message "Tag compliance for '$($sub.Name)'"

        $resources = Invoke-AotOperation -Operation "MissingTag:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzResource
        }

        foreach ($r in $resources) {
            $present = Get-AotTagKey -Tags $r.Tags
            $missing = $RequiredTag | Where-Object { $_ -notin $present }
            if (-not $missing) { continue }

            New-AotFinding -Category 'Governance' -Type 'MissingTag' `
                -Name $r.Name -ResourceId $r.ResourceId `
                -ResourceGroup $r.ResourceGroupName -Location $r.Location -Severity 'Low' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ResourceType = $r.ResourceType
                    MissingTags  = @($missing)
                    PresentTags  = $present
                }
        }
    }
}

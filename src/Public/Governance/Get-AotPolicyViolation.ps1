function Get-AotPolicyViolation {
    <#
    .SYNOPSIS
        Reports non-compliant resources from Azure Policy state.

    .DESCRIPTION
        Reads the latest policy compliance state and emits one finding per
        non-compliant resource/policy pair. Requires Az.PolicyInsights.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotPolicyViolation
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    if (-not (Get-Command Get-AzPolicyState -ErrorAction SilentlyContinue)) {
        throw 'Az.PolicyInsights is required for Get-AotPolicyViolation.'
    }

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    # Fast path: one tenant-wide Resource Graph query over policy states.
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        $subName = @{}; foreach ($s in $subs) { $subName[$s.Id] = $s.Name }
        try {
            $rows = Invoke-AotGraphQuery -Operation 'PolicyViolation:graph' -SubscriptionId @($subs.Id) -Query (
                "policyresources | where type == 'microsoft.policyinsights/policystates' and properties.complianceState == 'NonCompliant' " +
                '| project resourceId = tostring(properties.resourceId), subscriptionId, ' +
                'resourceGroup = tostring(properties.resourceGroup), location = tostring(properties.resourceLocation), ' +
                'resourceType = tostring(properties.resourceType), policyDefinitionName = tostring(properties.policyDefinitionName), ' +
                'policyAssignmentName = tostring(properties.policyAssignmentName)'
            )
            foreach ($row in $rows) {
                New-AotFinding -Category 'Governance' -Type 'PolicyViolation' `
                    -Name ($row.resourceId.Split('/')[-1]) -ResourceId $row.resourceId `
                    -ResourceGroup $row.resourceGroup -Location $row.location -Severity 'Medium' `
                    -SubscriptionId $row.subscriptionId -SubscriptionName $subName[[string]$row.subscriptionId] `
                    -Detail @{
                        PolicyDefinitionName = $row.policyDefinitionName
                        PolicyAssignmentName = $row.policyAssignmentName
                        ComplianceState      = 'NonCompliant'
                        ResourceType         = $row.resourceType
                    }
            }
            return
        }
        catch {
            Write-AotLog -Level Warning -Operation 'PolicyViolation' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'PolicyViolation' -Fetch {
        param($sub)
        Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'"
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($s in $entry.Items) {
            New-AotFinding -Category 'Governance' -Type 'PolicyViolation' `
                -Name $s.ResourceId.Split('/')[-1] -ResourceId $s.ResourceId `
                -ResourceGroup $s.ResourceGroup -Location $s.ResourceLocation -Severity 'Medium' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    PolicyDefinitionName   = $s.PolicyDefinitionName
                    PolicyAssignmentName   = $s.PolicyAssignmentName
                    ComplianceState        = $s.ComplianceState
                    ResourceType           = $s.ResourceType
                }
        }
    }
}

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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'PolicyViolation' -Message "Policy compliance for '$($sub.Name)'"

        $states = Invoke-AotOperation -Operation "PolicyViolation:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'"
        }

        foreach ($s in $states) {
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

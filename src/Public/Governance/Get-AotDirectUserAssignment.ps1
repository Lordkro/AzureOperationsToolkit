function Get-AotDirectUserAssignment {
    <#
    .SYNOPSIS
        Flags RBAC assignments granted directly to users rather than groups.

    .DESCRIPTION
        Direct user grants are hard to audit and off-board. Best practice is to
        assign roles to Entra groups. Every User-principal assignment is returned.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotDirectUserAssignment
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'DirectUserAssignment' -Message "Direct user grants for '$($sub.Name)'"

        $assignments = Invoke-AotOperation -Operation "DirectUserAssignment:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzRoleAssignment | Where-Object { $_.ObjectType -eq 'User' }
        }

        foreach ($a in $assignments) {
            $name = if ([string]::IsNullOrWhiteSpace($a.DisplayName)) { $a.SignInName ?? $a.ObjectId } else { $a.DisplayName }
            New-AotFinding -Category 'Governance' -Type 'DirectUserAssignment' `
                -Name $name -ResourceId $a.RoleAssignmentId -Severity 'Low' `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    RoleDefinitionName = $a.RoleDefinitionName
                    SignInName         = $a.SignInName
                    PrincipalId        = $a.ObjectId
                    Scope              = $a.Scope
                    Recommendation     = 'Assign the role to an Entra group instead of the user.'
                }
        }
    }
}

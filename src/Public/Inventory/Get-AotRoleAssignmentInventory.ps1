function Get-AotRoleAssignmentInventory {
    <#
    .SYNOPSIS
        Inventories RBAC role assignments across subscriptions.

    .DESCRIPTION
        Captures principal type, role definition and scope for every assignment,
        the raw material for governance checks (owners, direct user grants).

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotRoleAssignmentInventory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'RbacInventory' -Message "Role assignments for '$($sub.Name)'"

        $assignments = Invoke-AotOperation -Operation "RbacInventory:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzRoleAssignment
        }

        foreach ($a in $assignments) {
            New-AotFinding -Category 'Inventory' -Type 'RoleAssignment' `
                -Name $a.DisplayName -ResourceId $a.RoleAssignmentId `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    RoleDefinitionName = $a.RoleDefinitionName
                    PrincipalType      = $a.ObjectType
                    PrincipalId        = $a.ObjectId
                    SignInName         = $a.SignInName
                    Scope              = $a.Scope
                    CanDelegate        = $a.CanDelegate
                }
        }
    }
}

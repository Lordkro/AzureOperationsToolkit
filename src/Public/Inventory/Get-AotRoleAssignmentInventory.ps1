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

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'RbacInventory' -Fetch {
        param($sub)
        Get-AzRoleAssignment
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($a in $entry.Items) {
            # Deleted principals have an empty DisplayName; fall back to object id.
            $name = if ([string]::IsNullOrWhiteSpace($a.DisplayName)) { $a.ObjectId } else { $a.DisplayName }
            New-AotFinding -Category 'Inventory' -Type 'RoleAssignment' `
                -Name $name -ResourceId $a.RoleAssignmentId `
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

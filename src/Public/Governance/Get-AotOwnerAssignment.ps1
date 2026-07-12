function Get-AotOwnerAssignment {
    <#
    .SYNOPSIS
        Finds all Owner role assignments (a common privilege-sprawl signal).

    .DESCRIPTION
        Owners at subscription or resource-group scope are flagged High severity;
        broader tenant/management-group owners are surfaced too when in scope.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotOwnerAssignment
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'OwnerAssignment' -Message "Owner assignments for '$($sub.Name)'"

        $owners = Invoke-AotOperation -Operation "OwnerAssignment:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzRoleAssignment -RoleDefinitionName 'Owner'
        }

        foreach ($o in $owners) {
            $severity = if ($o.Scope -match '^/subscriptions/[^/]+$') { 'High' } else { 'Medium' }
            # Deleted principals have an empty DisplayName; fall back to object id.
            $name = if ([string]::IsNullOrWhiteSpace($o.DisplayName)) { $o.ObjectId } else { $o.DisplayName }
            New-AotFinding -Category 'Governance' -Type 'OwnerAssignment' `
                -Name $name -ResourceId $o.RoleAssignmentId -Severity $severity `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    PrincipalType = $o.ObjectType
                    PrincipalId   = $o.ObjectId
                    SignInName    = $o.SignInName
                    Scope         = $o.Scope
                }
        }
    }
}

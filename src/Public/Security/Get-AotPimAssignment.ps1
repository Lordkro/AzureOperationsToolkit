function Get-AotPimAssignment {
    <#
    .SYNOPSIS
        Lists PIM (Privileged Identity Management) eligible and active role assignments.

    .DESCRIPTION
        Uses Microsoft Graph identity governance endpoints to enumerate Entra
        directory-role eligibility and active schedules. Requires
        Microsoft.Graph with RoleManagement.Read.Directory.

    .PARAMETER State
        Which assignments to return: Eligible, Active or Both (default).

    .EXAMPLE
        Get-AotPimAssignment -State Eligible
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Eligible', 'Active', 'Both')]
        [string]$State = 'Both'
    )

    if (-not (Get-Command Get-MgRoleManagementDirectoryRoleEligibilitySchedule -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Identity.Governance is required for Get-AotPimAssignment. Run: Test-AotDependency -InstallMissing'
    }
    Assert-AotGraphConnection -RequiredScopes 'RoleManagement.Read.Directory'

    $roleDefs = Invoke-AotOperation -Operation 'PimRoleDefs' -ScriptBlock {
        Get-MgRoleManagementDirectoryRoleDefinition -All
    }
    $roleName = @{}
    foreach ($rd in $roleDefs) { $roleName[$rd.Id] = $rd.DisplayName }

    $emit = {
        param($item, $kind)
        $rid = $item.RoleDefinitionId
        New-AotFinding -Category 'Security' -Type "Pim$kind" `
            -Name ($roleName[$rid] ?? $rid) -ResourceId $item.Id -Severity 'Informational' `
            -Detail @{
                AssignmentState = $kind
                PrincipalId     = $item.PrincipalId
                RoleDefinition  = $roleName[$rid] ?? $rid
                StartDateTime   = $item.ScheduleInfo.StartDateTime
                EndDateTime     = $item.ScheduleInfo.Expiration.EndDateTime
                MemberType      = $item.MemberType
            }
    }

    if ($State -in 'Eligible', 'Both') {
        $eligible = Invoke-AotOperation -Operation 'PimEligible' -ScriptBlock {
            Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All
        }
        foreach ($e in $eligible) { & $emit $e 'Eligible' }
    }

    if ($State -in 'Active', 'Both') {
        $active = Invoke-AotOperation -Operation 'PimActive' -ScriptBlock {
            Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All
        }
        foreach ($a in $active) { & $emit $a 'Active' }
    }
}

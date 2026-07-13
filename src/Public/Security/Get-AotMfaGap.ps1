function Get-AotMfaGap {
    <#
    .SYNOPSIS
        Finds enabled member users without a registered strong MFA method.

    .DESCRIPTION
        Reads Graph credential-registration details and flags enabled member
        accounts where MFA is not registered/capable. Requires Microsoft.Graph
        with UserAuthenticationMethod.Read.All / Reports.Read.All.

    .PARAMETER IncludeGuests
        Also evaluate guest accounts (excluded by default).

    .EXAMPLE
        Get-AotMfaGap
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$IncludeGuests
    )

    if (-not (Get-Command Get-MgReportAuthenticationMethodUserRegistrationDetail -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Reports is required for Get-AotMfaGap. Run: Test-AotDependency -InstallMissing'
    }
    Assert-AotGraphConnection -RequiredScopes 'UserAuthenticationMethod.Read.All', 'AuditLog.Read.All'

    Write-AotLog -Level Information -Operation 'MfaGap' -Message 'Evaluating MFA registration'

    $details = Invoke-AotOperation -Operation 'MfaGap' -ScriptBlock {
        try {
            Get-MgReportAuthenticationMethodUserRegistrationDetail -All
        }
        catch {
            # The reports endpoints are gated behind directory roles, not just scopes.
            if ($_.Exception.Message -match 'Authentication_RequestFromUnsupportedUserRole|not in the allowed roles') {
                throw ('Reading authentication-method registration reports requires an Entra directory role ' +
                       'on the signed-in account: Global Reader, Reports Reader, Security Reader or Security ' +
                       'Administrator (the UserAuthenticationMethod.Read.All scope alone is not enough). ' +
                       'Assign one of those roles, reconnect with Connect-MgGraph, and retry.')
            }
            throw
        }
    }

    foreach ($d in $details) {
        if (-not $IncludeGuests -and $d.UserType -ne 'member') { continue }
        if ($d.IsMfaRegistered) { continue }

        New-AotFinding -Category 'Security' -Type 'MfaGap' `
            -Name $d.UserDisplayName -ResourceId $d.Id -Severity 'High' `
            -Detail @{
                UserPrincipalName    = $d.UserPrincipalName
                UserType             = $d.UserType
                IsMfaRegistered      = $d.IsMfaRegistered
                IsMfaCapable         = $d.IsMfaCapable
                MethodsRegistered    = $d.MethodsRegistered
                IsSsprRegistered     = $d.IsSsprRegistered
            }
    }
}

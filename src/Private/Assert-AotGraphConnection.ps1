function Assert-AotGraphConnection {
    <#
    .SYNOPSIS
        Throws a actionable error when Microsoft Graph is not connected.

    .DESCRIPTION
        Graph-based collectors fail with opaque auth errors when Connect-MgGraph
        has not been run; this converts that into a one-line instruction naming
        the scopes the toolkit needs.
    #>
    [CmdletBinding()]
    param(
        [string[]]$RequiredScopes = @()
    )

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Authentication is required. Run: Test-AotDependency -InstallMissing'
    }

    $ctx = Get-MgContext
    if (-not $ctx) {
        $scopes = if ($RequiredScopes) { " -Scopes '$($RequiredScopes -join "', '")'" } else { '' }
        throw "Not connected to Microsoft Graph. Run: Connect-MgGraph$scopes"
    }

    if ($RequiredScopes) {
        $granted = @($ctx.Scopes)
        $missing = $RequiredScopes | Where-Object { $_ -notin $granted }
        if ($missing) {
            Write-AotLog -Level Warning -Operation 'Graph' -Message (
                "Graph session may lack scope(s): $($missing -join ', '). " +
                'Reconnect with Connect-MgGraph -Scopes ... if calls fail.'
            )
        }
    }
}

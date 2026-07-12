function Connect-AotAzure {
    <#
    .SYNOPSIS
        Establishes an Azure session for the toolkit.

    .DESCRIPTION
        Thin wrapper over Connect-AzAccount that supports interactive, service
        principal and managed identity sign-in, and reuses an existing context
        when one is already present unless -Force is given.

    .PARAMETER TenantId
        Entra tenant to authenticate against.

    .PARAMETER SubscriptionId
        Optional default subscription to select after sign-in.

    .PARAMETER Identity
        Use a managed identity (e.g. in a runner or Azure VM).

    .PARAMETER ServicePrincipalCredential
        PSCredential where UserName is the app (client) id and Password the secret.

    .EXAMPLE
        Connect-AotAzure -Identity

    .EXAMPLE
        Connect-AotAzure -TenantId $tid -ServicePrincipalCredential $cred
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [string]$TenantId,
        [string]$SubscriptionId,

        [Parameter(ParameterSetName = 'Identity')]
        [switch]$Identity,

        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
        [pscredential]$ServicePrincipalCredential,

        [switch]$Force
    )

    # Silence Az "upcoming breaking change" banners for this process; they add
    # hundreds of lines of noise to an assessment sweep. Best-effort only.
    try {
        if (Get-Command Update-AzConfig -ErrorAction SilentlyContinue) {
            Update-AzConfig -DisplayBreakingChangeWarning $false -Scope Process -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-AotLog -Level Verbose -Operation 'Connect' -Message "Could not disable breaking-change banners: $($_.Exception.Message)"
    }

    if ((Get-AzContext) -and -not $Force) {
        Write-AotLog -Level Information -Operation 'Connect' -Message 'Reusing existing Azure context.'
    }
    else {
        Invoke-AotOperation -Operation 'Connect-AzAccount' -ScriptBlock {
            $params = @{ ErrorAction = 'Stop' }
            if ($TenantId) { $params.TenantId = $TenantId }

            switch ($PSCmdlet.ParameterSetName) {
                'Identity'         { $params.Identity = $true }
                'ServicePrincipal' { $params.ServicePrincipal = $true; $params.Credential = $ServicePrincipalCredential }
            }
            Connect-AzAccount @params | Out-Null
        }
        Write-AotLog -Level Information -Operation 'Connect' -Message 'Azure sign-in complete.'
        $script:AotSubscriptionCache.Clear()
    }

    if ($SubscriptionId) {
        Invoke-AotOperation -Operation 'Select subscription' -ScriptBlock {
            Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        }
    }

    Get-AzContext
}

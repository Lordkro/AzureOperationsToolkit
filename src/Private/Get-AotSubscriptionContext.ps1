function Get-AotSubscriptionContext {
    <#
    .SYNOPSIS
        Builds (and caches) one Azure context object per subscription.

    .DESCRIPTION
        Parallel sweeps cannot call Set-AzContext inside runspaces — the default
        context is process-wide and racy. Instead this resolves a context object
        per subscription once (cached for the session) so runspaces can pass it
        via -DefaultProfile. Subscriptions whose context cannot be resolved
        (e.g. AuthorizationFailed) are logged and omitted from the returned map.

    .OUTPUTS
        hashtable: subscription id -> PSAzureContext
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Subscription
    )

    $map = @{}
    $original = Get-AzContext

    foreach ($sub in $Subscription) {
        if ($script:AotContextCache.ContainsKey($sub.Id)) {
            $map[$sub.Id] = $script:AotContextCache[$sub.Id]
            continue
        }
        try {
            $ctx = Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop
            $script:AotContextCache[$sub.Id] = $ctx
            $map[$sub.Id] = $ctx
        }
        catch {
            Write-AotLog -Level Warning -Operation 'ContextMap' `
                -Message "No context for subscription '$($sub.Name)': $($_.Exception.Message)"
        }
    }

    # Building the map moved the process default; put it back.
    if ($original) {
        try { Set-AzContext -Context $original -ErrorAction Stop | Out-Null }
        catch {
            Write-AotLog -Level Verbose -Operation 'ContextMap' `
                -Message "Could not restore original context: $($_.Exception.Message)"
        }
    }

    $map
}

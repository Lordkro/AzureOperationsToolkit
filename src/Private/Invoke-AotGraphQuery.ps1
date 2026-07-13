function Invoke-AotGraphQuery {
    <#
    .SYNOPSIS
        Runs a paged Azure Resource Graph query across subscriptions.

    .DESCRIPTION
        One tenant-scoped (or subscription-filtered) query replaces dozens of
        per-subscription ARM calls — the fast path for large tenants. Handles
        SkipToken paging and both Az.ResourceGraph result shapes (bare rows or
        a .Data-wrapped response). Throws on failure so callers can fall back
        to a per-subscription sweep.

    .PARAMETER Query
        The KQL query.

    .PARAMETER SubscriptionId
        Restrict to specific subscriptions; omitted = tenant scope.

    .PARAMETER Operation
        Name used in log lines.

    .OUTPUTS
        Query rows (psobject[]).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [string[]]$SubscriptionId,

        [string]$Operation = 'GraphQuery'
    )

    Invoke-AotOperation -Operation $Operation -ScriptBlock {
        $skip = $null
        do {
            $params = @{ Query = $Query; First = 1000 }
            if ($SubscriptionId) { $params.Subscription = $SubscriptionId }
            else { $params.UseTenantScope = $true }
            if ($skip) { $params.SkipToken = $skip }

            $page = Search-AzGraph @params
            $data = if ($page -and $page.PSObject.Properties['Data']) { $page.Data } else { $page }
            if ($data) { $data }

            $skipProp = if ($page) { $page.PSObject.Properties['SkipToken'] }
            $skip = if ($skipProp) { $skipProp.Value } else { $null }
        } while ($skip)
    }
}

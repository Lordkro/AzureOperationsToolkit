function Get-AotSubscriptionScope {
    <#
    .SYNOPSIS
        Resolves the set of subscriptions a collection function should run against.

    .DESCRIPTION
        If -SubscriptionId is supplied, those are validated and returned. Otherwise
        every enabled subscription in the current context is returned. Centralising
        this keeps every public function's multi-subscription behaviour consistent.

    .OUTPUTS
        Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription[]
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubscriptionId,

        [switch]$Force   # bypass the module-scoped cache
    )

    Invoke-AotOperation -Operation 'Resolve subscription scope' -ScriptBlock {
        $context = Get-AzContext
        if (-not $context) {
            throw 'No Azure context. Call Connect-AotAzure first.'
        }

        if ($SubscriptionId) {
            $subs = foreach ($id in $SubscriptionId) {
                Get-AzSubscription -SubscriptionId $id -ErrorAction Stop
            }
        }
        else {
            # Every collector resolves scope; cache the tenant sweep so a full
            # New-AotReport run hits Get-AzSubscription once, not 20+ times
            # (which invites ARM throttling). Probe context members safely —
            # minimal/mocked contexts may not carry Tenant/Account objects.
            $tenantId  = Get-AotMember (Get-AotMember $context 'Tenant')  'Id' -Default 'unknown-tenant'
            $accountId = Get-AotMember (Get-AotMember $context 'Account') 'Id' -Default 'unknown-account'
            $cacheKey  = "$tenantId|$accountId"
            if (-not $Force -and $script:AotSubscriptionCache.ContainsKey($cacheKey)) {
                return $script:AotSubscriptionCache[$cacheKey]
            }

            $subs = Get-AzSubscription -ErrorAction Stop |
                Where-Object { $_.State -eq 'Enabled' }

            if ($subs) { $script:AotSubscriptionCache[$cacheKey] = $subs }
        }

        if (-not $subs) {
            $who = Get-AotMember (Get-AotMember $context 'Account') 'Id' -Default 'current account'
            throw ('No subscriptions resolved for the requested scope. Verify ' +
                   "'$who' has reader access, or pass -SubscriptionId explicitly.")
        }
        $subs
    }
}

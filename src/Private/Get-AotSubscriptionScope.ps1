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
        [string[]]$SubscriptionId
    )

    Invoke-AotOperation -Operation 'Resolve subscription scope' -ScriptBlock {
        if (-not (Get-AzContext)) {
            throw 'No Azure context. Call Connect-AotAzure first.'
        }

        if ($SubscriptionId) {
            $subs = foreach ($id in $SubscriptionId) {
                $sub = Get-AzSubscription -SubscriptionId $id -ErrorAction Stop
                $sub
            }
        }
        else {
            $subs = Get-AzSubscription -ErrorAction Stop |
                Where-Object { $_.State -eq 'Enabled' }
        }

        if (-not $subs) { throw 'No subscriptions resolved for the requested scope.' }
        $subs
    }
}

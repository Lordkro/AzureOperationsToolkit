function Get-AotActionGroup {
    <#
    .SYNOPSIS
        Inventories Azure Monitor action groups and flags empty/disabled ones.

    .DESCRIPTION
        An action group with no receivers, or one that is disabled, means alerts
        route nowhere. Both conditions are surfaced as findings.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotActionGroup
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$SubscriptionId
    )

    if (-not (Get-Command Get-AzActionGroup -ErrorAction SilentlyContinue)) {
        throw 'Az.Monitor is required for Get-AotActionGroup.'
    }

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId

    $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'ActionGroup' -Fetch {
        param($sub)
        Get-AzActionGroup
    }

    foreach ($entry in $sweep) {
        $sub = $entry.Subscription
        foreach ($g in $entry.Items) {
            # Receiver property names vary across Az.Monitor generations
            # (singular vs plural); probe both shapes safely.
            $receiverProps = @(
                'EmailReceiver', 'SmsReceiver', 'WebhookReceiver', 'AzureAppPushReceiver',
                'VoiceReceiver', 'ArmRoleReceiver', 'LogicAppReceiver',
                'AzureFunctionReceiver', 'EventHubReceiver',
                'EmailReceivers', 'SmsReceivers', 'WebhookReceivers', 'AzureAppPushReceivers',
                'VoiceReceivers', 'ArmRoleReceivers', 'LogicAppReceivers',
                'AzureFunctionReceivers', 'EventHubReceivers'
            )
            $receiverCount = @(
                foreach ($p in $receiverProps) { Get-AotMember $g $p }
            ).Where({ $_ }).Count

            $problems = @()
            if ($receiverCount -eq 0) { $problems += 'NoReceivers' }
            if ((Get-AotMember $g 'Enabled' -Default $true) -eq $false) { $problems += 'Disabled' }

            $agId = (Get-AotMember $g 'Id') ?? (Get-AotMember $g 'ResourceId')
            $agRg = (Get-AotMember $g 'ResourceGroupName') ??
                    $(if ($agId -match '/resourceGroups/([^/]+)/') { $Matches[1] })

            New-AotFinding -Category 'Monitoring' -Type 'ActionGroup' `
                -Name (Get-AotMember $g 'Name') -ResourceId $agId `
                -ResourceGroup $agRg -Location (Get-AotMember $g 'Location') `
                -Severity ($problems ? 'Medium' : 'Informational') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    Enabled       = (Get-AotMember $g 'Enabled' -Default $true)
                    GroupShortName = (Get-AotMember $g 'GroupShortName')
                    ReceiverCount = $receiverCount
                    Problems      = $problems
                }
        }
    }
}

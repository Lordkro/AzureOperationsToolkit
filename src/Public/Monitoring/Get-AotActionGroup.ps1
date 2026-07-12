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

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'ActionGroup' -Message "Action groups for '$($sub.Name)'"

        $groups = Invoke-AotOperation -Operation "ActionGroup:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzActionGroup
        }

        foreach ($g in $groups) {
            $receiverCount = @(
                $g.EmailReceiver; $g.SmsReceiver; $g.WebhookReceiver;
                $g.AzureAppPushReceiver; $g.VoiceReceiver; $g.ArmRoleReceiver;
                $g.LogicAppReceiver; $g.AzureFunctionReceiver; $g.EventHubReceiver
            ).Where({ $_ }).Count

            $problems = @()
            if ($receiverCount -eq 0) { $problems += 'NoReceivers' }
            if ($g.Enabled -eq $false) { $problems += 'Disabled' }

            New-AotFinding -Category 'Monitoring' -Type 'ActionGroup' `
                -Name $g.Name -ResourceId $g.Id `
                -ResourceGroup $g.ResourceGroupName -Location $g.Location `
                -Severity ($problems ? 'Medium' : 'Informational') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    Enabled       = $g.Enabled
                    GroupShortName = $g.GroupShortName
                    ReceiverCount = $receiverCount
                    Problems      = $problems
                }
        }
    }
}

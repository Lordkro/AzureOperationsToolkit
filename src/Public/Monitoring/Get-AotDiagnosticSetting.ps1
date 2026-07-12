function Get-AotDiagnosticSetting {
    <#
    .SYNOPSIS
        Reports diagnostic-setting coverage for resources, flagging gaps.

    .DESCRIPTION
        For every resource (optionally filtered by type) it checks whether any
        diagnostic setting exists. Lookups run in parallel because each resource
        query is independent. Resources with no setting are High severity.

    .PARAMETER ResourceType
        Optional resource-type filter (e.g. 'Microsoft.KeyVault/vaults').

    .PARAMETER OnlyGaps
        Return only resources missing diagnostic settings.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotDiagnosticSetting -OnlyGaps
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ResourceType,
        [switch]$OnlyGaps,
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId
    $throttle = $script:AotConfig.ThrottleLimit

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'DiagnosticSetting' -Message "Diagnostic coverage for '$($sub.Name)'"

        $resources = Invoke-AotOperation -Operation "DiagnosticSetting:$($sub.Id)" -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $all = Get-AzResource
            if ($ResourceType) { $all = $all | Where-Object ResourceType -eq $ResourceType }
            $all
        }

        # Parallel diagnostic lookups; return plain data, build findings after.
        $checked = $resources | ForEach-Object -ThrottleLimit $throttle -Parallel {
            $r = $_
            try {
                $ds = Get-AzDiagnosticSetting -ResourceId $r.ResourceId -ErrorAction Stop
                [pscustomobject]@{ Resource = $r; Settings = @($ds); Error = $null }
            }
            catch {
                # Many resource types don't support diagnostics; treat as N/A, not a gap.
                $na = $_.Exception.Message -match 'does not support|NotSupported|ResourceNotFound'
                [pscustomobject]@{ Resource = $r; Settings = @(); Error = ($na ? 'Unsupported' : $_.Exception.Message) }
            }
        }

        foreach ($c in $checked) {
            if ($c.Error -eq 'Unsupported') { continue }
            $hasSetting = $c.Settings.Count -gt 0
            if ($OnlyGaps -and $hasSetting) { continue }

            New-AotFinding -Category 'Monitoring' -Type 'DiagnosticSetting' `
                -Name $c.Resource.Name -ResourceId $c.Resource.ResourceId `
                -ResourceGroup $c.Resource.ResourceGroupName -Location $c.Resource.Location `
                -Severity ($hasSetting ? 'Informational' : 'High') `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    ResourceType    = $c.Resource.ResourceType
                    HasSetting      = $hasSetting
                    SettingCount    = $c.Settings.Count
                    SettingNames    = @($c.Settings.Name)
                }
        }
    }
}

function Get-AotDiagnosticSetting {
    <#
    .SYNOPSIS
        Reports diagnostic-setting coverage for resources, flagging gaps.

    .DESCRIPTION
        Builds the resource list with one tenant-wide Resource Graph query
        (fallback: parallel per-subscription sweep), then checks every resource
        in a single flat parallel loop across the whole tenant — the
        per-resource Get-AzDiagnosticSetting call is the unavoidable cost, so
        it is amortised over one runspace pool instead of one per subscription.
        Resources with no setting are High severity.

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
    $throttle = $script:AotConfig.ResourceScanThrottleLimit
    $subName = @{}
    foreach ($s in $subs) { $subName[$s.Id] = $s.Name }

    # --- 1. Flat resource list, normalised to one shape ---
    $targets = $null
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        try {
            $kql = 'resources | project id, name, type, resourceGroup, location, subscriptionId'
            if ($ResourceType) {
                $kql = "resources | where type =~ '$ResourceType' | project id, name, type, resourceGroup, location, subscriptionId"
            }
            $rows = Invoke-AotGraphQuery -Operation 'DiagnosticSetting:graph' -SubscriptionId @($subs.Id) -Query $kql
            $targets = @(foreach ($r in $rows) {
                [pscustomobject]@{
                    Id = $r.id; Name = $r.name; Type = $r.type
                    Rg = $r.resourceGroup; Location = $r.location; SubId = [string]$r.subscriptionId
                }
            })
        }
        catch {
            Write-AotLog -Level Warning -Operation 'DiagnosticSetting' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    if ($null -eq $targets) {
        $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'DiagnosticSetting' -Fetch {
            param($sub)
            Get-AzResource
        }
        $targets = @(foreach ($entry in $sweep) {
            foreach ($r in $entry.Items) {
                if ($ResourceType -and $r.ResourceType -ne $ResourceType) { continue }
                [pscustomobject]@{
                    Id = $r.ResourceId; Name = $r.Name; Type = $r.ResourceType
                    Rg = $r.ResourceGroupName; Location = $r.Location; SubId = $entry.Subscription.Id
                }
            }
        })
    }

    if (-not $targets) { return }

    $ctxMap = Get-AotSubscriptionContext -Subscription $subs

    # Shared scan block: one Get-AzDiagnosticSetting call per resource.
    $scan = {
        $r = $_
        try {
            $PSDefaultParameterValues = @{ '*-Az*:DefaultProfile' = ($using:ctxMap)[$r.SubId] }
            # -WarningAction: Az announces an output change to the Log/Metric
            # properties on every call; this collector only reads setting
            # names and counts, so the change cannot affect it.
            $ds = Get-AzDiagnosticSetting -ResourceId $r.Id -ErrorAction Stop -WarningAction SilentlyContinue
            [pscustomobject]@{ Resource = $r; Settings = @($ds); Error = $null }
        }
        catch {
            # Many resource types don't support diagnostics; treat as N/A, not a gap.
            $na = $_.Exception.Message -match 'does not support|NotSupported|ResourceNotFound'
            [pscustomobject]@{ Resource = $r; Settings = @(); Error = ($na ? 'Unsupported' : $_.Exception.Message) }
        }
    }

    # --- 2a. Probe one resource per type: diagnostic-setting support is a
    # property of the resource type, so an unsupported probe rules out every
    # resource of that type and typically halves the scan.
    $byType = $targets | Group-Object Type
    $probes = @(foreach ($g in $byType) { $g.Group[0] })
    Write-AotLog -Level Information -Operation 'DiagnosticSetting' `
        -Message "Probing $($probes.Count) resource type(s), $throttle parallel"
    $probeResults = $probes | ForEach-Object -ThrottleLimit $throttle -Parallel $scan

    $unsupportedTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $probeResults) {
        if ($p.Error -eq 'Unsupported') { [void]$unsupportedTypes.Add([string]$p.Resource.Type) }
    }

    # --- 2b. Scan the remaining resources of supported types.
    $probedIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($probes.Id), [System.StringComparer]::OrdinalIgnoreCase)
    $remaining = @($targets | Where-Object {
        -not $unsupportedTypes.Contains([string]$_.Type) -and -not $probedIds.Contains([string]$_.Id)
    })

    Write-AotLog -Level Information -Operation 'DiagnosticSetting' -Message (
        "Checking $($remaining.Count) resource(s) across supported types, $throttle parallel " +
        "($($unsupportedTypes.Count) type(s) skipped as unsupported)"
    )
    $checked = @($probeResults) + @($remaining | ForEach-Object -ThrottleLimit $throttle -Parallel $scan)

    # --- 3. Build findings sequentially ---
    foreach ($c in $checked) {
        if ($c.Error -eq 'Unsupported') { continue }
        $hasSetting = $c.Settings.Count -gt 0
        if ($OnlyGaps -and $hasSetting) { continue }

        New-AotFinding -Category 'Monitoring' -Type 'DiagnosticSetting' `
            -Name $c.Resource.Name -ResourceId $c.Resource.Id `
            -ResourceGroup $c.Resource.Rg -Location $c.Resource.Location `
            -Severity ($hasSetting ? 'Informational' : 'High') `
            -SubscriptionId $c.Resource.SubId -SubscriptionName $subName[$c.Resource.SubId] `
            -Detail @{
                ResourceType = $c.Resource.Type
                HasSetting   = $hasSetting
                SettingCount = $c.Settings.Count
                # Newer Az.Monitor diagnostic-setting objects don't expose a
                # Name property on every shape; probe instead of dotting.
                SettingNames = @($c.Settings | ForEach-Object { Get-AotMember $_ 'Name' })
                CheckError   = $c.Error
            }
    }
}

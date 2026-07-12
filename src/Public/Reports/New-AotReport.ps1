function New-AotReport {
    <#
    .SYNOPSIS
        Orchestrates a multi-module assessment and writes report(s) in one call.

    .DESCRIPTION
        Runs the selected module collectors, aggregates all findings, and emits
        the requested report format(s) to an output directory. Individual module
        failures are logged and skipped so one bad call doesn't sink the run.

    .PARAMETER Module
        Which module collectors to run. Defaults to all.

    .PARAMETER Format
        One or more of Html, Csv, Json. Defaults to all three.

    .PARAMETER OutputPath
        Directory for the generated report files.

    .PARAMETER SubscriptionId
        Restrict the assessment to specific subscriptions.

    .PARAMETER RequiredTag
        Tag keys used by the Governance missing-tag check.

    .PARAMETER PassThru
        Also return the aggregated findings to the pipeline.

    .EXAMPLE
        New-AotReport -Module Cost, Security -Format Html -OutputPath .\out

    .EXAMPLE
        New-AotReport -OutputPath .\out -RequiredTag Owner, CostCenter
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Inventory', 'Governance', 'Security', 'Cost', 'Monitoring')]
        [string[]]$Module = @('Inventory', 'Governance', 'Security', 'Cost', 'Monitoring'),

        [ValidateSet('Html', 'Csv', 'Json')]
        [string[]]$Format = @('Html', 'Csv', 'Json'),

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string[]]$SubscriptionId,

        [string[]]$RequiredTag = @('Owner', 'Environment', 'CostCenter'),

        [switch]$PassThru
    )

    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $subParam = if ($SubscriptionId) { @{ SubscriptionId = $SubscriptionId } } else { @{} }

    # Pre-flight: announce every collector that will be skipped for a missing
    # module, in one place, before the run starts.
    $missing = Test-AotDependency | Where-Object { -not $_.Installed }
    foreach ($dep in $missing) {
        Write-AotLog -Level Warning -Operation 'Report' -Message (
            "Module '$($dep.Module)' is not installed; skipping: $($dep.EnablesCommands -join ', '). " +
            "Run Test-AotDependency -InstallMissing to enable."
        )
    }

    # Map of module -> collector scriptblocks. Each is wrapped so a failure is
    # logged and skipped rather than aborting the whole report.
    $collectors = [ordered]@{
        Inventory  = @(
            { Get-AotResourceInventory @subParam },
            { Get-AotResourceGroupInventory @subParam },
            { Get-AotRoleAssignmentInventory @subParam },
            { Get-AotPolicyInventory @subParam },
            { Get-AotResourceLockInventory @subParam },
            { Get-AotTagInventory @subParam }
        )
        Governance = @(
            { Get-AotOwnerAssignment @subParam },
            { Get-AotDirectUserAssignment @subParam },
            { Get-AotStaleGuestAccount },
            { Get-AotMissingTag -RequiredTag $RequiredTag @subParam },
            { Get-AotPolicyViolation @subParam }
        )
        Security   = @(
            { Get-AotDefenderStatus @subParam },
            { Get-AotPimAssignment },
            { Get-AotExpiringPimRole },
            { Get-AotMfaGap },
            { Get-AotKeyVaultAudit @subParam }
        )
        Cost       = @(
            { Get-AotUnattachedDisk @subParam },
            { Get-AotIdlePublicIp @subParam },
            { Get-AotEmptyResourceGroup @subParam },
            { Get-AotReservedInstanceRecommendation @subParam }
        )
        Monitoring = @(
            { Get-AotDiagnosticSetting @subParam },
            { Test-AotLogAnalytics @subParam },
            { Get-AotMonitorAlert @subParam },
            { Get-AotActionGroup @subParam }
        )
    }

    $findings = [System.Collections.Generic.List[object]]::new()

    foreach ($m in $Module) {
        Write-AotLog -Level Information -Operation 'Report' -Message "Running module '$m'"
        foreach ($collector in $collectors[$m]) {
            try {
                $result = & $collector
                if ($result) { foreach ($r in $result) { $findings.Add($r) } }
            }
            catch {
                Write-AotLog -Level Warning -Operation 'Report' `
                    -Message "Collector skipped in module '$m': $($_.Exception.Message)"
            }
        }
    }

    Write-AotLog -Level Information -Operation 'Report' -Message "Aggregated $($findings.Count) findings"

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $written = @()
    if ('Json' -in $Format) { $written += (Export-AotJsonReport -Finding $findings -Path (Join-Path $OutputPath "aot-report-$stamp.json")) }
    if ('Csv'  -in $Format) { $written += (Export-AotCsvReport  -Finding $findings -Path (Join-Path $OutputPath "aot-report-$stamp.csv")) }
    if ('Html' -in $Format) { $written += (Export-AotHtmlReport -Finding $findings -Path (Join-Path $OutputPath "aot-report-$stamp.html")) }

    $summary = [pscustomobject]@{
        GeneratedAt   = (Get-Date).ToString('o')
        Modules       = $Module
        FindingCount  = $findings.Count
        BySeverity    = $findings | Group-Object Severity | ForEach-Object { [pscustomobject]@{ Severity = $_.Name; Count = $_.Count } }
        Reports       = $written.FullName
    }

    if ($PassThru) { [pscustomobject]@{ Summary = $summary; Findings = $findings } } else { $summary }
}

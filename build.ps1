#Requires -Version 7.5
<#
.SYNOPSIS
    Build entrypoint: lint, test and (optionally) package the module.

.DESCRIPTION
    Task-based build without external build engines. Installs dev dependencies
    (Pester, PSScriptAnalyzer) on demand, runs PSScriptAnalyzer, executes the
    Pester suite with code coverage, and can bump the module version.

.PARAMETER Task
    One or more of: Clean, Analyze, Test, Version, Package. Default: Analyze, Test.

.PARAMETER BumpType
    For the Version task: Major | Minor | Patch (Semantic Versioning).

.EXAMPLE
    ./build.ps1 -Task Analyze, Test

.EXAMPLE
    ./build.ps1 -Task Version -BumpType Minor
#>
[CmdletBinding()]
param(
    [ValidateSet('Clean', 'Analyze', 'Test', 'Version', 'Package')]
    [string[]]$Task = @('Analyze', 'Test'),

    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$BumpType = 'Patch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root       = $PSScriptRoot
$srcPath    = Join-Path $root 'src'
$manifest   = Join-Path $srcPath 'AzureOperationsToolkit.psd1'
$testsPath  = Join-Path $root 'tests'
$outPath    = Join-Path $root 'out'

function Install-DevDependency {
    param([string]$Name, [string]$MinimumVersion)
    $mod = Get-Module -ListAvailable -Name $Name |
        Where-Object { $_.Version -ge [version]$MinimumVersion } | Select-Object -First 1
    if (-not $mod) {
        Write-Host "Installing $Name >= $MinimumVersion..." -ForegroundColor Cyan
        Install-Module -Name $Name -MinimumVersion $MinimumVersion -Scope CurrentUser -Force -SkipPublisherCheck
    }
    Import-Module $Name -MinimumVersion $MinimumVersion -Force
}

function Invoke-CleanTask {
    if (Test-Path $outPath) { Remove-Item $outPath -Recurse -Force }
    Write-Host 'Clean complete.' -ForegroundColor Green
}

function Invoke-AnalyzeTask {
    Install-DevDependency -Name PSScriptAnalyzer -MinimumVersion '1.22.0'
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $results = Invoke-ScriptAnalyzer -Path $srcPath -Recurse -Settings $settings
    if ($results) {
        $results | Format-Table -AutoSize | Out-String | Write-Host
        $errors = $results | Where-Object Severity -eq 'Error'
        if ($errors) { throw "PSScriptAnalyzer found $($errors.Count) error(s)." }
        Write-Host "PSScriptAnalyzer: $($results.Count) warning(s), 0 error(s)." -ForegroundColor Yellow
    }
    else {
        Write-Host 'PSScriptAnalyzer: clean.' -ForegroundColor Green
    }
}

function Invoke-TestTask {
    Install-DevDependency -Name Pester -MinimumVersion '5.5.0'
    if (-not (Test-Path $outPath)) { New-Item -ItemType Directory -Path $outPath -Force | Out-Null }

    $config = New-PesterConfiguration
    $config.Run.Path                    = $testsPath
    $config.Run.Exit                    = $true
    $config.TestResult.Enabled          = $true
    $config.TestResult.OutputPath       = Join-Path $outPath 'testResults.xml'
    $config.TestResult.OutputFormat     = 'NUnitXml'
    $config.CodeCoverage.Enabled        = $true
    $config.CodeCoverage.Path           = $srcPath
    $config.CodeCoverage.OutputPath     = Join-Path $outPath 'coverage.xml'
    $config.CodeCoverage.OutputFormat   = 'JaCoCo'
    $config.Output.Verbosity            = 'Detailed'

    Invoke-Pester -Configuration $config
}

function Invoke-VersionTask {
    $data = Import-PowerShellDataFile -Path $manifest
    $current = [version]$data.ModuleVersion
    $new = switch ($BumpType) {
        'Major' { [version]::new($current.Major + 1, 0, 0) }
        'Minor' { [version]::new($current.Major, $current.Minor + 1, 0) }
        'Patch' { [version]::new($current.Major, $current.Minor, $current.Build + 1) }
    }
    (Get-Content $manifest -Raw) -replace "ModuleVersion\s*=\s*'[^']+'", "ModuleVersion     = '$new'" |
        Set-Content $manifest -Encoding utf8
    Write-Host "Version bumped $current -> $new" -ForegroundColor Green
}

function Invoke-PackageTask {
    if (-not (Test-Path $outPath)) { New-Item -ItemType Directory -Path $outPath -Force | Out-Null }
    $data    = Import-PowerShellDataFile -Path $manifest
    $version = $data.ModuleVersion
    $stage   = Join-Path $outPath "AzureOperationsToolkit\$version"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -Path (Join-Path $srcPath '*') -Destination $stage -Recurse -Force
    Test-ModuleManifest -Path (Join-Path $stage 'AzureOperationsToolkit.psd1') | Out-Null
    Write-Host "Packaged to $stage" -ForegroundColor Green
}

foreach ($t in $Task) {
    Write-Host "`n=== Task: $t ===" -ForegroundColor Magenta
    & "Invoke-${t}Task"
}

#Requires -Version 7.5

<#
    Root module. Dot-sources every Private and Public function at import time and
    exports only the Public surface. Keeping one function per file keeps the
    module navigable and unit-testable.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot

# Module-scoped state shared by the framework functions.
$script:AotConfig = [ordered]@{
    LogPath          = Join-Path ([System.IO.Path]::GetTempPath()) 'AzureOperationsToolkit'
    LogLevel         = 'Information'   # Verbose | Information | Warning | Error
    MaxRetryCount    = 3
    RetryDelaySeconds = 2
    ThrottleLimit    = 8               # default parallelism for subscription sweeps
    ResourceScanThrottleLimit = 24     # parallelism for flat per-resource scans (I/O bound)
    StaleGuestDays   = 90
    PimExpiryWindowDays = 14
}

# Cache of enabled subscriptions per tenant/account, filled by
# Get-AotSubscriptionScope and cleared by Connect-AotAzure.
$script:AotSubscriptionCache = @{}

# Cache of per-subscription Azure context objects (subscription id -> context),
# built once by Get-AotSubscriptionContext for parallel sweeps and cleared by
# Connect-AotAzure.
$script:AotContextCache = @{}

$folders = @('Private', 'Public')
foreach ($folder in $folders) {
    $path = Join-Path $script:ModuleRoot $folder
    if (-not (Test-Path $path)) { continue }

    $files = Get-ChildItem -Path $path -Filter '*.ps1' -Recurse -File |
        Where-Object { $_.Name -notmatch '\.Tests\.ps1$' }

    foreach ($file in $files) {
        try {
            . $file.FullName
        }
        catch {
            throw "Failed to import function file '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

$publicPath = Join-Path $script:ModuleRoot 'Public'
if (Test-Path $publicPath) {
    $publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse -File |
        Where-Object { $_.Name -notmatch '\.Tests\.ps1$' } |
        ForEach-Object { $_.BaseName }

    Export-ModuleMember -Function ($publicFunctions + @('Connect-AotAzure', 'Set-AotConfiguration', 'Get-AotConfiguration'))
}

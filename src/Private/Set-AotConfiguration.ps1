function Set-AotConfiguration {
    <#
    .SYNOPSIS
        Updates module-wide runtime configuration.

    .DESCRIPTION
        Controls logging, retry, parallelism and threshold defaults consumed by
        the collection functions. Only supplied parameters are changed.

    .EXAMPLE
        Set-AotConfiguration -LogLevel Verbose -ThrottleLimit 16
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LogPath,
        [ValidateSet('Verbose', 'Information', 'Warning', 'Error')][string]$LogLevel,
        [ValidateRange(0, 10)][int]$MaxRetryCount,
        [ValidateRange(0, 60)][int]$RetryDelaySeconds,
        [ValidateRange(1, 64)][int]$ThrottleLimit,
        [ValidateRange(1, 128)][int]$ResourceScanThrottleLimit,
        [ValidateRange(1, 3650)][int]$StaleGuestDays,
        [ValidateRange(1, 365)][int]$PimExpiryWindowDays
    )

    if ($PSCmdlet.ShouldProcess('AzureOperationsToolkit', 'Update configuration')) {
        foreach ($key in $PSBoundParameters.Keys) {
            if ($script:AotConfig.Contains($key)) {
                $script:AotConfig[$key] = $PSBoundParameters[$key]
            }
        }
    }
    Get-AotConfiguration
}

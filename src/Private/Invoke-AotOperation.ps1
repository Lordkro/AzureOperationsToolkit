function Invoke-AotOperation {
    <#
    .SYNOPSIS
        Central error-handling and retry wrapper for Azure calls.

    .DESCRIPTION
        Runs a scriptblock with structured logging and exponential backoff on
        transient failures (throttling / timeouts). Non-transient errors surface
        immediately. Returns whatever the scriptblock returns.

    .PARAMETER ScriptBlock
        The work to execute.

    .PARAMETER Operation
        Friendly name used in log lines.

    .PARAMETER MaxRetryCount
        Overrides the module default retry count.

    .EXAMPLE
        Invoke-AotOperation -Operation 'Get resources' -ScriptBlock { Get-AzResource }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [string]$Operation,

        [int]$MaxRetryCount = $script:AotConfig.MaxRetryCount,

        [int]$RetryDelaySeconds = $script:AotConfig.RetryDelaySeconds
    )

    $transientPatterns = @(
        'TooManyRequests', '429', 'throttl', 'timeout', 'timed out',
        'temporarily unavailable', 'ServerTimeout', 'gateway', 'connection reset'
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Write-AotLog -Level Verbose -Operation $Operation -Message "Attempt $attempt of $($MaxRetryCount + 1)"
            return & $ScriptBlock
        }
        catch {
            $msg = $_.Exception.Message
            $isTransient = $transientPatterns | Where-Object { $msg -match $_ }

            if ($attempt -le $MaxRetryCount -and $isTransient) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-AotLog -Level Warning -Operation $Operation `
                    -Message "Transient failure (attempt $attempt): $msg. Retrying in ${delay}s."
                Start-Sleep -Seconds $delay
                continue
            }

            Write-AotLog -Level Error -Operation $Operation `
                -Message "Operation failed after $attempt attempt(s): $msg" -ErrorRecord $_
            throw
        }
    }
}

function Write-AotLog {
    <#
    .SYNOPSIS
        Structured logger for the toolkit. Writes to the PowerShell streams and,
        when a log path is configured, appends a JSON line to a daily log file.

    .DESCRIPTION
        Honours the module LogLevel so noisy Verbose/Information messages can be
        suppressed without touching call sites. File logging is best-effort and
        never throws back into the caller.

    .EXAMPLE
        Write-AotLog -Level Information -Message 'Collected 42 resources'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Verbose', 'Information', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Operation = 'General',

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $order = @{ Verbose = 0; Information = 1; Warning = 2; Error = 3 }
    $configuredLevel = if ($script:AotConfig) { $script:AotConfig.LogLevel } else { 'Information' }

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Level     = $Level
        Operation = $Operation
        Message   = $Message
    }
    if ($ErrorRecord) {
        $entry.Exception  = $ErrorRecord.Exception.Message
        $entry.ScriptLine = $ErrorRecord.InvocationInfo.ScriptLineNumber
    }

    # Emit to the appropriate stream when the level is at or above threshold.
    if ($order[$Level] -ge $order[$configuredLevel]) {
        $line = "[$($entry.Timestamp)] [$Level] [$Operation] $Message"
        switch ($Level) {
            'Verbose'     { Write-Verbose $line }
            'Information' { Write-Information $line -InformationAction Continue }
            'Warning'     { Write-Warning $line }
            'Error'       { Write-Error $line -ErrorAction Continue }
        }
    }

    # Best-effort structured file logging.
    if ($script:AotConfig -and $script:AotConfig.LogPath) {
        try {
            if (-not (Test-Path $script:AotConfig.LogPath)) {
                New-Item -ItemType Directory -Path $script:AotConfig.LogPath -Force | Out-Null
            }
            $file = Join-Path $script:AotConfig.LogPath ("aot-{0:yyyyMMdd}.log" -f (Get-Date))
            ($entry | ConvertTo-Json -Compress -Depth 5) | Add-Content -Path $file -Encoding utf8
        }
        catch {
            Write-Warning "Log file write failed: $($_.Exception.Message)"
        }
    }
}

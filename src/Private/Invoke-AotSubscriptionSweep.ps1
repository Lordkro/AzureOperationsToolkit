function Invoke-AotSubscriptionSweep {
    <#
    .SYNOPSIS
        Runs a data-fetch scriptblock against many subscriptions, in parallel.

    .DESCRIPTION
        The workhorse behind every multi-subscription collector. Given a Fetch
        scriptblock containing ONLY Az cmdlets (module-private functions do not
        exist inside parallel runspaces), it returns one record per subscription:
        @{ Subscription; Items; Error }.

        Parallel mode (default) injects each subscription's cached context via
        $PSDefaultParameterValues['*-Az*:DefaultProfile'] so Fetch bodies never
        touch the process-wide default context. A small retry handles transient
        throttling inside each runspace.

        Sequential mode (ThrottleLimit <= 1, or a single subscription) uses
        Set-AzContext + Invoke-AotOperation exactly like the pre-parallel code
        path — this is also what keeps the collectors unit-testable, since
        Pester mocks do not propagate into parallel runspaces.

    .PARAMETER Subscription
        Subscriptions to sweep (from Get-AotSubscriptionScope).

    .PARAMETER Fetch
        param($sub) scriptblock returning the items for one subscription.
        Az cmdlets only; no module-private functions, no logging.

    .PARAMETER Operation
        Name used in log lines.

    .OUTPUTS
        pscustomobject records: Subscription, Items (array), Error (string/null).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Subscription,

        [Parameter(Mandatory)]
        [scriptblock]$Fetch,

        [Parameter(Mandatory)]
        [string]$Operation,

        [int]$ThrottleLimit = $script:AotConfig.ThrottleLimit
    )

    # --- sequential path: single subscription or parallelism disabled ---
    if ($ThrottleLimit -le 1 -or @($Subscription).Count -le 1) {
        foreach ($sub in $Subscription) {
            Write-AotLog -Level Information -Operation $Operation -Message "Collecting for '$($sub.Name)'"
            $items = Invoke-AotOperation -Operation "${Operation}:$($sub.Id)" -SkipOnError -ScriptBlock {
                Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
                & $Fetch $sub
            }
            [pscustomobject]@{ Subscription = $sub; Items = @($items); Error = $null }
        }
        return
    }

    # --- parallel path ---
    $ctxMap = Get-AotSubscriptionContext -Subscription $Subscription
    $work = @($Subscription | Where-Object { $ctxMap.ContainsKey($_.Id) })
    Write-AotLog -Level Information -Operation $Operation `
        -Message "Collecting across $($work.Count) subscription(s), $ThrottleLimit parallel"

    $fetchText = $Fetch.ToString()   # scriptblocks cannot cross the $using: boundary
    $maxRetry = $script:AotConfig.MaxRetryCount

    $results = $work | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $sub = $_
        try {
            # Route every Az cmdlet in Fetch at this subscription without
            # touching the process-wide default context.
            $PSDefaultParameterValues = @{ '*-Az*:DefaultProfile' = ($using:ctxMap)[$sub.Id] }
            $fn = [scriptblock]::Create($using:fetchText)

            $attempt = 0
            while ($true) {
                try {
                    $items = & $fn $sub
                    break
                }
                catch {
                    $attempt++
                    $transient = $_.Exception.Message -match 'TooManyRequests|429|throttl|timeout|timed out|gateway'
                    if (-not $transient -or $attempt -gt $using:maxRetry) { throw }
                    Start-Sleep -Seconds (2 * $attempt)
                }
            }
            [pscustomobject]@{ Subscription = $sub; Items = @($items); Error = $null }
        }
        catch {
            [pscustomobject]@{ Subscription = $sub; Items = @(); Error = $_.Exception.Message }
        }
    }

    foreach ($r in $results) {
        if ($r.Error) {
            Write-AotLog -Level Warning -Operation "${Operation}:$($r.Subscription.Id)" `
                -Message "Subscription skipped: $($r.Error)"
        }
    }
    $results
}

# Architecture

## Layout

```
src/
  AzureOperationsToolkit.psd1     # manifest: version, deps, exported surface
  AzureOperationsToolkit.psm1     # loader: dot-sources Private + Public, exports Public
  Private/                        # framework, never exported
    Write-AotLog.ps1              # structured, level-filtered logging (+ daily JSON file)
    Invoke-AotOperation.ps1       # retry/backoff + error wrapper for Azure calls
    Get-AotSubscriptionScope.ps1  # resolve target subscriptions
    New-AotFinding.ps1            # normalised output object (Aot.Finding)
    Connect-AotAzure.ps1          # sign-in (interactive / MI / SP)
    Set-AotConfiguration.ps1      # runtime config setters
    Get-AotConfiguration.ps1
  Public/
    Inventory/  Governance/  Security/  Cost/  Monitoring/  Reports/
tests/                            # Pester 5 suite (Azure mocked)
build.ps1                         # Clean | Analyze | Test | Version | Package
.github/workflows/ci.yml          # lint + test matrix, tag-triggered publish
```

## Design principles

### One shape to rule them all

Every collector returns `Aot.Finding` objects (`New-AotFinding`). This decoupling
means reporters and downstream tooling never special-case a module. Check-specific
data lives in the free-form `Detail` property.

### Resilience is centralised

`Invoke-AotOperation` is the single choke point for Azure calls. It:

- logs each attempt,
- classifies transient failures (429 / throttling / timeout / gateway),
- retries with exponential backoff up to `MaxRetryCount`,
- rethrows non-transient errors immediately.

`New-AotReport` additionally isolates each collector in a try/catch so a missing
optional module (e.g. `Az.Advisor`) degrades gracefully instead of aborting.

### Configuration over constants

`$script:AotConfig` holds log level/path, retry counts, `ThrottleLimit`, and
threshold defaults (stale-guest days, PIM expiry window). `Set-AotConfiguration`
mutates it; collectors read it, so behaviour is tunable without code edits.

### Parallelism, safely

`ForEach-Object -Parallel` is used only for **independent, resource-level**
lookups (Key Vault audit, diagnostic-setting coverage). Because module-private
functions are not present in child runspaces, parallel blocks use **only Az
cmdlets and `$using:` values**, return plain data, and the parent runspace builds
findings sequentially. Subscription context switching (`Set-AzContext`) stays
sequential because it is process-wide.

## Data flow

```
Connect-AotAzure
      │
      ▼
Get-AotSubscriptionScope ──► foreach subscription
      │                          │
      │                    Invoke-AotOperation ──► Az / Graph cmdlets
      │                          │
      ▼                          ▼
Set-AotConfiguration      New-AotFinding  ─────►  Aot.Finding[]
                                                   │
                          Export-Aot{Html,Csv,Json}Report ◄── New-AotReport
```

## Adding a module

Create a folder under `src/Public/`, add `Get-Aot*` collectors that emit findings,
register them in the manifest and (optionally) `New-AotReport`. The loader picks
up new files automatically; no manifest change is needed for the module to load,
only for it to be listed in `FunctionsToExport`.

# Azure Operations Toolkit

Production-grade PowerShell toolkit for assessing Azure estates across
**inventory, governance, security, cost and monitoring**, with pluggable
HTML / CSV / JSON reporting.

[![CI](https://github.com/example/AzureOperationsToolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/example/AzureOperationsToolkit/actions/workflows/ci.yml)

## Highlights

- **Modular** — one function per file, grouped by domain module. Private
  framework helpers are isolated from the public command surface.
- **Consistent output** — every collector emits the same `Aot.Finding` shape, so
  any result feeds straight into any reporter.
- **Resilient** — central retry/backoff wrapper (`Invoke-AotOperation`) handles
  throttling; a failed collector never sinks a full report run.
- **Observable** — structured, level-filtered logging to stream and daily JSON
  log file.
- **Parallel** — resource-level lookups (Key Vault audit, diagnostic-setting
  coverage) fan out with `ForEach-Object -Parallel`.
- **Tested & linted** — Pester suite with code coverage, PSScriptAnalyzer, and a
  cross-platform GitHub Actions matrix.

## Requirements

- PowerShell **7.5+**
- `Az.Accounts`, `Az.Resources` (required by the manifest)
- Feature-specific modules, imported on demand where used:
  - `Az.Security` — Defender status
  - `Az.PolicyInsights` — policy violations
  - `Az.Advisor` — reserved-instance recommendations
  - `Az.OperationalInsights`, `Az.Monitor` — monitoring checks
  - `Microsoft.Graph.*` — stale guests, PIM, MFA gaps

Check and install everything in one go:

```powershell
Test-AotDependency                  # what is missing and which commands it blocks
Test-AotDependency -InstallMissing  # install the gaps (CurrentUser)
```

### Microsoft Graph permissions

The identity checks run against Microsoft Graph and need a `Connect-MgGraph`
session. Scopes per command (delegated; or the equivalent application
permissions for unattended runs):

| Command | Scopes |
| --- | --- |
| `Get-AotStaleGuestAccount` | `User.Read.All`, `AuditLog.Read.All` |
| `Get-AotMfaGap` | `UserAuthenticationMethod.Read.All`, `AuditLog.Read.All` |
| `Get-AotPimAssignment`, `Get-AotExpiringPimRole` | `RoleManagement.Read.Directory` |

The commands fail fast with the exact `Connect-MgGraph -Scopes ...` line when
the session is missing or under-scoped.

> **Directory role required:** sign-in activity and the registration reports are
> additionally gated behind Entra directory roles — the signed-in account must
> hold **Global Reader**, **Reports Reader**, **Security Reader** or **Security
> Administrator**. Scope consent alone yields a 403
> (`Authentication_RequestFromUnsupportedUserRole`) on `Get-AotStaleGuestAccount`
> and `Get-AotMfaGap`.

## Install

```powershell
# From source
git clone https://github.com/example/AzureOperationsToolkit.git
Import-Module ./AzureOperationsToolkit/src/AzureOperationsToolkit.psd1

# Or, once published
Install-Module AzureOperationsToolkit -Scope CurrentUser
```

## Quick start

```powershell
Import-Module ./src/AzureOperationsToolkit.psd1

# Sign in (interactive, managed identity, or service principal)
Connect-AotAzure

# The Graph-based checks (stale guests, PIM, MFA gaps) also need a
# Microsoft Graph session with these scopes:
Connect-MgGraph -Scopes 'User.Read.All', 'AuditLog.Read.All',
                        'UserAuthenticationMethod.Read.All', 'RoleManagement.Read.Directory'

# Optional: tune logging / parallelism / thresholds
Set-AotConfiguration -LogLevel Information -ThrottleLimit 12

# Run a single check
Get-AotUnattachedDisk | Format-Table Name, ResourceGroup, @{ N='SizeGB'; E={ $_.Detail.DiskSizeGB } }

# Run a full assessment and produce all report formats
New-AotReport -OutputPath ./out -RequiredTag Owner, CostCenter, Environment
```

## Modules & commands

| Module | Commands |
| --- | --- |
| **Inventory** | `Get-AotResourceInventory`, `Get-AotResourceGroupInventory`, `Get-AotRoleAssignmentInventory`, `Get-AotPolicyInventory`, `Get-AotResourceLockInventory`, `Get-AotTagInventory` |
| **Governance** | `Get-AotOwnerAssignment`, `Get-AotDirectUserAssignment`, `Get-AotStaleGuestAccount`, `Get-AotMissingTag`, `Get-AotPolicyViolation` |
| **Security** | `Get-AotDefenderStatus`, `Get-AotPimAssignment`, `Get-AotExpiringPimRole`, `Get-AotMfaGap`, `Get-AotKeyVaultAudit` |
| **Cost** | `Get-AotUnattachedDisk`, `Get-AotIdlePublicIp`, `Get-AotEmptyResourceGroup`, `Get-AotReservedInstanceRecommendation` |
| **Monitoring** | `Get-AotDiagnosticSetting`, `Test-AotLogAnalytics`, `Get-AotMonitorAlert`, `Get-AotActionGroup` |
| **Reports** | `New-AotReport`, `Export-AotHtmlReport`, `Export-AotCsvReport`, `Export-AotJsonReport` |
| **Core** | `Connect-AotAzure`, `Set-AotConfiguration`, `Get-AotConfiguration`, `Test-AotDependency` |

Every collector accepts `-SubscriptionId` (one or more) and defaults to **all
enabled subscriptions** in the current context.

## The finding object

```text
Category          Inventory | Governance | Security | Cost | Monitoring
Type              e.g. UnattachedDisk, MfaGap, OwnerAssignment
Name              resource / principal name
Severity          Informational | Low | Medium | High | Critical
Subscription*     name + id
ResourceGroup     when applicable
Location          when applicable
ResourceId        ARM id
Detail            check-specific properties (object)
CollectedAt       ISO-8601 timestamp
```

## Reporting

```powershell
# Compose any collectors into one report set
$findings = Get-AotDefenderStatus; $findings += Get-AotKeyVaultAudit
$findings | Export-AotHtmlReport -Path ./out/security.html -Title 'Security posture'
$findings | Export-AotCsvReport  -Path ./out/security.csv
$findings | Export-AotJsonReport -Path ./out/security.json
```

`New-AotReport` runs many collectors, aggregates, and writes all requested
formats in one call. See [docs/](docs/) for module deep-dives.

## Development

```powershell
./build.ps1 -Task Analyze, Test      # lint + Pester with coverage
./build.ps1 -Task Version -BumpType Minor
./build.ps1 -Task Package            # staged module + manifest validation
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/architecture.md](docs/architecture.md).

## Versioning

[Semantic Versioning](https://semver.org). Tags `vMAJOR.MINOR.PATCH` trigger the
publish job. Changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE).

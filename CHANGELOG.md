# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.2] - 2026-07-12

### Fixed

- `Get-AotReservedInstanceRecommendation` failed on Az.Advisor 3.x with
  "Parameter set cannot be resolved": the autorest rewrite removed
  subscription-wide `-Category` filtering. The collector now uses
  `-Filter "Category eq 'Cost'"` on 3.x and keeps `-Category Cost` on 2.x, and
  reads `ExtendedProperty` in both its hashtable (2.x) and typed-object (3.x)
  shapes.

## [1.1.1] - 2026-07-12

### Fixed

- `Get-AotKeyVaultAudit` no longer prints the Az.KeyVault "upcoming breaking
  change" banner per vault for `Get-AzKeyVaultSecret`/`Get-AzKeyVaultKey`. The
  announced change (certificate-backed items excluded from listings) is already
  handled in code, so the warning stream is silenced on those two calls only —
  no global or module-wide suppression.

## [1.1.0] - 2026-07-12

### Added

- `Test-AotDependency`: reports which optional modules are installed and which
  toolkit commands each one enables; `-InstallMissing` installs the gaps from
  PSGallery (CurrentUser).
- `New-AotReport` pre-flight: every collector that will be skipped for a missing
  module is announced once, up front, with the install hint.
- Graph collectors (`Get-AotStaleGuestAccount`, `Get-AotMfaGap`,
  `Get-AotPimAssignment`) now fail fast with the exact `Connect-MgGraph -Scopes`
  command needed instead of an opaque Graph auth error, and warn when the
  connected session is missing an expected scope.

## [1.0.2] - 2026-07-12

### Changed

- Az "upcoming breaking change" warnings are no longer suppressed; the announced
  changes are handled in code instead.
- `Get-AotKeyVaultAudit` now skips Managed (certificate-backed) secrets and keys
  when scanning for expiry, adopting the Az.KeyVault 7.0.0 listing behaviour
  early. Certificate expiry is still audited via `Get-AzKeyVaultCertificate`,
  which also removes the previous double-counting of certificate-backed items.

### Removed

- Process-wide `SuppressAzurePowerShellBreakingChangeWarnings` and the
  `Update-AzConfig -DisplayBreakingChangeWarning $false` call added in 1.0.1.

## [1.0.1] - 2026-07-12

### Fixed

- StrictMode crashes on real tenants: null/`pscustomobject` tags no longer break
  `Get-AotResourceGroupInventory`, `Get-AotMissingTag`, `Get-AotEmptyResourceGroup`
  or `Get-AotResourceInventory` (new `Get-AotTagKey` helper).
- Role assignments for deleted principals (empty `DisplayName`) no longer abort
  RBAC, Owner and direct-user collectors; findings fall back to the object id.
- `Get-AotMonitorAlert` no longer fails on newer Az.Monitor output that dropped
  `ResourceGroupName` from scheduled-query rules; the resource group is derived
  from the ARM id. `Get-AotActionGroup`, `Get-AotDiagnosticSetting` and
  `Test-AotLogAnalytics` now probe version-dependent properties safely.
- `Get-AotResourceInventory` handles both Az.ResourceGraph result shapes
  (bare rows and `.Data`-wrapped responses).

### Added

- Per-subscription resilience: a failing subscription (e.g. AuthorizationFailed)
  is logged and skipped instead of aborting the whole collector
  (`Invoke-AotOperation -SkipOnError`).
- Subscription-scope caching: a full `New-AotReport` run now calls
  `Get-AzSubscription` once instead of once per collector, reducing ARM
  throttling. The cache clears on `Connect-AotAzure`.
- Az "upcoming breaking change" banners are suppressed for the process
  (`SuppressAzurePowerShellBreakingChangeWarnings`, plus `Update-AzConfig`
  best-effort in `Connect-AotAzure`).

## [1.0.0] - 2026-07-12

### Added

- **Core framework**: structured JSON logging (`Write-AotLog`), retry/error
  wrapper with exponential backoff (`Invoke-AotOperation`), normalised finding
  shape (`New-AotFinding`), subscription scoping, connection and configuration.
- **Inventory module**: resources, resource groups, RBAC role assignments,
  policy assignments, resource locks, tag usage.
- **Governance module**: owner assignments, direct user assignments, stale guest
  accounts, missing required tags, policy violations.
- **Security module**: Defender for Cloud plan coverage, PIM eligible/active
  assignments, expiring PIM roles, MFA registration gaps, Key Vault auditing.
- **Cost module**: unattached disks, idle public IPs, empty resource groups,
  reserved-instance (Advisor) recommendations.
- **Monitoring module**: diagnostic-setting coverage, Log Analytics validation,
  Azure Monitor alert rules, action groups.
- **Reports module**: HTML, CSV and JSON exporters plus `New-AotReport`
  orchestrator.
- Pester test suite, PSScriptAnalyzer configuration, task-based `build.ps1`,
  GitHub Actions CI (lint + test matrix) and tag-triggered PSGallery publish.

[Unreleased]: https://github.com/Lordkro/AzureOperationsToolkit/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/Lordkro/AzureOperationsToolkit/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/Lordkro/AzureOperationsToolkit/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Lordkro/AzureOperationsToolkit/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/Lordkro/AzureOperationsToolkit/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Lordkro/AzureOperationsToolkit/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Lordkro/AzureOperationsToolkit/releases/tag/v1.0.0

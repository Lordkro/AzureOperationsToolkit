# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/example/AzureOperationsToolkit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/example/AzureOperationsToolkit/releases/tag/v1.0.0

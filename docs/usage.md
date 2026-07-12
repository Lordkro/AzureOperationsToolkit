# Usage Guide

## Authentication

```powershell
# Interactive
Connect-AotAzure -TenantId <tenant> -SubscriptionId <sub>

# Managed identity (CI runner / Azure VM)
Connect-AotAzure -Identity

# Service principal
$cred = Get-Credential   # UserName = app (client) id, Password = secret
Connect-AotAzure -TenantId <tenant> -ServicePrincipalCredential $cred
```

For Graph-backed checks (stale guests, PIM, MFA), also connect Microsoft Graph
with the appropriate scopes:

```powershell
Connect-MgGraph -Scopes 'User.Read.All', 'AuditLog.Read.All',
                        'UserAuthenticationMethod.Read.All', 'RoleManagement.Read.Directory'
```

Per-command scope details are in the README's "Microsoft Graph permissions"
section; each Graph command also names its required scopes when it fails.

## Configuration

```powershell
Set-AotConfiguration `
    -LogLevel Information `      # Verbose | Information | Warning | Error
    -LogPath  ./logs `
    -ThrottleLimit 12 `         # parallel degree for resource-level lookups
    -MaxRetryCount 4 `
    -StaleGuestDays 60 `
    -PimExpiryWindowDays 7

Get-AotConfiguration
```

## Recipes

### Cost cleanup shortlist

```powershell
$cost  = Get-AotUnattachedDisk
$cost += Get-AotIdlePublicIp
$cost += Get-AotEmptyResourceGroup
$cost | Sort-Object Severity |
    Export-AotHtmlReport -Path ./out/cost.html -Title 'Cost cleanup'
```

### Security posture snapshot

```powershell
$sec  = Get-AotDefenderStatus
$sec += Get-AotKeyVaultAudit -WithinDays 30
$sec += Get-AotMfaGap
$sec += Get-AotExpiringPimRole -WithinDays 14
$sec | Export-AotJsonReport -Path ./out/security.json
```

### Governance / tagging audit

```powershell
Get-AotMissingTag -RequiredTag Owner, CostCenter, Environment |
    Export-AotCsvReport -Path ./out/missing-tags.csv

Get-AotOwnerAssignment | Where-Object Severity -eq 'High'
```

### Full multi-module assessment

```powershell
$summary = New-AotReport `
    -Module Inventory, Governance, Security, Cost, Monitoring `
    -Format Html, Csv, Json `
    -OutputPath ./out `
    -RequiredTag Owner, CostCenter

$summary.BySeverity        # counts per severity
$summary.Reports           # generated file paths
```

Use `-PassThru` to also get the raw aggregated findings back:

```powershell
$run = New-AotReport -OutputPath ./out -PassThru
$run.Findings | Where-Object Category -eq 'Security'
```

## Scoping to specific subscriptions

Every collector accepts `-SubscriptionId`:

```powershell
Get-AotResourceInventory -SubscriptionId '00000000-0000-0000-0000-000000000001',
                                          '00000000-0000-0000-0000-000000000002'
```

Omit it to sweep **all enabled subscriptions** in the current context.

## Scheduling

Run non-interactively (e.g. an Azure Automation runbook or GitHub Actions cron)
with a managed identity:

```powershell
Connect-AotAzure -Identity
Set-AotConfiguration -LogLevel Warning
New-AotReport -OutputPath $env:REPORT_DIR -Format Json, Html
```

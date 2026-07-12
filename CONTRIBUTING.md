# Contributing

Thanks for improving the Azure Operations Toolkit.

## Ground rules

- **One function per file**, named after the function, under `src/Public/<Module>`
  (exported) or `src/Private` (internal).
- Public collectors are **read-only** `Get-*` (or `Test-*`) verbs and must emit
  `New-AotFinding` objects — never write to Azure.
- Wrap every Azure call in `Invoke-AotOperation` so retries and logging are
  consistent.
- Log through `Write-AotLog`, not `Write-Host`.
- Support `-SubscriptionId` and default to all enabled subscriptions via
  `Get-AotSubscriptionScope`.

## Before opening a PR

```powershell
./build.ps1 -Task Analyze, Test
```

- PSScriptAnalyzer must report **zero errors**.
- Add or update Pester tests. Azure calls must be **mocked** — tests never touch
  a live tenant.
- Update `CHANGELOG.md` under `[Unreleased]`.
- Follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).

## Adding a new check

1. Create `src/Public/<Module>/Get-AotThing.ps1` with comment-based help and an
   `[OutputType([pscustomobject])]`.
2. Emit findings with `New-AotFinding`.
3. Register it in the exported list in `AzureOperationsToolkit.psd1` and, if it
   should run in full assessments, in `New-AotReport`'s collector map.
4. Add a mocked Pester test under `tests/`.

## Versioning

Semantic Versioning. Maintainers bump with `./build.ps1 -Task Version -BumpType
<Major|Minor|Patch>` and tag `vX.Y.Z` to publish.

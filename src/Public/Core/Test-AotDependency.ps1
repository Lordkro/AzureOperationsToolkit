function Test-AotDependency {
    <#
    .SYNOPSIS
        Reports which toolkit commands are usable with the modules installed,
        and optionally installs what is missing.

    .DESCRIPTION
        Each optional feature module (Defender status, Advisor recommendations,
        Log Analytics, Graph-based identity checks) requires an extra PowerShell
        module. A New-AotReport run silently skips collectors whose dependency
        is absent — this command makes those gaps visible up front.

    .PARAMETER InstallMissing
        Install every missing module from the PSGallery (CurrentUser scope).

    .EXAMPLE
        Test-AotDependency

    .EXAMPLE
        Test-AotDependency -InstallMissing
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$InstallMissing
    )

    $dependencies = @(
        [pscustomobject]@{ Module = 'Az.Accounts';                        Required = $true;  EnablesCommands = @('Connect-AotAzure', 'all collectors') }
        [pscustomobject]@{ Module = 'Az.Resources';                       Required = $true;  EnablesCommands = @('Get-AotResourceInventory', 'Get-AotResourceGroupInventory', 'Get-AotRoleAssignmentInventory', 'Get-AotPolicyInventory', 'Get-AotResourceLockInventory', 'Get-AotTagInventory', 'Get-AotOwnerAssignment', 'Get-AotDirectUserAssignment', 'Get-AotMissingTag', 'Get-AotEmptyResourceGroup') }
        [pscustomobject]@{ Module = 'Az.Compute';                         Required = $false; EnablesCommands = @('Get-AotUnattachedDisk') }
        [pscustomobject]@{ Module = 'Az.Network';                         Required = $false; EnablesCommands = @('Get-AotIdlePublicIp') }
        [pscustomobject]@{ Module = 'Az.KeyVault';                        Required = $false; EnablesCommands = @('Get-AotKeyVaultAudit') }
        [pscustomobject]@{ Module = 'Az.Monitor';                         Required = $false; EnablesCommands = @('Get-AotDiagnosticSetting', 'Get-AotMonitorAlert', 'Get-AotActionGroup') }
        [pscustomobject]@{ Module = 'Az.PolicyInsights';                  Required = $false; EnablesCommands = @('Get-AotPolicyViolation') }
        [pscustomobject]@{ Module = 'Az.Security';                        Required = $false; EnablesCommands = @('Get-AotDefenderStatus') }
        [pscustomobject]@{ Module = 'Az.Advisor';                         Required = $false; EnablesCommands = @('Get-AotReservedInstanceRecommendation') }
        [pscustomobject]@{ Module = 'Az.OperationalInsights';             Required = $false; EnablesCommands = @('Test-AotLogAnalytics') }
        [pscustomobject]@{ Module = 'Az.ResourceGraph';                   Required = $false; EnablesCommands = @('Get-AotResourceInventory (fast path)') }
        [pscustomobject]@{ Module = 'Microsoft.Graph.Authentication';     Required = $false; EnablesCommands = @('Connect-MgGraph for all Graph checks') }
        [pscustomobject]@{ Module = 'Microsoft.Graph.Users';              Required = $false; EnablesCommands = @('Get-AotStaleGuestAccount') }
        [pscustomobject]@{ Module = 'Microsoft.Graph.Reports';            Required = $false; EnablesCommands = @('Get-AotMfaGap') }
        [pscustomobject]@{ Module = 'Microsoft.Graph.Identity.Governance'; Required = $false; EnablesCommands = @('Get-AotPimAssignment', 'Get-AotExpiringPimRole') }
    )

    foreach ($dep in $dependencies) {
        $installed = Get-Module -ListAvailable -Name $dep.Module |
            Sort-Object Version -Descending | Select-Object -First 1

        if (-not $installed -and $InstallMissing -and
            $PSCmdlet.ShouldProcess($dep.Module, 'Install-Module from PSGallery (CurrentUser)')) {
            Write-AotLog -Level Information -Operation 'Dependency' -Message "Installing $($dep.Module)"
            try {
                Install-Module -Name $dep.Module -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
                $installed = Get-Module -ListAvailable -Name $dep.Module |
                    Sort-Object Version -Descending | Select-Object -First 1
            }
            catch {
                Write-AotLog -Level Warning -Operation 'Dependency' `
                    -Message "Install of $($dep.Module) failed: $($_.Exception.Message)"
            }
        }

        [pscustomobject]@{
            PSTypeName      = 'Aot.Dependency'
            Module          = $dep.Module
            Required        = $dep.Required
            Installed       = [bool]$installed
            Version         = $installed.Version
            EnablesCommands = $dep.EnablesCommands
        }
    }
}

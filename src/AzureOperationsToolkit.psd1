@{
    RootModule        = 'AzureOperationsToolkit.psm1'
    ModuleVersion     = '1.1.3'
    GUID              = 'b8f4c2e1-6a3d-4f9e-9c1b-7d5e2a8f0c4a'
    Author            = 'Azure Operations Toolkit Contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) Azure Operations Toolkit Contributors. All rights reserved.'
    Description       = 'Production-grade PowerShell toolkit for Azure inventory, governance, security, cost, monitoring and reporting operations.'
    PowerShellVersion = '7.5'

    RequiredModules   = @(
        @{ ModuleName = 'Az.Accounts';    ModuleVersion = '3.0.0' }
        @{ ModuleName = 'Az.Resources';   ModuleVersion = '7.0.0' }
    )

    # Loaded on demand by the root module; listed here for discoverability.
    FunctionsToExport = @(
        # Inventory
        'Get-AotResourceInventory'
        'Get-AotResourceGroupInventory'
        'Get-AotRoleAssignmentInventory'
        'Get-AotPolicyInventory'
        'Get-AotResourceLockInventory'
        'Get-AotTagInventory'
        # Governance
        'Get-AotOwnerAssignment'
        'Get-AotDirectUserAssignment'
        'Get-AotStaleGuestAccount'
        'Get-AotMissingTag'
        'Get-AotPolicyViolation'
        # Security
        'Get-AotDefenderStatus'
        'Get-AotPimAssignment'
        'Get-AotExpiringPimRole'
        'Get-AotMfaGap'
        'Get-AotKeyVaultAudit'
        # Cost
        'Get-AotUnattachedDisk'
        'Get-AotIdlePublicIp'
        'Get-AotEmptyResourceGroup'
        'Get-AotReservedInstanceRecommendation'
        # Monitoring
        'Get-AotDiagnosticSetting'
        'Test-AotLogAnalytics'
        'Get-AotMonitorAlert'
        'Get-AotActionGroup'
        # Reports
        'New-AotReport'
        'Export-AotHtmlReport'
        'Export-AotCsvReport'
        'Export-AotJsonReport'
        # Core
        'Connect-AotAzure'
        'Set-AotConfiguration'
        'Get-AotConfiguration'
        'Test-AotDependency'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Azure', 'Governance', 'Security', 'Cost', 'Monitoring', 'FinOps', 'Inventory')
            LicenseUri   = 'https://github.com/example/AzureOperationsToolkit/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/example/AzureOperationsToolkit'
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}

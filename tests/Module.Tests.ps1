#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $script:ManifestPath = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psd1' | Resolve-Path
    # Import the root module directly so the suite runs without the Az RequiredModules
    # present (they are mocked in tests). The manifest is still asserted on separately.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psm1' | Resolve-Path
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module AzureOperationsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'has a valid manifest' {
        # Az modules may not be installed in CI; test structure not dependency load.
        $data = Import-PowerShellDataFile -Path $script:ManifestPath
        $data.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
        $data.PowerShellVersion | Should -Be '7.5'
    }

    It 'declares GUID' {
        $data = Import-PowerShellDataFile -Path $script:ManifestPath
        $data.GUID | Should -Not -BeNullOrEmpty
    }
}

Describe 'Public surface' {
    It 'exports the expected collector functions' {
        $exported = (Get-Command -Module AzureOperationsToolkit).Name
        $expected = @(
            'Get-AotResourceInventory', 'Get-AotOwnerAssignment', 'Get-AotDefenderStatus',
            'Get-AotUnattachedDisk', 'Get-AotDiagnosticSetting', 'New-AotReport',
            'Connect-AotAzure', 'Set-AotConfiguration', 'Get-AotConfiguration',
            'Test-AotDependency'
        )
        foreach ($fn in $expected) { $exported | Should -Contain $fn }
    }

    It 'keeps private helpers private' {
        (Get-Command -Module AzureOperationsToolkit).Name | Should -Not -Contain 'New-AotFinding'
        (Get-Command -Module AzureOperationsToolkit).Name | Should -Not -Contain 'Invoke-AotOperation'
    }
}

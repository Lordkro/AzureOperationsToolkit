#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $module = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psm1' | Resolve-Path
    Import-Module $module -Force
}

AfterAll {
    Remove-Module AzureOperationsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AotResourceInventory (mocked Azure)' {
    It 'emits one Inventory/Resource finding per resource, per subscription' {
        InModuleScope AzureOperationsToolkit {
            # Force the Get-AzResource fallback path (no Resource Graph).
            Mock Get-Command -ParameterFilter { $Name -eq 'Search-AzGraph' } -MockWith { $null }
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription {
                @([pscustomobject]@{ Id = 's1'; Name = 'Sub A'; State = 'Enabled' })
            }
            Mock Set-AzContext { }
            Mock Get-AzResource {
                @(
                    [pscustomobject]@{ Name = 'vm1'; ResourceId = '/x/vm1'; ResourceGroupName = 'rg1'; Location = 'eastus'; ResourceType = 'Microsoft.Compute/virtualMachines'; Tags = @{ Owner = 'a' } },
                    [pscustomobject]@{ Name = 'sa1'; ResourceId = '/x/sa1'; ResourceGroupName = 'rg1'; Location = 'eastus'; ResourceType = 'Microsoft.Storage/storageAccounts'; Tags = $null }
                )
            }

            $findings = Get-AotResourceInventory

            $findings.Count | Should -Be 2
            $findings[0].Category | Should -Be 'Inventory'
            $findings[0].Type | Should -Be 'Resource'
            ($findings | Where-Object Name -eq 'vm1').Detail.TagCount | Should -Be 1
        }
    }
}

Describe 'Get-AotUnattachedDisk (mocked Azure)' {
    It 'returns only Unattached disks with no owner' {
        InModuleScope AzureOperationsToolkit {
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 's1'; Name = 'Sub A'; State = 'Enabled' }) }
            Mock Set-AzContext { }
            Mock Get-AzDisk {
                @(
                    [pscustomobject]@{ Name = 'd1'; Id = '/x/d1'; ResourceGroupName = 'rg'; Location = 'eastus'; DiskState = 'Unattached'; ManagedBy = $null; DiskSizeGB = 64; Sku = @{ Name = 'Premium_LRS' }; TimeCreated = (Get-Date) },
                    [pscustomobject]@{ Name = 'd2'; Id = '/x/d2'; ResourceGroupName = 'rg'; Location = 'eastus'; DiskState = 'Attached'; ManagedBy = '/x/vm'; DiskSizeGB = 128; Sku = @{ Name = 'Premium_LRS' }; TimeCreated = (Get-Date) }
                )
            }

            $findings = Get-AotUnattachedDisk
            $findings.Count | Should -Be 1
            $findings[0].Name | Should -Be 'd1'
            $findings[0].Category | Should -Be 'Cost'
            $findings[0].Detail.DiskSizeGB | Should -Be 64
        }
    }
}

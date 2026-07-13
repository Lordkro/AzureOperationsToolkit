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
            $script:AotSubscriptionCache.Clear()
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

Describe 'Get-AotResourceGroupInventory (mocked Azure)' {
    It 'survives resource groups with null tags' {
        InModuleScope AzureOperationsToolkit {
            # each test mocks a different subscription set; do not leak the scope cache
            $script:AotSubscriptionCache.Clear()
            # force the per-subscription path; the Resource Graph fast path would hit live Azure
            Mock Get-Command -ParameterFilter { $Name -eq 'Search-AzGraph' } -MockWith { $null }
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 's1'; Name = 'Sub A'; State = 'Enabled' }) }
            Mock Set-AzContext { }
            Mock Get-AzResourceGroup {
                @(
                    [pscustomobject]@{ ResourceGroupName = 'rg1'; ResourceId = '/x/rg1'; Location = 'eastus'; ProvisioningState = 'Succeeded'; Tags = $null },
                    [pscustomobject]@{ ResourceGroupName = 'rg2'; ResourceId = '/x/rg2'; Location = 'eastus'; ProvisioningState = 'Succeeded'; Tags = @{ Owner = 'a' } }
                )
            }
            Mock Get-AzResource { @() }

            $findings = Get-AotResourceGroupInventory
            $findings.Count | Should -Be 2
            ($findings | Where-Object Name -eq 'rg1').Detail.TagCount | Should -Be 0
            ($findings | Where-Object Name -eq 'rg2').Detail.TagCount | Should -Be 1
        }
    }
}

Describe 'Get-AotRoleAssignmentInventory (mocked Azure)' {
    It 'survives deleted principals with an empty DisplayName' {
        InModuleScope AzureOperationsToolkit {
            # each test mocks a different subscription set; do not leak the scope cache
            $script:AotSubscriptionCache.Clear()
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 's1'; Name = 'Sub A'; State = 'Enabled' }) }
            Mock Set-AzContext { }
            Mock Get-AzRoleAssignment {
                @(
                    [pscustomobject]@{ DisplayName = ''; ObjectId = 'deleted-guid'; RoleAssignmentId = '/x/ra1'; RoleDefinitionName = 'Reader'; ObjectType = 'Unknown'; SignInName = $null; Scope = '/subscriptions/s1'; CanDelegate = $false },
                    [pscustomobject]@{ DisplayName = 'Alice'; ObjectId = 'g2'; RoleAssignmentId = '/x/ra2'; RoleDefinitionName = 'Owner'; ObjectType = 'User'; SignInName = 'a@x.com'; Scope = '/subscriptions/s1'; CanDelegate = $false }
                )
            }

            $findings = Get-AotRoleAssignmentInventory
            $findings.Count | Should -Be 2
            $findings[0].Name | Should -Be 'deleted-guid'
            $findings[1].Name | Should -Be 'Alice'
        }
    }
}

Describe 'Per-subscription isolation' {
    It 'continues with remaining subscriptions when one fails' {
        InModuleScope AzureOperationsToolkit {
            # each test mocks a different subscription set; do not leak the scope cache
            $script:AotSubscriptionCache.Clear()
            # Force the sequential sweep path: Pester mocks do not propagate
            # into parallel runspaces.
            Set-AotConfiguration -ThrottleLimit 1 | Out-Null
            # force the per-subscription path; the Resource Graph fast path would hit live Azure
            Mock Get-Command -ParameterFilter { $Name -eq 'Search-AzGraph' } -MockWith { $null }
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription {
                @(
                    [pscustomobject]@{ Id = 'bad'; Name = 'Sub Bad'; State = 'Enabled' },
                    [pscustomobject]@{ Id = 'good'; Name = 'Sub Good'; State = 'Enabled' }
                )
            }
            # -SubscriptionId binds to Set-AzContext's -Subscription via alias.
            Mock Set-AzContext { if ($Subscription -eq 'bad') { throw 'AuthorizationFailed' } }
            Mock Get-AzDisk {
                @([pscustomobject]@{ Name = 'd1'; Id = '/x/d1'; ResourceGroupName = 'rg'; Location = 'eastus'; DiskState = 'Unattached'; ManagedBy = $null; DiskSizeGB = 64; Sku = @{ Name = 'Premium_LRS' }; TimeCreated = (Get-Date) })
            }

            $findings = Get-AotUnattachedDisk 3>$null
            @($findings).Count | Should -Be 1
            $findings[0].SubscriptionName | Should -Be 'Sub Good'

            Set-AotConfiguration -ThrottleLimit 8 | Out-Null
        }
    }
}

Describe 'Get-AotUnattachedDisk (mocked Azure)' {
    It 'returns only Unattached disks with no owner' {
        InModuleScope AzureOperationsToolkit {
            # each test mocks a different subscription set; do not leak the scope cache
            $script:AotSubscriptionCache.Clear()
            # force the per-subscription path; the Resource Graph fast path would hit live Azure
            Mock Get-Command -ParameterFilter { $Name -eq 'Search-AzGraph' } -MockWith { $null }
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

#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $module = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psm1' | Resolve-Path
    Import-Module $module -Force
}

AfterAll {
    Remove-Module AzureOperationsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'New-AotFinding' {
    It 'produces a normalised finding shape' {
        InModuleScope AzureOperationsToolkit {
            $f = New-AotFinding -Category 'Cost' -Type 'UnattachedDisk' -Name 'disk1' `
                -Severity 'Low' -Detail @{ DiskSizeGB = 128 }
            $f.PSObject.TypeNames | Should -Contain 'Aot.Finding'
            $f.Category | Should -Be 'Cost'
            $f.Severity | Should -Be 'Low'
            $f.Detail.DiskSizeGB | Should -Be 128
            $f.CollectedAt | Should -Not -BeNullOrEmpty
        }
    }

    It 'rejects an invalid severity' {
        InModuleScope AzureOperationsToolkit {
            { New-AotFinding -Category 'X' -Type 'Y' -Name 'Z' -Severity 'Bogus' } | Should -Throw
        }
    }
}

Describe 'Invoke-AotOperation retry' {
    It 'returns the scriptblock result on success' {
        InModuleScope AzureOperationsToolkit {
            Invoke-AotOperation -Operation 'ok' -ScriptBlock { 42 } | Should -Be 42
        }
    }

    It 'retries transient failures then succeeds' {
        InModuleScope AzureOperationsToolkit {
            $script:attempts = 0
            $result = Invoke-AotOperation -Operation 'transient' -RetryDelaySeconds 0 -ScriptBlock {
                $script:attempts++
                if ($script:attempts -lt 3) { throw 'TooManyRequests: throttled' }
                'done'
            }
            $result | Should -Be 'done'
            $script:attempts | Should -Be 3
        }
    }

    It 'does not retry non-transient failures' {
        InModuleScope AzureOperationsToolkit {
            $script:attempts = 0
            {
                Invoke-AotOperation -Operation 'fatal' -ScriptBlock {
                    $script:attempts++
                    throw 'AuthorizationFailed'
                }
            } | Should -Throw
            $script:attempts | Should -Be 1
        }
    }
}

Describe 'Configuration' {
    It 'updates only supplied keys' {
        $before = Get-AotConfiguration
        Set-AotConfiguration -ThrottleLimit 16 -LogLevel Warning | Out-Null
        $after = Get-AotConfiguration
        $after.ThrottleLimit | Should -Be 16
        $after.LogLevel | Should -Be 'Warning'
        $after.MaxRetryCount | Should -Be $before.MaxRetryCount
    }

    It 'validates ranges' {
        { Set-AotConfiguration -ThrottleLimit 0 } | Should -Throw
    }
}

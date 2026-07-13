#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $module = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psm1' | Resolve-Path
    Import-Module $module -Force
}

AfterAll {
    Remove-Module AzureOperationsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AotStaleGuestAccount role gating' -Skip:(-not (Get-Command Get-MgUser -ErrorAction SilentlyContinue)) {
    It 'translates the SignInActivity 403 into the directory-role requirement' {
        InModuleScope AzureOperationsToolkit {
            Mock Get-MgContext { [pscustomobject]@{ Scopes = @('User.Read.All', 'AuditLog.Read.All') } }
            Mock Get-MgUser { throw 'User is not in the allowed roles  Status: 403 (Forbidden) ErrorCode: Authentication_RequestFromUnsupportedUserRole' }

            { Get-AotStaleGuestAccount } | Should -Throw '*Global Reader, Reports Reader, Security Reader*'
        }
    }

    It 'flags never-signed-in and stale guests, skips active ones' {
        InModuleScope AzureOperationsToolkit {
            Mock Get-MgContext { [pscustomobject]@{ Scopes = @('User.Read.All', 'AuditLog.Read.All') } }
            Mock Get-MgUser {
                @(
                    [pscustomobject]@{ Id = 'g1'; DisplayName = 'Never'; UserPrincipalName = 'n@x'; CreatedDateTime = (Get-Date).AddYears(-1); AccountEnabled = $true; SignInActivity = [pscustomobject]@{ LastSignInDateTime = $null } },
                    [pscustomobject]@{ Id = 'g2'; DisplayName = 'Stale'; UserPrincipalName = 's@x'; CreatedDateTime = (Get-Date).AddYears(-1); AccountEnabled = $true; SignInActivity = [pscustomobject]@{ LastSignInDateTime = (Get-Date).AddDays(-200) } },
                    [pscustomobject]@{ Id = 'g3'; DisplayName = 'Active'; UserPrincipalName = 'a@x'; CreatedDateTime = (Get-Date).AddYears(-1); AccountEnabled = $true; SignInActivity = [pscustomobject]@{ LastSignInDateTime = (Get-Date).AddDays(-2) } }
                )
            }

            $findings = Get-AotStaleGuestAccount -StaleDays 90
            @($findings).Count | Should -Be 2
            @($findings).Name | Should -Not -Contain 'Active'
            (@($findings) | Where-Object Name -eq 'Never').Detail.LastSignInDateTime | Should -Be 'Never'
        }
    }
}

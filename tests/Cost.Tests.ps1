#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $module = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psm1' | Resolve-Path
    Import-Module $module -Force
}

AfterAll {
    Remove-Module AzureOperationsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AotReservedInstanceRecommendation (mocked Azure)' -Skip:(-not (Get-Command Get-AzAdvisorRecommendation -ErrorAction SilentlyContinue)) {
    It 'uses -Filter on Az.Advisor 3.x and reads the typed ExtendedProperty shape' {
        InModuleScope AzureOperationsToolkit {
            $script:AotSubscriptionCache.Clear()
            # Force the per-subscription fallback: the Resource Graph fast path
            # would hit live Azure, so make it fail and exercise the fallback.
            if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
                Mock Search-AzGraph { throw 'graph disabled for test' }
            }
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 's1'; Name = 'Sub A'; State = 'Enabled' }) }
            Mock Set-AzContext { }
            Mock Get-AzAdvisorRecommendation {
                # Az.Advisor 3.x autorest shape: no ResourceId property,
                # ExtendedProperty is a typed object rather than a hashtable.
                @([pscustomobject]@{
                    Name                     = 'rec1'
                    Id                       = '/subscriptions/s1/providers/Microsoft.Advisor/recommendations/rec1'
                    ShortDescriptionProblem  = 'You could save money'
                    ShortDescriptionSolution = 'Buy a reservation'
                    Impact                   = 'High'
                    ExtendedProperty         = [pscustomobject]@{
                        annualSavingsAmount = '1234.56'
                        savingsCurrency     = 'USD'
                        term                = 'P3Y'
                        lookbackPeriod      = '30'
                    }
                })
            }

            $findings = Get-AotReservedInstanceRecommendation

            # Az.Advisor 3.x exposes -Filter; the collector must use it there.
            $cmd = Get-Command Get-AzAdvisorRecommendation
            if ($cmd.Parameters.ContainsKey('Filter')) {
                Should -Invoke Get-AzAdvisorRecommendation -Times 1 -Exactly -ParameterFilter {
                    $Filter -eq "Category eq 'Cost'"
                }
            }

            @($findings).Count | Should -Be 1
            $findings[0].Name | Should -Be 'Buy a reservation'
            $findings[0].ResourceId | Should -Match '/recommendations/rec1$'
            $findings[0].Detail.AnnualSavings | Should -Be '1234.56'
            $findings[0].Detail.Term | Should -Be 'P3Y'
        }
    }

    It 'reads a hashtable ExtendedProperty (Az.Advisor 2.x shape)' {
        InModuleScope AzureOperationsToolkit {
            $script:AotSubscriptionCache.Clear()
            # Force the per-subscription fallback: the Resource Graph fast path
            # would hit live Azure, so make it fail and exercise the fallback.
            if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
                Mock Search-AzGraph { throw 'graph disabled for test' }
            }
            Mock Get-AzContext { [pscustomobject]@{ Account = 'test' } }
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 's1'; Name = 'Sub A'; State = 'Enabled' }) }
            Mock Set-AzContext { }
            Mock Get-AzAdvisorRecommendation {
                @([pscustomobject]@{
                    Name                     = 'rec2'
                    ResourceId               = '/x/rec2'
                    ShortDescriptionProblem  = 'p'
                    ShortDescriptionSolution = 's'
                    Impact                   = 'Medium'
                    ExtendedProperty         = @{ annualSavingsAmount = '99'; savingsCurrency = 'EUR' }
                })
            }

            $findings = Get-AotReservedInstanceRecommendation
            @($findings).Count | Should -Be 1
            $findings[0].ResourceId | Should -Be '/x/rec2'
            $findings[0].Detail.AnnualSavings | Should -Be '99'
            $findings[0].Detail.SavingsCurrency | Should -Be 'EUR'
        }
    }
}

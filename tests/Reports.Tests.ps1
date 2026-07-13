#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $module = Join-Path $PSScriptRoot '..' 'src' 'AzureOperationsToolkit.psm1' | Resolve-Path
    Import-Module $module -Force

    $script:sample = @(
        [pscustomobject]@{
            PSTypeName = 'Aot.Finding'; Category = 'Cost'; Type = 'UnattachedDisk'
            Name = 'disk1'; Severity = 'Low'; SubscriptionName = 'Sub A'; SubscriptionId = 's1'
            ResourceGroup = 'rg1'; Location = 'eastus'; ResourceId = '/x/disk1'
            Detail = [pscustomobject]@{ DiskSizeGB = 128 }; CollectedAt = (Get-Date).ToString('o')
        },
        [pscustomobject]@{
            PSTypeName = 'Aot.Finding'; Category = 'Security'; Type = 'MfaGap'
            Name = 'user1'; Severity = 'High'; SubscriptionName = 'Sub A'; SubscriptionId = 's1'
            ResourceGroup = $null; Location = $null; ResourceId = 'u1'
            Detail = [pscustomobject]@{ UserPrincipalName = 'user1@x.com <script>' }; CollectedAt = (Get-Date).ToString('o')
        }
    )
    $script:outDir = Join-Path $TestDrive 'reports'
}

AfterAll {
    Remove-Module AzureOperationsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Export-AotJsonReport' {
    It 'writes valid JSON with all findings' {
        $path = Join-Path $script:outDir 'r.json'
        $script:sample | Export-AotJsonReport -Path $path | Out-Null
        Test-Path $path | Should -BeTrue
        $data = Get-Content $path -Raw | ConvertFrom-Json
        $data.Count | Should -Be 2
        $data.Findings[0].Category | Should -Be 'Cost'
    }
}

Describe 'Export-AotCsvReport' {
    It 'writes a CSV row per finding with a serialised Detail column' {
        $path = Join-Path $script:outDir 'r.csv'
        $script:sample | Export-AotCsvReport -Path $path | Out-Null
        $rows = Import-Csv $path
        $rows.Count | Should -Be 2
        $rows[0].Detail | Should -Match 'DiskSizeGB'
    }
}

Describe 'Export-AotHtmlReport' {
    It 'writes HTML and encodes untrusted content' {
        $path = Join-Path $script:outDir 'r.html'
        $script:sample | Export-AotHtmlReport -Path $path -Title 'Test' | Out-Null
        $html = Get-Content $path -Raw
        $html | Should -Match '<title>Test</title>'
        # The raw <script> payload from the detail must be HTML-encoded, not
        # injected literally (the page's own sorting <script> is expected).
        $html | Should -Not -Match 'user1@x\.com <script>'
        $html | Should -Match 'user1@x\.com &lt;script&gt;'
    }

    It 'renders sortable headers, severity tiles and filters' {
        $path = Join-Path $script:outDir 'r2.html'
        $script:sample | Export-AotHtmlReport -Path $path | Out-Null
        $html = Get-Content $path -Raw
        $html | Should -Match 'aria-sort'
        $html | Should -Match "class='tile' data-sev='High'"
        $html | Should -Match 'id="sev"'
        $html | Should -Match 'id="cat"'
        # detail rendered as key/value pairs, not a JSON blob
        $html | Should -Match "class='kv'"
    }
}

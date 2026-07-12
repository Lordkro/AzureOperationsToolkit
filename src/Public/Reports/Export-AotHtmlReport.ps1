function Export-AotHtmlReport {
    <#
    .SYNOPSIS
        Renders findings into a self-contained, styled HTML report.

    .DESCRIPTION
        Groups findings by category, shows a severity summary and a sortable-ish
        table per category. No external assets — CSS is inlined so the file opens
        anywhere.

    .PARAMETER Finding
        Aot.Finding objects (accepts pipeline input).

    .PARAMETER Path
        Destination .html file path.

    .PARAMETER Title
        Report heading.

    .EXAMPLE
        Get-AotDefenderStatus | Export-AotHtmlReport -Path .\defender.html
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject[]]$Finding,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Title = 'Azure Operations Toolkit Report'
    )

    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($f in $Finding) { $all.Add($f) } }
    end {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

        $sevColors = @{
            Critical = '#7f1d1d'; High = '#b91c1c'; Medium = '#c2760c'
            Low = '#2563eb'; Informational = '#4b5563'
        }
        $sevOrder = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Informational = 4 }

        # Severity summary tiles.
        $bySeverity = $all | Group-Object Severity
        $tiles = foreach ($sev in ($bySeverity | Sort-Object { $sevOrder[$_.Name] })) {
            $color = $sevColors[$sev.Name] ?? '#4b5563'
            "<div class='tile' style='border-left:6px solid $color'><span class='num'>$($sev.Count)</span><span class='lbl'>$(& $enc $sev.Name)</span></div>"
        }

        # One section per category.
        $sections = foreach ($cat in ($all | Group-Object Category | Sort-Object Name)) {
            $rows = foreach ($f in ($cat.Group | Sort-Object { $sevOrder[$_.Severity] })) {
                $color = $sevColors[$f.Severity] ?? '#4b5563'
                $detailJson = & $enc ($f.Detail | ConvertTo-Json -Compress -Depth 6)
                @"
<tr>
<td><span class='badge' style='background:$color'>$(& $enc $f.Severity)</span></td>
<td>$(& $enc $f.Type)</td>
<td>$(& $enc $f.Name)</td>
<td>$(& $enc $f.SubscriptionName)</td>
<td>$(& $enc $f.ResourceGroup)</td>
<td>$(& $enc $f.Location)</td>
<td class='detail'>$detailJson</td>
</tr>
"@
            }
            @"
<section>
<h2>$(& $enc $cat.Name) <span class='count'>$($cat.Count)</span></h2>
<div class='tablewrap'>
<table>
<thead><tr><th>Severity</th><th>Type</th><th>Name</th><th>Subscription</th><th>Resource Group</th><th>Location</th><th>Detail</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
</div>
</section>
"@
        }

        $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>$(& $enc $Title)</title>
<style>
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body { font-family: -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 2rem; background: #f8fafc; color: #0f172a; }
@media (prefers-color-scheme: dark) { body { background: #0b1120; color: #e2e8f0; } table { background: #111827; } th { background: #1f2937 !important; } .detail { color: #94a3b8; } }
h1 { margin: 0 0 .25rem; font-size: 1.6rem; }
.meta { color: #64748b; margin-bottom: 1.5rem; font-size: .9rem; }
.tiles { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 2rem; }
.tile { background: #fff; border-radius: 8px; padding: 1rem 1.25rem; min-width: 120px; box-shadow: 0 1px 3px rgba(0,0,0,.1); display: flex; flex-direction: column; }
@media (prefers-color-scheme: dark) { .tile { background: #111827; } }
.tile .num { font-size: 1.8rem; font-weight: 700; }
.tile .lbl { color: #64748b; font-size: .8rem; text-transform: uppercase; letter-spacing: .05em; }
section { margin-bottom: 2.5rem; }
h2 { font-size: 1.15rem; border-bottom: 2px solid #e2e8f0; padding-bottom: .4rem; }
h2 .count { background: #e2e8f0; color: #334155; border-radius: 999px; padding: .1rem .6rem; font-size: .8rem; margin-left: .5rem; }
.tablewrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; background: #fff; font-size: .85rem; border-radius: 8px; overflow: hidden; }
th, td { text-align: left; padding: .55rem .7rem; border-bottom: 1px solid #e2e8f0; vertical-align: top; }
th { background: #f1f5f9; font-weight: 600; position: sticky; top: 0; }
.badge { color: #fff; padding: .15rem .55rem; border-radius: 999px; font-size: .72rem; font-weight: 600; }
.detail { font-family: ui-monospace, Consolas, monospace; font-size: .72rem; color: #475569; max-width: 420px; word-break: break-word; }
</style>
</head>
<body>
<h1>$(& $enc $Title)</h1>
<div class='meta'>Generated $(& $enc ((Get-Date).ToString('u'))) &middot; $($all.Count) finding(s)</div>
<div class='tiles'>
$($tiles -join "`n")
</div>
$($sections -join "`n")
</body>
</html>
"@

        $html | Set-Content -Path $Path -Encoding utf8
        Write-AotLog -Level Information -Operation 'Report' -Message "Wrote $($all.Count) findings to HTML: $Path"
        Get-Item $Path
    }
}

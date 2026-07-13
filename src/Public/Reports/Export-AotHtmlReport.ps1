function Export-AotHtmlReport {
    <#
    .SYNOPSIS
        Renders findings into a self-contained, dark-mode-first HTML dashboard.

    .DESCRIPTION
        Produces a single file with no external assets: severity stat tiles,
        a filter row (search, severity, category) and one unified findings
        table with click-to-sort columns. Light mode is derived from the same
        roles via prefers-color-scheme.

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

        # Status palette (never color-alone: every badge pairs the dot with text).
        $sevMeta = [ordered]@{
            Critical      = @{ Rank = 0; Color = '#d03b3b' }
            High          = @{ Rank = 1; Color = '#ec835a' }
            Medium        = @{ Rank = 2; Color = '#fab219' }
            Low           = @{ Rank = 3; Color = '#3987e5' }
            Informational = @{ Rank = 4; Color = '#898781' }
        }

        $fmtValue = {
            param($v)
            if ($null -eq $v) { return '' }
            if ($v -is [string] -or $v.GetType().IsValueType) { return [string]$v }
            try { return ($v | ConvertTo-Json -Compress -Depth 4) } catch { return [string]$v }
        }

        # --- severity tiles ---
        $counts = @{}
        foreach ($f in $all) { $counts[[string]$f.Severity] = 1 + ($counts[[string]$f.Severity] ?? 0) }
        $tileSb = [System.Text.StringBuilder]::new()
        foreach ($sev in $sevMeta.Keys) {
            $n = $counts[$sev] ?? 0
            [void]$tileSb.AppendLine(
                "<button class='tile' data-sev='$sev' title='Filter to $sev'>" +
                "<span class='tile-num'>$n</span>" +
                "<span class='tile-lbl'><span class='dot' style='background:$($sevMeta[$sev].Color)'></span>$sev</span>" +
                '</button>')
        }

        # --- category filter options ---
        $catOptions = ($all | Group-Object Category | Sort-Object Name | ForEach-Object {
            "<option value='$(& $enc $_.Name)'>$(& $enc $_.Name) ($($_.Count))</option>"
        }) -join "`n"

        # --- table rows ---
        $rowSb = [System.Text.StringBuilder]::new()
        foreach ($f in $all) {
            $sev = [string]$f.Severity
            $meta = $sevMeta[$sev] ?? @{ Rank = 9; Color = '#898781' }

            # Detail as readable key/value pairs; overflow behind <details>.
            $pairs = @(
                foreach ($p in $f.Detail.PSObject.Properties) {
                    $val = & $fmtValue $p.Value
                    if ([string]::IsNullOrEmpty($val)) { continue }
                    "<div class='kv'><span class='k'>$(& $enc $p.Name)</span><span class='v'>$(& $enc $val)</span></div>"
                }
            )
            $detailHtml =
                if ($pairs.Count -le 3) { $pairs -join '' }
                else {
                    ($pairs[0..2] -join '') +
                    "<details><summary>+$($pairs.Count - 3) more</summary>" + ($pairs[3..($pairs.Count - 1)] -join '') + '</details>'
                }

            [void]$rowSb.AppendLine(
                "<tr data-sev='$sev' data-cat='$(& $enc $f.Category)'>" +
                "<td data-sort='$($meta.Rank)'><span class='badge'><span class='dot' style='background:$($meta.Color)'></span>$(& $enc $sev)</span></td>" +
                "<td>$(& $enc $f.Category)</td>" +
                "<td>$(& $enc $f.Type)</td>" +
                "<td class='strong' title='$(& $enc $f.ResourceId)'>$(& $enc $f.Name)</td>" +
                "<td>$(& $enc $f.SubscriptionName)</td>" +
                "<td>$(& $enc $f.ResourceGroup)</td>" +
                "<td>$(& $enc $f.Location)</td>" +
                "<td class='detail'>$detailHtml</td>" +
                '</tr>')
        }

        # Single-quoted template; PowerShell values are injected via token
        # replacement so the CSS/JS below needs no escaping.
        $template = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root {
  color-scheme: dark;
  --plane: #0d0d0d; --surface: #1a1a19;
  --ink: #ffffff; --ink-2: #c3c2b7; --muted: #898781;
  --grid: #2c2c2a; --border: rgba(255,255,255,.10);
  --hover: rgba(255,255,255,.05); --accent: #3987e5;
}
@media (prefers-color-scheme: light) {
  :root {
    color-scheme: light;
    --plane: #f9f9f7; --surface: #fcfcfb;
    --ink: #0b0b0b; --ink-2: #52514e; --muted: #898781;
    --grid: #e1e0d9; --border: rgba(11,11,11,.10);
    --hover: rgba(11,11,11,.04); --accent: #2a78d6;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 24px; background: var(--plane); color: var(--ink);
  font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif;
}
main { max-width: 1500px; margin: 0 auto; }
h1 { margin: 0; font-size: 20px; font-weight: 650; letter-spacing: -.01em; }
.meta { color: var(--muted); font-size: 12.5px; margin: 4px 0 20px; }

.tiles { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 20px; }
.tile {
  display: flex; flex-direction: column; gap: 2px; min-width: 128px;
  padding: 14px 16px; text-align: left; cursor: pointer;
  background: var(--surface); color: var(--ink);
  border: 1px solid var(--border); border-radius: 10px;
  font: inherit; transition: border-color .15s;
}
.tile:hover { border-color: var(--muted); }
.tile.active { border-color: var(--accent); outline: 1px solid var(--accent); }
.tile-num { font-size: 26px; font-weight: 650; }
.tile-lbl { display: flex; align-items: center; gap: 6px; color: var(--ink-2); font-size: 12px; }

.dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; flex: none; }

.filters { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; margin-bottom: 14px; }
.filters input[type=search], .filters select {
  background: var(--surface); color: var(--ink);
  border: 1px solid var(--border); border-radius: 8px;
  padding: 8px 10px; font: inherit; font-size: 13px;
}
.filters input[type=search] { width: 300px; }
.filters input[type=search]:focus, .filters select:focus { outline: 1px solid var(--accent); border-color: var(--accent); }
.count { color: var(--muted); font-size: 12.5px; margin-left: auto; }
.reset { background: none; border: none; color: var(--accent); cursor: pointer; font: inherit; font-size: 12.5px; padding: 4px; }

.tablewrap { overflow: auto; max-height: calc(100vh - 260px); background: var(--surface); border: 1px solid var(--border); border-radius: 10px; }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
thead th {
  position: sticky; top: 0; z-index: 1; background: var(--surface);
  text-align: left; font-weight: 600; color: var(--ink-2); white-space: nowrap;
  padding: 10px 12px; border-bottom: 1px solid var(--grid); cursor: pointer; user-select: none;
}
thead th:hover { color: var(--ink); }
thead th::after { content: ''; display: inline-block; width: 1em; color: var(--accent); }
thead th[aria-sort=ascending]::after { content: ' \2191'; }
thead th[aria-sort=descending]::after { content: ' \2193'; }
tbody td { padding: 9px 12px; border-bottom: 1px solid var(--grid); vertical-align: top; color: var(--ink-2); }
tbody tr:hover td { background: var(--hover); }
tbody tr:last-child td { border-bottom: none; }
td:nth-child(1), td:nth-child(2), td:nth-child(3), td:nth-child(7) { white-space: nowrap; }
td.strong { color: var(--ink); font-weight: 550; min-width: 220px; max-width: 340px; overflow-wrap: anywhere; }
td:nth-child(5), td:nth-child(6) { min-width: 140px; overflow-wrap: anywhere; }
.badge { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }

td.detail { min-width: 360px; max-width: 480px; }
.kv { margin: 1px 0; overflow-wrap: anywhere; }
.kv .k { color: var(--muted); }
.kv .k::after { content: ': '; }
.kv .v { font-variant-numeric: tabular-nums; }
details { margin-top: 2px; }
summary { cursor: pointer; color: var(--accent); font-size: 12px; }

.empty { padding: 32px; text-align: center; color: var(--muted); display: none; }
</style>
</head>
<body>
<main>
<h1>__TITLE__</h1>
<div class="meta">Generated __GENERATED__ &middot; __TOTAL__ finding(s)</div>

<div class="tiles">
__TILES__
</div>

<div class="filters">
  <input id="q" type="search" placeholder="Search name, type, subscription, detail&hellip;" aria-label="Search findings">
  <select id="sev" aria-label="Filter by severity">
    <option value="">All severities</option>
    __SEV_OPTIONS__
  </select>
  <select id="cat" aria-label="Filter by category">
    <option value="">All categories</option>
    __CAT_OPTIONS__
  </select>
  <button class="reset" id="reset" type="button">Reset</button>
  <span class="count" id="count"></span>
</div>

<div class="tablewrap">
<table id="findings">
<thead><tr>
<th aria-sort="ascending">Severity</th><th>Category</th><th>Type</th><th>Name</th>
<th>Subscription</th><th>Resource group</th><th>Location</th><th>Detail</th>
</tr></thead>
<tbody>
__ROWS__
</tbody>
</table>
<div class="empty" id="empty">No findings match the current filters.</div>
</div>
</main>

<script>
(function () {
  var table = document.getElementById('findings');
  var tbody = table.tBodies[0];
  var rows = Array.prototype.slice.call(tbody.rows);
  var q = document.getElementById('q');
  var sevSel = document.getElementById('sev');
  var catSel = document.getElementById('cat');
  var countEl = document.getElementById('count');
  var emptyEl = document.getElementById('empty');

  // Search index built once; keeps the HTML payload lean.
  var textOf = new Map();
  rows.forEach(function (r) { textOf.set(r, r.textContent.toLowerCase()); });

  function applyFilters() {
    var needle = q.value.trim().toLowerCase();
    var sev = sevSel.value, cat = catSel.value, shown = 0;
    rows.forEach(function (r) {
      var ok = (!sev || r.dataset.sev === sev) &&
               (!cat || r.dataset.cat === cat) &&
               (!needle || textOf.get(r).indexOf(needle) !== -1);
      r.style.display = ok ? '' : 'none';
      if (ok) shown++;
    });
    countEl.textContent = shown === rows.length
      ? rows.length + ' finding(s)'
      : shown + ' of ' + rows.length + ' finding(s)';
    emptyEl.style.display = shown === 0 ? 'block' : 'none';
    document.querySelectorAll('.tile').forEach(function (t) {
      t.classList.toggle('active', t.dataset.sev === sev);
    });
  }

  q.addEventListener('input', applyFilters);
  sevSel.addEventListener('change', applyFilters);
  catSel.addEventListener('change', applyFilters);
  document.getElementById('reset').addEventListener('click', function () {
    q.value = ''; sevSel.value = ''; catSel.value = ''; applyFilters();
  });
  document.querySelectorAll('.tile').forEach(function (t) {
    t.addEventListener('click', function () {
      sevSel.value = sevSel.value === t.dataset.sev ? '' : t.dataset.sev;
      applyFilters();
    });
  });

  // Click-to-sort: numeric when both values parse, else locale text compare.
  var headers = table.tHead.rows[0].cells;
  Array.prototype.forEach.call(headers, function (th, idx) {
    th.addEventListener('click', function () {
      var dir = th.getAttribute('aria-sort') === 'ascending' ? 'descending' : 'ascending';
      Array.prototype.forEach.call(headers, function (h) { h.removeAttribute('aria-sort'); });
      th.setAttribute('aria-sort', dir);
      var mul = dir === 'ascending' ? 1 : -1;
      var sorted = rows.slice().sort(function (a, b) {
        var av = a.cells[idx].dataset.sort || a.cells[idx].textContent.trim().toLowerCase();
        var bv = b.cells[idx].dataset.sort || b.cells[idx].textContent.trim().toLowerCase();
        var an = parseFloat(av), bn = parseFloat(bv);
        if (!isNaN(an) && !isNaN(bn)) { return (an - bn) * mul; }
        return av.localeCompare(bv) * mul;
      });
      sorted.forEach(function (r) { tbody.appendChild(r); });
    });
  });

  applyFilters();
})();
</script>
</body>
</html>
'@

        $sevOptions = ($sevMeta.Keys | ForEach-Object { "<option value='$_'>$_</option>" }) -join "`n"

        $html = $template.
            Replace('__TITLE__', (& $enc $Title)).
            Replace('__GENERATED__', (& $enc ((Get-Date).ToString('u')))).
            Replace('__TOTAL__', [string]$all.Count).
            Replace('__TILES__', $tileSb.ToString()).
            Replace('__SEV_OPTIONS__', $sevOptions).
            Replace('__CAT_OPTIONS__', $catOptions).
            Replace('__ROWS__', $rowSb.ToString())

        $html | Set-Content -Path $Path -Encoding utf8
        Write-AotLog -Level Information -Operation 'Report' -Message "Wrote $($all.Count) findings to HTML: $Path"
        Get-Item $Path
    }
}

function Export-AotJsonReport {
    <#
    .SYNOPSIS
        Writes findings to a JSON file (round-trippable, full Detail preserved).

    .PARAMETER Finding
        Aot.Finding objects (accepts pipeline input).

    .PARAMETER Path
        Destination .json file path.

    .EXAMPLE
        Get-AotUnattachedDisk | Export-AotJsonReport -Path .\disks.json
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject[]]$Finding,

        [Parameter(Mandatory)]
        [string]$Path
    )

    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($f in $Finding) { $all.Add($f) } }
    end {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $payload = [ordered]@{
            GeneratedAt = (Get-Date).ToString('o')
            Count       = $all.Count
            Findings    = $all
        }
        $payload | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding utf8
        Write-AotLog -Level Information -Operation 'Report' -Message "Wrote $($all.Count) findings to JSON: $Path"
        Get-Item $Path
    }
}

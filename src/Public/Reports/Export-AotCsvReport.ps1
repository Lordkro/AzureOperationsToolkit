function Export-AotCsvReport {
    <#
    .SYNOPSIS
        Writes findings to a flat CSV (Detail serialised to a JSON column).

    .PARAMETER Finding
        Aot.Finding objects (accepts pipeline input).

    .PARAMETER Path
        Destination .csv file path.

    .EXAMPLE
        Get-AotMissingTag -RequiredTag Owner | Export-AotCsvReport -Path .\missing.csv
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

        $flat = $all | ForEach-Object {
            [pscustomobject]@{
                Category         = $_.Category
                Type             = $_.Type
                Name             = $_.Name
                Severity         = $_.Severity
                SubscriptionName = $_.SubscriptionName
                SubscriptionId   = $_.SubscriptionId
                ResourceGroup    = $_.ResourceGroup
                Location         = $_.Location
                ResourceId       = $_.ResourceId
                Detail           = ($_.Detail | ConvertTo-Json -Compress -Depth 6)
                CollectedAt      = $_.CollectedAt
            }
        }
        $flat | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
        Write-AotLog -Level Information -Operation 'Report' -Message "Wrote $($all.Count) findings to CSV: $Path"
        Get-Item $Path
    }
}

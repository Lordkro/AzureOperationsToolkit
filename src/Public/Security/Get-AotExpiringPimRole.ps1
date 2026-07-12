function Get-AotExpiringPimRole {
    <#
    .SYNOPSIS
        Flags active PIM role assignments expiring within a window.

    .DESCRIPTION
        Reuses Get-AotPimAssignment output and filters to active assignments whose
        end date falls inside the configured PimExpiryWindowDays (default 14).

    .PARAMETER WithinDays
        Override the expiry look-ahead window in days.

    .EXAMPLE
        Get-AotExpiringPimRole -WithinDays 7
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$WithinDays = $script:AotConfig.PimExpiryWindowDays
    )

    $cutoff = (Get-Date).AddDays($WithinDays)
    Write-AotLog -Level Information -Operation 'ExpiringPim' -Message "PIM roles expiring before $($cutoff.ToString('yyyy-MM-dd'))"

    Get-AotPimAssignment -State Active | ForEach-Object {
        $end = $_.Detail.EndDateTime
        if (-not $end) { return }        # permanent assignment, not expiring
        $endDate = [datetime]$end
        if ($endDate -gt $cutoff -or $endDate -lt (Get-Date)) { return }

        $daysLeft = [math]::Round(($endDate - (Get-Date)).TotalDays, 1)
        New-AotFinding -Category 'Security' -Type 'ExpiringPimRole' `
            -Name $_.Name -ResourceId $_.ResourceId `
            -Severity ($daysLeft -le 3 ? 'High' : 'Medium') `
            -Detail @{
                RoleDefinition = $_.Detail.RoleDefinition
                PrincipalId    = $_.Detail.PrincipalId
                EndDateTime    = $end
                DaysRemaining  = $daysLeft
            }
    }
}

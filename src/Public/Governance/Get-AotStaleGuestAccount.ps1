function Get-AotStaleGuestAccount {
    <#
    .SYNOPSIS
        Finds Entra guest (B2B) accounts that are stale or never signed in.

    .DESCRIPTION
        Requires Microsoft.Graph with directory + audit-log read permissions.
        A guest is stale when its last interactive sign-in is older than the
        configured StaleGuestDays (default 90) or it has never signed in.

    .PARAMETER StaleDays
        Override the staleness threshold in days.

    .EXAMPLE
        Get-AotStaleGuestAccount -StaleDays 60
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$StaleDays = $script:AotConfig.StaleGuestDays
    )

    if (-not (Get-Command Get-MgUser -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Users is required for Get-AotStaleGuestAccount. Run: Test-AotDependency -InstallMissing'
    }
    Assert-AotGraphConnection -RequiredScopes 'User.Read.All', 'AuditLog.Read.All'

    $cutoff = (Get-Date).AddDays(-$StaleDays)
    Write-AotLog -Level Information -Operation 'StaleGuest' -Message "Guests idle since $($cutoff.ToString('yyyy-MM-dd'))"

    $guests = Invoke-AotOperation -Operation 'StaleGuest' -ScriptBlock {
        Get-MgUser -All -Filter "userType eq 'Guest'" `
            -Property Id, DisplayName, UserPrincipalName, CreatedDateTime, AccountEnabled, SignInActivity
    }

    foreach ($g in $guests) {
        $lastSignIn = $g.SignInActivity.LastSignInDateTime
        $isStale = (-not $lastSignIn) -or ([datetime]$lastSignIn -lt $cutoff)
        if (-not $isStale) { continue }

        New-AotFinding -Category 'Governance' -Type 'StaleGuestAccount' `
            -Name $g.DisplayName -ResourceId $g.Id -Severity 'Medium' `
            -Detail @{
                UserPrincipalName = $g.UserPrincipalName
                AccountEnabled    = $g.AccountEnabled
                CreatedDateTime   = $g.CreatedDateTime
                LastSignInDateTime = $lastSignIn ?? 'Never'
                ThresholdDays     = $StaleDays
            }
    }
}

function Get-AotKeyVaultAudit {
    <#
    .SYNOPSIS
        Audits Key Vault security posture and expiring secrets/keys/certificates.

    .DESCRIPTION
        For each vault it checks soft-delete, purge protection, public network
        access and RBAC authorization, then scans contained objects for items
        expiring within -WithinDays. Vault detail lookups run in parallel because
        each is an independent Azure call; findings are assembled sequentially.

    .PARAMETER WithinDays
        Expiry look-ahead window for secrets/keys/certificates.

    .PARAMETER SubscriptionId
        One or more subscriptions. Defaults to every enabled subscription.

    .EXAMPLE
        Get-AotKeyVaultAudit -WithinDays 30
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$WithinDays = 30,
        [string[]]$SubscriptionId
    )

    $subs = Get-AotSubscriptionScope -SubscriptionId $SubscriptionId
    $throttle = $script:AotConfig.ThrottleLimit
    $cutoff = (Get-Date).AddDays($WithinDays)

    foreach ($sub in $subs) {
        Write-AotLog -Level Information -Operation 'KeyVaultAudit' -Message "Key Vaults for '$($sub.Name)'"

        $vaults = Invoke-AotOperation -Operation "KeyVaultList:$($sub.Id)" -SkipOnError -ScriptBlock {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Get-AzKeyVault
        }

        # Parallel: fetch full properties + object expiries per vault. Only Az
        # cmdlets and $using: values are referenced inside the parallel block.
        $audited = $vaults | ForEach-Object -ThrottleLimit $throttle -Parallel {
            $v = $_
            $cutoff = $using:cutoff
            try {
                $full = Get-AzKeyVault -VaultName $v.VaultName -ErrorAction Stop
                $expiring = [System.Collections.Generic.List[object]]::new()

                # Skip Managed (certificate-backed) secrets/keys: they are audited
                # through Get-AzKeyVaultCertificate below, and Az.KeyVault 7.0.0
                # stops returning them from these listings anyway — filtering now
                # adopts that behaviour early and avoids double-counting.
                foreach ($s in (Get-AzKeyVaultSecret -VaultName $v.VaultName -ErrorAction SilentlyContinue)) {
                    if ($s.Managed) { continue }
                    if ($s.Expires -and $s.Expires -le $cutoff) {
                        $expiring.Add(@{ Kind = 'Secret'; Name = $s.Name; Expires = $s.Expires })
                    }
                }
                foreach ($k in (Get-AzKeyVaultKey -VaultName $v.VaultName -ErrorAction SilentlyContinue)) {
                    if ($k.Managed) { continue }
                    if ($k.Expires -and $k.Expires -le $cutoff) {
                        $expiring.Add(@{ Kind = 'Key'; Name = $k.Name; Expires = $k.Expires })
                    }
                }
                foreach ($c in (Get-AzKeyVaultCertificate -VaultName $v.VaultName -ErrorAction SilentlyContinue)) {
                    if ($c.Expires -and $c.Expires -le $cutoff) {
                        $expiring.Add(@{ Kind = 'Certificate'; Name = $c.Name; Expires = $c.Expires })
                    }
                }

                [pscustomobject]@{
                    Vault    = $full
                    Expiring = $expiring
                    Error    = $null
                }
            }
            catch {
                [pscustomobject]@{ Vault = $v; Expiring = @(); Error = $_.Exception.Message }
            }
        }

        foreach ($a in $audited) {
            $v = $a.Vault
            if ($a.Error) {
                Write-AotLog -Level Warning -Operation 'KeyVaultAudit' `
                    -Message "Vault '$($v.VaultName)' partial audit: $($a.Error)"
            }

            $weaknesses = @()
            if (-not $v.EnableSoftDelete)      { $weaknesses += 'SoftDeleteDisabled' }
            if (-not $v.EnablePurgeProtection) { $weaknesses += 'PurgeProtectionDisabled' }
            if ($v.PublicNetworkAccess -eq 'Enabled') { $weaknesses += 'PublicNetworkAccess' }
            if (-not $v.EnableRbacAuthorization) { $weaknesses += 'AccessPolicyModel' }

            $severity = if ($weaknesses -contains 'PurgeProtectionDisabled' -or $a.Expiring.Count -gt 0) { 'High' }
                        elseif ($weaknesses) { 'Medium' } else { 'Informational' }

            New-AotFinding -Category 'Security' -Type 'KeyVaultAudit' `
                -Name $v.VaultName -ResourceId $v.ResourceId `
                -ResourceGroup $v.ResourceGroupName -Location $v.Location -Severity $severity `
                -SubscriptionId $sub.Id -SubscriptionName $sub.Name `
                -Detail @{
                    Weaknesses          = $weaknesses
                    PublicNetworkAccess = $v.PublicNetworkAccess
                    RbacEnabled         = $v.EnableRbacAuthorization
                    ExpiringObjectCount = $a.Expiring.Count
                    ExpiringObjects     = @($a.Expiring)
                }
        }
    }
}

function Get-AotKeyVaultAudit {
    <#
    .SYNOPSIS
        Audits Key Vault security posture and expiring secrets/keys/certificates.

    .DESCRIPTION
        Vault list and control-plane posture (soft-delete, purge protection,
        public network access, RBAC authorization) come from one tenant-wide
        Resource Graph query (fallback: parallel per-subscription sweep of
        Get-AzKeyVault). The data-plane expiry scan then runs as a single flat
        parallel loop across every vault in the tenant.

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
    $throttle = $script:AotConfig.ResourceScanThrottleLimit
    $cutoff = (Get-Date).AddDays($WithinDays)
    $subName = @{}
    foreach ($s in $subs) { $subName[$s.Id] = $s.Name }

    # --- 1. Vault list + control-plane posture, normalised to one shape ---
    $vaults = $null
    if (Get-Command Search-AzGraph -ErrorAction SilentlyContinue) {
        try {
            $rows = Invoke-AotGraphQuery -Operation 'KeyVaultAudit:graph' -SubscriptionId @($subs.Id) -Query (
                "resources | where type == 'microsoft.keyvault/vaults' " +
                '| project id, name, subscriptionId, resourceGroup, location, ' +
                'softDelete = tobool(properties.enableSoftDelete), purgeProtection = tobool(properties.enablePurgeProtection), ' +
                "publicNetworkAccess = iff(isempty(tostring(properties.publicNetworkAccess)), 'Enabled', tostring(properties.publicNetworkAccess)), " +
                'rbacEnabled = tobool(properties.enableRbacAuthorization)'
            )
            $vaults = @(foreach ($r in $rows) {
                [pscustomobject]@{
                    Name = $r.name; Id = $r.id; Rg = $r.resourceGroup; Location = $r.location
                    SubId = [string]$r.subscriptionId
                    SoftDelete = [bool]$r.softDelete; PurgeProtection = [bool]$r.purgeProtection
                    PublicNetworkAccess = $r.publicNetworkAccess; RbacEnabled = [bool]$r.rbacEnabled
                }
            })
        }
        catch {
            Write-AotLog -Level Warning -Operation 'KeyVaultAudit' `
                -Message "Resource Graph path failed ($($_.Exception.Message)); falling back to per-subscription sweep."
        }
    }

    if ($null -eq $vaults) {
        $sweep = Invoke-AotSubscriptionSweep -Subscription $subs -Operation 'KeyVaultAudit' -Fetch {
            param($sub)
            # The list call returns light objects; re-fetch each vault for the
            # full security properties.
            Get-AzKeyVault | ForEach-Object { Get-AzKeyVault -VaultName $_.VaultName }
        }
        $vaults = @(foreach ($entry in $sweep) {
            foreach ($v in $entry.Items) {
                [pscustomobject]@{
                    Name = $v.VaultName; Id = $v.ResourceId; Rg = $v.ResourceGroupName; Location = $v.Location
                    SubId = $entry.Subscription.Id
                    SoftDelete = [bool]$v.EnableSoftDelete; PurgeProtection = [bool]$v.EnablePurgeProtection
                    PublicNetworkAccess = $v.PublicNetworkAccess; RbacEnabled = [bool]$v.EnableRbacAuthorization
                }
            }
        })
    }

    if (-not $vaults) { return }

    # --- 2. One flat parallel data-plane expiry scan across all vaults ---
    Write-AotLog -Level Information -Operation 'KeyVaultAudit' `
        -Message "Scanning $($vaults.Count) vault(s) for expiring objects, $throttle parallel"

    $ctxMap = Get-AotSubscriptionContext -Subscription $subs

    $audited = $vaults | ForEach-Object -ThrottleLimit $throttle -Parallel {
        $v = $_
        $cutoff = $using:cutoff
        try {
            $PSDefaultParameterValues = @{ '*-Az*:DefaultProfile' = ($using:ctxMap)[$v.SubId] }
            $expiring = [System.Collections.Generic.List[object]]::new()

            # Skip Managed (certificate-backed) secrets/keys: they are audited
            # through Get-AzKeyVaultCertificate below, and Az.KeyVault 7.0.0
            # stops returning them from these listings anyway.
            # -WarningAction: the announced change is already handled here.
            foreach ($s in (Get-AzKeyVaultSecret -VaultName $v.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)) {
                if ($s.Managed) { continue }
                if ($s.Expires -and $s.Expires -le $cutoff) {
                    $expiring.Add(@{ Kind = 'Secret'; Name = $s.Name; Expires = $s.Expires })
                }
            }
            foreach ($k in (Get-AzKeyVaultKey -VaultName $v.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)) {
                if ($k.Managed) { continue }
                if ($k.Expires -and $k.Expires -le $cutoff) {
                    $expiring.Add(@{ Kind = 'Key'; Name = $k.Name; Expires = $k.Expires })
                }
            }
            foreach ($c in (Get-AzKeyVaultCertificate -VaultName $v.Name -ErrorAction SilentlyContinue)) {
                if ($c.Expires -and $c.Expires -le $cutoff) {
                    $expiring.Add(@{ Kind = 'Certificate'; Name = $c.Name; Expires = $c.Expires })
                }
            }

            [pscustomobject]@{ Vault = $v; Expiring = $expiring; Error = $null }
        }
        catch {
            [pscustomobject]@{ Vault = $v; Expiring = @(); Error = $_.Exception.Message }
        }
    }

    # --- 3. Build findings sequentially ---
    foreach ($a in $audited) {
        $v = $a.Vault
        if ($a.Error) {
            Write-AotLog -Level Warning -Operation 'KeyVaultAudit' `
                -Message "Vault '$($v.Name)' partial audit: $($a.Error)"
        }

        $weaknesses = @()
        if (-not $v.SoftDelete)      { $weaknesses += 'SoftDeleteDisabled' }
        if (-not $v.PurgeProtection) { $weaknesses += 'PurgeProtectionDisabled' }
        if ($v.PublicNetworkAccess -eq 'Enabled') { $weaknesses += 'PublicNetworkAccess' }
        if (-not $v.RbacEnabled)     { $weaknesses += 'AccessPolicyModel' }

        $severity = if ($weaknesses -contains 'PurgeProtectionDisabled' -or $a.Expiring.Count -gt 0) { 'High' }
                    elseif ($weaknesses) { 'Medium' } else { 'Informational' }

        New-AotFinding -Category 'Security' -Type 'KeyVaultAudit' `
            -Name $v.Name -ResourceId $v.Id `
            -ResourceGroup $v.Rg -Location $v.Location -Severity $severity `
            -SubscriptionId $v.SubId -SubscriptionName $subName[$v.SubId] `
            -Detail @{
                Weaknesses          = $weaknesses
                PublicNetworkAccess = $v.PublicNetworkAccess
                RbacEnabled         = $v.RbacEnabled
                ExpiringObjectCount = $a.Expiring.Count
                ExpiringObjects     = @($a.Expiring)
                ScanError           = $a.Error
            }
    }
}

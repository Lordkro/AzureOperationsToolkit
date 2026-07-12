function Get-AotMember {
    <#
    .SYNOPSIS
        Safely reads a property that may be absent from an object.

    .DESCRIPTION
        Under Set-StrictMode -Version Latest, referencing a non-existent property
        throws. Collectors that normalise across different SDK shapes (Az cmdlets
        vs Resource Graph vs Graph API) need to probe maybe-present properties, so
        they use this to return $null (or a default) instead of throwing.

    .EXAMPLE
        Get-AotMember -InputObject $r -Name 'Sku'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { $prop.Value } else { $Default }
}

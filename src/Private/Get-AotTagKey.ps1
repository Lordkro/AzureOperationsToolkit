function Get-AotTagKey {
    <#
    .SYNOPSIS
        Returns the tag keys of a resource as a string array, never throwing.

    .DESCRIPTION
        Tags arrive as $null, a hashtable (Az cmdlets) or a pscustomobject
        (Resource Graph / REST). Under Set-StrictMode -Version Latest, touching
        .Keys on the wrong shape throws — every tag-reading collector goes
        through this instead.

    .EXAMPLE
        (Get-AotTagKey -Tags $resource.Tags).Count
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]$Tags
    )

    $keys = @(
        if ($null -eq $Tags) { }
        elseif ($Tags -is [System.Collections.IDictionary]) { $Tags.Keys }
        else { $Tags.PSObject.Properties.Name }
    )
    # Comma operator stops the pipeline unwrapping a 0/1-element array to
    # $null/scalar on return; callers rely on .Count under StrictMode.
    return , $keys
}

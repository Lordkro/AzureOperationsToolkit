function Get-AotConfiguration {
    <#
    .SYNOPSIS
        Returns a copy of the current module configuration.

    .EXAMPLE
        Get-AotConfiguration
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]$script:AotConfig
}

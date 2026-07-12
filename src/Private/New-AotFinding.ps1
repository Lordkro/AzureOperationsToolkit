function New-AotFinding {
    <#
    .SYNOPSIS
        Builds a normalised finding object used by every collection function.

    .DESCRIPTION
        A single, consistent shape lets the Reports module render any module's
        output without special-casing. Every public Get-Aot* function emits these.

    .OUTPUTS
        pscustomobject with a PSTypeName of 'Aot.Finding'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Category,      # e.g. 'Inventory', 'Security'
        [Parameter(Mandatory)][string]$Type,          # e.g. 'UnattachedDisk'
        [Parameter(Mandatory)][string]$Name,
        [string]$ResourceId,
        [string]$ResourceGroup,
        [string]$SubscriptionId,
        [string]$SubscriptionName,
        [string]$Location,

        [ValidateSet('Informational', 'Low', 'Medium', 'High', 'Critical')]
        [string]$Severity = 'Informational',

        [hashtable]$Detail = @{}
    )

    [pscustomobject]@{
        PSTypeName       = 'Aot.Finding'
        Category         = $Category
        Type             = $Type
        Name             = $Name
        Severity         = $Severity
        SubscriptionName = $SubscriptionName
        SubscriptionId   = $SubscriptionId
        ResourceGroup    = $ResourceGroup
        Location         = $Location
        ResourceId       = $ResourceId
        Detail           = [pscustomobject]$Detail
        CollectedAt      = (Get-Date).ToString('o')
    }
}

@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Collection functions are read-only Get-* verbs; ShouldProcess noise not wanted.
        'PSUseShouldProcessForStateChangingFunctions',
        # Plural nouns are intentional for inventory/aggregate commands.
        'PSUseSingularNouns',
        # Parameters are consumed inside Invoke-AotOperation/-Parallel closures the
        # analyzer cannot follow, so this rule only yields false positives here.
        'PSReviewUnusedParameter',
        # Backtick line-continuation of long -Parameter chains is an intentional,
        # readable style choice; the indentation rule fights it.
        'PSUseConsistentIndentation',
        # UTF-8 (no BOM) is the intended encoding for generated/report source.
        'PSUseBOMForUnicodeEncodedFile'
    )
    Rules = @{
        PSPlaceOpenBrace = @{ Enable = $true; OnSameLine = $true }
    }
}

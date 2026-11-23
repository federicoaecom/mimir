#requires -Version 7.4

# The inventory replaces interior tabs; advanced documentation preserves them.
function Format-MdCell {
    param(
        [AllowNull()][object]$Value,
        [switch]$ReplaceTabs
    )

    if ($null -eq $Value) { return "" }

    $text = [string]$Value
    $text = $text -replace '\r?\n', '<br/>'
    $text = $text -replace '\|', '\|'
    if ($ReplaceTabs) { $text = $text -replace '\t', ' ' }
    return $text.Trim()
}

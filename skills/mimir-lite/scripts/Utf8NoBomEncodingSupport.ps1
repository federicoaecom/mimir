#requires -Version 7.4

Set-StrictMode -Version Latest

function Get-Utf8NoBomEncoding {
    return [System.Text.UTF8Encoding]::new($false)
}

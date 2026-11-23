#requires -Version 7.4
<#
.SYNOPSIS
Provides an exclusive, fail-fast lock on an existing corpus directory.
.DESCRIPTION
Call Enter-GeneXusCorpusLock and release its result with Exit-GeneXusCorpusLock
in a finally block. The persistent .mimir-sync.lock is never truncated or removed.
Participants must use the same byte-range protocol. This helper alone does not
protect a corpus or validate its identity. Only one PowerShell-held corpus
lock is permitted per process, including across runspaces and distinct paths.
#>

function Enter-GeneXusCorpusLock {
    param([Parameter(Mandatory)][string]$CorpusRoot)
    $root = (Resolve-Path -LiteralPath $CorpusRoot -ErrorAction Stop).ProviderPath
    if (-not [IO.Directory]::Exists($root)) { throw "Corpus directory does not exist: $CorpusRoot" }
    $path = [IO.Path]::Combine($root, '.mimir-sync.lock')
    $domain = [AppDomain]::CurrentDomain
    $key = 'Mimir.GeneXusCorpusLock.Reserved'
    [Threading.Monitor]::Enter($domain)
    try {
        if ($domain.GetData($key)) { throw 'Corpus lock already owned by this process' }
        $domain.SetData($key, $true)
    } finally { [Threading.Monitor]::Exit($domain) }
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        $stream.Lock(0, 1)
        return [pscustomobject]@{ Stream = $stream; Path = $path; Released = $false }
    } catch {
        try { if ($null -ne $stream) { $stream.Dispose() } } finally {
            [Threading.Monitor]::Enter($domain)
            try { $domain.SetData($key, $null) } finally { [Threading.Monitor]::Exit($domain) }
        }
        throw
    }
}

function Exit-GeneXusCorpusLock {
    param([Parameter(Mandatory)]$Lock)
    $domain = [AppDomain]::CurrentDomain
    $key = 'Mimir.GeneXusCorpusLock.Reserved'
    [Threading.Monitor]::Enter($domain)
    try {
        if ($Lock.Released) { throw 'Corpus lock already released' }
        $Lock.Released = $true
    } finally { [Threading.Monitor]::Exit($domain) }
    try {
        try { $Lock.Stream.Unlock(0, 1) } finally { $Lock.Stream.Dispose() }
    } finally {
        [Threading.Monitor]::Enter($domain)
        try { $domain.SetData($key, $null) } finally { [Threading.Monitor]::Exit($domain) }
    }
}

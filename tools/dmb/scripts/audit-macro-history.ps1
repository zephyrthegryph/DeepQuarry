#requires -Version 7.0
<#
.SYNOPSIS
Read-only macro edit frequency and current lexical fanout from real Git history.
.NOTES
Compares complete multi-line macro definitions between each commit and its first
parent. Current fanout is lexical (including strings/comments), not a claim that
every matching file is active or semantically dependent in one build configuration.
#>
param(
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../../..").Path,
    [ValidateRange(1, 1000)][int]$CommitLimit = 50,
    [ValidateRange(1, 200)][int]$FanoutLimit = 20,
    [string]$Since = '',
    [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
function Invoke-Git([string[]]$Arguments, [switch]$MissingOkay) {
    $lines = @(& git -C $ProjectRoot @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0 -and !$MissingOkay) { throw "Git command failed: $($Arguments -join ' ')" }
    return $lines
}
function Get-Definitions([string[]]$Lines) {
    $definitions = @{}
    $occurrences = @{}
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^\s*#\s*(?:define|undef)\s+([A-Za-z_][A-Za-z_0-9]*)') { continue }
        $name = $Matches[1]
        $body = [Collections.Generic.List[string]]::new()
        do {
            $body.Add($Lines[$i].TrimEnd())
            if (!$Lines[$i].TrimEnd().EndsWith('\') -or $i + 1 -eq $Lines.Count) { break }
            $i++
        } while ($true)
        if (!$occurrences.ContainsKey($name)) { $occurrences[$name] = 0 }
        $key = "$name#$($occurrences[$name])"
        $occurrences[$name]++
        $definitions[$key] = @{ Name = $name; Body = $body -join "`n" }
    }
    return $definitions
}
$logArguments = @('log', "-n$CommitLimit", '--format=%H')
if ($Since) { $logArguments += "--since=$Since" }
$logArguments += @('--', '*.dm', '*.dme')
$commits = @(Invoke-Git $logArguments)
$frequency = @{}
$changed = [Collections.Generic.List[object]]::new()
foreach ($commit in $commits) {
    $parents = (@(Invoke-Git @('rev-list', '--parents', '-n1', $commit)))[0].Split(' ')
    if ($parents.Count -lt 2) { continue }
    $parent = $parents[1]
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $files = @(Invoke-Git @('diff', '--name-only', $parent, $commit, '--', '*.dm', '*.dme'))
    # One batched tree search avoids opening two versions of every ordinary DM
    # file in sweeping commits. Only files actually containing macro directives
    # in either revision require complete-definition comparison.
    $macroFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in @(Invoke-Git @('grep', '-l', '-E', '^[[:space:]]*#[[:space:]]*(define|undef)[[:space:]]', $parent, $commit, '--', '*.dm', '*.dme') -MissingOkay)) {
        $null = $macroFiles.Add($row.Substring($row.IndexOf(':') + 1))
    }
    $files = @($files | Where-Object { $macroFiles.Contains($_) })
    foreach ($file in $files) {
        $old = Get-Definitions @(Invoke-Git @('show', "${parent}:$file") -MissingOkay)
        $new = Get-Definitions @(Invoke-Git @('show', "${commit}:$file") -MissingOkay)
        foreach ($key in @(@($old.Keys) + @($new.Keys) | Sort-Object -Unique)) {
            if ($old.ContainsKey($key) -and $new.ContainsKey($key) -and $old[$key].Body -ceq $new[$key].Body) { continue }
            $name = if ($new.ContainsKey($key)) { $new[$key].Name } else { $old[$key].Name }
            $null = $names.Add($name)
            $changed.Add([pscustomobject]@{ Commit = $commit; File = $file; Macro = $name })
        }
    }
    foreach ($name in $names) {
        if (!$frequency.ContainsKey($name)) { $frequency[$name] = 0 }
        $frequency[$name]++
    }
}
$fanout = [Collections.Generic.List[object]]::new()
foreach ($entry in @($frequency.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $FanoutLimit)) {
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $occurrences = 0
    $rows = @(& rg --json --word-regexp --fixed-strings $entry.Key --glob '*.dm' --glob '*.dme' --glob '!tools/**' --glob '!**/target/**' -- $ProjectRoot)
    if ($LASTEXITCODE -gt 1) { throw 'Current macro fanout search failed.' }
    foreach ($row in $rows) {
        $match = $row | ConvertFrom-Json
        if ($match.type -ne 'match') { continue }
        $null = $paths.Add($match.data.path.text)
        $occurrences += $match.data.submatches.Count
    }
    $fanout.Add([pscustomobject]@{ Macro = $entry.Key; ChangedCommits = $entry.Value; LexicalFiles = $paths.Count; LexicalOccurrences = $occurrences; Files = @($paths | Sort-Object) })
}
$report = [ordered]@{
    FormatVersion = 1
    Head = (@(Invoke-Git @('rev-parse', 'HEAD')))[0]
    CommitsExamined = $commits.Count
    MacroChangingCommits = @($changed.Commit | Sort-Object -Unique).Count
    Since = $Since
    Method = 'Complete multiline define/undef comparison against first parent; current lexical fanout includes comments/strings and inactive source.'
    MacroChanges = $changed
    Fanout = $fanout
}
$Output = [IO.Path]::GetFullPath($Output)
$parent = Split-Path -Parent $Output
if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output -Encoding utf8NoBOM
Write-Host "Examined $($commits.Count) commits; $($report.MacroChangingCommits) changed macros. Report: $Output"

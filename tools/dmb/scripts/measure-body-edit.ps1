param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Builtins,
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../../..").Path,
    [string]$MirrorRoot = "",
    [string]$DaemonAddress = "",
    [string]$ProjectFile = 'deepquarry.dme',
    [switch]$ReuseMirror,
    [switch]$PrepareOnly,
    [string[]]$Defines = @('-DCITESTING')
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Builtins = (Resolve-Path -LiteralPath $Builtins).Path
if (!$MirrorRoot) { $MirrorRoot = Join-Path $ProjectRoot "tools/dmb/target/body-edit-$([Guid]::NewGuid().ToString('N'))" }
if ((Test-Path -LiteralPath $MirrorRoot) -and !$ReuseMirror) { throw 'Mirror directory must be new unless -ReuseMirror is supplied.' }
$editedRelative = 'code/datums/interactions/tools.dm'
$original = Join-Path $ProjectRoot $editedRelative
$before = [IO.File]::ReadAllText($original)
$pattern = '(?m)(^/proc/tool_skill_factor\(mob/actor, quality\)\r?\n\s*return )1(?=\r?$)'
if ([regex]::Matches($before, $pattern).Count -ne 1) { throw 'Expected isolated literal-return procedure was not found exactly once.' }

# Only the ancestry of the edited file is mirrored. Other directories are read-only
# compiler inputs reached through junctions; files are hardlinked until replaced.
function New-MirrorBranch([string]$source, [string]$destination, [string[]]$remaining) {
    New-Item -ItemType Directory -Path $destination | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $source -Force) {
        if ($entry.Name -eq '.git') { continue }
        $target = Join-Path $destination $entry.Name
        if ($entry.PSIsContainer) {
            if (($source -eq $ProjectRoot -and @('maps', 'interface') -contains $entry.Name) -or $remaining.Count -eq 0) {
                # Maps enforce project containment after canonicalization, so their
                # directories must be real; file hardlinks still avoid payload copies.
                New-MirrorBranch $entry.FullName $target @()
            } elseif ($remaining.Count -gt 1 -and $entry.Name -eq $remaining[0]) {
                New-MirrorBranch $entry.FullName $target $remaining[1..($remaining.Count - 1)]
            } else {
                New-Item -ItemType Junction -Path $target -Target $entry.FullName | Out-Null
            }
        } elseif ($remaining.Count -eq 1 -and $entry.Name -eq $remaining[0]) {
            Copy-Item -LiteralPath $entry.FullName -Destination $target
        } else {
            New-Item -ItemType HardLink -Path $target -Target $entry.FullName | Out-Null
        }
    }
}
if (!$ReuseMirror) {
    New-MirrorBranch $ProjectRoot $MirrorRoot ($editedRelative.Split('/'))
} else {
    $mirrorFile = Get-Item -LiteralPath (Join-Path $MirrorRoot $editedRelative)
    if ($mirrorFile.LinkType -or ($mirrorFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The edited mirror file must be a private copy.'
    }
    [IO.File]::WriteAllText($mirrorFile.FullName, $before, [Text.UTF8Encoding]::new($false))
}
$gitDirectory = (& git -C $ProjectRoot rev-parse --absolute-git-dir).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine shared Git cache directory.' }
# The daemon resolves cache roots in its own process, so the client's GIT_DIR
# environment alone is insufficient. This pointer is used only for Git discovery.
[IO.File]::WriteAllText((Join-Path $MirrorRoot '.git'), "gitdir: $gitDirectory`n", [Text.UTF8Encoding]::new($false))
if ($PrepareOnly) {
    if ([IO.File]::ReadAllText($original) -cne $before) { throw 'Original source changed during mirror preparation.' }
    Write-Host "Prepared private measurement mirror at $MirrorRoot"
    return
}
$savedGitDirectory = $env:GIT_DIR
$savedTrace = $env:DM_BUILD_TRACE
try {
    $env:GIT_DIR = $gitDirectory
    $env:DM_BUILD_TRACE = '1'
    Push-Location $MirrorRoot
    try {
        $output = Join-Path $MirrorRoot 'timing-output'
        foreach ($phase in @('baseline', 'changed-body', 'unchanged', 'fresh-cli-unchanged')) {
            if ($phase -eq 'changed-body') {
                [IO.File]::WriteAllText((Join-Path $MirrorRoot $editedRelative), [regex]::Replace($before, $pattern, '${1}2'), [Text.UTF8Encoding]::new($false))
            }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            if ($DaemonAddress -and $phase -ne 'fresh-cli-unchanged') {
                & $Compiler build-project-daemon $DaemonAddress $ProjectFile $Builtins $output @Defines 2>&1 | Tee-Object -FilePath (Join-Path $MirrorRoot "$phase.log")
            } else {
                & $Compiler build-project $ProjectFile $Builtins $output @Defines 2>&1 | Tee-Object -FilePath (Join-Path $MirrorRoot "$phase.log")
            }
            if ($LASTEXITCODE -ne 0) { throw "$phase build failed." }
            $clock.Stop()
            Write-Host "$phase elapsed $($clock.Elapsed.TotalSeconds.ToString('F3')) seconds"
        }
    } finally { Pop-Location }
} finally {
    $env:GIT_DIR = $savedGitDirectory
    $env:DM_BUILD_TRACE = $savedTrace
    if ([IO.File]::ReadAllText($original) -cne $before) { throw 'Original source changed during measurement.' }
    Write-Host "Measurement mirror retained at $MirrorRoot"
}

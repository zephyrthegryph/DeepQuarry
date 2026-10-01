#requires -Version 7.0
<#
.SYNOPSIS
Replay real commits in an owned linked worktree and compare native cached/fresh bytes.
.DESCRIPTION
Never checks out or edits the source repository. The daemon stays alive across
revisions; each reference process gets an empty cache root covering every stage.
Stops only owned processes on timeout or aggregate-memory overrun. No DD runs.
#>
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Daemon,
    [string]$SourceRoot = "$PSScriptRoot/../../..",
    [string]$Builtins = "$PSScriptRoot/../fixtures/native_template.bin",
    [string[]]$Commits = @(),
    [ValidateRange(1, 100)][int]$Last = 3,
    [string]$ProjectFile = 'deepquarry.dme',
    [string[]]$Defines = @('-DCBT', '-DCIBUILDING', '-DCITESTING'),
    [string]$OutputRoot = '',
    [string]$AssetOverlayRoot = '',
    [string[]]$AssetDirectories = @('icons/gen'),
    [ValidateRange(256, 2048)][int]$DaemonMemoryMb = 1536,
    [ValidateRange(256, 2048)][int]$ClientMemoryMb = 1536,
    [ValidateRange(512, 4096)][int]$AggregateMemoryMb = 2048,
    [ValidateRange(10, 1800)][int]$TimeoutSeconds = 900,
    [switch]$KeepFreshArtifacts
)
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/process.psm1" -Force
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Daemon = (Resolve-Path -LiteralPath $Daemon).Path
$Builtins = (Resolve-Path -LiteralPath $Builtins).Path
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
if (!$OutputRoot) { $OutputRoot = Join-Path $SourceRoot "tools/dmb/target/replay-$([Guid]::NewGuid().ToString('N').Substring(0, 10))" }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new and exclusively owned by this run.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$worktree = [IO.Path]::GetFullPath((Join-Path $OutputRoot 'worktree'))
$ownedPrefix = $OutputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (!$worktree.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Worktree must stay inside the owned output root.' }
$project = [IO.Path]::GetFullPath((Join-Path $worktree $ProjectFile))
if (!$project.StartsWith($worktree + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'ProjectFile must identify a project within the owned worktree.' }
function Git([string]$Directory, [string[]]$Arguments) {
    $text = & git -C $Directory -c core.longpaths=true @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git replay operation failed: $text" }
    return @($text | ForEach-Object { "$_" })
}
if ($Commits.Count) {
    $revisions = @($Commits | ForEach-Object { @(Git $SourceRoot @('rev-parse', '--verify', '--end-of-options', "$_^{commit}"))[0] })
} else {
    $revisions = @(Git $SourceRoot @('rev-list', '--first-parent', "--max-count=$Last", 'HEAD'))
    [Array]::Reverse($revisions)
}
if (!$revisions.Count) { throw 'No commits selected.' }
[void](Git $SourceRoot @('worktree', 'add', '--detach', $worktree, $revisions[0]))

# Optional ignored assets are copied once, outside any tracked source path. The
# result records this overlay: it is not represented as a pristine Git snapshot.
$overlayDigest = $null
if ($AssetOverlayRoot) {
    $AssetOverlayRoot = (Resolve-Path -LiteralPath $AssetOverlayRoot).Path
    $overlayRecords = [Collections.Generic.List[string]]::new()
    foreach ($directory in $AssetDirectories) {
        $destination = [IO.Path]::GetFullPath((Join-Path $worktree $directory))
        if (!$destination.StartsWith($worktree + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Asset overlay destination escapes the owned worktree.' }
        $source = Join-Path $AssetOverlayRoot $directory
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
            $relative = [IO.Path]::GetRelativePath($AssetOverlayRoot, $file.FullName)
            $target = Join-Path $worktree $relative
            $tracked = & git -C $worktree ls-files --error-unmatch -- $relative 2>$null
            if ($LASTEXITCODE -eq 0) { continue }
            if (Test-Path -LiteralPath $target) { throw "Overlay would replace an existing file: $target" }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
            $overlayRecords.Add("$relative $((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)")
        }
    }
    $overlayText = (@($overlayRecords | Sort-Object) -join "`n")
    $overlayDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($overlayText))).ToLowerInvariant()
    $overlayText | Set-Content -LiteralPath (Join-Path $OutputRoot 'asset-overlay.txt')
}
$cache = Join-Path $OutputRoot 'shared-cache'
$rows = [Collections.Generic.List[object]]::new()
$peak = 0L
$report = [ordered]@{ schema = 1; ok = $false; compiler_sha256 = (Get-FileHash -LiteralPath $Compiler).Hash; builtin_sha256 = (Get-FileHash -LiteralPath $Builtins).Hash; target = '516.1687'; source_repository = $SourceRoot; owned_worktree = $worktree; commit_order = $revisions; defines = $Defines; overlay_root = $AssetOverlayRoot; overlay_manifest_sha256 = $overlayDigest; aggregate_limit_mb = $AggregateMemoryMb; sampled_peak_private_bytes = 0L; fallback_count = 0; revisions = @(); failure = $null }
function Save-Report {
    $report.revisions = $rows.ToArray()
    $report.sampled_peak_private_bytes = $script:peak
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputRoot 'replay.json')
}
function Assert-CleanSource {
    # Only generated output directories installed by this driver are excluded.
    # Ordinary checkout still refuses to overwrite ignored/untracked collisions.
    $changes = @(Git $worktree @('status', '--porcelain', '--untracked-files=all', '--', '.', ':(exclude).dm-native/**'))
    if ($changes.Count) { throw "Owned replay source changed unexpectedly; preserving it: $($changes -join '; ')" }
}
try {
    $daemonInfo = Start-CompilerDaemon $Daemon $worktree $cache (Join-Path $OutputRoot 'daemon') $DaemonMemoryMb 1
    for ($i = 0; $i -lt $revisions.Count; $i++) {
        $revision = $revisions[$i]
        Assert-CleanSource
        [void](Git $worktree @('checkout', '--detach', '--no-overwrite-ignore', $revision))
        if (!(Test-Path -LiteralPath $project -PathType Leaf)) { throw "Project is absent at $revision" }
        Write-Host "Native commit replay $($i + 1)/$($revisions.Count): $revision"
        $prefix = Join-Path $OutputRoot "$i-incremental"
        $nativeReport = "$prefix.json"
        $arguments = @('integrated-build', $project, '--mode', 'native', '--strict', '--builtins', $Builtins, '--daemon', $daemonInfo.Address, '--output-root', (Join-Path $OutputRoot 'native-output'), '--report', $nativeReport) + $Defines
        $run = Start-CompilerRun $Compiler $worktree $arguments $prefix @{ DM_COMPILER_CACHE_ROOT = $cache; DQ_COMPILER_STRICT = '1'; DQ_NATIVE_TARGET = '516.1687' } $ClientMemoryMb
        $nativeTiming = Wait-CompilerRun $run $TimeoutSeconds $AggregateMemoryMb
        $peak = [Math]::Max($peak, $nativeTiming.sampled_peak_private_bytes)
        if ($daemonInfo.Run.Process.HasExited) { throw 'Replay daemon exited.' }
        $native = Get-Content -LiteralPath $nativeReport -Raw | ConvertFrom-Json
        $freshRoot = [IO.Path]::GetFullPath((Join-Path $OutputRoot "fresh-$i"))
        $freshPrefix = Join-Path $OutputRoot "$i-fresh"
        $freshRun = Start-CompilerRun $Compiler $worktree (@('build-project-json', $project, $Builtins, (Join-Path $freshRoot 'output')) + $Defines) $freshPrefix @{ DM_COMPILER_CACHE_ROOT = (Join-Path $freshRoot 'cache'); DQ_NATIVE_DAEMON = $null; DQ_NATIVE_TARGET = '516.1687' } $ClientMemoryMb
        $freshTiming = Wait-CompilerRun $freshRun $TimeoutSeconds $AggregateMemoryMb
        $peak = [Math]::Max($peak, $freshTiming.sampled_peak_private_bytes)
        $fresh = Get-Content -LiteralPath "$freshPrefix.stdout.log" -Raw | ConvertFrom-Json
        $row = [ordered]@{ commit = $revision; incremental_runtime_seconds = $nativeTiming.runtime_seconds; fresh_runtime_seconds = $freshTiming.runtime_seconds; incremental_ok = $native.ok; fresh_ok = $fresh.ok; incremental_failure = $native.failure; fresh_error = $fresh.error; fallback = $native.fallback; same_source_revision = $native.source_digest -eq $fresh.source_digest; incremental_source_digest = $native.source_digest; fresh_source_digest = $fresh.source_digest; generation = $native.build.generation; fresh_generation = $fresh.build.generation; emitted_procs = $native.build.emitted_procs; lowered_procs = $native.build.lowered_procs; reused_procs = $native.build.reused_procs; dmb_sha256 = $null; fresh_dmb_sha256 = $null; rsc_sha256 = $null; fresh_rsc_sha256 = $null; bytes_match = $false }
        if ($native.fallback) { $report.fallback_count++ }
        if ($nativeTiming.exit_code -eq 0 -and $freshTiming.exit_code -eq 0 -and $native.ok -and $fresh.ok) {
            $row.dmb_sha256 = (Get-FileHash -LiteralPath $native.build.dmb -Algorithm SHA256).Hash
            $row.fresh_dmb_sha256 = (Get-FileHash -LiteralPath $fresh.build.dmb -Algorithm SHA256).Hash
            $row.rsc_sha256 = (Get-FileHash -LiteralPath $native.build.rsc -Algorithm SHA256).Hash
            $row.fresh_rsc_sha256 = (Get-FileHash -LiteralPath $fresh.build.rsc -Algorithm SHA256).Hash
            $row.bytes_match = $row.dmb_sha256 -eq $row.fresh_dmb_sha256 -and $row.rsc_sha256 -eq $row.fresh_rsc_sha256
        }
        $rows.Add([pscustomobject]$row)
        Save-Report
        if (!$native.ok -or !$fresh.ok -or $native.fallback -or $native.producing_compiler -ne 'native' -or !$native.native_gate_passed) { throw 'Commit replay requires successful native compilation with zero fallback; inspect raw logs and classifications.' }
        if (!$row.same_source_revision -or !$row.bytes_match) { throw 'Incremental/fresh outputs differ or source changed during comparison.' }
        if (!$KeepFreshArtifacts -and (Test-Path -LiteralPath $freshRoot)) {
            if (!$freshRoot.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fresh cleanup target escapes the owned root.' }
            if ((Get-Item -LiteralPath $freshRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fresh cleanup target is a reparse point; preserving it.' }
            Remove-Item -LiteralPath $freshRoot -Recurse -Force
        }
    }
    $report.ok = $true
    Save-Report
    Write-Host "Commit replay passed; report: $OutputRoot/replay.json"
} catch {
    $report.failure = $_.Exception.Message
    Save-Report
    throw
} finally {
    Close-CompilerRuns
    # Keep the owned linked worktree and failing artifacts for review. Removing
    # it later should use git worktree remove after checking for human changes.
}

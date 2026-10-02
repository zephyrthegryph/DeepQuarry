#requires -Version 7.0
<#
.SYNOPSIS
Compare canonical and cache-free native builds in six owned game worktrees.
.DESCRIPTION
Pins an explicit Git commit, snapshots generated assets once, and edits only an
owned probe included by an owned root-level DME. One heavy process runs at a time:
the daemon is stopped before each set of isolated fresh builds. No worlds run.
PlanOnly validates inputs and prints the plan without creating directories,
checking out worktrees, copying assets, or starting compiler processes.
#>
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Daemon,
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$GitRef,
    [string]$Builtins = "$PSScriptRoot/../fixtures/native_template.bin",
    [string]$ProjectFile = 'deepquarry.dme',
    [string[]]$Defines = @('-DCBT', '-DCIBUILDING', '-DCITESTING'),
    [string]$AssetOverlayRoot = '',
    [string[]]$AssetDirectories = @('icons/gen'),
    [string]$OutputRoot = '',
    [ValidateRange(256, 2048)][int]$DaemonMemoryMb = 2048,
    [ValidateRange(64, 256)][int]$TransportMemoryMb = 256,
    [ValidateRange(256, 2048)][int]$FreshMemoryMb = 2048,
    [ValidateRange(512, 2048)][int]$AggregateMemoryMb = 2048,
    [ValidateRange(10, 1800)][int]$TimeoutSeconds = 900,
    [switch]$PlanOnly,
    [switch]$KeepFreshArtifacts,
    [switch]$CleanupWorktrees
)
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/process.psm1" -Force
$utf8 = [Text.UTF8Encoding]::new($false)
$wrapperName = '__dq_acceptance.dme'
$probeName = '__dq_acceptance_probe.dm'
$rows = [Collections.Generic.List[object]]::new()
$worktrees = [Collections.Generic.List[object]]::new()
$junctions = [Collections.Generic.List[object]]::new()
$assets = [Collections.Generic.List[object]]::new()
$ownedRootCreated = $false
$daemonInfo = $null
$daemonSequence = 0
$peak = 0L
$report = [ordered]@{
    schema = 2; mode = 'owned-game'; ok = $false; native_gate_passed = $false
    target = '516.1687'; source_repository = $Repository; requested_ref = $GitRef
    commit = $null; defines = $Defines; project = $ProjectFile
    owned_root = $null; overlay_project = $wrapperName; overlay_probe = $probeName
    compiler_sha256 = $null; daemon_sha256 = $null; builtin_sha256 = $null
    asset_overlay_root = $null; asset_manifest_sha256 = $null; asset_files = 0; asset_bytes = 0L
    asset_manifest = $null
    max_clients = 1; daemon_workers = 1; lowering_workers = 1
    daemon_limit_mb = $DaemonMemoryMb; transport_limit_mb = $TransportMemoryMb
    fresh_limit_mb = $FreshMemoryMb; aggregate_limit_mb = $AggregateMemoryMb
    sampled_peak_private_bytes = 0L; fallback_count = 0; phases = @()
    worktrees = @(); failure = $null; cleanup = @()
}

function Invoke-OwnedGit([string]$Directory, [string[]]$Arguments) {
    $lines = & git -C $Directory -c core.longpaths=true @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git acceptance operation failed: $($lines -join '; ')" }
    return @($lines | ForEach-Object { "$_" })
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-TextSha([string]$Text) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($Text))).ToLowerInvariant() }
function Write-NewText([string]$Path, [string]$Text) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = $utf8.GetBytes($Text); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}
function Assert-Within([string]$Path, [string]$Root) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (!$absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes its owned root: $absolute" }
    return $absolute
}
function Assert-NoReparse([string]$Path) {
    # Check every existing ancestor, so a safe-looking child cannot redirect a
    # recursive operation into another workspace through an ancestor junction.
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Unexpected reparse point: $cursor" }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
function Save-Report {
    $report.phases = $rows.ToArray()
    $report.worktrees = @($worktrees | ForEach-Object { [pscustomobject]@{ index = $_.Index; path = $_.Path; probe_sha256 = $_.ProbeSha } })
    $report.sampled_peak_private_bytes = $script:peak
    if ($ownedRootCreated) {
        $temporary = Join-Path $OutputRoot 'acceptance.json.tmp'
        $report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $temporary -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination (Join-Path $OutputRoot 'acceptance.json') -Force
    }
}
function Get-Probe([string]$State, [int]$Index) {
    $default = if ($State -eq 'default-edit') { 50 + $Index } else { 7 }
    $body = if ($State -eq 'body-edit') { 8 + $Index } else { 7 }
    $signature = if ($State -eq 'signature-edit') { "acceptance_argument = $(70 + $Index)" } else { '' }
    $text = "/datum/__dq_compiler_acceptance_fixture`n    var/acceptance_value = $default`n"
    if ($State -eq 'new-var') { $text += "    var/acceptance_added = $(20 + $Index)`n" }
    $text += "/proc/__dq_compiler_acceptance_probe($signature)`n    return $body`n"
    if ($State -eq 'new-proc') { $text += "/proc/__dq_compiler_acceptance_added()`n    return $(30 + $Index)`n" }
    return $text
}
function Assert-CleanSource($Worktree) {
    $exclusions = @($relativeAssets | ForEach-Object { ":(exclude)$_" })
    $changes = @(Invoke-OwnedGit $Worktree.Path (@('status', '--porcelain', '--untracked-files=all', '--ignored', '--', '.', ":(exclude)$wrapperName", ":(exclude)$probeName", ':(exclude)__dq_acceptance.dmb', ':(exclude)__dq_acceptance.rsc', ':(exclude).dm-native/publication/__dq_acceptance.dme/**') + $exclusions))
    if ($changes.Count) { throw "Owned worktree has unexpected human/source changes; preserving it: $($changes -join '; ')" }
    if ((Get-Sha (Join-Path $Worktree.Path $wrapperName)) -ne $Worktree.WrapperSha -or (Get-Sha (Join-Path $Worktree.Path $probeName)) -ne $Worktree.ProbeSha) { throw 'Owned probe or manifest changed outside this driver; preserving it.' }
    if (@(Invoke-OwnedGit $Worktree.Path @('rev-parse', 'HEAD'))[0] -ne $report.commit) { throw 'Owned worktree HEAD changed outside this driver.' }
}
function Set-Probe([string]$State) {
    foreach ($worktree in $worktrees) {
        Assert-CleanSource $worktree
        $path = Join-Path $worktree.Path $probeName
        Assert-NoReparse $path
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $previous = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
            if ($previous -ne $worktree.ProbeSha) { throw 'Probe changed before the exclusive edit lock; preserving it.' }
            $bytes = $utf8.GetBytes((Get-Probe $State $worktree.Index))
            $stream.Position = 0; $stream.SetLength(0); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true)
            $worktree.ProbeSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        } finally { $stream.Dispose() }
    }
}
function Check-Memory {
    $bytes = Get-CompilerPrivateMemory
    $script:peak = [Math]::Max($script:peak, $bytes)
    if ($bytes -gt [long]$AggregateMemoryMb * 1MB) { throw "Owned aggregate memory exceeded $AggregateMemoryMb MiB; limits are never raised automatically." }
}
function Wait-Owned($Run) {
    while (!$Run.Process.HasExited) {
        Check-Memory
        if ($Run.Started.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw "Native acceptance timed out: $($Run.Prefix)" }
        Start-Sleep -Milliseconds 25
    }
    Complete-CompilerRun $Run
    return [pscustomobject]@{ exit_code = $Run.Process.ExitCode; runtime_seconds = ($Run.Process.ExitTime - $Run.Process.StartTime).TotalSeconds }
}
function Start-Daemon {
    if ($script:daemonInfo -and !$script:daemonInfo.Run.Finished) { throw 'An owned daemon is already running.' }
    $script:daemonSequence++
    $script:daemonInfo = Start-CompilerDaemon $Daemon $worktrees[0].Path $cache (Join-Path $OutputRoot "daemon-$daemonSequence") $DaemonMemoryMb 1 @{ DM_COMPILER_WORKERS = '1'; DQ_COMPILER_STRICT = '1'; DQ_NATIVE_DAEMON = $null; DQ_NATIVE_TARGET = '516.1687' }
}
function Stop-Daemon {
    if ($script:daemonInfo -and !$script:daemonInfo.Run.Finished) { Complete-CompilerRun $script:daemonInfo.Run -Stop }
}
function Remove-OwnedTree([string]$Path) {
    $target = Assert-Within $Path $OutputRoot
    Assert-NoReparse $target
    if (!(Test-Path -LiteralPath $target)) { return }
    # Reject nested links too; Remove-Item must never be trusted to decide which
    # junctions to traverse on a different PowerShell/Windows version.
    foreach ($entry in Get-ChildItem -LiteralPath $target -Force -Recurse) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Cleanup contains a reparse point; preserving $target" }
    }
    Remove-Item -LiteralPath $target -Recurse -Force
}
function Assert-Junction($Junction) {
    [void](Assert-Within $Junction.Path $OutputRoot)
    Assert-NoReparse ([IO.Path]::GetDirectoryName($Junction.Path))
    $info = [IO.DirectoryInfo]::new($Junction.Path)
    if (!($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Owned asset junction replaced: $($Junction.Path)" }
    $target = $info.ResolveLinkTarget($true)
    if (!$target -or ![string]::Equals($target.FullName.TrimEnd('\'), $Junction.Target.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { throw "Owned asset junction target changed: $($Junction.Path)" }
    Assert-NoReparse $Junction.Target
}
function Validate-Assets {
    foreach ($junction in $junctions) { Assert-Junction $junction }
    if ((Get-Sha $report.asset_manifest) -ne $report.asset_manifest_sha256) { throw 'Frozen asset manifest changed.' }
    $inventory = @(Get-ChildItem -LiteralPath $snapshot -Force -Recurse -File)
    if ($inventory.Count -ne $assets.Count + 1) { throw 'Frozen asset inventory changed.' }
    foreach ($asset in $assets) {
        Assert-NoReparse $asset.Path
        if ((Get-Sha $asset.Path) -ne $asset.Sha256) { throw "Frozen asset changed: $($asset.Relative)" }
    }
}
function Compare-State([string]$Name, [string]$ProbeState = 'baseline', [switch]$ExpectBaseline) {
    Write-Host "Owned game acceptance: $Name (six worktrees; one compiler request at a time)"
    foreach ($worktree in $worktrees) {
        Assert-CleanSource $worktree
        $prefix = Join-Path $OutputRoot "$Name-$($worktree.Index)-cached"
        $responsePath = "$prefix.json"
        $arguments = @('integrated-build', $wrapperName, '--mode', 'native', '--strict', '--builtins', $Builtins, '--daemon', $daemonInfo.Address, '--output-root', (Join-Path $OutputRoot "native-$($worktree.Index)"), '--report', $responsePath) + $Defines
        $run = Start-CompilerRun $Compiler $worktree.Path $arguments $prefix @{ DM_COMPILER_CACHE_ROOT = $cache; DM_COMPILER_WORKERS = '1'; DQ_COMPILER_STRICT = '1'; DQ_NATIVE_TARGET = '516.1687'; DQ_NATIVE_DAEMON = $null } $TransportMemoryMb
        $timing = Wait-Owned $run
        if ($daemonInfo.Run.Process.HasExited) { throw 'The owned daemon exited during compilation.' }
        $native = if (Test-Path -LiteralPath $responsePath) { Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json } else { $null }
        $row = [ordered]@{ phase = $Name; probe_state = $ProbeState; worktree = $worktree.Index; probe_sha256 = $worktree.ProbeSha; cached_seconds = $timing.runtime_seconds; fresh_seconds = $null; cached_exit = $timing.exit_code; fresh_exit = $null; source_digest = $native.source_digest; fresh_source_digest = $null; generation = $native.build.generation; fresh_generation = $null; lowered_procs = $native.build.lowered_procs; reused_procs = $native.build.reused_procs; rsc_reused = $native.conventional.reused_archive; producing_compiler = $native.producing_compiler; fallback = $native.fallback; failure = $native.failure; dmb_sha256 = $null; rsc_sha256 = $null; fresh_dmb_sha256 = $null; fresh_rsc_sha256 = $null; bytes_match = $false; cached_response = $responsePath; fresh_response = $null; fresh_failure_kind = $null; fresh_error = $null }
        $rows.Add($row)
        if ($native.fallback) { $report.fallback_count++ }
        Save-Report
        if ($timing.exit_code -ne 0 -or !$native.ok -or $native.fallback -or $native.producing_compiler -ne 'native' -or !$native.native_gate_passed) { throw "Native gate failed ($Name, worktree $($worktree.Index)); no fallback is accepted." }
        $row.dmb_sha256 = Get-Sha $native.build.dmb; $row.rsc_sha256 = Get-Sha $native.build.rsc
        if ($ExpectBaseline -and $baseline.ContainsKey($worktree.Index) -and ($row.generation -ne $baseline[$worktree.Index])) { throw 'Canonical generation changed after reverting an owned edit.' }
        if ($ProbeState -ne 'baseline' -and $row.generation -eq $baseline[$worktree.Index]) { throw 'An authored probe edit did not change the generated output.' }
        Assert-CleanSource $worktree
    }
    Save-Report
}
function Compare-FreshState([string]$Name) {
    if ($daemonInfo -and !$daemonInfo.Run.Finished) { throw 'Fresh reference requires the daemon to be stopped.' }
    $stateRows = @($rows | Where-Object { $_.phase -eq $Name })
    if ($stateRows.Count -ne 6) { throw 'Each state must contain exactly six cached builds.' }
    Set-Probe $stateRows[0].probe_state
    foreach ($row in $stateRows) {
        $worktree = $worktrees[$row.worktree]
        Assert-CleanSource $worktree
        if ($worktree.ProbeSha -ne $row.probe_sha256) { throw 'Fresh replay did not restore the exact cached probe revision.' }
        $freshRoot = Assert-Within (Join-Path $OutputRoot "fresh-$Name-$($worktree.Index)") $OutputRoot
        if (Test-Path -LiteralPath $freshRoot) { throw 'Fresh reference cache must be absent before compilation.' }
        $prefix = Join-Path $OutputRoot "$Name-$($worktree.Index)-fresh"
        $row.fresh_response = "$prefix.stdout.log"
        $run = Start-CompilerRun $Compiler $worktree.Path (@('build-project-json', $wrapperName, $Builtins, (Join-Path $freshRoot 'output')) + $Defines) $prefix @{ DM_COMPILER_CACHE_ROOT = (Join-Path $freshRoot 'cache'); DM_COMPILER_WORKERS = '1'; DM_DAEMON_WORKERS = '1'; DQ_COMPILER_STRICT = '1'; DQ_NATIVE_DAEMON = $null; DQ_NATIVE_TARGET = '516.1687' } $FreshMemoryMb
        $timing = Wait-Owned $run
        $fresh = Get-Content -LiteralPath "$prefix.stdout.log" -Raw | ConvertFrom-Json
        $row.fresh_seconds = $timing.runtime_seconds; $row.fresh_exit = $timing.exit_code; $row.fresh_source_digest = $fresh.source_digest; $row.fresh_generation = $fresh.build.generation
        $row.fresh_failure_kind = $fresh.failure_kind; $row.fresh_error = $fresh.error
        Save-Report
        if ($timing.exit_code -ne 0 -or !$fresh.ok) { throw "Fresh native build failed ($Name, worktree $($worktree.Index)): $($fresh.failure_kind) $($fresh.error)" }
        $row.fresh_dmb_sha256 = Get-Sha $fresh.build.dmb; $row.fresh_rsc_sha256 = Get-Sha $fresh.build.rsc
        $row.bytes_match = $row.source_digest -eq $row.fresh_source_digest -and $row.dmb_sha256 -eq $row.fresh_dmb_sha256 -and $row.rsc_sha256 -eq $row.fresh_rsc_sha256
        Save-Report
        if (!$row.bytes_match) { throw "Cached/fresh full DMB/RSC mismatch or different source revision ($Name, worktree $($worktree.Index))." }
        Assert-CleanSource $worktree
        if (!$KeepFreshArtifacts) { Remove-OwnedTree $freshRoot }
    }
    Save-Report
}

try {
    if (!$IsWindows) { throw 'Owned generated-asset ACL/junction acceptance currently requires Windows.' }
    if ([string]::IsNullOrWhiteSpace($GitRef)) { throw 'An explicit Git ref is required.' }
    $Repository = (Resolve-Path -LiteralPath $Repository).Path
    $Compiler = (Resolve-Path -LiteralPath $Compiler).Path; $Daemon = (Resolve-Path -LiteralPath $Daemon).Path; $Builtins = (Resolve-Path -LiteralPath $Builtins).Path
    Assert-NoReparse $Repository
    $report.source_repository = $Repository
    $report.commit = @(Invoke-OwnedGit $Repository @('rev-parse', '--verify', '--end-of-options', "$GitRef^{commit}"))[0]
    if ($report.commit -notmatch '^[0-9a-f]{40,64}$') { throw 'Git did not resolve the explicit ref to one full commit ID.' }
    if ([IO.Path]::IsPathRooted($ProjectFile) -or $ProjectFile.Contains('"') -or $ProjectFile.Contains("`n") -or $ProjectFile.Contains("`r")) { throw 'ProjectFile must be a relative include path.' }
    $ProjectFile = [IO.Path]::GetRelativePath($Repository, (Assert-Within (Join-Path $Repository $ProjectFile) $Repository)).Replace('\', '/')
    if (!@(Invoke-OwnedGit $Repository @('ls-tree', '--name-only', $report.commit, '--', $ProjectFile)).Count) { throw 'ProjectFile is not present at the selected Git ref.' }
    foreach ($name in @($wrapperName, $probeName)) {
        if (@(Invoke-OwnedGit $Repository @('ls-tree', '--name-only', $report.commit, '--', $name)).Count) { throw 'Acceptance overlay paths already exist at the selected Git ref.' }
    }
    if (!$AssetOverlayRoot) { $AssetOverlayRoot = $Repository }
    $AssetOverlayRoot = (Resolve-Path -LiteralPath $AssetOverlayRoot).Path
    Assert-NoReparse $AssetOverlayRoot
    $report.asset_overlay_root = $AssetOverlayRoot
    $report.compiler_sha256 = Get-Sha $Compiler; $report.daemon_sha256 = Get-Sha $Daemon; $report.builtin_sha256 = Get-Sha $Builtins
    $relativeAssets = @($AssetDirectories | ForEach-Object { [IO.Path]::GetRelativePath($AssetOverlayRoot, (Assert-Within (Join-Path $AssetOverlayRoot $_) $AssetOverlayRoot)).Replace('\', '/') })
    for ($i = 0; $i -lt $relativeAssets.Count; $i++) {
        if ($relativeAssets[$i] -eq '.git' -or $relativeAssets[$i].StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase) -or $relativeAssets[$i] -eq 'manifest.sha256') { throw 'Reserved asset overlay path.' }
        foreach ($other in $relativeAssets) { if ($other -ne $relativeAssets[$i] -and $other.StartsWith($relativeAssets[$i] + '/', [StringComparison]::OrdinalIgnoreCase)) { throw 'Asset directories may not overlap.' } }
        $source = Join-Path $AssetOverlayRoot $relativeAssets[$i]
        if (!(Test-Path -LiteralPath $source -PathType Container)) { throw "Missing generated asset directory: $source" }
        Assert-NoReparse $source
        if (@(Invoke-OwnedGit $Repository @('ls-tree', '-r', '--name-only', $report.commit, '--', $relativeAssets[$i])).Count) { throw 'Asset overlay may only fill paths absent from the selected Git commit.' }
    }
    if (($relativeAssets | Sort-Object -Unique).Count -ne $relativeAssets.Count) { throw 'Asset directories must be unique.' }
    if (!$OutputRoot) { $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "dq-six-$([Guid]::NewGuid().ToString('N').Substring(0, 10))" }
    $OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
    Assert-NoReparse $OutputRoot
    if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new and exclusively owned by this run.' }
    $report.owned_root = $OutputRoot
    $report.project = $ProjectFile
    if ($PlanOnly) {
        $report['plan_only'] = $true
        $report['asset_directories'] = $relativeAssets
        $report['planned_phases'] = @('baseline', 'unchanged', 'body-edit', 'body-revert', 'new-proc', 'proc-revert', 'new-var', 'var-revert', 'default-edit', 'default-revert', 'signature-edit', 'signature-revert', 'disk-restart')
        $report['comparisons'] = 'Warm daemon builds all states, then six isolated cache-free full DMB/RSC comparisons replay every exact state with daemon stopped.'
        $report | ConvertTo-Json -Depth 12
        return
    }
    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
    $ownedRootCreated = $true; Save-Report
    $cache = Join-Path $OutputRoot 'shared-cache'; $snapshot = Join-Path $OutputRoot 'assets'
    New-Item -ItemType Directory -Path $snapshot | Out-Null
    foreach ($directory in $relativeAssets) {
        $sourceRoot = Join-Path $AssetOverlayRoot $directory
        $targetRoot = Assert-Within (Join-Path $snapshot $directory) $snapshot
        New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        foreach ($entry in Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Asset snapshot rejects nested reparse points: $($entry.FullName)" }
            if ($entry.PSIsContainer) { continue }
            $relative = [IO.Path]::GetRelativePath($AssetOverlayRoot, $entry.FullName).Replace('\', '/')
            $target = Assert-Within (Join-Path $snapshot $relative) $snapshot
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            # ShareRead prevents other handles writing/deleting this source file
            # while copied. The manifest describes the owned copy, not Git art.
            $inputStream = $null; $outputStream = $null
            try {
                $inputStream = [IO.File]::Open($entry.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $inputStream.CopyTo($outputStream, 65536)
            } finally { if ($inputStream) { $inputStream.Dispose() }; if ($outputStream) { $outputStream.Dispose() } }
            $assets.Add([pscustomobject]@{ Relative = $relative; Path = $target; Sha256 = (Get-Sha $target); Bytes = ([IO.FileInfo]::new($target)).Length })
        }
    }
    $manifest = (@($assets | Sort-Object Relative | ForEach-Object { "$($_.Sha256) $($_.Bytes) $($_.Relative)" }) -join "`n") + "`n"
    $report.asset_manifest = Join-Path $snapshot 'manifest.sha256'
    Write-NewText $report.asset_manifest $manifest
    $report.asset_manifest_sha256 = Get-TextSha $manifest; $report.asset_files = $assets.Count; $report.asset_bytes = [long](($assets | Measure-Object Bytes -Sum).Sum)
    # A junction alone is writable. Deny writes/deletion for this user's token
    # on the owned snapshot; no ACL on the user's generated art is changed.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rights = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, $rights, ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit), [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Deny)
    $acl = Get-Acl -LiteralPath $snapshot; $acl.AddAccessRule($rule); Set-Acl -LiteralPath $snapshot -AclObject $acl
    foreach ($i in 0..5) {
        $path = Assert-Within (Join-Path $OutputRoot "worktree-$i") $OutputRoot
        [void](Invoke-OwnedGit $Repository @('worktree', 'add', '--quiet', '--detach', $path, $report.commit))
        $worktree = [pscustomobject]@{ Index = $i; Path = $path; ProbeSha = $null; WrapperSha = $null }
        $worktrees.Add($worktree)
        foreach ($name in @($wrapperName, $probeName)) { if (Test-Path -LiteralPath (Join-Path $path $name)) { throw 'Acceptance overlay would replace an existing file.' } }
        # Keep the wrapper at the root: native resource paths resolve from the
        # project directory. An overlay under .dm-native would change that base.
        $wrapper = "#include `"$($ProjectFile.Replace('/', '\'))`"`n#include `"$probeName`"`n"
        Write-NewText (Join-Path $path $wrapperName) $wrapper
        Write-NewText (Join-Path $path $probeName) (Get-Probe 'baseline' $i)
        $worktree.WrapperSha = Get-TextSha $wrapper; $worktree.ProbeSha = Get-Sha (Join-Path $path $probeName)
        foreach ($directory in $relativeAssets) {
            $destination = Assert-Within (Join-Path $path $directory) $path
            if (Test-Path -LiteralPath $destination) { throw "Generated asset overlay path already exists: $destination" }
            Assert-NoReparse $destination
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
            $target = [IO.Path]::GetFullPath((Join-Path $snapshot $directory))
            New-Item -ItemType Junction -Path $destination -Target $target | Out-Null
            $junction = [pscustomobject]@{ Path = $destination; Target = $target; Worktree = $i }
            $junctions.Add($junction); Assert-Junction $junction
        }
        Assert-CleanSource $worktree
    }
    Validate-Assets; Save-Report
    $baseline = @{}
    Start-Daemon; Compare-State 'baseline'
    foreach ($row in $rows) { $baseline[$row.worktree] = $row.generation }
    Compare-State 'unchanged' -ExpectBaseline
    foreach ($edit in @(@('body-edit', 'body-revert'), @('new-proc', 'proc-revert'), @('new-var', 'var-revert'), @('default-edit', 'default-revert'), @('signature-edit', 'signature-revert'))) {
        Set-Probe $edit[0]; Compare-State $edit[0] -ProbeState $edit[0]
        Set-Probe 'baseline'; Compare-State $edit[1] -ExpectBaseline
    }
    Stop-Daemon; Start-Daemon; Compare-State 'disk-restart' -ExpectBaseline
    # Preserve warm edit measurements above. Replay those exact source states
    # later for references, with no retained daemon competing for game memory.
    Stop-Daemon; Validate-Assets
    foreach ($name in @($rows | ForEach-Object { $_.phase } | Select-Object -Unique)) { Compare-FreshState $name }
    Set-Probe 'baseline'
    Validate-Assets
    $report.ok = $true; $report.native_gate_passed = $true; Save-Report
    Write-Host "Owned game acceptance passed; report: $OutputRoot/acceptance.json"
} catch {
    $report.failure = $_.Exception.Message
    Save-Report
    # Even a preflight failure that cannot safely create an owned output root
    # produces structured JSON, without writing into an existing human folder.
    $report | ConvertTo-Json -Depth 16 | Write-Output
    throw
} finally {
    Close-CompilerRuns
    if ($CleanupWorktrees -and $report.ok) {
        $cleanupRows = [Collections.Generic.List[object]]::new()
        foreach ($worktree in $worktrees) {
            try {
                Assert-CleanSource $worktree
                foreach ($junction in @($junctions | Where-Object Worktree -eq $worktree.Index)) {
                    Assert-Junction $junction
                    # Delete only the verified link entry, never recursively.
                    [IO.Directory]::Delete($junction.Path, $false)
                }
                Assert-NoReparse $worktree.Path
                foreach ($entry in Get-ChildItem -LiteralPath $worktree.Path -Force -Recurse) {
                    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected nested reparse point; preserving worktree.' }
                }
                [void](Invoke-OwnedGit $Repository @('worktree', 'remove', '--force', $worktree.Path))
                $cleanupRows.Add([pscustomobject]@{ worktree = $worktree.Index; removed = $true; reason = $null })
            } catch { $cleanupRows.Add([pscustomobject]@{ worktree = $worktree.Index; removed = $false; reason = $_.Exception.Message }) }
        }
        $report.cleanup = $cleanupRows.ToArray(); Save-Report
    }
    # Failed runs and the frozen asset snapshot stay available for inspection.
    # No recursive cleanup of a worktree containing an asset junction occurs.
}

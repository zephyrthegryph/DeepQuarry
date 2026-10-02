#requires -Version 7.0
<#
.SYNOPSIS
Check canonical native builds across six worktrees without launching a world.
.DESCRIPTION
With no Worktrees, creates a tiny Git repository and six actual linked worktrees.
Supplied worktrees are built read-only; body/revert checks run only on owned fixtures.
At most two clients run together. All processes are owned by this script, hidden,
have compiler memory ceilings, and are stopped if sampled aggregate memory exceeds
the budget. Cache-free comparisons run sequentially with the daemon stopped.
#>
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Daemon,
    [string]$Builtins = "$PSScriptRoot/../fixtures/native_template.bin",
    [ValidateCount(0, 6)][string[]]$Worktrees = @(),
    [string]$ProjectFile = 'deepquarry.dme',
    [string[]]$Defines = @(),
    [string]$OutputRoot = '',
    [string]$OwnedGameRepository = '',
    [string]$GitRef = '',
    [string]$AssetOverlayRoot = '',
    [string[]]$AssetDirectories = @('icons/gen'),
    [ValidateRange(64, 256)][int]$TransportMemoryMb = 256,
    [ValidateRange(256, 2048)][int]$FreshMemoryMb = 2048,
    [switch]$PlanOnly,
    [switch]$KeepFreshArtifacts,
    [switch]$CleanupWorktrees,
    [ValidateRange(1, 2)][int]$MaxClients = 2,
    [ValidateRange(256, 2048)][int]$DaemonMemoryMb = 1536,
    [ValidateRange(256, 2048)][int]$ClientMemoryMb = 1024,
    [ValidateRange(512, 4096)][int]$AggregateMemoryMb = 2048,
    [ValidateRange(10, 1800)][int]$TimeoutSeconds = 900
)
$ErrorActionPreference = 'Stop'
if ($OwnedGameRepository) {
    try {
        if ($Worktrees.Count) { throw 'OwnedGameRepository and supplied Worktrees are separate acceptance modes.' }
        if ($PSBoundParameters.ContainsKey('MaxClients') -and $MaxClients -ne 1) { throw 'Owned game acceptance currently permits one transport client.' }
        if ($PSBoundParameters.ContainsKey('ClientMemoryMb')) { throw 'Use TransportMemoryMb and FreshMemoryMb for owned game acceptance.' }
        if ($AggregateMemoryMb -gt 2048) { throw 'Owned game acceptance caps its aggregate budget at 2048 MiB.' }
    } catch {
        [pscustomobject]@{ schema = 2; mode = 'owned-game'; ok = $false; native_gate_passed = $false; failure = $_.Exception.Message } | ConvertTo-Json
        throw
    }
    $ownedArguments = @{ Compiler = $Compiler; Daemon = $Daemon; Builtins = $Builtins; Repository = $OwnedGameRepository; GitRef = $GitRef; ProjectFile = $ProjectFile; OutputRoot = $OutputRoot; AssetOverlayRoot = $AssetOverlayRoot; AssetDirectories = $AssetDirectories; TransportMemoryMb = $TransportMemoryMb; FreshMemoryMb = $FreshMemoryMb; AggregateMemoryMb = $AggregateMemoryMb; TimeoutSeconds = $TimeoutSeconds; PlanOnly = $PlanOnly; KeepFreshArtifacts = $KeepFreshArtifacts; CleanupWorktrees = $CleanupWorktrees }
    if ($PSBoundParameters.ContainsKey('DaemonMemoryMb')) { $ownedArguments.DaemonMemoryMb = $DaemonMemoryMb }
    if ($PSBoundParameters.ContainsKey('Defines')) { $ownedArguments.Defines = $Defines }
    & "$PSScriptRoot/accept-game-worktrees.ps1" @ownedArguments
    return
}
if ($PlanOnly -or $GitRef -or $AssetOverlayRoot -or $KeepFreshArtifacts -or $CleanupWorktrees) { throw 'These options require OwnedGameRepository; tiny and supplied-worktree modes retain their existing behavior.' }
Import-Module "$PSScriptRoot/process.psm1" -Force
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Daemon = (Resolve-Path -LiteralPath $Daemon).Path
$Builtins = (Resolve-Path -LiteralPath $Builtins).Path
if ($Worktrees.Count -ne 0 -and $Worktrees.Count -ne 6) { throw 'Supply exactly six worktrees, or none for the small fixture gate.' }
if (!$OutputRoot) { $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "dm-six-worktrees-$([Guid]::NewGuid().ToString('N'))" }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new; results are preserved for inspection.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$fixture = $Worktrees.Count -eq 0
$cache = Join-Path $OutputRoot 'shared-cache'
$rows = [Collections.Generic.List[object]]::new()
$overallPeak = 0L
$daemonJob = $null
$fixtureHeader = "/datum/probe_resources`n    var/asset = 'asset.txt'`n/proc/probe()`n    return "

function Invoke-FixtureGit([string]$Directory, [string[]]$Arguments) {
    $text = & git -C $Directory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git fixture setup failed: $text" }
}
if ($fixture) {
    $repository = Join-Path $OutputRoot 'repository'
    New-Item -ItemType Directory -Path $repository | Out-Null
    [IO.File]::WriteAllText((Join-Path $repository 'project.dme'), "#include `"probe.dm`"`n")
    [IO.File]::WriteAllText((Join-Path $repository 'probe.dm'), $fixtureHeader + "7`n")
    [IO.File]::WriteAllText((Join-Path $repository 'asset.txt'), "shared acceptance resource`n")
    Invoke-FixtureGit $repository @('init', '--quiet')
    Invoke-FixtureGit $repository @('add', 'project.dme', 'probe.dm', 'asset.txt')
    Invoke-FixtureGit $repository @('-c', 'user.name=Compiler acceptance', '-c', 'user.email=compiler-test@invalid', 'commit', '--quiet', '-m', 'Small compiler worktree fixture')
    $Worktrees = @(for ($i = 0; $i -lt 6; $i++) {
        $worktree = Join-Path $OutputRoot "worktree-$i"
        Invoke-FixtureGit $repository @('worktree', 'add', '--quiet', '--detach', $worktree, 'HEAD')
        $worktree
    })
    $ProjectFile = 'project.dme'
} else {
    $Worktrees = @($Worktrees | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
}
foreach ($worktree in $Worktrees) {
    if (!(Test-Path -LiteralPath (Join-Path $worktree $ProjectFile) -PathType Leaf)) { throw "Missing project in $worktree" }
}

function Start-Owned([string]$Executable, [string]$Directory, [string[]]$Arguments, [string]$Prefix, [string]$CacheRoot, [int]$MemoryMb) {
    Start-CompilerRun $Executable $Directory $Arguments $Prefix @{ DM_COMPILER_CACHE_ROOT = $CacheRoot; DM_DAEMON_WORKERS = '2'; DQ_COMPILER_STRICT = '1'; DQ_NATIVE_TARGET = '516.1687' } $MemoryMb
}
function Finish-Owned($Job, [switch]$Stop) {
    Complete-CompilerRun $Job -Stop:$Stop
}
function Check-Memory {
    $bytes = Get-CompilerPrivateMemory
    $script:overallPeak = [Math]::Max($script:overallPeak, $bytes)
    if ($bytes -gt [long]$AggregateMemoryMb * 1MB) { throw "Compiler aggregate memory exceeded $AggregateMemoryMb MiB; stopping owned processes." }
}
function Start-Daemon {
    $daemonInfo = Start-CompilerDaemon $Daemon $Worktrees[0] $cache (Join-Path $OutputRoot "daemon-$([Guid]::NewGuid().ToString('N'))") $DaemonMemoryMb 2
    $script:daemonJob = $daemonInfo.Run
    $script:address = $daemonInfo.Address
}
function Phase([string]$Name) {
    Write-Host "Native acceptance: $Name (six worktrees, at most $MaxClients clients)"
    $queue = [Collections.Generic.Queue[int]]::new()
    for ($i = 0; $i -lt 6; $i++) { $queue.Enqueue($i) }
    $active = [Collections.Generic.List[object]]::new()
    while ($queue.Count -or $active.Count) {
        while ($queue.Count -and $active.Count -lt $MaxClients) {
            $i = $queue.Dequeue()
            $report = Join-Path $OutputRoot "$Name-$i.json"
            $arguments = @('integrated-build', $ProjectFile, '--mode', 'native', '--strict', '--builtins', $Builtins, '--daemon', $address, '--report', $report) + $Defines
            $job = Start-Owned $Compiler $Worktrees[$i] $arguments (Join-Path $OutputRoot "$Name-$i") $cache $ClientMemoryMb
            $job | Add-Member -NotePropertyName Index -NotePropertyValue $i
            $job | Add-Member -NotePropertyName Report -NotePropertyValue $report
            $active.Add($job)
        }
        Check-Memory
        if ($daemonJob.Process.HasExited) { throw 'The compiler daemon exited during acceptance.' }
        foreach ($job in @($active.ToArray())) {
            if ($job.Started.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw "$Name timed out." }
            if (!$job.Process.HasExited) { continue }
            Finish-Owned $job
            if ($job.Process.ExitCode -ne 0) { throw "$Name worktree $($job.Index) failed; see $($job.Prefix).stderr.log" }
            $report = Get-Content -LiteralPath $job.Report -Raw | ConvertFrom-Json
            if (!$report.ok -or $report.fallback -or $report.producing_compiler -ne 'native' -or !$report.native_gate_passed) { throw 'Acceptance requires native success and zero fallback.' }
            $rows.Add([pscustomobject]@{ phase = $Name; worktree = $job.Index; elapsed_seconds = $job.Started.Elapsed.TotalSeconds; generation = $report.build.generation; source_digest = $report.source_digest; lowered_procs = $report.build.lowered_procs; reused_procs = $report.build.reused_procs; rsc_reused = $report.conventional.reused_archive; dmb = $report.build.dmb; rsc = $report.build.rsc })
            [void]$active.Remove($job)
        }
        Start-Sleep -Milliseconds 25
    }
}
try {
    Start-Daemon
    Phase 'warm'
    Phase 'unchanged'
    if ($fixture) {
        for ($i = 0; $i -lt 6; $i++) { [IO.File]::WriteAllText((Join-Path $Worktrees[$i] 'probe.dm'), $fixtureHeader + "$($i + 8)`n") }
        Phase 'body-edit'
        for ($i = 0; $i -lt 6; $i++) { [IO.File]::WriteAllText((Join-Path $Worktrees[$i] 'probe.dm'), $fixtureHeader + "7`n") }
        Phase 'revert'
        for ($i = 0; $i -lt 6; $i++) {
            $first = $rows | Where-Object { $_.phase -eq 'warm' -and $_.worktree -eq $i }
            $revert = $rows | Where-Object { $_.phase -eq 'revert' -and $_.worktree -eq $i }
            if ($first.generation -ne $revert.generation) { throw 'Canonical output changed after a body edit and revert.' }
        }
    }
    Finish-Owned $daemonJob -Stop
    Start-Daemon
    Phase 'disk-restart'
    Finish-Owned $daemonJob -Stop
    for ($i = 0; $i -lt 6; $i++) {
        Write-Host "Native acceptance: isolated fresh comparison $i"
        $isolated = Join-Path $OutputRoot "fresh-$i"
        $job = Start-Owned $Compiler $Worktrees[$i] (@('build-project-json', $ProjectFile, $Builtins, (Join-Path $isolated 'output')) + $Defines) (Join-Path $OutputRoot "fresh-$i") (Join-Path $isolated 'cache') $ClientMemoryMb
        while (!$job.Process.HasExited) {
            Check-Memory
            if ($job.Started.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'Fresh native comparison timed out.' }
            Start-Sleep -Milliseconds 25
        }
        Finish-Owned $job
        if ($job.Process.ExitCode -ne 0) { throw "Fresh native build failed; see $($job.Prefix).stderr.log" }
        $fresh = Get-Content -LiteralPath "$($job.Prefix).stdout.log" -Raw | ConvertFrom-Json
        $cached = $rows | Where-Object { $_.phase -eq 'disk-restart' -and $_.worktree -eq $i }
        if (!$fresh.ok) { throw 'Fresh response did not report success.' }
        if ($fresh.source_digest -ne $cached.source_digest) { throw 'Source changed between cached and fresh comparisons.' }
        foreach ($extension in @('dmb', 'rsc')) {
            if ((Get-FileHash -LiteralPath $cached.$extension).Hash -ne (Get-FileHash -LiteralPath $fresh.build.$extension).Hash) { throw "Cached/fresh $extension mismatch in worktree $i" }
        }
    }
    [pscustomobject]@{ schema = 1; native_gate_passed = $true; fallback_count = 0; fixture = $fixture; worktrees = 6; max_clients = $MaxClients; sampled_peak_private_bytes = $overallPeak; aggregate_limit_mb = $AggregateMemoryMb; cache = $cache; results = $rows.ToArray() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputRoot 'acceptance.json')
    Write-Host "Acceptance passed; report: $OutputRoot/acceptance.json"
} finally { Close-CompilerRuns }

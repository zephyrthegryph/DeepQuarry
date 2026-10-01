#requires -Version 7.0
<#
.SYNOPSIS
Measure two simultaneous body edits through a dedicated two-worker daemon.
.EXAMPLE
pwsh -File scripts/measure-concurrent-worktrees.ps1 -Compiler target/frozen-compiler.exe -Builtins fixtures/native_template.bin -DaemonAddress 127.0.0.1:47616 -DaemonProcessId 1234
.NOTES
Start a dedicated frozen daemon with DM_DAEMON_WORKERS=2 and its default aggregate
2 GiB process limit. This script creates private source mirrors, warms both,
then changes one literal-return procedure per mirror. It never edits original
game source and never launches DreamDaemon. It stops only its own CLI clients;
closing a client does not cancel an already admitted daemon compilation.
#>
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Builtins,
    [Parameter(Mandatory = $true)][string]$DaemonAddress,
    [Parameter(Mandatory = $true)][int]$DaemonProcessId,
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../../..").Path,
    [string]$BenchmarkRoot = '',
    [string]$ProjectFile = 'deepquarry.dme',
    [string[]]$Defines = @('-DCBT', '-DCIBUILDING', '-DCITESTING'),
    [ValidateCount(2, 2)][int[]]$BodyReturnValues = @(2, 3),
    [switch]$ReuseMirrors,
    [int]$TimeoutSeconds = 900,
    [int]$SampleIntervalMs = 25
)
$ErrorActionPreference = 'Stop'
if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 1800 -or $SampleIntervalMs -lt 5 -or $SampleIntervalMs -gt 1000) { throw 'Invalid timeout or sampling interval.' }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Builtins = (Resolve-Path -LiteralPath $Builtins).Path
$daemon = Get-Process -Id $DaemonProcessId
$daemonStarted = $daemon.StartTime
if (!$BenchmarkRoot) { $BenchmarkRoot = Join-Path $ProjectRoot "tools/dmb/target/concurrent-worktrees-$([Guid]::NewGuid().ToString('N'))" }
$BenchmarkRoot = [IO.Path]::GetFullPath($BenchmarkRoot)
if ((Test-Path -LiteralPath $BenchmarkRoot) -and !$ReuseMirrors) { throw 'Benchmark root must be new unless -ReuseMirrors is supplied.' }
New-Item -ItemType Directory -Path $BenchmarkRoot -Force | Out-Null
$editedRelative = 'code/datums/interactions/tools.dm'
$original = Join-Path $ProjectRoot $editedRelative
$before = [IO.File]::ReadAllText($original)
$pattern = '(?m)(^/proc/tool_skill_factor\(mob/actor, quality\)\r?\n\s*return )1(?=\r?$)'
if ([regex]::Matches($before, $pattern).Count -ne 1) { throw 'Expected isolated literal-return procedure was not found exactly once.' }
$mirrors = @((Join-Path $BenchmarkRoot 'first'), (Join-Path $BenchmarkRoot 'second'))
$results = [Collections.Generic.List[object]]::new()
$overallPeak = 0L

function Start-Client([string]$Mirror, [string]$Phase, [int]$Index) {
    $prefix = Join-Path $BenchmarkRoot "$Phase-$Index"
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Compiler
    $start.WorkingDirectory = $Mirror
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['DM_BUILD_TRACE'] = '1'
    foreach ($arg in @('build-project-daemon', $DaemonAddress, $ProjectFile, $Builtins, (Join-Path $Mirror 'timing-output')) + $Defines) { $start.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    $stdout = [IO.File]::Create("$prefix.stdout.log")
    $stderr = [IO.File]::Create("$prefix.stderr.log")
    try {
        $started = $process.Start()
        if (!$started) { throw 'Compiler client could not start.' }
        $copyOut = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
        $copyError = $process.StandardError.BaseStream.CopyToAsync($stderr)
        [pscustomobject]@{ Process = $process; Files = @($stdout, $stderr); Tasks = @($copyOut, $copyError); Prefix = $prefix; Mirror = $Mirror; Index = $Index }
    } catch {
        if ($started -and !$process.HasExited) { $process.Kill($true) }
        $stdout.Dispose(); $stderr.Dispose(); $process.Dispose()
        throw
    }
}

function Measure-Phase([string]$Phase, [string[]]$PhaseMirrors) {
    $jobs = [Collections.Generic.List[object]]::new()
    $daemon.Refresh()
    if ($daemon.HasExited -or $daemon.StartTime -ne $daemonStarted) { throw 'The supplied daemon exited or was replaced.' }
    $cpuBefore = $daemon.TotalProcessorTime.TotalSeconds
    $peak = $daemon.PrivateMemorySize64
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        for ($i = 0; $i -lt $PhaseMirrors.Count; $i++) { $jobs.Add((Start-Client $PhaseMirrors[$i] $Phase $i)) }
        while (@($jobs | Where-Object { !$_.Process.HasExited }).Count) {
            $daemon.Refresh()
            if ($daemon.HasExited) { throw 'The compiler daemon exited during measurement.' }
            $peak = [Math]::Max($peak, $daemon.PrivateMemorySize64)
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw "$Phase timed out; closing clients does not cancel admitted daemon requests." }
            Start-Sleep -Milliseconds $SampleIntervalMs
        }
        $daemon.Refresh()
        $peak = [Math]::Max($peak, $daemon.PrivateMemorySize64)
        $firstStart = ($jobs | ForEach-Object { $_.Process.StartTime.ToUniversalTime() } | Sort-Object | Select-Object -First 1)
        $lastExit = ($jobs | ForEach-Object { $_.Process.ExitTime.ToUniversalTime() } | Sort-Object | Select-Object -Last 1)
        $clients = @($jobs | ForEach-Object {
            foreach ($task in $_.Tasks) { [void]$task.GetAwaiter().GetResult() }
            foreach ($file in $_.Files) { $file.Dispose() }
            [pscustomobject]@{ worktree = $_.Mirror; elapsed_seconds = ($_.Process.ExitTime - $_.Process.StartTime).TotalSeconds; exit_code = $_.Process.ExitCode; stdout = "$($_.Prefix).stdout.log"; stderr = "$($_.Prefix).stderr.log" }
        })
        $result = [pscustomobject]@{ phase = $Phase; elapsed_seconds = ($lastExit - $firstStart).TotalSeconds; daemon_cpu_seconds = $daemon.TotalProcessorTime.TotalSeconds - $cpuBefore; daemon_peak_private_bytes = $peak; clients = $clients }
        $results.Add($result)
        $script:overallPeak = [Math]::Max($script:overallPeak, $peak)
        Write-Host ("{0}: wall {1:F3}s, daemon CPU {2:F3}s, aggregate daemon peak {3:F1} MiB" -f $Phase, $result.elapsed_seconds, $result.daemon_cpu_seconds, ($peak / 1MB))
        foreach ($client in $clients) {
            Get-Content -LiteralPath $client.stdout
            if ($client.exit_code -ne 0) { Get-Content -LiteralPath $client.stderr -Tail 20; throw "$Phase client failed with exit code $($client.exit_code)." }
        }
    } finally {
        foreach ($job in $jobs) {
            if (!$job.Process.HasExited) { $job.Process.Kill($true); $job.Process.WaitForExit() }
            foreach ($task in $job.Tasks) { try { [void]$task.GetAwaiter().GetResult() } catch {} }
            foreach ($file in $job.Files) { $file.Dispose() }
            $job.Process.Dispose()
        }
    }
}

try {
    foreach ($mirror in $mirrors) {
        & "$PSScriptRoot/measure-body-edit.ps1" -Compiler $Compiler -Builtins $Builtins -ProjectRoot $ProjectRoot -MirrorRoot $mirror -ProjectFile $ProjectFile -Defines $Defines -PrepareOnly -ReuseMirror:$ReuseMirrors
    }
    # Baselines run separately to establish each worker's warm project state.
    Measure-Phase 'baseline-first' @($mirrors[0])
    Measure-Phase 'baseline-second' @($mirrors[1])
    Measure-Phase 'warm-baselines' $mirrors
    for ($i = 0; $i -lt $mirrors.Count; $i++) {
        $replacement = '${1}' + $BodyReturnValues[$i]
        [IO.File]::WriteAllText((Join-Path $mirrors[$i] $editedRelative), [regex]::Replace($before, $pattern, $replacement), [Text.UTF8Encoding]::new($false))
    }
    Measure-Phase 'concurrent-body-edits' $mirrors
    Measure-Phase 'concurrent-unchanged' $mirrors
} finally {
    if ([IO.File]::ReadAllText($original) -cne $before) { throw 'Original source changed during measurement.' }
    $summary = [pscustomobject]@{ compiler = $Compiler; builtins = $Builtins; daemon_address = $DaemonAddress; daemon_process_id = $DaemonProcessId; body_return_values = $BodyReturnValues; sample_interval_ms = $SampleIntervalMs; aggregate_daemon_peak_private_bytes = $overallPeak; phases = @($results.ToArray()) }
    [IO.File]::WriteAllText((Join-Path $BenchmarkRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Write-Host "Measurement mirrors and logs retained at $BenchmarkRoot"
}

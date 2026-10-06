param(
    [string]$FrozenRoot='D:/dmb-native-v2-phase0/frozen',
    [string]$DreamDaemon='D:/Program Files (x86)/BYOND516/bin/dd.exe',
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=3600,
    [ValidateRange(128,65536)][int]$MemoryLimitMB=2048,
    [string]$ResumeSession,
    [string]$PauseBetweenRuns
)
$ErrorActionPreference='Stop'
if (-not ('Phase0ReplayErrorMode' -as [type])) { Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class Phase0ReplayErrorMode {
 [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
}
"@ }
$engineManifest=Join-Path $PSScriptRoot 'frozen-engine.json'
$engineManifestHash=(Get-FileHash -LiteralPath $engineManifest -Algorithm SHA256).Hash
function Test-PinnedEngineClosure {
    $audit=[ordered]@{phase='before-launch';checked_utc=[DateTime]::UtcNow.ToString('o');manifest=$engineManifest;manifest_sha256=$engineManifestHash;files=@();mismatches=@();matched=$false}
    if ((Get-FileHash -LiteralPath $engineManifest -Algorithm SHA256).Hash -ne $engineManifestHash) { throw 'Pinned engine manifest changed during replay.' }
    $pinned=Get-Content -LiteralPath $engineManifest -Raw | ConvertFrom-Json
    if (@($pinned.files).Count -ne 12) { throw 'Pinned engine closure must contain exactly12 files.' }
    $bin=[IO.Path]::GetFullPath($pinned.bin).TrimEnd('\','/')
    foreach ($row in $pinned.files) {
        $path=[IO.Path]::GetFullPath($row.path)
        if ([IO.Path]::GetDirectoryName($path).TrimEnd('\','/') -ne $bin -or [IO.Path]::GetExtension($path) -notin @('.exe','.dll')) { throw 'Engine manifest contains a file outside its declared bin closure.' }
        $actual=$null;$bytes=$null;$errorText=$null
        try { $bytes=(Get-Item -LiteralPath $path).Length;$actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } catch { $errorText=$_.Exception.Message }
        $match=($actual -eq $row.sha256 -and $bytes -eq $row.bytes -and $null -eq $errorText)
        $audit.files+=@{path=$path;sha256=$actual;bytes=$bytes;matched=$match;error=$errorText}
        if (-not $match) { $audit.mismatches+=$path }
    }
    if (@($audit.files | Where-Object {$_.path -eq $engine}).Count -ne 1) { throw 'Selected DreamDaemon is not in pinned engine closure.' }
    $audit.matched=($audit.mismatches.Count -eq 0)
    return $audit
}
$frozen=(Resolve-Path -LiteralPath $FrozenRoot).Path
$engine=(Resolve-Path -LiteralPath $DreamDaemon).Path
$runtimeSource=Join-Path $frozen 'runtime'
$selection=(Resolve-Path -LiteralPath (Join-Path $frozen 'expected-runnable-tests.txt')).Path
$selectionHash=(Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash
if (-not (Test-Path -LiteralPath $runtimeSource -PathType Container)) { throw 'Frozen runtime missing.' }
$fixture=Join-Path $runtimeSource 'code/modules/unit_tests/data/dq_constraint_parity.json'
if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) { throw 'Frozen runtime missing constraint parity fixture; repair freezer before replay. Existing evidence remains untouched.' }
$fixtureHash=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
$fixtureSource=Join-Path $frozen 'source/code/modules/unit_tests/data/dq_constraint_parity.json'
if ($fixtureHash -ne (Get-FileHash -LiteralPath $fixtureSource -Algorithm SHA256).Hash) { throw 'Runtime constraint fixture differs from pinned frozen source.' }

if ($ResumeSession) {
    $session=(Resolve-Path -LiteralPath $ResumeSession).Path
    $parent=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
    if ([IO.Path]::GetDirectoryName($session).TrimEnd('\','/') -ne $parent -or [IO.Path]::GetFileName($session) -notmatch '^replay-[a-f0-9]{32}$') { throw 'ResumeSession must be an existing replay-ID directly within OutputRoot.' }
} else {
    $session=Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ('replay-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $session -Force | Out-Null
}
# Current old runner may not hold this lock: existing incomplete/running directories
# are refused below rather than overwritten, even if their child has exited.
$sessionLock=[IO.File]::Open((Join-Path $session 'coordinator.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$engineHash=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
$runs=@()
# Alternate matching repetitions, serially. Never launch a second child while one lives.
try {
foreach ($repetition in 1..3) { foreach ($producer in @('byond','native')) {
    $id="$producer-$repetition"
    $root=Join-Path $session $id
    if (Test-Path -LiteralPath $root) {
        $existingFile=Join-Path $root 'receipt.json'
        if (-not (Test-Path -LiteralPath $existingFile)) { throw "Existing unfinished directory $root; coordinator must preserve/move it explicitly before resume." }
        $existing=Get-Content -LiteralPath $existingFile -Raw | ConvertFrom-Json
        if ($existing.status -notin @('complete-results','complete-results-abnormal-exit') -or -not $existing.suite_complete -or -not $existing.shutdown_complete -or -not $existing.selection_coverage_exact -or $null -eq $existing.exit_code -or $null -ne $existing.stop_reason -or -not $existing.results_present -or -not (Test-Path -LiteralPath (Join-Path $root 'unit_tests.json'))) { throw "Existing incomplete run $id; refuse overwrite. Coordinator must stop its own child and move this directory explicitly." }
        if ($existing.constraint_fixture_sha256 -ne $fixtureHash -or $existing.engine_sha256 -ne $engineHash -or $existing.test_selection_sha256 -ne $selectionHash -or $existing.frozen_runtime -ne $runtimeSource -or $existing.timeout_seconds -ne $TimeoutSeconds -or $existing.memory_limit_mb -ne $MemoryLimitMB -or $existing.producer -ne $producer -or $existing.repetition -ne $repetition) { throw "Resume receipt identity/configuration mismatch: $id" }
        foreach ($extension in @('dmb','rsc')) {
            $saved=@($existing.pair | Where-Object {$_.extension -eq $extension})
            $currentHash=(Get-FileHash -LiteralPath (Join-Path $frozen "pairs/$producer/world.$extension") -Algorithm SHA256).Hash
            if ($saved.Count -ne 1 -or $saved[0].sha256 -ne $currentHash) { throw "Resume frozen pair mismatch: $id/$extension" }
        }
        $runs+=@{run=$id;receipt=$existingFile;status=$existing.status}
        Write-Output "Verified complete run $id; skipping."
        continue
    }
    if ($PauseBetweenRuns -and (Test-Path -LiteralPath $PauseBetweenRuns)) {
        Write-Output "Paused before $id; session $session. Remove marker and use -ResumeSession to continue."
        return
    }
    $engineClosure=Test-PinnedEngineClosure
    $engineClosure | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $session "engine-preflight-$id.json") -Encoding UTF8
    if (-not $engineClosure.matched) { throw "Pinned engine closure mismatch before $id; see per-file audit." }
    $runtime=Join-Path $root 'runtime'
    New-Item -ItemType Directory -Path $root,$runtime -Force | Out-Null
    $setup=[Diagnostics.Stopwatch]::StartNew()
    & robocopy.exe $runtimeSource $runtime /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NFL /NDL /NP /LOG:"$root/copy.log" | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Frozen runtime copy failed for $id; code $LASTEXITCODE" }
    $pair=Join-Path $frozen "pairs/$producer"
    $before=@()
    foreach ($extension in @('dmb','rsc')) {
        $source=Join-Path $pair "world.$extension"
        $destination=Join-Path $runtime "world.$extension"
        Copy-Item -LiteralPath $source -Destination $destination
        (Get-Item -LiteralPath $destination).IsReadOnly=$false
        $before+=@{extension=$extension;source=$source;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash}
    }
    # Writable copies throughout; no link can mutate preserved evidence.
    Get-ChildItem -LiteralPath $runtime -Recurse -File | ForEach-Object { $_.IsReadOnly=$false }
    $results=Join-Path $root 'unit_tests.json'
    $logId='phase0-'+[Guid]::NewGuid().ToString('N')
    $clean=Join-Path $runtime "data/logs/$logId/clean_run.lk"
    $expectedNames=@(Get-Content -LiteralPath $selection | Where-Object {$_.Trim().Length -gt 0} | ForEach-Object {$_.Trim()})
    $params='log-directory='+$logId+'&unit-tests-file='+[Uri]::EscapeDataString($results.Replace('\','/'))+'&test-tier=normal'
    $params+='&test-select='+[Uri]::EscapeDataString($selection.Replace('\','/'))
    $receipt=[ordered]@{run=$id;producer=$producer;repetition=$repetition;status='running';runtime=$runtime;frozen_runtime=$runtimeSource;engine=$engine;engine_sha256=$engineHash;engine_version=(Get-Item -LiteralPath $engine).VersionInfo.FileVersion;pair=$before;timeout_seconds=$TimeoutSeconds;memory_limit_mb=$MemoryLimitMB;params=$params;seed_policy='preserved compiled world; no seed override';seed_evidence='world/test seeds captured in raw logs/results when emitted; no invented seed';setup_seconds=$setup.Elapsed.TotalSeconds;pid=$null;started_utc=[DateTime]::UtcNow.ToString('o');exit_code=$null;stop_reason=$null;peak_private_bytes=0;clean_marker=$false;results_present=$false}
    $child=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
    $receipt.engine_closure=$engineClosure
    $receipt.constraint_fixture_sha256=$fixtureHash
    $receipt.test_selection=$selection
    $receipt.test_selection_sha256=$selectionHash
    try {
        $old=[Phase0ReplayErrorMode]::SetErrorMode(3)
        try {
            $child=Start-Process -FilePath $engine -ArgumentList @(('"'+(Join-Path $runtime 'world.dmb')+'"'),'0','-cd',('"'+$runtime+'"'),'-close','-trusted','-invisible','-params',('"'+$params+'"')) -WorkingDirectory $runtime -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'stdout.log') -RedirectStandardError (Join-Path $root 'stderr.log') -PassThru
        } finally { [void][Phase0ReplayErrorMode]::SetErrorMode($old) }
        $receipt.pid=$child.Id
        $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'receipt.json') -Encoding UTF8
        while (-not $child.WaitForExit(250)) {
            $child.Refresh();$receipt.peak_private_bytes=[Math]::Max($receipt.peak_private_bytes,$child.PrivateMemorySize64)
            if ($child.PrivateMemorySize64 -gt ([long]$MemoryLimitMB*1048576)) { $receipt.stop_reason='memory-limit';break }
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) { $receipt.stop_reason='timeout';break }
            if ((Test-Path -LiteralPath $results) -and (Test-Path -LiteralPath $clean)) {
                if (-not $child.WaitForExit(3000)) { $receipt.stop_reason='clean-marker-shutdown-grace' }
                break
            }
        }
    } catch { $receipt.stop_reason='runner-error: '+$_.Exception.Message }
    finally {
        if ($child -and -not $child.HasExited) { & taskkill.exe /PID $child.Id /T /F | Out-Null;$child.WaitForExit() }
        if ($child) { $child.Refresh();$receipt.exit_code=$child.ExitCode }
        $receipt.clean_marker=Test-Path -LiteralPath $clean
        $receipt.results_present=Test-Path -LiteralPath $results
        $receipt.elapsed_seconds=$watch.Elapsed.TotalSeconds
        $receipt.finished_utc=[DateTime]::UtcNow.ToString('o')
        $receipt.suite_complete=$false
        $receipt.shutdown_complete=$false
        $receipt.selection_coverage_exact=$false
        if ($receipt.results_present) {
            try {
                $actual=Get-Content -LiteralPath $results -Raw | ConvertFrom-Json
                $names=@($actual.PSObject.Properties.Name)
                $receipt.selection_coverage_exact=(@(Compare-Object $expectedNames $names).Count -eq 0)
                $receipt.result_count=$names.Count
                $receipt.suite_complete=(@(Select-String -LiteralPath (Join-Path $root 'stdout.log'),(Join-Path $root 'stderr.log') -Pattern "Unit-test suite finished: $($expectedNames.Count) test types," -SimpleMatch).Count -gt 0)
                $receipt.shutdown_complete=(@(Select-String -LiteralPath (Join-Path $root 'stdout.log'),(Join-Path $root 'stderr.log') -Pattern 'Shutdown complete' -SimpleMatch).Count -gt 0)
            } catch { $receipt.completion_error=$_.Exception.Message }
        }
        # clean_run.lk means no failures/runtimes, NOT suite completion.
        $receipt.execution_complete=($receipt.results_present -and $receipt.selection_coverage_exact -and $receipt.suite_complete -and $receipt.shutdown_complete -and $null -ne $receipt.exit_code -and $null -eq $receipt.stop_reason)
        $receipt.normal_exit_gate_passed=($receipt.execution_complete -and $receipt.exit_code -eq 0)
        $receipt.status=if (-not $receipt.execution_complete) {'incomplete'} elseif ($receipt.normal_exit_gate_passed) {'complete-results'} else {'complete-results-abnormal-exit'}
        # Failed test statuses are preserved data, not a reason to skip later repetitions.
        $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'receipt.json') -Encoding UTF8
        $runs+=@{run=$id;receipt=(Join-Path $root 'receipt.json');status=$receipt.status}
        $runs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $session 'runs.json') -Encoding UTF8
    }
} }
} finally { $sessionLock.Dispose() }
Write-Output "Six serial runtime replays retained in $session"
if (@($runs | Where-Object {$_.status -eq 'incomplete'}).Count) { throw 'One or more replays incomplete; all available evidence retained.' }

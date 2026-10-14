param(
    [Parameter(Mandatory = $true)][string]$DmbFile,
    [Parameter(Mandatory = $true)][string]$ByondDirectory,
    [int]$TimeoutSeconds = 360,
    [int]$MemoryLimitMB = 2048,
    [string]$RuntimeDirectory,
    [string]$TestNamesFile,
    [ValidateSet('normal', 'all', 'exhaustive')][string]$TestTier = 'normal'
)

# Run an already compiled CBT/CIBUILDING/CITESTING world with the real runtime.
# Keep results separate from ordinary test runs in this worktree.
$ErrorActionPreference = 'Stop'
function Read-TestEntries($Results) {
    if ($null -eq $Results -or $Results -isnot [pscustomobject]) { throw 'Test results must be a JSON object keyed by test path.' }
    $entries = @($Results.PSObject.Properties | ForEach-Object {
        $entry = $_.Value
        $status = if ($null -ne $entry) { $entry.PSObject.Properties['status'] } else { $null }
        if ($null -eq $status -or $status.Value -isnot [ValueType] -or $status.Value -is [bool] -or $status.Value -notin @(0, 1, 2)) {
            throw "Invalid or missing test status for $($_.Name)."
        }
        $entry
    })
    return $entries
}
function Show-RuntimeDiagnostics([string[]]$Paths) {
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        Write-Output "Diagnostics: $path"
        $first = Select-String -LiteralPath $path -Pattern 'runtime error|fatal|exception|error:' -List | Select-Object -First 1
        if ($null -ne $first) { Write-Output ("First error, line {0}: {1}" -f $first.LineNumber, $first.Line.Substring(0, [Math]::Min(1000, $first.Line.Length))) }
        Get-Content -LiteralPath $path -Tail 15 | ForEach-Object { $_.Substring(0, [Math]::Min(1000, $_.Length)) }
    }
}
if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 3600 -or $MemoryLimitMB -lt 128) {
    throw 'Invalid runtime timeout or memory limit.'
}
$toolRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot = [IO.Path]::GetFullPath((Join-Path $toolRoot '../..'))
$runtimeRoot = if ($RuntimeDirectory) { (Resolve-Path -LiteralPath $RuntimeDirectory).Path } else { $projectRoot }
$dmb = (Resolve-Path -LiteralPath $DmbFile).Path
$daemon = Join-Path $ByondDirectory 'dd.exe'
if (-not (Test-Path -LiteralPath $daemon -PathType Leaf)) { throw "Missing DreamDaemon: $daemon" }
$runId = 'native-compiler-' + [Guid]::NewGuid().ToString('N')
$sourceRsc = [IO.Path]::ChangeExtension($dmb, '.rsc')
if (-not (Test-Path -LiteralPath $sourceRsc -PathType Leaf)) { throw "Missing resource pair: $sourceRsc" }
$runRoot = Join-Path $toolRoot "target/runtime-tests/$runId"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultsFile = Join-Path $runRoot 'unit_tests.json'
$stdout = Join-Path $runRoot 'stdout.log'
$stderr = Join-Path $runRoot 'stderr.log'
$clean = Join-Path $runtimeRoot "data/logs/$runId/clean_run.lk"
$params = 'log-directory=' + $runId + '&unit-tests-file=' + [Uri]::EscapeDataString($resultsFile.Replace('\', '/'))
$params += '&test-tier=' + $TestTier
if ($TestNamesFile) {
    $selection = (Resolve-Path -LiteralPath $TestNamesFile).Path
    if (-not (Test-Path -LiteralPath $selection -PathType Leaf)) { throw "Missing test selection: $selection" }
    $names = @(Get-Content -LiteralPath $selection | Where-Object { $_.Trim().Length -gt 0 })
    if ($names.Count -eq 0 -or @($names | Where-Object { $_.Trim() -notmatch '^/datum/unit_test/[A-Za-z0-9_/]+$' }).Count -gt 0) {
        throw 'Test selection must contain one absolute unit-test type path per line.'
    }
    $params += '&test-select=' + [Uri]::EscapeDataString($selection.Replace('\', '/'))
}
$process = $null
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    # BYOND changes to the world directory by default, independently of the
    # parent's working directory. Resolve config and DLLs from this worktree.
    if (-not ('NativeCompilerTestErrorMode' -as [type])) { Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class NativeCompilerTestErrorMode {
    [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
}
'@
    }
    # Only this child inherits headless native-error handling. Keep crash exit
    # codes and diagnostics visible without a Windows close-program dialog.
    $previousErrorMode = [NativeCompilerTestErrorMode]::SetErrorMode(3)
    try {
        $process = Start-Process -FilePath $daemon -ArgumentList @("`"$dmb`"", '0', '-cd', "`"$runtimeRoot`"", '-close', '-trusted', '-invisible', '-params', "`"$params`"") `
            -WorkingDirectory $runtimeRoot -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    }
    finally { [void][NativeCompilerTestErrorMode]::SetErrorMode($previousErrorMode) }
    Write-Output "Trusted runtime test started; results: $runRoot"
    while (-not $process.WaitForExit(250)) {
        $process.Refresh()
        if ($process.PrivateMemorySize64 -gt ([long]$MemoryLimitMB * 1024 * 1024)) { throw 'Runtime exceeded memory limit.' }
        if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'Runtime tests timed out.' }
        if ((Test-Path -LiteralPath $resultsFile -PathType Leaf) -and (Test-Path -LiteralPath $clean -PathType Leaf)) {
            # Results precede round completion; wait for the clean shutdown marker.
            if (-not $process.WaitForExit(3000)) { Stop-Process -Id $process.Id }
            break
        }
    }
    if (-not (Test-Path -LiteralPath $resultsFile -PathType Leaf)) {
        $process.Refresh()
        throw ("Runtime exited before test completion (exit code {0}); see {1} and {2}." -f $process.ExitCode, $stdout, $stderr)
    }
    $results = Get-Content -LiteralPath $resultsFile -Raw | ConvertFrom-Json
    $entries = @(Read-TestEntries $results)
    $failed = @($entries | Where-Object { $_.status -eq 1 })
    $skipped = @($entries | Where-Object { $_.status -eq 2 })
    Write-Output ("{0} tests, {1} failures, {2} skipped, {3:N1} seconds" -f $entries.Count, $failed.Count, $skipped.Count, $watch.Elapsed.TotalSeconds)
    $runtimeEntries = @($entries | Where-Object { $_.runtimes -gt 0 })
    $runtimeCount = ($runtimeEntries | Measure-Object -Property runtimes -Sum).Sum
    Write-Output ("{0} tests recorded {1} runtime errors." -f $runtimeEntries.Count, $(if ($null -eq $runtimeCount) { 0 } else { $runtimeCount }))
    $runtimeEntries | Select-Object -First 30 | ForEach-Object { Write-Output ("RUNTIMES {0}: {1} ({2} ds)" -f $_.name, $_.runtimes, $_.duration_ds) }
    $failed | Select-Object -First 30 | ForEach-Object {
        $message = [string]$_.message
        Write-Output ("FAIL {0}: {1}" -f $_.name, $message.Substring(0, [Math]::Min(1000, $message.Length)))
    }
    if ($failed.Count -gt 30 -or $runtimeEntries.Count -gt 30) { Write-Output "Additional entries are preserved in $resultsFile." }
    if ($entries.Count -eq 0 -or $failed.Count -gt 0 -or -not (Test-Path -LiteralPath $clean)) {
        throw "Runtime test run failed or was not clean; results: $runRoot"
    }
    Write-Output 'Native compiler project tests passed.'
}
catch {
    Show-RuntimeDiagnostics @($stdout, $stderr)
    throw
}
finally {
    if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
}

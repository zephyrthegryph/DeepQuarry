param(
    [int]$Iterations = 1,
    [int]$TimeoutSeconds = 600,
    [switch]$Forever,
    [switch]$SkipBuild,
    [switch]$ProfileTypes
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$daemon = 'D:\Program Files (x86)\BYOND516\bin\dreamdaemon.exe'
if (-not (Test-Path -LiteralPath $daemon)) {
    throw "DreamDaemon was not found at $daemon"
}

Set-Location -LiteralPath $root
$run = 0
while ($Forever -or $run -lt $Iterations) {
    $run++
    Get-Process -Name DreamDaemon -ErrorAction SilentlyContinue | Stop-Process -Force
    if (-not $SkipBuild) {
        & "$root\bin\build.cmd"
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed before soak iteration $run"
        }
    }

    New-Item -ItemType File -Path "$root\data\benchmark_sm" -Force | Out-Null
    if ($ProfileTypes) {
        New-Item -ItemType File -Path "$root\data\benchmark_type_profile" -Force | Out-Null
    }
    $runtimeLog = "$root\data\logs\atmos-soak\runtime.log"
    if (Test-Path -LiteralPath $runtimeLog) {
        $archiveName = "runtime-$((Get-Date).ToString('yyyyMMdd-HHmmss-fff')).log"
        Move-Item -LiteralPath $runtimeLog -Destination (Join-Path (Split-Path $runtimeLog) $archiveName)
    }
    $started = Get-Date
    $memoryLog = "$root\data\logs\atmos-soak\memory-$((Get-Date).ToString('yyyyMMdd-HHmmss-fff')).csv"
    'timestamp,elapsed_seconds,private_bytes,working_set_bytes,virtual_bytes,paged_bytes,handles,threads' |
        Set-Content -LiteralPath $memoryLog
    $process = Start-Process -FilePath $daemon `
        -ArgumentList @('deepquarry.dmb', '-trusted', '-verbose', '-params', 'log-directory=atmos-soak') `
        -WorkingDirectory $root -WindowStyle Hidden -PassThru
    Write-Host "ATMOS_SOAK run=$run pid=$($process.Id) timeout=${TimeoutSeconds}s started=$($started.ToString('o'))"

    $deadline = $started.AddSeconds($TimeoutSeconds)
    $completed = $false
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $process.Refresh()
        if (-not $process.HasExited) {
            $elapsedSample = ((Get-Date) - $started).TotalSeconds
            $sample = @(
                (Get-Date).ToString('o'),
                [math]::Round($elapsedSample, 3),
                $process.PrivateMemorySize64,
                $process.WorkingSet64,
                $process.VirtualMemorySize64,
                $process.PagedMemorySize64,
                $process.HandleCount,
                $process.Threads.Count
            ) -join ','
            Add-Content -LiteralPath $memoryLog -Value $sample
        }
        if (Test-Path -LiteralPath $runtimeLog) {
            # A completion dump can append hundreds of profiler lines in less
            # than one sampling interval, so checking only the tail races past
            # the marker and leaves the daemon running until the hard timeout.
            if (Select-String -LiteralPath $runtimeLog -SimpleMatch 'ATMOS_BENCHMARK COMPLETE' -Quiet) {
                $completed = $true
                Write-Host "ATMOS_SOAK run=$run completed workload; terminating benchmark server"
                & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
                break
            }
        }
    }
    if (-not $process.HasExited -and -not $completed) {
        Write-Warning "ATMOS_SOAK run=$run exceeded its hard timeout; force-killing pid=$($process.Id)"
        # DreamDaemon can detach from the Start-Process wrapper during startup.
        # Kill the whole process tree, then verify that no daemon from this run
        # survived before beginning another iteration.
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        Get-Process -Name DreamDaemon -ErrorAction SilentlyContinue |
            Where-Object StartTime -ge $started |
            Stop-Process -Force -ErrorAction SilentlyContinue
        $killDeadline = (Get-Date).AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 250
            $survivors = @(Get-Process -Name DreamDaemon -ErrorAction SilentlyContinue |
                Where-Object StartTime -ge $started)
        } while ($survivors.Count -and (Get-Date) -lt $killDeadline)
        if ($survivors.Count) {
            throw "Hard timeout failed to terminate DreamDaemon pid(s): $($survivors.Id -join ', ')"
        }
    }

    $latest = Get-ChildItem "$root\data\logs\atmos-soak" -File -ErrorAction SilentlyContinue |
        Where-Object Name -eq 'runtime.log' |
        Sort-Object LastWriteTime | Select-Object -Last 1
    $elapsed = ((Get-Date) - $started).TotalSeconds
    Write-Host "ATMOS_SOAK run=$run elapsed=$([math]::Round($elapsed, 1))s log=$($latest.FullName) memory=$memoryLog"
    Remove-Item -LiteralPath "$root\data\benchmark_sm" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$root\data\benchmark_type_profile" -Force -ErrorAction SilentlyContinue
    if ($Forever) {
        Start-Sleep -Seconds 5
    }
}

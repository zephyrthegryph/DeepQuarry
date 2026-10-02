# Shared process/log/memory helpers for compile-only acceptance drivers.
# Every process returned here is created by the calling driver. No external PID
# is accepted for termination; children are hidden and compiler ceilings apply.
$script:ownedRuns = [Collections.Generic.List[object]]::new()
function Start-CompilerRun {
    param([string]$Executable, [string]$Directory, [string[]]$Arguments, [string]$Prefix, [hashtable]$Environment = @{}, [int]$MemoryMb = 1024)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['DM_MEMORY_LIMIT_MB'] = "$MemoryMb"
    foreach ($key in $Environment.Keys) {
        if ($null -eq $Environment[$key]) { [void]$start.Environment.Remove($key) }
        else { $start.Environment[$key] = [string]$Environment[$key] }
    }
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $stdout = [IO.File]::Create("$Prefix.stdout.log")
    $stderr = [IO.File]::Create("$Prefix.stderr.log")
    $started = $false
    try {
        $started = $process.Start()
        if (!$started) { throw 'Could not start owned compiler process.' }
        $run = [pscustomobject]@{ Process = $process; Prefix = $Prefix; Files = @($stdout, $stderr); Tasks = @($process.StandardOutput.BaseStream.CopyToAsync($stdout), $process.StandardError.BaseStream.CopyToAsync($stderr)); Finished = $false; Started = [Diagnostics.Stopwatch]::StartNew() }
        $script:ownedRuns.Add($run)
        return $run
    } catch {
        if ($started -and !$process.HasExited) { $process.Kill($true) }
        $stdout.Dispose(); $stderr.Dispose(); $process.Dispose()
        throw
    }
}
function Complete-CompilerRun {
    param($Run, [switch]$Stop)
    if ($Run.Finished) { return }
    if ($Stop -and !$Run.Process.HasExited) { $Run.Process.Kill($true) }
    if (!$Run.Process.HasExited) { throw 'Owned compiler process is still running.' }
    foreach ($task in $Run.Tasks) { [void]$task.GetAwaiter().GetResult() }
    foreach ($file in $Run.Files) { $file.Dispose() }
    $Run.Finished = $true
}
function Get-CompilerPrivateMemory {
    $bytes = 0L
    foreach ($run in $script:ownedRuns) {
        if (!$run.Finished -and !$run.Process.HasExited) { $run.Process.Refresh(); $bytes += $run.Process.PrivateMemorySize64 }
    }
    return $bytes
}
function Wait-CompilerRun {
    param($Run, [int]$TimeoutSeconds = 900, [int]$AggregateMemoryMb = 2048)
    $peak = Get-CompilerPrivateMemory
    while (!$Run.Process.HasExited) {
        $bytes = Get-CompilerPrivateMemory
        $peak = [Math]::Max($peak, $bytes)
        if ($bytes -gt [long]$AggregateMemoryMb * 1MB) { throw "Owned compiler aggregate memory exceeded $AggregateMemoryMb MiB." }
        if ($Run.Started.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw "Compiler timed out; see $($Run.Prefix).stderr.log" }
        Start-Sleep -Milliseconds 25
    }
    Complete-CompilerRun $Run
    return [pscustomobject]@{ exit_code = $Run.Process.ExitCode; runtime_seconds = ($Run.Process.ExitTime - $Run.Process.StartTime).TotalSeconds; sampled_peak_private_bytes = $peak }
}
function Start-CompilerDaemon {
    param([string]$Executable, [string]$Directory, [string]$CacheRoot, [string]$Prefix, [int]$MemoryMb = 1536, [int]$Workers = 1, [hashtable]$Environment = @{})
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $childEnvironment = @{} + $Environment
    $childEnvironment['DM_COMPILER_CACHE_ROOT'] = $CacheRoot
    $childEnvironment['DM_DAEMON_WORKERS'] = "$Workers"
    $run = Start-CompilerRun $Executable $Directory @("$port", $CacheRoot) $Prefix $childEnvironment $MemoryMb
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt 30) {
        if ($run.Process.HasExited) { Complete-CompilerRun $run; throw "Daemon startup failed; see $Prefix.stderr.log" }
        $socket = [Net.Sockets.TcpClient]::new()
        try {
            $socket.ReceiveTimeout = 500
            $socket.Connect('127.0.0.1', $port)
            $stream = $socket.GetStream()
            $ping = [Text.Encoding]::UTF8.GetBytes('{"command":"ping"}' + "`n")
            $stream.Write($ping, 0, $ping.Length)
            $reader = [IO.StreamReader]::new($stream)
            $response = $reader.ReadLine() | ConvertFrom-Json
            if (!$response.ok) { throw 'Daemon ping failed.' }
            return [pscustomobject]@{ Run = $run; Address = "127.0.0.1:$port" }
        } catch { Start-Sleep -Milliseconds 50 }
        finally { $socket.Dispose() }
    }
    throw 'Owned daemon startup timed out.'
}
function Close-CompilerRuns {
    foreach ($run in $script:ownedRuns) {
        if (!$run.Finished) { Complete-CompilerRun $run -Stop }
        $run.Process.Dispose()
    }
    $script:ownedRuns.Clear()
}
Export-ModuleMember -Function Start-CompilerRun, Complete-CompilerRun, Get-CompilerPrivateMemory, Wait-CompilerRun, Start-CompilerDaemon, Close-CompilerRuns

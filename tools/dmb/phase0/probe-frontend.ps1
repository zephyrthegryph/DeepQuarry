param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$EngineTemplate,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string[]]$Defines = @('DM_VERSION=516', 'DM_BUILD=1687', 'CITESTING=1'),
    [ValidateRange(1,2)][int]$Workers = 2,
    [ValidateRange(1,285)][int]$TimeoutSeconds = 285
)
$ErrorActionPreference = 'Stop'
# Analysis probes are explicitly not whole-compiler latency measurements.
# This script never starts DreamDaemon or an external profiler.
$taskCompiler = (Resolve-Path -LiteralPath $Compiler).Path
$taskProject = (Resolve-Path -LiteralPath $Project).Path
$taskTemplate = (Resolve-Path -LiteralPath $EngineTemplate).Path
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'Choose a new output directory; preserve previous evidence.'
}
$taskOutput = (New-Item -ItemType Directory -Path $OutputDirectory).FullName
function Quote-Argument([string]$Value) {
    # Windows command-line argument escaping, not shell interpolation.
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
$taskArguments = @('analyze', '--no-daemon', $taskProject, '--workers', "$Workers",
    '--engine-template', $taskTemplate, '--bootstrap-catalog', '--progress')
$taskArguments += @($Defines | ForEach-Object { '-D' + $_ })
$taskReceipt = [ordered]@{
    scope = 'frontend-only'
    compiler_sha256 = (Get-FileHash -LiteralPath $taskCompiler -Algorithm SHA256).Hash
    engine_sha256 = (Get-FileHash -LiteralPath $taskTemplate -Algorithm SHA256).Hash
    project = $taskProject
    defines = $Defines
    workers = $Workers
    watchdog_seconds = $TimeoutSeconds
    process_completed = $false
    model_completed = $false
    sample_interval_seconds = 1
    sampled_max_private_bytes = [long]0
    status = 'running'
}
$taskWatch = [Diagnostics.Stopwatch]::StartNew()
$taskProcess = Start-Process -FilePath $taskCompiler -ArgumentList (@($taskArguments | ForEach-Object { Quote-Argument $_ }) -join ' ') `
    -WorkingDirectory (Split-Path -Parent $taskProject) -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $taskOutput 'analysis.jsonl') `
    -RedirectStandardError (Join-Path $taskOutput 'diagnostics.log')
$taskReceipt.pid = $taskProcess.Id
try {
    while (-not $taskProcess.HasExited) {
        $taskProcess.Refresh()
        $taskReceipt.sampled_max_private_bytes = [Math]::Max($taskReceipt.sampled_max_private_bytes, $taskProcess.PrivateMemorySize64)
        if ($taskWatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $taskReceipt.status = 'watchdog-expired'
            $taskProcess.Kill()
            break
        }
        Start-Sleep -Seconds 1
    }
    $taskProcess.WaitForExit()
    $taskReceipt.exit_code = $taskProcess.ExitCode
    $taskReceipt.process_completed = $taskProcess.HasExited
    $taskReceipt.model_completed = $taskProcess.ExitCode -eq 0
    if ($taskReceipt.status -eq 'running') {
        $taskReceipt.status = if ($taskReceipt.model_completed) { 'completed' } else { 'failed' }
    }
} finally {
    if (-not $taskProcess.HasExited) { $taskProcess.Kill(); $taskProcess.WaitForExit() }
    $taskReceipt.seconds = $taskWatch.Elapsed.TotalSeconds
    $taskReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskOutput 'receipt.json') -Encoding utf8
}
$taskReceipt | ConvertTo-Json -Depth 4

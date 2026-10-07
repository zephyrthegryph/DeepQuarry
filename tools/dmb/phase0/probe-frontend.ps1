param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$EngineTemplate,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('analyze','compile')][string]$Mode = 'analyze',
    [string[]]$Defines = @('DM_VERSION=516', 'DM_BUILD=1687', 'CITESTING=1'),
    [ValidateRange(1,2)][int]$Workers = 2,
    [ValidateRange(1,285)][int]$TimeoutSeconds = 285
)
$ErrorActionPreference = 'Stop'
# Scope is explicit: analyze is not whole-compiler latency; compile includes
# conventional output installation through the actual command-line entry point.
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
$taskArguments = @($Mode, '--no-daemon', $taskProject, '--workers', "$Workers",
    '--engine-template', $taskTemplate, '--bootstrap-catalog', '--progress')
$taskArguments += @($Defines | ForEach-Object { '-D' + $_ })
$taskReceipt = [ordered]@{
    scope = $(if ($Mode -eq 'compile') { 'uncached-compiler-cli' } else { 'frontend-only' })
    compiler_sha256 = (Get-FileHash -LiteralPath $taskCompiler -Algorithm SHA256).Hash
    engine_sha256 = (Get-FileHash -LiteralPath $taskTemplate -Algorithm SHA256).Hash
    project = $taskProject
    defines = $Defines
    workers = $Workers
    watchdog_seconds = $TimeoutSeconds
    process_completed = $false
    model_completed = $false
    artifact_completed = $false
    sample_interval_seconds = 1
    sampled_max_private_bytes = [long]0
    status = 'running'
}
$taskWatch = [Diagnostics.Stopwatch]::StartNew()
$taskProcess = Start-Process -FilePath $taskCompiler -ArgumentList (@($taskArguments | ForEach-Object { Quote-Argument $_ }) -join ' ') `
    -WorkingDirectory (Split-Path -Parent $taskProject) -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $taskOutput $(if ($Mode -eq 'compile') { 'stdout.log' } else { 'analysis.jsonl' })) `
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
    $taskReceipt.model_completed = $Mode -eq 'analyze' -and $taskProcess.ExitCode -eq 0
    if ($Mode -eq 'compile' -and $taskProcess.ExitCode -eq 0) {
        $taskMarker = [IO.Path]::ChangeExtension($taskProject, 'dmb-pair.json')
        $taskDmb = [IO.Path]::ChangeExtension($taskProject, 'dmb')
        $taskRsc = [IO.Path]::ChangeExtension($taskProject, 'rsc')
        $taskReceipt.artifact_completed = (Test-Path -LiteralPath $taskMarker) -and
            (Test-Path -LiteralPath $taskDmb) -and (Test-Path -LiteralPath $taskRsc)
        if ($taskReceipt.artifact_completed) {
            $taskReceipt.dmb_sha256 = (Get-FileHash -LiteralPath $taskDmb -Algorithm SHA256).Hash
            $taskReceipt.rsc_sha256 = (Get-FileHash -LiteralPath $taskRsc -Algorithm SHA256).Hash
            $taskReceipt.pair_marker_sha256 = (Get-FileHash -LiteralPath $taskMarker -Algorithm SHA256).Hash
            Copy-Item -LiteralPath $taskMarker -Destination (Join-Path $taskOutput 'pair.json')
        }
    }
    if ($taskReceipt.status -eq 'running') {
        $taskReceipt.status = if ($taskReceipt.model_completed -or $taskReceipt.artifact_completed) { 'completed' } else { 'failed' }
    }
} finally {
    if (-not $taskProcess.HasExited) { $taskProcess.Kill(); $taskProcess.WaitForExit() }
    $taskReceipt.seconds = $taskWatch.Elapsed.TotalSeconds
    $taskReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskOutput 'receipt.json') -Encoding utf8
}
$taskReceipt | ConvertTo-Json -Depth 4

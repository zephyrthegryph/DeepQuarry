param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('cold','incremental','exact')][string]$Mode='incremental',
    [string[]]$Defines=@('DM_VERSION=516','DM_BUILD=1687'),
    [ValidateRange(1,2)][int]$Workers=2,
    [ValidateRange(1,285)][int]$TimeoutSeconds=285
)
$ErrorActionPreference='Stop'
$taskCompiler=(Resolve-Path -LiteralPath $Compiler).Path
$taskProject=(Resolve-Path -LiteralPath $Project).Path
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Preserve previous receipts; choose a new directory.' }
$taskOutput=(New-Item -ItemType Directory -Path $OutputDirectory).FullName
function Quote-Argument([string]$Value) {
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
$taskArguments=@('compile','--no-daemon',$taskProject,'--workers',"$Workers",'--progress')
if ($Mode -eq 'cold') { $taskArguments+='--no-cache' }
if ($Mode -eq 'exact') { $taskArguments+='--exact-inputs' }
$taskArguments+=@($Defines | ForEach-Object { '-D'+$_ })
$taskReceipt=[ordered]@{
    scope='complete-compiler-cli-through-conventional-install'
    mode=$Mode
    project=$taskProject
    compiler_sha256=(Get-FileHash -LiteralPath $taskCompiler -Algorithm SHA256).Hash
    defines=$Defines
    workers=$Workers
    watchdog_seconds=$TimeoutSeconds
    memory_sample_interval_seconds=1
    sampled_max_private_bytes=[long]0
    sampled_cpu_seconds=0.0
    competing_cargo_rustc_count_at_start=@(Get-Process -Name cargo,rustc -ErrorAction SilentlyContinue).Count
    status='running'
}
$taskWatch=[Diagnostics.Stopwatch]::StartNew()
$taskProcess=Start-Process -FilePath $taskCompiler -ArgumentList (@($taskArguments | ForEach-Object {Quote-Argument $_}) -join ' ') `
    -WorkingDirectory (Split-Path -Parent $taskProject) -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $taskOutput 'stdout.log') -RedirectStandardError (Join-Path $taskOutput 'diagnostics.log')
$taskReceipt.pid=$taskProcess.Id
$taskNextSample=0.0
try {
    while (-not $taskProcess.WaitForExit(20)) {
        if ($taskWatch.Elapsed.TotalSeconds -ge $taskNextSample) {
            $taskProcess.Refresh()
            $taskReceipt.sampled_max_private_bytes=[Math]::Max($taskReceipt.sampled_max_private_bytes,$taskProcess.PrivateMemorySize64)
            $taskReceipt.sampled_cpu_seconds=$taskProcess.TotalProcessorTime.TotalSeconds
            $taskNextSample=$taskWatch.Elapsed.TotalSeconds+1
        }
        if ($taskWatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $taskReceipt.status='watchdog-expired'
            $taskProcess.Kill()
            break
        }
    }
    $taskProcess.WaitForExit()
    $taskWatch.Stop()
    $taskReceipt.process_seconds=$taskWatch.Elapsed.TotalSeconds
    $taskReceipt.competing_cargo_rustc_count_at_end=@(Get-Process -Name cargo,rustc -ErrorAction SilentlyContinue).Count
    $taskReceipt.exit_code=$taskProcess.ExitCode
    $taskReceipt.session_hit=[IO.File]::ReadAllText((Join-Path $taskOutput 'diagnostics.log')).Contains('native session hit:')
    if ($taskReceipt.status -eq 'running') {
        $taskReceipt.status=if ($taskProcess.ExitCode -eq 0) {'completed'} else {'failed'}
    }
    if ($taskProcess.ExitCode -eq 0) {
        foreach ($taskExtension in @('dmb','rsc','dmb-pair.json')) {
            $taskPath=[IO.Path]::ChangeExtension($taskProject,$taskExtension)
            $taskReceipt[($taskExtension+'_sha256')]=(Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash
            $taskReceipt[($taskExtension+'_bytes')]=(Get-Item -LiteralPath $taskPath).Length
        }
    }
} catch {
    $taskReceipt.status='receipt-or-artifact-failed'
    $taskReceipt.error=$_.Exception.Message
    throw
} finally {
    if (-not $taskProcess.HasExited) {$taskProcess.Kill();$taskProcess.WaitForExit()}
    $taskReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskOutput 'receipt.json') -Encoding utf8
}
$taskReceipt | ConvertTo-Json -Depth 4

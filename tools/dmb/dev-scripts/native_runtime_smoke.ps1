param(
    [Parameter(Mandatory = $true)]
    [string]$ByondDirectory,
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$toolRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$daemon = Join-Path $ByondDirectory 'dd.exe'
if (-not (Test-Path -LiteralPath $daemon -PathType Leaf)) {
    throw "Console DreamDaemon not found: $daemon"
}
if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 60) {
    throw 'TimeoutSeconds must be between 1 and 60.'
}
if (Get-Command sccache -ErrorAction SilentlyContinue) {
    $env:RUSTC_WRAPPER = 'sccache'
}
$outputRoot = Join-Path $toolRoot 'target/runtime-smoke-output'
& cargo run --manifest-path (Join-Path $toolRoot 'Cargo.toml') -p dm-compile -j 1 -- build-project `
    (Join-Path $toolRoot 'fixtures/native_compiler/runtime_smoke.dme') `
    (Join-Path $toolRoot 'fixtures/native_template.bin') $outputRoot
if ($LASTEXITCODE -ne 0) { throw 'Rust compiler smoke build failed.' }
$id = (Get-Content -LiteralPath (Join-Path $outputRoot 'HEAD') | Select-Object -Last 1).Trim()
if ($id -notmatch '^[0-9a-f]{64}$') { throw 'Invalid generation ID.' }
$generation = Join-Path $outputRoot "generations/$id"
$dmb = Join-Path $generation 'world.dmb'
$stdout = Join-Path $outputRoot 'stdout.log'
$stderr = Join-Path $outputRoot 'stderr.log'
$process = $null
try {
    if (-not ('NativeCompilerSmokeErrorMode' -as [type])) { Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class NativeCompilerSmokeErrorMode {
    [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
}
'@
    }
    $previousErrorMode = [NativeCompilerSmokeErrorMode]::SetErrorMode(3)
    try {
        $process = Start-Process -FilePath $daemon -ArgumentList @("`"$dmb`"", '0', '-trusted', '-invisible') `
            -WorkingDirectory $generation -WindowStyle Hidden -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr -PassThru
    } finally { [void][NativeCompilerSmokeErrorMode]::SetErrorMode($previousErrorMode) }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'Runtime smoke timed out.' }
    $process.Refresh()
    $log = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
    Write-Output $log
    if ($process.ExitCode -ne 0 -or $log -match 'runtime error:' `
        -or $log -notmatch '(?m)^RUST_COMPILER_SMOKE 23\s*$') {
        throw "Runtime smoke failed; see $stdout and $stderr."
    }
    Write-Output 'Rust compiler runtime smoke passed.'
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    }
}

param(
    [string]$StrictModule,
    [switch]$StrictTypes,
    [switch]$FailOnNew
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$tool = Join-Path $repo 'tools/dm-health'
$target = Join-Path $tool 'target'
$dotnet = Join-Path $target 'dotnet10/dotnet.exe'
$bridge = Join-Path $tool 'opendream-bridge/bin/Release/net10.0/OpenDreamBridge.dll'
$compiler = Join-Path $target 'DMCompiler_win-x64'
$analyzer = Join-Path $target 'release/dm-health.exe'

foreach ($required in @($dotnet, $bridge, $compiler, $analyzer)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required Windows build artifact is missing: $required"
    }
}

$id = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$snapshots = Join-Path $target 'snapshots'
$snapshot = Join-Path $snapshots $id
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'deepquarry.dme') -Destination $snapshot
foreach ($directory in @('code', 'maps', 'interface', 'html', 'strings', 'config')) {
    Copy-Item -LiteralPath (Join-Path $repo $directory) -Destination $snapshot -Recurse
}

$ast = Join-Path $snapshots "$id.ast.jsonl"
$report = Join-Path $snapshots "$id.report.json"
$bridgeLog = Join-Path $snapshots "$id.bridge.log"
& $dotnet $bridge (Join-Path $snapshot 'deepquarry.dme') $ast $compiler *> $bridgeLog
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath $bridgeLog -Tail 20
    throw "OpenDream export failed for $snapshot"
}

$arguments = @('--root', $snapshot, '--ast', $ast, '--report', $report, '--summary',
    '--cache-dir', (Join-Path $target 'analysis-cache'))
if ($StrictModule) {
    $arguments += @('--strict-module', $StrictModule)
}
if ($StrictTypes) {
    $arguments += '--strict-types'
}
if ($FailOnNew) {
    $arguments += @('--baseline', (Join-Path $tool 'baseline.json'), '--fail-on-new')
}
& $analyzer @arguments
$status = $LASTEXITCODE
Write-Output "Source snapshot: $snapshot"
Write-Output "Report: $report"
exit $status

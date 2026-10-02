#requires -Version 7.0
# Read-only contract checks: no compiler process, worktree or asset copy starts.
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Daemon,
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$GitRef,
    [string]$AssetOverlayRoot = '',
    [string]$ProjectFile = 'deepquarry.dme'
)
$ErrorActionPreference = 'Stop'
$base = @{ Compiler = $Compiler; Daemon = $Daemon; OwnedGameRepository = $Repository; GitRef = $GitRef; AssetOverlayRoot = $AssetOverlayRoot; ProjectFile = $ProjectFile; PlanOnly = $true; OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) "dq-plan-$([Guid]::NewGuid().ToString('N'))") }
function Invoke-PlanCase([hashtable]$Arguments, [switch]$ExpectFailure) {
    $lines = [Collections.Generic.List[string]]::new()
    $failure = $null
    try { & "$PSScriptRoot/accept-six-worktrees.ps1" @Arguments | ForEach-Object { $lines.Add([string]$_) } }
    catch { $failure = $_ }
    $result = ($lines.ToArray() -join "`n") | ConvertFrom-Json
    if (!!$failure -ne !!$ExpectFailure) { throw 'Unexpected plan success/failure.' }
    if ($ExpectFailure -and (!$result.failure -or $result.ok -or $result.native_gate_passed)) { throw 'Plan failure lacks its structured failure record.' }
    return $result
}
foreach ($file in @('accept-game-worktrees.ps1', 'accept-six-worktrees.ps1', 'process.psm1')) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors.Message -join '; ') }
}
$plan = Invoke-PlanCase $base
if (!$plan.plan_only -or $plan.commit -notmatch '^[0-9a-f]{40,64}$' -or $plan.planned_phases.Count -ne 13 -or $plan.max_clients -ne 1 -or $plan.daemon_workers -ne 1 -or $plan.daemon_limit_mb -ne 2048 -or $plan.transport_limit_mb -ne 256 -or $plan.fresh_limit_mb -ne 2048 -or $plan.aggregate_limit_mb -ne 2048) { throw 'Invalid owned-game plan contract.' }
if (Test-Path -LiteralPath $base.OutputRoot) { throw 'PlanOnly created its output root.' }
$badRef = @{} + $base; $badRef.GitRef = "refs/heads/does-not-exist-$([Guid]::NewGuid().ToString('N'))"
[void](Invoke-PlanCase $badRef -ExpectFailure)
$escaped = @{} + $base; $escaped.ProjectFile = '../outside-project.dme'
[void](Invoke-PlanCase $escaped -ExpectFailure)
$existing = @{} + $base; $existing.OutputRoot = $Repository
[void](Invoke-PlanCase $existing -ExpectFailure)
$tooMany = @{} + $base; $tooMany.MaxClients = 2
[void](Invoke-PlanCase $tooMany -ExpectFailure)
if (Test-Path -LiteralPath $base.OutputRoot) { throw 'A failing preflight created its output root.' }
[pscustomobject]@{ ok = $true; plan_cases = 5; parser_files = 3; compiler_processes_started = 0; worktrees_created = 0; commit = $plan.commit } | ConvertTo-Json -Compress

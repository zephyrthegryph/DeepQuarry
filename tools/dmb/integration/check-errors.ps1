#requires -Version 7.0
<#
.SYNOPSIS
Capture tiny BYOND/native compile-error probes without launching a world.
.DESCRIPTION
Reports exit/status parity and raw located diagnostics. Different error messages
are retained, not normalized into an invented semantic-equivalence claim.
#>
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Byond,
    [string]$Builtins = "$PSScriptRoot/../fixtures/native_template.bin",
    [string[]]$Defines = @(),
    [string]$OutputRoot = '',
    [ValidateRange(256, 2048)][int]$ClientMemoryMb = 512,
    [ValidateRange(512, 4096)][int]$AggregateMemoryMb = 1024,
    [ValidateRange(10, 120)][int]$TimeoutSeconds = 30
)
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/process.psm1" -Force
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Byond = (Resolve-Path -LiteralPath $Byond).Path
$Builtins = (Resolve-Path -LiteralPath $Builtins).Path
if (!$OutputRoot) { $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "dm-errors-$([Guid]::NewGuid().ToString('N'))" }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new; diagnostic captures are preserved.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$rows = [Collections.Generic.List[object]]::new()
$report = [ordered]@{ schema = 1; ok = $false; target = '516.1687'; compiler_sha256 = (Get-FileHash -LiteralPath $Compiler).Hash; builtin_sha256 = (Get-FileHash -LiteralPath $Builtins).Hash; byond_executable = $Byond; defines = $Defines; fallback_count = 0; diagnostic_equivalence = 'not_evaluated'; fixtures = @(); failure = $null }
function Save-Report { $report.fixtures = $rows.ToArray(); $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputRoot 'errors.json') }
function Diagnostics([string]$Prefix) {
    $records = [Collections.Generic.List[object]]::new()
    foreach ($file in @("$Prefix.stdout.log", "$Prefix.stderr.log")) {
        foreach ($line in [IO.File]::ReadLines($file)) {
            $match = [regex]::Match($line, '^(?<source>.*?):(?<line>\d+):error(?:\s*\((?<code>[^)]+)\))?:\s*(?<message>.*)$')
            if (!$match.Success) { continue }
            $records.Add([pscustomobject]@{ severity = 'error'; source = $match.Groups['source'].Value; line = [int]$match.Groups['line'].Value; code = $match.Groups['code'].Value; message = $match.Groups['message'].Value; raw = $line })
        }
    }
    return $records.ToArray()
}
$fixtures = @(
    @{ name = 'valid'; source = "/proc/probe()`n    return 7`n"; expected_success = $true },
    @{ name = 'explicit-preprocess-error'; source = "#error explicit_error_probe`n"; expected_success = $false },
    @{ name = 'missing-include'; source = "#include `"absent_probe.dm`"`n"; expected_success = $false },
    @{ name = 'unterminated-string'; source = "/proc/probe()`n    return `"unterminated`n"; expected_success = $false },
    @{ name = 'unknown-procedure'; source = "/proc/probe()`n    return definitely_absent_probe()`n"; expected_success = $false },
    @{ name = 'unknown-type'; source = "/proc/probe()`n    var/datum/definitely_absent_probe/value = new`n    return value`n"; expected_success = $false }
)
try {
    $versionPrefix = Join-Path $OutputRoot 'byond-version'
    $versionRun = Start-CompilerRun $Byond $OutputRoot @() $versionPrefix @{} $ClientMemoryMb
    [void](Wait-CompilerRun $versionRun $TimeoutSeconds $AggregateMemoryMb)
    $versionText = [IO.File]::ReadAllText("$versionPrefix.stdout.log") + [IO.File]::ReadAllText("$versionPrefix.stderr.log")
    $version = [regex]::Match($versionText, 'DM compiler version (\d+\.\d+)')
    if (!$version.Success -or $version.Groups[1].Value -ne $report.target) { throw "Error probes require reference BYOND $($report.target); see captured version output." }
    foreach ($fixture in $fixtures) {
        Write-Host "Compile-error probe: $($fixture.name)"
        $directory = Join-Path $OutputRoot $fixture.name
        New-Item -ItemType Directory -Path $directory | Out-Null
        $project = Join-Path $directory 'probe.dme'
        [IO.File]::WriteAllText($project, "#include `"probe.dm`"`n")
        [IO.File]::WriteAllText((Join-Path $directory 'probe.dm'), $fixture.source)
        $byondPrefix = Join-Path $directory 'byond'
        $byondRun = Start-CompilerRun $Byond $directory ($Defines + @($project)) $byondPrefix @{} $ClientMemoryMb
        $byondTiming = Wait-CompilerRun $byondRun $TimeoutSeconds $AggregateMemoryMb
        $byondDiagnostics = @(Diagnostics $byondPrefix)
        $byondOk = $byondTiming.exit_code -eq 0 -and $byondDiagnostics.Count -eq 0 -and (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($project, 'dmb')) -PathType Leaf)
        # Only located compiler diagnostics prove a source failure. A crash or
        # nonzero exit without them is unclassified, never source parity.
        $byondKind = if ($byondOk) { $null } elseif ($byondDiagnostics.Count) { 'source' } elseif ($byondTiming.exit_code -lt 0) { 'internal' } else { 'unclassified' }
        $nativePrefix = Join-Path $directory 'native'
        $nativeReport = Join-Path $directory 'native.json'
        $nativeRun = Start-CompilerRun $Compiler $directory (@('integrated-build', $project, '--mode', 'native', '--strict', '--builtins', $Builtins, '--report', $nativeReport) + $Defines) $nativePrefix @{ DM_COMPILER_CACHE_ROOT = (Join-Path $directory 'private-cache'); DQ_NATIVE_DAEMON = $null; DQ_NATIVE_TARGET = '516.1687'; DQ_COMPILER_STRICT = '1' } $ClientMemoryMb
        $nativeTiming = Wait-CompilerRun $nativeRun $TimeoutSeconds $AggregateMemoryMb
        $native = Get-Content -LiteralPath $nativeReport -Raw | ConvertFrom-Json
        $nativeOk = $nativeTiming.exit_code -eq 0 -and $native.ok -and $native.producing_compiler -eq 'native' -and $native.native_gate_passed
        $nativeDiagnostics = @(Diagnostics $nativePrefix)
        if ($native.fallback) { $report.fallback_count++ }
        $sameStatus = $nativeOk -eq $byondOk
        $sameSourceClass = !$nativeOk -and !$byondOk -and $native.failure.kind -eq 'source' -and $byondKind -eq 'source'
        $row = [pscustomobject]@{ fixture = $fixture.name; expected_success = $fixture.expected_success; status_matches = $sameStatus; source_failure_classification_matches = $sameSourceClass; diagnostic_equivalence = 'not_evaluated'; byond = @{ ok = $byondOk; exit_code = $byondTiming.exit_code; failure_kind = $byondKind; runtime_seconds = $byondTiming.runtime_seconds; diagnostics = $byondDiagnostics; stdout = "$byondPrefix.stdout.log"; stderr = "$byondPrefix.stderr.log" }; native = @{ ok = $nativeOk; exit_code = $nativeTiming.exit_code; failure = $native.failure; fallback = $native.fallback; runtime_seconds = $nativeTiming.runtime_seconds; diagnostics = $nativeDiagnostics; stdout = "$nativePrefix.stdout.log"; stderr = "$nativePrefix.stderr.log" }; gate_passed = $sameStatus -and ($byondOk -eq $fixture.expected_success) -and ($byondOk -or $sameSourceClass) -and !$native.fallback }
        $rows.Add($row)
        Save-Report
    }
    $report.ok = @($rows | Where-Object { !$_.gate_passed }).Count -eq 0 -and $report.fallback_count -eq 0
    Save-Report
    Write-Host "Compile-error captures: $OutputRoot/errors.json"
    if (!$report.ok) { throw 'Compile-error status/classification probes differ; raw diagnostics are preserved for review.' }
} catch {
    $report.failure = $_.Exception.Message
    Save-Report
    throw
} finally { Close-CompilerRuns }

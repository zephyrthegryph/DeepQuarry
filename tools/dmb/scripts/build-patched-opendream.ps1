param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$Dotnet
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path $SourceRoot).Path
$dotnetPath = (Resolve-Path $Dotnet).Path
$expectedCommit = '1362abc5accbc2037df9b45efa1de13fb1bb677f'
$actualCommit = (& git -C $source rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
    throw "Expected pinned OpenDream commit $expectedCommit; found $actualCommit"
}
if (-not (Test-Path (Join-Path $source 'RobustToolbox/Robust.Shared.Maths/Robust.Shared.Maths.csproj'))) {
    throw 'The RobustToolbox submodule is missing; initialize it before building.'
}

foreach ($patchName in @('opendream-combined-1362abc.patch', 'opendream-multiple-include-1362abc.patch', 'opendream-savefile-version-1362abc.patch')) {
    $patch = (Resolve-Path (Join-Path $PSScriptRoot "../patches/$patchName")).Path
    & git -C $source apply -R --check $patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Already applied: $patchName"
        continue
    }
    & git -C $source apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw "Cannot apply $patchName to $source" }
    & git -C $source apply $patch
    if ($LASTEXITCODE -ne 0) { throw "Failed to apply $patchName to $source" }
    Write-Output "Applied: $patchName"
}

& $dotnetPath build (Join-Path $source 'DMCompiler/DMCompiler.csproj') -c Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'OpenDream compiler build failed.' }
Write-Output "Patched compiler: $(Join-Path $source 'bin/DMCompiler/DMCompiler.exe')"

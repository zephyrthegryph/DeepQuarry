param(
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../../..").Path,
    [string]$Summary = "$PSScriptRoot/../target/failing-tests-41-summary.txt",
    [string]$MirrorRoot = "",
    [string[]]$TestNames = @()
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$names = if ($TestNames.Count) { @($TestNames) } else { @(Select-String -LiteralPath $Summary -Pattern '^(/datum/unit_test/[^ ]+) \[native PASS\]$' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
if (!$names.Count -or @($names | Select-Object -Unique).Count -ne $names.Count -or @($names | Where-Object { $_ -notmatch '^/datum/unit_test/[A-Za-z0-9_]+$' }).Count) { throw 'Expected distinct absolute unit-test paths.' }
if (!$MirrorRoot) { $MirrorRoot = Join-Path $ProjectRoot "tools/dmb/target/focused-regressions-$([Guid]::NewGuid().ToString('N'))" }
if (Test-Path -LiteralPath $MirrorRoot) { throw 'Mirror directory must be new.' }
$manifest = Join-Path $ProjectRoot 'deepquarry.dme'
$originalManifest = [IO.File]::ReadAllBytes($manifest)
function New-Mirror([string]$source, [string]$destination, [bool]$deep) {
    New-Item -ItemType Directory -Path $destination | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $source -Force) {
        if ($entry.Name -eq '.git') { continue }
        $target = Join-Path $destination $entry.Name
        if ($entry.PSIsContainer) {
            if ($deep -or @('maps', 'interface') -contains $entry.Name) {
                New-Mirror $entry.FullName $target $true
            } else {
                New-Item -ItemType Junction -Path $target -Target $entry.FullName | Out-Null
            }
        } elseif ($source -eq $ProjectRoot -and $entry.Name -eq 'deepquarry.dme') {
            Copy-Item -LiteralPath $entry.FullName -Destination $target
        } else {
            New-Item -ItemType HardLink -Path $target -Target $entry.FullName | Out-Null
        }
    }
}
New-Mirror $ProjectRoot $MirrorRoot $false
$gitDirectory = (& git -C $ProjectRoot rev-parse --absolute-git-dir).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine shared Git cache directory.' }
[IO.File]::WriteAllText((Join-Path $MirrorRoot '.git'), "gitdir: $gitDirectory`n", [Text.UTF8Encoding]::new($false))
$focus = ($names | ForEach-Object { "$_`n`t focus = TRUE" }) -join "`n`n"
[IO.File]::WriteAllText((Join-Path $MirrorRoot 'ownedfocus.dm'), "$focus`n", [Text.UTF8Encoding]::new($false))
[IO.File]::AppendAllText((Join-Path $MirrorRoot 'deepquarry.dme'), "`n#include `"ownedfocus.dm`"`n", [Text.UTF8Encoding]::new($false))
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($manifest)) -cne [Convert]::ToBase64String($originalManifest)) { throw 'Original manifest changed during preparation.' }
Write-Output "Mirror: $MirrorRoot"
$names | Write-Output


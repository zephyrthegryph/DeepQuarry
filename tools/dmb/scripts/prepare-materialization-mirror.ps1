#requires -Version 7.0
<#
.SYNOPSIS
Prepare an isolated read-only input mirror for materialization_bench; no game files are edited.
#>
param(
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../../..").Path,
    [Parameter(Mandatory = $true)][string]$MirrorRoot,
    [string]$GeneratedIcons = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$MirrorRoot = [IO.Path]::GetFullPath($MirrorRoot)
if (Test-Path -LiteralPath $MirrorRoot) { throw 'Mirror must be a new directory.' }
if ($GeneratedIcons) { $GeneratedIcons = (Resolve-Path -LiteralPath $GeneratedIcons).Path }
function Copy-Tree([string]$Source, [string]$Target, [bool]$Deep) {
    New-Item -ItemType Directory -Path $Target | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $Source -Force) {
        if ($entry.Name -eq '.git') { continue }
        $destination = Join-Path $Target $entry.Name
        if ($entry.PSIsContainer) {
            if ($Source -eq $ProjectRoot -and @('maps','interface','icons') -contains $entry.Name) {
                Copy-Tree $entry.FullName $destination ($entry.Name -ne 'icons')
            } elseif ($Deep) { Copy-Tree $entry.FullName $destination $true }
            else { New-Item -ItemType Junction -Path $destination -Target $entry.FullName | Out-Null }
        } elseif ($Source -eq $ProjectRoot -and $entry.Extension -eq '.dme') {
            Copy-Item -LiteralPath $entry.FullName -Destination $destination
        } else { New-Item -ItemType HardLink -Path $destination -Target $entry.FullName | Out-Null }
    }
}
Copy-Tree $ProjectRoot $MirrorRoot $false
if ($GeneratedIcons -and !(Test-Path -LiteralPath (Join-Path $MirrorRoot 'icons/gen'))) {
    New-Item -ItemType Junction -Path (Join-Path $MirrorRoot 'icons/gen') -Target $GeneratedIcons | Out-Null
}
Write-Output (Join-Path $MirrorRoot 'deepquarry.dme')

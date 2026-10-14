param([string]$OutputDirectory, [string]$UnitTestTemplate)

# Build a disposable runtime asset tree. Every modified file is a real copy;
# the source worktree and its junction-backed mirrors are never written.
$ErrorActionPreference = 'Stop'
$toolRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot = [IO.Path]::GetFullPath((Join-Path $toolRoot '../..'))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $toolRoot ('target/runtime-assets/' + [Guid]::NewGuid().ToString('N'))
}
$overlay = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $overlay) { throw "Overlay directory must be new: $overlay" }
New-Item -ItemType Directory -Path $overlay | Out-Null

foreach ($name in @('code', 'icons', 'sound', 'strings', 'html', 'interface', 'tgui', 'SQL')) {
    $source = Join-Path $projectRoot $name
    if (Test-Path -LiteralPath $source -PathType Container) {
        New-Item -ItemType Junction -Path (Join-Path $overlay $name) -Target $source | Out-Null
    }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'config') -Destination (Join-Path $overlay 'config') -Recurse
New-Item -ItemType Directory -Path (Join-Path $overlay 'data') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'data') -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.json', '.txt') } |
    Copy-Item -Destination (Join-Path $overlay 'data')
Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.dll' | Copy-Item -Destination $overlay

$maps = Join-Path $overlay 'maps'
New-Item -ItemType Directory -Path $maps | Out-Null
foreach ($item in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'maps')) {
    $destination = Join-Path $maps $item.Name
    if ($item.Name -eq 'templates') {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse
    } elseif ($item.PSIsContainer) {
        New-Item -ItemType Junction -Path $destination -Target $item.FullName | Out-Null
    } else {
        Copy-Item -LiteralPath $item.FullName -Destination $destination
    }
}
$template = Join-Path $maps 'templates/unit_tests.dmm'
if ((Get-Item -LiteralPath (Split-Path $template)).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Refusing to edit a junction-backed template directory.'
}
if ($UnitTestTemplate) {
    Copy-Item -LiteralPath (Resolve-Path -LiteralPath $UnitTestTemplate).Path -Destination $template
}
$content = [IO.File]::ReadAllText($template)
if ((-not $content.Contains('/turf/closed/indestructible') -and -not $content.Contains('/turf/simulated/wall')) -or
    (-not $content.Contains('/area/misc/testroom') -and -not $content.Contains('/area/rnd/test_area'))) {
    throw 'Expected stale unit-test template paths were not found; reassess the workaround.'
}
$content = $content.Replace('/turf/closed/indestructible', '/turf/simulated/wall').Replace('/area/misc/testroom', '/area/rnd/test_area')
[IO.File]::WriteAllText($template, $content, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    RuntimeDirectory = $overlay
    Template = $template
    Workaround = 'Replace two nonexistent unit-test template type paths with existing wall and area types.'
} | ConvertTo-Json

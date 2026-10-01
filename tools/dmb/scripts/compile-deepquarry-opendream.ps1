param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$OutputJson,
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
    [string]$ByondVersion = '516.1687',
    [string]$ScratchRoot = [IO.Path]::GetTempPath(),
    [switch]$NativeConditionalBranches,
    [switch]$BaseRuntimeCompatibility,
    [string]$NativeCompiler,
    [string]$NativeOutputBase,
    [string[]]$Defines = @()
)

$ErrorActionPreference = 'Stop'
foreach ($define in $Defines) {
    if ($define -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "Invalid preprocessor define: $define"
    }
}
$root = (Resolve-Path $ProjectRoot).Path
$compilerPath = (Resolve-Path $Compiler).Path
if ($NativeCompiler -and -not $NativeOutputBase) {
    throw 'NativeOutputBase is required when compiling the paired native reference.'
}
$nativeCompilerPath = if ($NativeCompiler) { (Resolve-Path $NativeCompiler).Path } else { $null }
$outputPath = [IO.Path]::GetFullPath($OutputJson)
[IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
$scratch = Join-Path $ScratchRoot ('od_probe_' + [guid]::NewGuid().ToString('N'))
$tempRoot = [IO.Path]::GetFullPath($ScratchRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$scratch = [IO.Path]::GetFullPath($scratch)
if (-not $scratch.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Scratch directory escaped the temporary directory: $scratch"
}
$manifestPath = Join-Path $scratch 'deepquarry.dme'
$overlayPath = Join-Path $scratch 'overlay.dm'
$generatedJson = [IO.Path]::ChangeExtension($manifestPath, '.json')
$logPath = [IO.Path]::ChangeExtension($outputPath, '.log')
$linkedDirectories = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object {
    $_.Name -notin @('.git', '.codex')
})

try {
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    foreach ($directory in $linkedDirectories) {
        New-Item -ItemType Junction -Path (Join-Path $scratch $directory.Name) -Target $directory.FullName | Out-Null
    }
    $manifest = [IO.File]::ReadAllText((Join-Path $root 'deepquarry.dme'))
    $manifest = $manifest.Replace('#include "code\__odlint.dm"', '')
    # The generated child getter redeclares an inherited proc in this source
    # snapshot. Both compilers must see the same legal override for a paired
    # diagnostic build; keep the original game tree untouched.
    $bindingsPath = Join-Path $root 'code/__defines/verdigris/_bindings_types.dm'
    $bindings = [IO.File]::ReadAllText($bindingsPath)
    $declaration = '/obj/item/gas_mix_holder/proc/get_temperature()'
    if ($bindings.Contains($declaration)) {
        $compatBindings = Join-Path $scratch '_bindings_types.dm'
        [IO.File]::WriteAllText($compatBindings, $bindings.Replace($declaration, '/obj/item/gas_mix_holder/get_temperature()'))
        $manifest = $manifest.Replace('#include "code\__defines\verdigris\_bindings_types.dm"', '#include "' + $compatBindings + '"')
    }
    if ($BaseRuntimeCompatibility) {
        # DreamMaker accepts mob/usr here, but the base OpenDream compiler
        # reserves usr. Keep this compatibility rename inside the scratch tree.
        $casinoSource = [IO.File]::ReadAllText((Join-Path $root 'code/modules/casino/casino.dm'))
        $startMarker = '/obj/machinery/wheel_of_fortune/proc/interaction_setinterval(mob/usr)'
        $endMarker = "`n//`n//Sentient Prize Terminal"
        $start = $casinoSource.IndexOf($startMarker, [StringComparison]::Ordinal)
        if ($start -lt 0) { throw 'Casino compatibility proc not found' }
        $end = $casinoSource.IndexOf($endMarker, $start, [StringComparison]::Ordinal)
        if ($end -lt 0) { throw 'Casino compatibility proc end not found' }
        $section = $casinoSource.Substring($start, $end - $start)
        $renamed = [regex]::Replace($section, '\busr\b', 'user')
        $compatCasino = Join-Path $scratch 'casino.dm'
        [IO.File]::WriteAllText($compatCasino, $casinoSource.Substring(0, $start) + $renamed + $casinoSource.Substring($end))
        $manifest = $manifest.Replace('#include "code\modules\casino\casino.dm"', '#include "' + $compatCasino + '"')
    }
    $manifest = [regex]::Replace($manifest, '(?m)^#include "([^"]+)"', {
        param($match)
        $included = $match.Groups[1].Value
        # DMF is serialized as the interface/resource path in OpenDream JSON.
        # Keep it relative while the scratch directory's interface junction
        # supplies the actual file to the compiler.
        if ($included.EndsWith('.dmf', [StringComparison]::OrdinalIgnoreCase)) {
            return '#include "' + $included.Replace('\', '/') + '"'
        }
        if ([IO.Path]::IsPathRooted($included)) { return $match.Value }
        return '#include "' + (Join-Path $root $included) + '"'
    })
    $manifest = [regex]::Replace($manifest, '(?m)^#define FILE_DIR ([^"\s][^\r\n]*)$', {
        param($match)
        return '#define FILE_DIR "' + $match.Groups[1].Value + '"'
    })
    # Keep the compatibility type after authored declarations. Defining it in
    # the prefix reserves the /obj subtree before root procs and changes native
    # resource import order even though the type itself has no assets.
    $manifest = "#include `"$overlayPath`"`r`n" + $manifest + "`r`n/obj/item/dq_rule_test`r`n"

    # OpenDream defines OPENDREAM in its standard header. For static comparison
    # with a Dream Maker build, remove it before any project source is included
    # so native-only branches (for example lootpanel/open) are retained.
    $nativeConditionals = if ($NativeConditionalBranches) { "#undef OPENDREAM`r`n" } else { '' }
    $definePrefix = ($Defines | ForEach-Object { "#define $_`r`n" }) -join ''
    [IO.File]::WriteAllText($overlayPath, $nativeConditionals + $definePrefix)
    [IO.File]::WriteAllText($manifestPath, $manifest)

    if ($nativeCompilerPath) {
        $nativeLog = & $nativeCompilerPath $manifestPath 2>&1
        $nativeExit = $LASTEXITCODE
        $nativeBase = [IO.Path]::GetFullPath($NativeOutputBase)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($nativeBase)) | Out-Null
        [IO.File]::WriteAllLines($nativeBase + '.log', [string[]]$nativeLog)
        if ($nativeExit -ne 0) { throw "Native compile failed with exit code $nativeExit. See $nativeBase.log" }
        foreach ($extension in @('.dmb', '.rsc')) {
            Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($manifestPath, $extension)) -Destination ($nativeBase + $extension) -Force
        }
    }

    $log = & $compilerPath "--version=$ByondVersion" $manifestPath 2>&1
    $exitCode = $LASTEXITCODE
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
    [IO.File]::WriteAllLines($logPath, [string[]]$log)
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $generatedJson)) {
        throw "OpenDream failed with exit code $exitCode. See $logPath"
    }
    Copy-Item -LiteralPath $generatedJson -Destination $outputPath -Force
    Write-Output "Compiled diagnostic JSON: $outputPath"
    Write-Output "Compiler log: $logPath"
} finally {
    if (Test-Path -LiteralPath $scratch) {
        foreach ($directory in $linkedDirectories) {
            $junction = Join-Path $scratch $directory.Name
            if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
        }
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}

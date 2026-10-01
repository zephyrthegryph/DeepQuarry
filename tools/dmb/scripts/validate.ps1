# Check translated artifacts. DreamDaemon runs only with -RunDreamDaemon.
# The temporary runtime log is retained on failure.
param(
    [Parameter(Mandatory = $true)][string]$OpenDreamJson,
    [Parameter(Mandatory = $true)][string]$DmbPath,
    [switch]$RunDreamDaemon,
    [string]$DreamDaemon,
    [string]$ExpectedLog,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Read-LogText([string]$Path) {
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $reader = [IO.StreamReader]::new($stream)
            return $reader.ReadToEnd()
        } finally {
            $stream.Dispose()
        }
    } catch [IO.IOException] {
        # DreamDaemon may briefly hold its new log exclusively while opening it.
        return ''
    }
}

$jsonFile = Resolve-ExistingFile $OpenDreamJson 'OpenDream JSON'
$dmbFile = Resolve-ExistingFile $DmbPath 'DMB'

if ([IO.Path]::GetExtension($dmbFile) -ine '.dmb') {
    throw "DMB path must end in .dmb: $dmbFile"
}
if (-not $RunDreamDaemon) {
    Write-Output "Validated input paths: $jsonFile and $dmbFile"
    Write-Output 'DreamDaemon was not launched. Use -RunDreamDaemon for a runtime check.'
    return
}
if ([string]::IsNullOrWhiteSpace($DreamDaemon)) {
    throw 'DreamDaemon executable path is required with -RunDreamDaemon.'
}
$daemonFile = Resolve-ExistingFile $DreamDaemon 'DreamDaemon executable'
if ([string]::IsNullOrEmpty($ExpectedLog)) {
    throw 'ExpectedLog must be a nonempty complete log line.'
}

$worldDirectory = [IO.Path]::GetDirectoryName($dmbFile)
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $logFile = Join-Path $worldDirectory ("dmb-validate-{0}.log" -f [guid]::NewGuid().ToString('N'))
} else {
    $logFile = [IO.Path]::GetFullPath($LogPath)
    if (Test-Path -LiteralPath $logFile) {
        throw "Refusing to overwrite existing log: $logFile"
    }
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($logFile)) -PathType Container)) {
        throw "Log directory does not exist: $logFile"
    }
}

$process = $null
$matched = $false
try {
    # DreamDaemon accepts the world, a port, and options. Port 0 selects an
    # available port; -log captures world.log plus runtime diagnostics.
    $arguments = @(
        '"' + $dmbFile + '"',
        '0',
        '-trusted',
        '-invisible',
        '-log',
        '"' + $logFile + '"'
    )
    $process = Start-Process -FilePath $daemonFile -ArgumentList $arguments `
        -WorkingDirectory $worldDirectory -WindowStyle Hidden -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $logFile -PathType Leaf) {
            $logText = Read-LogText $logFile
            if (@($logText -split "`r?`n" | Where-Object { $_ -eq $ExpectedLog }).Count -gt 0) {
                $matched = $true
                break
            }
        }
        $process.Refresh()
        if ($process.HasExited) {
            break
        }
        Start-Sleep -Milliseconds 200
    }
} finally {
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit(5000) | Out-Null
        }
        $process.Dispose()
    }
}

if (-not $matched) {
    $observed = if (Test-Path -LiteralPath $logFile -PathType Leaf) {
        Read-LogText $logFile
    } else {
        '<no log created>'
    }
    throw "DreamDaemon did not log '$ExpectedLog' within $TimeoutSeconds seconds. Log: $logFile`n$observed"
}

Write-Output "PASS: DreamDaemon logged '$ExpectedLog' for $dmbFile"
Write-Output "OpenDream input: $jsonFile"
Write-Output "Runtime log: $logFile"

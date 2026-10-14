param(
    [Parameter(Mandatory=$true)][string]$Dmb,
    [string]$Rsc,
    [string]$DreamDaemon = 'D:/Program Files (x86)/BYOND516/bin/dd.exe',
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [ValidateSet('writable-copy','readonly-hardlink')][string]$Case = 'writable-copy',
    [ValidateRange(1,30)][int]$TimeoutSeconds = 30,
    [string]$Procmon,
    [string]$BackingFile
)
$ErrorActionPreference = 'Stop'
# This script launches only its own DreamDaemon. Procmon capture/export is an
# explicit coordinator action, since terminating Procmon can affect other traces.
if (-not ('Phase0AccessErrorMode' -as [type])) {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class Phase0AccessErrorMode {
    [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
}
"@
}
$previousMode = [Phase0AccessErrorMode]::SetErrorMode(3)
$child = $null
$receipt = $null
try {
    $sourceDmb = (Resolve-Path -LiteralPath $Dmb).Path
    if (-not $Rsc) { $Rsc = [IO.Path]::ChangeExtension($sourceDmb,'.rsc') }
    $sourceRsc = (Resolve-Path -LiteralPath $Rsc).Path
    $engine = (Resolve-Path -LiteralPath $DreamDaemon).Path
    $runRoot = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ('access-' + [Guid]::NewGuid().ToString('N'))
    $reference = Join-Path $runRoot 'reference'
    $slot = Join-Path $runRoot 'slot'
    New-Item -ItemType Directory -Path $reference,$slot -Force | Out-Null
    $paths = @()
    foreach ($entry in @(@($sourceDmb,'access_probe.dmb'),@($sourceRsc,'access_probe.rsc'))) {
        $privateCopy = Join-Path $reference $entry[1]
        $slotFile = Join-Path $slot $entry[1]
        Copy-Item -LiteralPath $entry[0] -Destination $privateCopy
        (Get-Item -LiteralPath $privateCopy).IsReadOnly = $false
        if ($Case -eq 'readonly-hardlink') {
            (Get-Item -LiteralPath $privateCopy).IsReadOnly = $true
            New-Item -ItemType HardLink -Path $slotFile -Target $privateCopy | Out-Null
        } else { Copy-Item -LiteralPath $privateCopy -Destination $slotFile }
        $paths += $slotFile
    }
    $before = @($paths | ForEach-Object { @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} })
    $receipt = [ordered]@{
        status='running';case=$Case;root=$runRoot;engine=$engine
        engine_sha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
        engine_file_version=(Get-Item -LiteralPath $engine).VersionInfo.FileVersion
        arguments=@($paths[0],'0','-trusted','-close');timeout_seconds=$TimeoutSeconds
        pid=$null;started_utc=[DateTime]::UtcNow.ToString('o');exit_code=$null;timed_out=$false
        before=$before;after=@();marker_ok=$false;pair_unchanged=$false
        access_trace_status='not assessed';procmon=$Procmon;backing_file=$BackingFile
        hardlink_access_conclusion='inconclusive until requested-access trace reviewed'
    }
    if ($Procmon) {
        $traceTool = (Resolve-Path -LiteralPath $Procmon).Path
        if (-not $BackingFile) { $BackingFile = Join-Path $runRoot 'access.pml'; $receipt.backing_file=$BackingFile }
        Write-Output "Coordinator: start capture BEFORE running this probe with $traceTool /AcceptEula /Quiet /Minimized /BackingFile `"$BackingFile`". Capture all file-system events; filter the recorded PID afterwards. This runner does not start, stop or export a shared Procmon session."
    }
    $out = Join-Path $runRoot 'stdout.log'
    $err = Join-Path $runRoot 'stderr.log'
    $child = Start-Process -FilePath $engine -ArgumentList @(('"' + $paths[0] + '"'),'0','-trusted','-close') -WorkingDirectory $slot -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $receipt.pid=$child.Id
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'receipt.json') -Encoding UTF8
    Write-Output "DreamDaemon PID $($child.Id); evidence directory $runRoot"
    if (-not $child.WaitForExit($TimeoutSeconds*1000)) {
        $receipt.timed_out=$true
        # Only the exact child created by this runner and its descendants.
        & taskkill.exe /PID $child.Id /T /F | Out-Null
        $child.WaitForExit()
    }
    $child.Refresh()
    $receipt.exit_code=$child.ExitCode
    $receipt.after=@($paths | ForEach-Object { @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} })
    $receipt.pair_unchanged=($before[0].sha256 -eq $receipt.after[0].sha256 -and $before[1].sha256 -eq $receipt.after[1].sha256)
    $logs = (Get-Content -LiteralPath $out,$err -Raw -ErrorAction SilentlyContinue) -join "`n"
    $receipt.marker_ok=($logs.Contains('PHASE0_PAIR_PROBE_OK') -and -not $logs.Contains('PHASE0_PAIR_PROBE_FAIL'))
    $receipt.status=if ($receipt.timed_out -or -not $receipt.marker_ok -or -not $receipt.pair_unchanged) {'fail'} else {'runtime-pass-access-unassessed'}
    $receipt.finished_utc=[DateTime]::UtcNow.ToString('o')
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'receipt.json') -Encoding UTF8
    Write-Output "Result $($receipt.status); access-mask evidence must be reviewed separately."
    if ($Procmon) { Write-Output "Coordinator: stop ONLY your capture, then export: `"$Procmon`" /OpenLog `"$BackingFile`" /SaveAs `"$runRoot/access.csv`". Retain original PML. Review CreateFile Desired Access for PID $($child.Id), pair paths and .dyn.rsc separately." }
    if ($receipt.status -eq 'fail') { throw 'Access probe failed; evidence retained.' }
} finally {
    if ($child -and -not $child.HasExited) {
        & taskkill.exe /PID $child.Id /T /F | Out-Null
        $child.WaitForExit()
    }
    [void][Phase0AccessErrorMode]::SetErrorMode($previousMode)
}

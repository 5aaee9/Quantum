# Git for Windows — the single most important runner dependency.
# OFFLINE: the guest has no working TCP under QEMU, so the installer rides
# on the provision ISO at <cd>:\payloads\Git-64-bit.exe (fetched host-side by
# scripts/fetch-windows-drivers.sh). Fall back to a live download only if the
# payload is somehow absent.
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$installer = $null
# find the provision CD by its PROVISION volume label (the letter is not
# stable — it can be D:, E:, F:, ...), falling back to every CD-ROM drive.
# prefer the on-disk staging dir that specialize copies the provision CD to
# (C:\provision\) — the CD itself may be ejected/unmounted by first-logon.
$cdDrives = @('C:\provision') + (Get-CimInstance Win32_Volume -Filter "DriveType=5" | ForEach-Object { "${($_.DriveLetter)}:" })
if ($cdDrives.Count -eq 1) { $cdDrives += 'D','E','F','G','H' }
foreach ($d in $cdDrives) {
    foreach ($p in "$d\payloads\Git-64-bit.exe", "$d\Git-64-bit.exe") {
        if (Test-Path $p) { $installer = $p; break }
    }
    if ($installer) { break }
}
if (-not $installer) {
    Write-Host 'git payload not on the ISO — downloading'
    $release = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest'
    $asset = $release.assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
    if (-not $asset) { throw 'could not find the Git-*-64-bit.exe asset in the latest git-for-windows release' }
    $installer = "$env:TEMP\$($asset.name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $installer
}
Write-Host "Installing Git from $installer ..."
&$installer /VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" | Out-Null
if ($LASTEXITCODE) { throw "git installer failed with exit code $LASTEXITCODE" }

# Match the official windows runner image git defaults.
& 'C:\Program Files\Git\bin\git.exe' config --system --add safe.directory '*'
& 'C:\Program Files\Git\bin\git.exe' config --system core.longpaths true
& 'C:\Program Files\Git\bin\git.exe' config --system core.autocrlf false
& 'C:\Program Files\Git\bin\git.exe' config --system core.symlinks true

Write-Host 'Done installing Git.'

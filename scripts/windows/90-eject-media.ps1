# Eject every non-fixed volume (provision ISO, install ISO) so the sealed
# template has no media attached. Uses EjectVolumeMedia, a tiny helper that
# calls the documented eject IOCTLs.
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

$exe = $null
$cdDrives = @('C:\provision') + (Get-CimInstance Win32_Volume -Filter "DriveType=5" | ForEach-Object { "${($_.DriveLetter)}:" })
if ($cdDrives.Count -eq 1) { $cdDrives += 'D','E','F','G','H' }
foreach ($d in $cdDrives) {
    foreach ($p in "$d\payloads\EjectVolumeMedia.exe", "$d\EjectVolumeMedia.exe") {
        if (Test-Path $p) { $exe = $p; break }
    }
    if ($exe) { break }
}
if (-not $exe) {
    $exe = "$env:TEMP\EjectVolumeMedia.exe"
    Invoke-WebRequest `
        'https://github.com/rgl/EjectVolumeMedia/releases/download/v1.0.0/EjectVolumeMedia.exe' `
        -OutFile $exe
}
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
if ($hash -ne 'f7863394085e1b3c5aa999808b012fba577b4a027804ea292abf7962e5467ba0') {
    throw "EjectVolumeMedia.exe hash mismatch: $hash"
}

Get-Volume | Where-Object { $_.DriveType -ne 'Fixed' -and $_.DriveLetter } | ForEach-Object {
    Write-Host "Ejecting $($_.DriveLetter): ..."
    & $exe $_.DriveLetter
}

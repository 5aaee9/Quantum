# PowerShell 7 (pwsh) — many GH actions and scripts expect it; the official
# windows runner images ship it too.
# OFFLINE: install the MSI from <cd>:\payloads\PowerShell-win-x64.msi.
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

$msi = $null
$cdDrives = @('C:\provision') + (Get-CimInstance Win32_Volume -Filter "DriveType=5" | ForEach-Object { "${($_.DriveLetter)}:" })
if ($cdDrives.Count -eq 1) { $cdDrives += 'D','E','F','G','H' }
foreach ($d in $cdDrives) {
    foreach ($p in "$d\payloads\PowerShell-win-x64.msi", "$d\PowerShell-win-x64.msi") {
        if (Test-Path $p) { $msi = $p; break }
    }
    if ($msi) { break }
}
if (-not $msi) {
    Write-Host 'pwsh payload not on the ISO — downloading'
    $release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $asset = $release.assets | Where-Object { $_.name -like 'PowerShell-*-win-x64.msi' } | Select-Object -First 1
    if (-not $asset) { throw 'could not find the PowerShell-*-win-x64.msi asset in the latest PowerShell release' }
    $msi = "$env:TEMP\$($asset.name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $msi
}
Write-Host "Installing PowerShell 7 from $msi ..."
# USE_MU/ENABLE_MU register pwsh in Microsoft Update for future servicing.
msiexec /i $msi /qn ADD_PATH=1 USE_MU=1 ENABLE_MU=1 /l*v "$env:TEMP\pwsh-msi.log" | Out-Null
if ($LASTEXITCODE) { throw "pwsh msi failed with exit code $LASTEXITCODE (see $env:TEMP\pwsh-msi.log)" }

Write-Host 'Done installing PowerShell 7.'

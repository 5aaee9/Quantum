# PowerShell 7 (pwsh) — many GH actions and scripts expect it; the official
# windows runner images ship it too.
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

$release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
$asset = $release.assets | Where-Object { $_.name -like 'PowerShell-*-win-x64.msi' } | Select-Object -First 1
if (-not $asset) { throw 'could not find the PowerShell-*-win-x64.msi asset in the latest PowerShell release' }

$msi = "$env:TEMP\$($asset.name)"
Write-Host "Downloading $($asset.browser_download_url) ..."
Invoke-WebRequest $asset.browser_download_url -OutFile $msi

Write-Host 'Installing PowerShell 7...'
# USE_MU/ENABLE_MU register pwsh in Microsoft Update for future servicing.
msiexec /i $msi /qn ADD_PATH=1 USE_MU=1 ENABLE_MU=1 /l*v "$msi.log" | Out-Null
if ($LASTEXITCODE) { throw "pwsh msi failed with exit code $LASTEXITCODE (see $msi.log)" }
Remove-Item $msi

Write-Host 'Done installing PowerShell 7.'

# Git for Windows — the single most important runner dependency.
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

$release = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest'
$asset = $release.assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
if (-not $asset) { throw 'could not find the Git-*-64-bit.exe asset in the latest git-for-windows release' }

$installer = "$env:TEMP\$($asset.name)"
Write-Host "Downloading $($asset.browser_download_url) ..."
Invoke-WebRequest $asset.browser_download_url -OutFile $installer

Write-Host 'Installing Git...'
&$installer /VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" | Out-Null
if ($LASTEXITCODE) { throw "git installer failed with exit code $LASTEXITCODE" }
Remove-Item $installer

# Match the official windows runner image git defaults.
& 'C:\Program Files\Git\bin\git.exe' config --system --add safe.directory '*'
& 'C:\Program Files\Git\bin\git.exe' config --system core.longpaths true
& 'C:\Program Files\Git\bin\git.exe' config --system core.autocrlf false
& 'C:\Program Files\Git\bin\git.exe' config --system core.symlinks true

Write-Host 'Done installing Git.'

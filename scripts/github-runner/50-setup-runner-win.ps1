# Pre-install the GitHub Actions self-hosted runner (windows-x64) under
# C:\actions-runner, owned by the local `runner` user (Administrators —
# self-hosted CI jobs routinely need elevation).
#
# Registration is intentionally left to deploy time because the
# registration token is short-lived. After cloudbase-init brings the clone
# up, register it once:
#
#   C:\actions-runner\config.cmd --unattended `
#       --url https://github.com/<org-or-repo> --token <token> `
#       --runasservice --windowslogonaccount ".\runner" `
#       --windowslogonpassword "<runner password>"
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

$runnerDir = 'C:\actions-runner'
$runnerUser = 'runner'
$runnerPassword = '4tH2F34cEDRApj8Y@B26' # same convention as the linux images

# --- runner user ----------------------------------------------------------
if (-not (Get-LocalUser -Name $runnerUser -ErrorAction SilentlyContinue)) {
    $securePassword = ConvertTo-SecureString $runnerPassword -AsPlainText -Force
    New-LocalUser -Name $runnerUser -Password $securePassword `
        -FullName 'GitHub Runner' -Description 'GitHub Actions runner service account' `
        -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
}
Add-LocalGroupMember -Group 'Administrators' -Member $runnerUser -ErrorAction SilentlyContinue

# --- runner bundle ----------------------------------------------------------
# OFFLINE: prefer the zip shipped on the provision ISO at
# <cd>:\payloads\actions-runner-win-x64.zip (the guest has no working TCP).
$zip = $null
$cdDrives = @('C:\provision') + (Get-CimInstance Win32_Volume -Filter "DriveType=5" | ForEach-Object { "${($_.DriveLetter)}:" })
if ($cdDrives.Count -eq 1) { $cdDrives += 'D','E','F','G','H' }
foreach ($d in $cdDrives) {
    foreach ($p in "$d\payloads\actions-runner-win-x64.zip", "$d\actions-runner-win-x64.zip") {
        if (Test-Path $p) { $zip = $p; break }
    }
    if ($zip) { break }
}
if (-not $zip) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/actions/runner/releases/latest'
    $asset = $release.assets | Where-Object { $_.name -like 'actions-runner-win-x64-*.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'could not find the actions-runner-win-x64 asset in the latest actions/runner release' }
    $zip = "$env:TEMP\$($asset.name)"
    Write-Host "Downloading $($asset.browser_download_url) ..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip
} else {
    Write-Host "Using runner bundle from ISO: $zip"
}

New-Item -ItemType Directory -Force $runnerDir | Out-Null
Expand-Archive $zip $runnerDir
# only remove a temp copy we downloaded — never the read-only ISO payload.
if ($zip -like "$env:TEMP*") { Remove-Item $zip -Force -ErrorAction SilentlyContinue }

# give the runner user full control over its directory.
$acl = Get-Acl $runnerDir
$acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    $runnerUser, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl $runnerDir $acl

Write-Host 'Done installing the actions runner bundle.'

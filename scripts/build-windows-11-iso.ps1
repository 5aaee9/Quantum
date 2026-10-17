# Run in elevated Windows PowerShell 5.1+ on modern Windows (not Linux pwsh).
# UUP's Windows converter is required for updates and Windows 11 Store apps.
[CmdletBinding()]
param(
    [string]$WorkDirectory = 'C:\uup-windows-11',
    [int]$TimeoutMinutes = 180
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\windows\uup-helpers.ps1"
if ($env:OS -ne 'Windows_NT') { throw 'ISO conversion requires Windows; Linux conversion is not supported' }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run elevated as Administrator' }
$WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
if ($WorkDirectory -match '[\s&|<>^%!]') { throw 'Use a workspace path without whitespace or shell metacharacters' }
if (Test-Path $WorkDirectory) { throw 'Use a new work directory to exclude stale ISO files' }
New-Item -ItemType Directory $WorkDirectory | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Request-Uup([string]$Uri, [string]$OutFile) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
            return
        } catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Seconds (30 * $attempt)
        }
    }
}

# Same Retail channel as the homepage's Latest Public Release x64 option.
$apiUrl = 'https://api.uupdump.net/fetchupd.php?arch=amd64&ring=Retail'
$sourceUrl = $apiUrl
try {
    Request-Uup $apiUrl "$WorkDirectory\retail.json"
    $build = Select-PublicWindows11Build ((Get-Content "$WorkDirectory\retail.json" -Raw | ConvertFrom-Json).response)
} catch {
    Write-Warning "Retail JSON API failed: $($_.Exception.Message). Trying the official Latest Public Release page."
    $sourceUrl = 'https://uupdump.net/fetchupd.php?arch=amd64&ring=retail'
    Request-Uup $sourceUrl "$WorkDirectory\retail.html"
    $build = Get-PublicWindows11BuildFromHtml (Get-Content "$WorkDirectory\retail.html" -Raw)
}
Write-Host "Selected $($build.updateTitle) / $($build.updateId)"
# Enterprise is a virtual edition derived from Pro, not a direct UUP edition.
$packageUrl = "https://uupdump.net/get.php?id=$($build.updateId)&pack=en-us&edition=professional&autodl=2"
Request-Uup $packageUrl "$WorkDirectory\uup.zip"
Expand-Archive "$WorkDirectory\uup.zip" "$WorkDirectory\convert"
$configPath = "$WorkDirectory\convert\ConvertConfig.ini"
Set-EnterpriseUupConfig (Get-Content $configPath -Raw) | Set-Content -Encoding ascii $configPath

$process = Start-Process $env:ComSpec -WorkingDirectory "$WorkDirectory\convert" `
    -ArgumentList '/d /c uup_download_windows.cmd' -PassThru `
    -RedirectStandardOutput "$WorkDirectory\convert.stdout.log" `
    -RedirectStandardError "$WorkDirectory\convert.stderr.log"
# Retain the process handle so ExitCode remains available after completion.
$null = $process.Handle
if (-not $process.WaitForExit($TimeoutMinutes * 60000)) {
    & taskkill /PID $process.Id /T /F
    throw 'UUP download/conversion timed out; inspect converter logs'
}
$process.Refresh()
if ($process.ExitCode -ne 0) { throw "UUP converter exited $($process.ExitCode)" }
$isos = @(Get-ChildItem "$WorkDirectory\convert" -Filter '*.iso')
if ($isos.Count -ne 1) { throw "Expected exactly one newly generated ISO, got $($isos.Count)" }
$iso = $isos[0].FullName
# Exit codes alone are insufficient: check the actual image edition and build.
$disk = Mount-DiskImage -ImagePath $iso -PassThru
try {
    $volume = $disk | Get-Volume
    $wim = "$($volume.DriveLetter):\sources\install.wim"
    $images = @(Get-WindowsImage -ImagePath $wim)
    $enterprise = @($images | Where-Object ImageName -eq 'Windows 11 Enterprise')
    if ($enterprise.Count -ne 1) { throw 'Generated ISO lacks a unique Windows 11 Enterprise image' }
    $detail = Get-WindowsImage -ImagePath $wim -Index $enterprise[0].ImageIndex
    if ($detail.EditionId -ne 'Enterprise' -or $detail.Architecture -ne 9) { throw 'Wrong image edition/architecture' }
    if ([string]$detail.Version -ne "10.0.$($build.foundBuild)") {
        throw "Image version $($detail.Version) differs from selected $($build.foundBuild); do not publish a base/unpatched ISO"
    }
} finally {
    Dismount-DiskImage -ImagePath $iso | Out-Null
}
$destination = "$WorkDirectory\windows-11.iso"
Move-Item $iso $destination
$hash = (Get-FileHash $destination -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  windows-11.iso" | Set-Content -Encoding ascii "$WorkDirectory\windows-11.iso.sha256"
@{
    updateId=$build.updateId; title=$build.updateTitle; build=$build.foundBuild
    architecture='amd64'; language='en-us'; edition='Enterprise'; channel='Retail'
    sha256=$hash; source=$sourceUrl; package=$packageUrl
} | ConvertTo-Json | Set-Content -Encoding ascii "$WorkDirectory\windows-11.json"
Write-Host "Validated ISO: $destination"

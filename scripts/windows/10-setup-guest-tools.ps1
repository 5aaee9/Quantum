# Installs virtio-win-guest-tools.exe from the provision ISO (or, as a
# fallback, over the packer HTTP server). Brings in the full virtio driver
# set plus QEMU-GA and the SPICE agent.
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

function Get-GuestTool($filename) {
    $path = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $p = Join-Path $_.Root $filename
        if (Test-Path $p) { $p }
    } | Select-Object -First 1
    if (!$path) {
        $url = "http://$env:PACKER_HTTP_ADDR/drivers/$filename"
        $path = "$env:TEMP\$filename"
        Write-Host "Downloading $url..."
        Invoke-WebRequest $url -OutFile $path
    }
    return $path
}

$guestTools = Get-GuestTool virtio-win-guest-tools.exe
Write-Host "Installing $guestTools ..."
$guestToolsLog = "$env:TEMP\virtio-win-guest-tools.log"
&$guestTools /install /norestart /quiet /log $guestToolsLog | Out-String -Stream
# NB 3010 means "success, restart required" — packer restarts next anyway.
if ($LASTEXITCODE -and $LASTEXITCODE -ne 3010) {
    throw "failed to install guest tools with exit code $LASTEXITCODE"
}

Write-Host 'Asserting the QEMU-GA service exists...'
Get-Service QEMU-GA | Out-Null

Write-Host 'Done installing the guest tools.'

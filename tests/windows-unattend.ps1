$ErrorActionPreference = 'Stop'
[xml]$xml = Get-Content -Raw "$PSScriptRoot/../http/windows-2025-runner/autounattend.xml"
$ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
$commands = $xml.SelectNodes('//u:settings[@pass="specialize"]//u:Path', $ns)
if ($commands.InnerText -match 'Get-NetConnectionProfile|Set-NetConnectionProfile') {
    throw 'Network-profile queries must not block offline specialize.'
}
$entries = $xml.SelectNodes('//u:CommandLine|//u:Path', $ns) |
    Where-Object { $_.InnerText -match '(?i)powershell.*-File C:\\provision\\provision-first-logon.ps1' }
if (@($entries).Count -ne 1) { throw 'Provisioning must have exactly one entry point.' }
$count = $xml.SelectSingleNode('//u:AutoLogon/u:LogonCount', $ns)
if (-not $count -or $count.InnerText -ne '1') { throw 'Build autologon must be bounded.' }
Write-Host 'PASS: offline specialize and single provisioning entry point.'

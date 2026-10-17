$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/../scripts/windows/uup-helpers.ps1"
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Build($Title, $Version, $Arch = 'amd64') {
    [pscustomobject]@{updateTitle=$Title; foundBuild=$Version; arch=$Arch; updateId='00000000-0000-0000-0000-000000000001'}
}
$valid = Build 'Windows 11, version 25H2 (26200.100)' '26200.100'
$response = [pscustomobject]@{updateArray=@(
    (Build 'Windows 11, version 24H2 (26100.999)' '26100.999'),
    (Build 'Windows 11 Insider Preview (28000.100)' '28000.100'),
    (Build 'Cumulative Update for Windows 11 (28000.100)' '28000.100'),
    (Build 'Windows 11, version 26H2 (28000.100)' '28000.100' 'arm64'),
    $valid
)}
Assert ((Select-PublicWindows11Build $response).foundBuild -eq '26200.100') 'Wrong Retail feature build selected'
Assert ((Select-PublicWindows11Build $valid).foundBuild -eq '26200.100') 'Single update response failed'
foreach ($bad in @(
    [pscustomobject]@{error='RATE_LIMITED'},
    [pscustomobject]@{updateArray=@()},
    [pscustomobject]@{updateArray=@((Build 'Windows 11 Insider Preview' '28000.100'))}
)) {
    $failed = $false
    try { Select-PublicWindows11Build $bad | Out-Null } catch { $failed = $true }
    Assert $failed 'Invalid UUP response accepted'
}
$config = @'
[convert-UUP]
AutoStart =0
AddUpdates =0
StartVirtual =0
AutoExit =0
SkipISO =1
wim2esd =0
[Store_Apps]
SkipApps =1
[create_virtual_editions]
vAutoStart =0
vDeleteSource =0
vAutoEditions =
vSkipISO =1
vwim2esd =0
'@
$result = Set-EnterpriseUupConfig $config
foreach ($line in 'AddUpdates=1','StartVirtual=1','SkipApps=0','vAutoEditions=Enterprise','vDeleteSource=1','AutoExit=1') {
    Assert ($result.Contains($line)) "Missing configuration $line"
}
$failed = $false
try { Set-EnterpriseUupConfig 'unexpected converter format' | Out-Null } catch { $failed = $true }
Assert $failed 'Unknown converter format silently accepted'
[xml]$answer = Get-Content "$PSScriptRoot/../http/windows-11/autounattend.xml" -Raw
$ns = New-Object Xml.XmlNamespaceManager($answer.NameTable)
$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
Assert ($answer.SelectSingleNode('//u:MetaData/u:Key',$ns).InnerText -eq '/IMAGE/NAME') 'WIM must select edition by name'
Assert ($answer.SelectSingleNode('//u:MetaData/u:Value',$ns).InnerText -eq 'Windows 11 Enterprise') 'Wrong WIM name'
Assert ($null -eq $answer.SelectSingleNode('//u:component[@name="Microsoft-Windows-ServerManager-SvrMgrNc"]',$ns)) 'Server component in client answer file'
$provision = Get-Content "$PSScriptRoot/../http/windows-11/provision-first-logon.ps1" -Raw
Assert ($provision.Contains("Payload 'CloudbaseInitSetup.msi'")) 'Cloudbase-Init missing'
Assert ($provision.Contains("Payload 'qemu-ga-x86_64.msi'")) 'Guest agent missing'
Assert (-not $provision.Contains("Payload 'actions-runner-win-x64.zip'")) 'Runner installation present'
foreach ($path in @('scripts/build-windows-11-iso.ps1','scripts/windows/uup-helpers.ps1','http/windows-11/provision-first-logon.ps1')) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path "$PSScriptRoot/.." $path), [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "PowerShell syntax errors in ${path}: $errors"
}
Write-Host 'PASS: Retail selection, Enterprise conversion settings, answer file and provisioner contracts'

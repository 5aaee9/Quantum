param([string]$SourcePath = "$PSScriptRoot/../http/windows-2025-runner/provision-first-logon.ps1")
$ErrorActionPreference = 'Stop'
# Exercise the actual helper without executing any Windows provisioning.
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $SourcePath), [ref]$tokens, [ref]$errors
)
if ($errors.Count) { throw 'Provisioner has syntax errors' }
$run = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Run'
}, $true)
. ([scriptblock]::Create($run.Extent.Text))
function Log($message) { Write-Host $message }
function Must-Fail([scriptblock]$action) {
    $failed = $false
    try { & $action } catch { $failed = $true; Write-Host "Expected failure: $_" }
    if (-not $failed) { throw 'Command failure was silently accepted' }
}
$pwsh = (Get-Process -Id $PID).Path
Run $pwsh @('-NoProfile', '-Command', '"exit 0"') 10
Must-Fail { Run $pwsh @('-NoProfile', '-Command', '"exit 23"') 10 }
Must-Fail { Run $pwsh @('-NoProfile', '-Command', '"Start-Sleep 30"') 1 }
Must-Fail { Run 'quantum-nonexistent-executable' @() 1 }
Run $pwsh @('-NoProfile', '-Command', '"exit 7"') 10 @(7)
$noArgs = if ($env:OS -eq 'Windows_NT') { 'whoami.exe' } else {
    # Ubuntu exposes true through both /usr/bin and /bin. Select one command,
    # rather than coercing every matching path into a single executable name.
    (Get-Command true -CommandType Application | Select-Object -First 1).Source
}
Run $noArgs @() 10
Write-Host 'PASS: exit status, accepted codes, timeout, missing executable and empty arguments.'

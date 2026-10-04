# Run with pwsh on Linux or powershell.exe on Windows. Match the en-US
# Windows PowerShell 5.1 source decoder, not PowerShell 7's UTF-8 default.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$paths = @(
    Get-ChildItem "$root/http" -Recurse -Filter '*.ps1'
    Get-ChildItem "$root/scripts" -Recurse -Filter '*.ps1'
)
$failed = $false
foreach ($file in $paths) {
    $reader = [IO.StreamReader]::new($file.FullName, [Text.Encoding]::GetEncoding(1252), $true)
    try { $source = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    foreach ($err in $errors) {
        Write-Host "$($file.Name):$($err.Extent.StartLineNumber): $($err.Message)"
        $failed = $true
    }
}
if ($failed) { throw 'Windows PowerShell source parsing failed (en-US ANSI/BOM decoding).' }
Write-Host "PASS: $($paths.Count) Windows scripts parse with Windows PowerShell source decoding."

# Pure helpers also exercised on Linux by tests/windows-11-uup.ps1.
Set-StrictMode -Version Latest

function Select-PublicWindows11Build($Response) {
    if ($Response.PSObject.Properties['error']) { throw "UUP API error: $($Response.error)" }
    $updates = if ($Response.PSObject.Properties['updateArray']) { @($Response.updateArray) } else { @($Response) }
    $candidates = @($updates | Where-Object {
        $_.arch -eq 'amd64' -and
        $_.updateTitle -match '^Windows 11(?:,|\s+version|\s*\()' -and
        $_.updateTitle -notmatch 'Insider|Preview|Cumulative|Dynamic' -and
        $_.foundBuild -match '^\d+\.\d+$' -and
        $_.updateId -match '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}(?:_rev\.\d+)?$'
    } | Sort-Object { [version]$_.foundBuild } -Descending)
    if ($candidates.Count -eq 0) { throw 'Retail response contains no complete public Windows 11 x64 feature build' }
    return $candidates[0]
}

function Get-PublicWindows11BuildFromHtml([string]$Html) {
    # Only accept the official Retail page's selectlang links, never search
    # results or arbitrary recently-added builds (which may be Insider).
    $pattern = '<a\s+href="selectlang\.php\?id=([0-9a-fA-F-]+(?:_rev\.\d+)?)"\s*>\s*([^<]+)</a>'
    $updates = @()
    foreach ($match in [regex]::Matches($Html, $pattern)) {
        $label = [Net.WebUtility]::HtmlDecode($match.Groups[2].Value).Trim()
        if ($label -notmatch '^(.*?)\s+\((\d+\.\d+)\)\s+amd64$') { continue }
        $updates += [pscustomobject]@{
            updateId=$match.Groups[1].Value; arch='amd64'
            updateTitle=$Matches[1]; foundBuild=$Matches[2]
        }
    }
    return Select-PublicWindows11Build ([pscustomobject]@{updateArray=$updates})
}

function Set-UupConfigValue([string]$Config, [string]$Key, [string]$Value) {
    $pattern = '(?m)^' + [regex]::Escape($Key) + '\s*=.*$'
    if ([regex]::Matches($Config, $pattern).Count -ne 1) { throw "Missing/ambiguous converter setting: $Key" }
    return [regex]::Replace($Config, $pattern, "$Key=$Value`r")
}

function Set-EnterpriseUupConfig([string]$Config) {
    $settings = [ordered]@{
        AutoStart='1'; AddUpdates='1'; StartVirtual='1'; AutoExit='1'
        SkipISO='0'; SkipApps='0'; vAutoStart='1'; vDeleteSource='1'
        vAutoEditions='Enterprise'; vSkipISO='0'; wim2esd='0'; vwim2esd='0'
    }
    foreach ($key in $settings.Keys) { $Config = Set-UupConfigValue $Config $key $settings[$key] }
    return $Config
}

param(
    [string]$AutorunRoot = 'F:/SteamLibrary/steamapps/common/Dragons Dogma 2/reframework/autorun'
)
$ErrorActionPreference = 'Stop'
$taskRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function ConvertTo-TaskLua($Value) {
    if ($null -eq $Value) { return 'nil' }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [string]) {
        $equals = '='
        while ($Value.Contains("]$equals]")) { $equals += '=' }
        return "[$equals[$Value]$equals]"
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = foreach ($key in $Value.Keys) { '[ ' + (ConvertTo-TaskLua ([string]$key)) + ' ]=' + (ConvertTo-TaskLua $Value[$key]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = foreach ($item in $Value) { ConvertTo-TaskLua $item }
        return '{' + ($parts -join ',') + '}'
    }
    return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
}
$taskManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
$taskDocuments = @{
    original = Get-Content -LiteralPath (Join-Path $taskRepo $taskManifest.backup) -Raw | ConvertFrom-Json -AsHashtable
    prepared = Get-Content -LiteralPath (Join-Path $taskRepo $taskManifest.prepared) -Raw | ConvertFrom-Json -AsHashtable
}
$taskFixture = Join-Path ([IO.Path]::GetTempPath()) ('magic-evade-' + [guid]::NewGuid().ToString('N') + '.lua')
try {
    [IO.File]::WriteAllText($taskFixture, ('return ' + (ConvertTo-TaskLua $taskDocuments)), [Text.UTF8Encoding]::new($false))
    & lua (Join-Path $PSScriptRoot 'verify.lua') $AutorunRoot $taskFixture
    if ($LASTEXITCODE -ne 0) { throw 'Magic Evade verification failed' }
} finally {
    if (Test-Path -LiteralPath $taskFixture) { Remove-Item -LiteralPath $taskFixture }
}


$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskRuntime = 'F:/SteamLibrary/steamapps/common/Dragons Dogma 2/reframework/autorun'
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
$documents = @{ original=@{}; prepared=@{} }
foreach ($item in (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json)) {
    $documents.original[$item.family] = Get-Content -LiteralPath $item.backup -Raw | ConvertFrom-Json -AsHashtable
    $documents.prepared[$item.family] = Get-Content -LiteralPath $item.prepared -Raw | ConvertFrom-Json -AsHashtable
}
$fixturePath = Join-Path $PSScriptRoot 'documents.generated.lua'
[IO.File]::WriteAllText($fixturePath, ('return ' + (ConvertTo-TaskLua $documents)), [Text.UTF8Encoding]::new($false))
& lua (Join-Path $PSScriptRoot 'verify.lua') $taskRuntime $fixturePath
if ($LASTEXITCODE -ne 0) { throw 'Cancellation verification failed' }

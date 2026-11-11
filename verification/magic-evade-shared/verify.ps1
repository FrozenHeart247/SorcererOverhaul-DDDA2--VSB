param([string]$AutorunRoot='F:/SteamLibrary/steamapps/common/Dragons Dogma 2/reframework/autorun')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function ConvertTo-TaskLua($Value) {
    if($null -eq $Value){return 'nil'}
    if($Value -is [bool]){return $Value.ToString().ToLowerInvariant()}
    if($Value -is [string]){
        $equals='='
        while($Value.Contains("]$equals]")){$equals+='='}
        return "[$equals[$Value]$equals]"
    }
    if($Value -is [System.Collections.IDictionary]){
        $parts=foreach($key in $Value.Keys){'[ '+(ConvertTo-TaskLua ([string]$key))+' ]='+(ConvertTo-TaskLua $Value[$key])}
        return '{'+($parts -join ',')+'}'
    }
    if($Value -is [System.Collections.IEnumerable]){
        $parts=foreach($item in $Value){ConvertTo-TaskLua $item}
        return '{'+($parts -join ',')+'}'
    }
    return [Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
}
$bundleRoot=Join-Path $repoRoot 'prepared/magic-evade-shared/reframework'
$skillRoot=Join-Path $bundleRoot 'data/VSB/packs/fh_sorc/skills'
$documents=@{
    original=Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'backups/magic-evade-shared/new_skill_7.json') | ConvertFrom-Json -AsHashtable
    prepared=Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'new_skill_7.json') | ConvertFrom-Json -AsHashtable
    archer=Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'new_skill_7_copy.json') | ConvertFrom-Json -AsHashtable
}
foreach($fileName in @('new_skill_7.json','new_skill_7_copy.json')){
    $before=Get-Content -Raw -LiteralPath (Join-Path (Join-Path $repoRoot 'backups/magic-evade-shared') $fileName) | ConvertFrom-Json -AsHashtable
    $after=Get-Content -Raw -LiteralPath (Join-Path $skillRoot $fileName) | ConvertFrom-Json -AsHashtable
    $before.Remove('meta'); $after.Remove('meta')
    if(($before | ConvertTo-Json -Depth 100 -Compress) -cne ($after | ConvertTo-Json -Depth 100 -Compress)){throw "Unrelated skill edits in $fileName"}
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('magic-evade-shared-'+[guid]::NewGuid().ToString('N')+'.lua')
try{
    [IO.File]::WriteAllText($fixture,'return '+(ConvertTo-TaskLua $documents),[Text.UTF8Encoding]::new($false))
    & 'C:/msys64/ucrt64/bin/lua.exe' (Join-Path $PSScriptRoot 'verify.lua') $AutorunRoot $fixture (Join-Path $bundleRoot 'autorun')
    if($LASTEXITCODE -ne 0){throw 'Shared Magic Evade verification failed'}
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture}
}

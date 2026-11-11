param(
    [string]$GameRoot = 'F:\SteamLibrary\steamapps\common\Dragons Dogma 2',
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'captures'),
    [string]$Python = 'C:\Users\krist\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$destination = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Path $destination | Out-Null
$processActive = $null -ne (Get-Process -Name DD2 -ErrorAction SilentlyContinue)
$copied = @()
$problems = @()
$paths = @(
    'reframework_crash.dmp',
    're2_framework_log.txt',
    'reframework_faulty_files.txt',
    'reframework_accessed_files.txt',
    'reframework_loose_files.txt',
    're2_fw_config.txt',
    'reframework\data\VSB\diagnostics\magic_evade_native_status.json',
    'reframework\data\VSB\diagnostics\levin_targeting_status.json',
    'reframework\data\DragonCore\crashguard.json',
    'reframework\data\VocationPlanner.log',
    'reframework\data\usercontent\bundles\Elf Origin - Arbor Garb.json'
)
foreach ($relative in $paths) {
    $source = Join-Path $GameRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    try {
        $target = Join-Path $destination $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        $sourceInfo = Get-Item -LiteralPath $source
        Copy-Item -LiteralPath $source -Destination $target
        $copied += [ordered]@{
            path = $relative
            source_modified_utc = $sourceInfo.LastWriteTimeUtc.ToString('o')
            copied_bytes = (Get-Item -LiteralPath $target).Length
            sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        }
    } catch { $problems += "$relative : $($_.Exception.Message)" }
}
$autorunRoot = Join-Path $GameRoot 'reframework\autorun'
if (Test-Path -LiteralPath $autorunRoot) {
    $inventory = @(Get-ChildItem -LiteralPath $autorunRoot -File -Filter '*.lua' |
        ForEach-Object { [ordered]@{name=$_.Name; modified_utc=$_.LastWriteTimeUtc.ToString('o');
            sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
    $inventory | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'autorun-inventory.json') -Encoding utf8
}
$manifest = [ordered]@{
    captured_utc = (Get-Date).ToUniversalTime().ToString('o')
    game_process_active = $processActive
    note = 'A dump may predate the current launch. Compare source timestamps. Resource logs show accesses, not proof of fault.'
    suspect = @{ name="Arbor Warden's Jerkin"; item_id=31751; style_no=2155; bundle='Elf Origin - Arbor Garb' }
    files = $copied
    copy_errors = $problems
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'capture.json') -Encoding utf8
$dump = Join-Path $destination 'reframework_crash.dmp'
if ((Test-Path -LiteralPath $dump) -and (Test-Path -LiteralPath $Python)) {
    & $Python (Join-Path $PSScriptRoot 'inspect_dump.py') $dump --output (Join-Path $destination 'dump-summary.json') |
        Set-Content -LiteralPath (Join-Path $destination 'dump-summary.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Dump parser failed; the original dump is preserved.' }
}
Write-Output $destination
if ($processActive) { Write-Warning 'DD2 is still running. Logs may still change; collect again after the crash/exit.' }
if ($problems.Count -gt 0) { Write-Warning ($problems -join "`n") }

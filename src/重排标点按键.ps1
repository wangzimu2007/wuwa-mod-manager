# 标点键重排：把每个 ini 里出现的 VK_OEM_2 / VK_OEM_PERIOD / VK_OEM_COMMA
# 按「/ 。 ，」的新顺序重新分配（按文件中出现顺序），其余键（方向键/数字/字母）不动
param(
    [string]$Root = 'F:\GameMods\WWMI-Mods\Skins',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$canon = @('VK_OEM_2', 'VK_OEM_PERIOD', 'VK_OEM_COMMA')   # / 。 ，
$punct = @('VK_OEM_2', 'VK_OEM_PERIOD', 'VK_OEM_COMMA')

function Split-KeyLine([string]$raw) {
    $tokens = @($raw.Trim() -split '\s+')
    $mods = @()
    $i = 0
    while ($i -lt $tokens.Count - 1 -and ($tokens[$i] -match '^(?i)(no_)?(alt|ctrl|shift|no_alt|no_ctrl|no_shift)$')) {
        $mods += $tokens[$i].ToLower(); $i++
    }
    $key = (($tokens[$i..($tokens.Count - 1)]) -join ' ').Trim()
    return [pscustomobject]@{ mods = @($mods); key = $key }
}

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notmatch '(?i)\.bak|\.off|_\d{4}-\d{2}-\d{2}' })

$changedFiles = 0; $changedRows = 0
foreach ($f in $files) {
    $lines = [Collections.Generic.List[string]]::new()
    [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }

    # 收集需要重排的行（按出现顺序）：仅裸键（无 alt/ctrl/shift）且属于三个标点键
    $rows = @()
    $sec = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^\[(.+?)\]') { $sec = $Matches[1]; continue }
        if ($t -match '^key\s*=\s*(.+)$') {
            $sp = Split-KeyLine $Matches[1]
            if ($sp.key -in $punct) {
                $rows += [pscustomobject]@{ idx = $i; section = $sec; parsed = $sp; raw = $Matches[1].Trim() }
            }
        }
    }
    if ($rows.Count -lt 2) { continue }

    # 只处理「裸键」（mods 为空），带 alt/ctrl/shift 的不动
    $bare = @($rows | Where-Object { $_.parsed.mods.Count -eq 0 })
    if ($bare.Count -lt 2) { continue }

    $localChanged = 0
    for ($k = 0; $k -lt [Math]::Min($bare.Count, $canon.Count); $k++) {
        $r = $bare[$k]
        $newKey = $canon[$k]
        if ($r.parsed.key -ne $newKey) {
            if (-not $WhatIf) {
                $lines[$r.idx] = $lines[$r.idx] -replace '^(\s*key\s*=\s*).+$', "`$1$newKey"
            }
            $localChanged++
            if ($WhatIf) { Write-Host ("  {0} [{1}] {2} -> {3}" -f (Split-Path $f.Directory -Leaf), $r.section, $r.parsed.key, $newKey) }
        }
    }

    if ($localChanged -gt 0) {
        $changedFiles++; $changedRows += $localChanged
        if (-not $WhatIf) {
            Copy-Item -LiteralPath $f.FullName -Destination ($f.FullName + '.bak-reorder') -Force
            [IO.File]::WriteAllLines($f.FullName, $lines, (New-Object Text.UTF8Encoding($false)))
        }
    }
}

Write-Host ""
Write-Host ("重排完成：{0} 个文件，{1} 处按键{2}" -f $changedFiles, $changedRows, $(if ($WhatIf) { '（预演，未写入）' } else { '' }))

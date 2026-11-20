# 重排到优先键：把 ctrl+字母 / 单字母 的裸键，改成方向键→/。，→数字 里第一个空闲键
# 保护：鼠标键、enable_mods、带 alt/shift 的组合键 一律不动
param(
    [string]$Root = 'F:\GameMods\WWMI-Mods\Skins',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Pool = @('VK_UP', 'VK_DOWN', 'VK_LEFT', 'VK_RIGHT',
          'VK_OEM_2', 'VK_OEM_PERIOD', 'VK_OEM_COMMA',
          '0', '9', '8', '7', '6')

function Split-Key([string]$raw) {
    $tokens = @($raw.Trim() -split '\s+')
    $mods = @(); $i = 0
    while ($i -lt $tokens.Count - 1 -and ($tokens[$i] -match '^(?i)(no_)?(alt|ctrl|shift)$')) {
        $mods += $tokens[$i].ToLower(); $i++
    }
    return [pscustomobject]@{ mods = @($mods); key = (($tokens[$i..($tokens.Count - 1)]) -join ' ').Trim() }
}

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notmatch '(?i)\.bak|\.off|_\d{4}-\d{2}-\d{2}' })

$changedFiles = 0; $changedRows = 0
foreach ($f in $files) {
    $lines = [Collections.Generic.List[string]]::new()
    [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }

    $rows = @(); $sec = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^\[(.+?)\]') { $sec = $Matches[1]; continue }
        if ($t -match '^key\s*=\s*(.+)$') {
            $rows += [pscustomobject]@{ idx = $i; section = $sec; raw = $Matches[1].Trim(); p = (Split-Key $Matches[1]) }
        }
    }
    if ($rows.Count -eq 0) { continue }

    # 已占用的裸键（不含修饰符）与任意键
    $usedBare = @{}
    foreach ($r in $rows) { if ($r.p.mods.Count -eq 0) { $usedBare[$r.p.key.ToUpper()] = $true } }

    $local = 0
    foreach ($r in $rows) {
        if ($r.section -match '(?i)enable_mods') { continue }
        if ($r.p.key -match '(?i)VK_(L|R|M)BUTTON') { continue }
        if ($r.p.mods -contains 'alt' -or $r.p.mods -contains 'shift') { continue }
        # 只处理「单字母」或「ctrl + 字母」
        $k = $r.p.key
        $isCtrlLetter = (($r.p.mods -contains 'ctrl') -and ($k -match '^[A-Za-z]$'))
        $isBareLetter = (($r.p.mods.Count -eq 0) -and ($k -match '^[A-Za-z]$'))
        if (-not ($isCtrlLetter -or $isBareLetter)) { continue }

        # 找空闲池键
        $pick = $null
        foreach ($c in $Pool) { if (-not $usedBare.ContainsKey($c.ToUpper())) { $pick = $c; break } }
        if (-not $pick) { continue }

        $prefix = @($r.p.mods | Where-Object { $_ -like 'no_*' })
        $newRaw = (($prefix + $pick) -join ' ').Trim()
        if ($newRaw -eq $r.raw) { continue }

        $usedBare.Remove($k.ToUpper()) | Out-Null
        $usedBare[$pick.ToUpper()] = $true
        if (-not $WhatIf) {
            $lines[$r.idx] = $lines[$r.idx] -replace '^(\s*key\s*=\s*).+$', "`$1$newRaw"
        }
        if ($WhatIf) { Write-Host ("  {0} [{1}] {2} -> {3}" -f (Split-Path $f.Directory -Leaf), $r.section, $r.raw, $newRaw) }
        $local++
    }

    if ($local -gt 0) {
        $changedFiles++; $changedRows += $local
        if (-not $WhatIf) {
            Copy-Item -LiteralPath $f.FullName -Destination ($f.FullName + '.bak-prefer') -Force
            [IO.File]::WriteAllLines($f.FullName, $lines, (New-Object Text.UTF8Encoding($false)))
        }
    }
}

Write-Host ""
Write-Host ("重排完成：{0} 个文件，{1} 处按键{2}" -f $changedFiles, $changedRows, $(if ($WhatIf) { '（预演，未写入）' } else { '' }))

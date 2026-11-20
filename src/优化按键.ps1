# 按键优化：把不可用的键换成 75 配列能按到的键（优先单键，不需要按修饰键）
#
# 不可用键：小键盘 VK_NUMPAD0-9、Insert/Delete/PgUp/PgDn/Home/End、主键盘数字 1~5
# 可用池（按优先级）：↑ ↓ ← →  然后 VK_OEM_COMMA(逗号)  VK_OEM_2(斜杠)  0 9 8 7 6
#
# 「优先单键」的含义：改完的键不带 alt/ctrl 前缀，一个键就能按。
# 只有在该裸键已经被同目录其它功能占用时，才保留原来的修饰前缀。
#
# 用法：
#   .\优化按键.ps1 -Target <目录> [-WhatIf]
#   .\优化按键.ps1 -AllLibrary [-WhatIf]
#   .\优化按键.ps1 -FixDoubled [-AllLibrary]    # 修复写坏的 "no_alt no_alt" 这类重复前缀

param(
    [string]$Target,
    [switch]$AllLibrary,
    [switch]$WhatIf,
    [switch]$FixDoubled
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$SkinsRoot = 'E:\GameMods\WWMI-Mods\Skins'
# 单键池：只要非字母（字母做单键容易和游戏快捷键打架）
$Pool = @('VK_UP', 'VK_DOWN', 'VK_LEFT', 'VK_RIGHT',
          'VK_OEM_COMMA', 'VK_OEM_2', '0', '9', '8', '7', '6')
# 字母救急池：仅在单键池用完时才用，且一律配 ctrl 前缀（组合键）
$LetterPool = @('m', 'n', 'k', 'j', 'u', 'i', 'o', 'l', 'p', 'b', 'v', 'g', 'h', 'y')
$BadExact = @('VK_INSERT', 'VK_DELETE', 'VK_PRIOR', 'VK_NEXT', 'VK_HOME', 'VK_END',
              'VK_PAGEUP', 'VK_PAGEDOWN', 'INSERT', 'DELETE', 'PAGEUP', 'PAGEDOWN', 'HOME', 'END',
              '1', '2', '3', '4', '5')
$ModTokens = @('no_alt', 'alt', 'ctrl', 'shift')

function Test-BadKey([string]$k) {
    if (-not $k) { return $false }
    $u = $k.Trim().ToUpper()
    if ($u -match '^VK_NUMPAD\d$' -or $u -match '^NUMPAD\d$') { return $true }
    return ($BadExact -contains $u)
}

# 解析 key = 行，返回 prefix(规范化的修饰串) 与主键
function Split-KeyLine([string]$raw) {
    $tokens = @($raw.Trim() -split '\s+')
    $mods = @()
    $i = 0
    while ($i -lt $tokens.Count - 1 -and ($ModTokens -contains $tokens[$i].ToLower() -or $tokens[$i] -match '^(?i)no_(alt|ctrl|shift)$')) {
        $mods += $tokens[$i].ToLower(); $i++
    }
    $key = ($tokens[$i..($tokens.Count - 1)] -join ' ')
    return [pscustomobject]@{ mods = ($mods -join ' '); key = $key.Trim() }
}

function Get-IniFiles([string]$dir) {
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.bak|_\d{4}-\d{2}-\d{2}' }
}

function Optimize-Folder([string]$dir) {
    $files = @(Get-IniFiles $dir)
    if ($files.Count -eq 0) { return @{ dir = $dir; changed = @() } }

    # 建立行模型
    $model = @{}
    $rows = @()
    foreach ($f in $files) {
        $lines = [Collections.Generic.List[string]]::new()
        [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }
        $model[$f.FullName] = $lines
        $section = ''
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t -match '^\[(.+?)\]') { $section = $Matches[1]; continue }
            if ($t -match '^key\s*=\s*(.+)$') {
                $sp = Split-KeyLine $Matches[1]
                $rows += [pscustomobject]@{
                    file = $f.FullName; line = $i; section = $section
                    mods = $sp.mods; key = $sp.key; raw = $Matches[1].Trim()
                }
            }
        }
    }
    if ($rows.Count -eq 0) { return @{ dir = $dir; changed = @() } }

    # 已被占用的裸键（不含修饰前缀）
    $bareUsed = @{}
    foreach ($r in $rows) { if ($r.key) { $bareUsed[$r.key.ToUpper()] = $true } }

    $changed = @()
    $assigned = @{}      # section(功能) -> 新键
    $assignedMods = @{}  # section(功能) -> 需要加的修饰前缀（字母救急时用 ctrl）

    foreach ($r in $rows) {
        # 字母键一律不用（含 NO_ALT/NO_CTRL 修饰的），换到方向键/标点/数字
        $letterOnly = ($r.key -match '^[A-Za-z]$')
        $needFix = (Test-BadKey $r.key) -or $letterOnly
        if (-not $needFix -and -not $FixDoubled) {
            # 非坏键：只有在「要拆修饰键」时才处理
            if (-not $r.mods) { continue }
        }
        if (-not $needFix -and (Test-BadKey $r.key)) { continue }

        $func = $r.section
        if (-not $assigned.ContainsKey($func)) {
            if ($needFix) {

                $pick = $null
                foreach ($c in $Pool) { if (-not $bareUsed.ContainsKey($c.ToUpper())) { $pick = $c; break } }
                if ($pick) {
                    $bareUsed[$pick.ToUpper()] = $true
                    $assigned[$func] = $pick
                    $assignedMods[$func] = ''
                } else {
                    # 单键池用完：退到字母，但必须配 ctrl（不做单键）
                    foreach ($c in $LetterPool) {
                        if (-not $bareUsed.ContainsKey($c.ToUpper())) { $pick = $c; break }
                    }
                    if (-not $pick) { continue }
                    $bareUsed[$pick.ToUpper()] = $true
                    $assigned[$func] = $pick
                    $assignedMods[$func] = 'ctrl'
                }
            } else {
                $assigned[$func] = $r.key
                $assignedMods[$func] = ''
            }
        }
        $newKey = $assigned[$func]
        if (-not $newKey) { continue }

        # 决定新行：优先单键（去掉修饰前缀）
        $keepMods = $false
        if (-not $needFix -and $r.mods) {
            # 若是「同键双档」（如 alt 7 / no_alt 7），去掉前缀会撞车 → 保留前缀
            $sameKeyOthers = @($rows | Where-Object { $_ -ne $r -and $_.section -ne $r.section -and $_.key -eq $r.key })
            if ($sameKeyOthers.Count -gt 0) { $keepMods = $true }
        }
        # 字母键一律不做单键；含 no_* 的前缀必须保留（那是"排除某个修饰键"的语义）
        $isLetter = ($newKey -match '^[A-Za-z]$')
        $hasNoMods = ($r.mods -match '(?i)no_')
        $forced = if ($assignedMods.ContainsKey($func)) { $assignedMods[$func] } else { '' }
        $newMods = if ($forced) { $forced }
                   elseif ($keepMods -or $isLetter -or $hasNoMods) { $r.mods }
                   else { '' }
        $newRaw = if ($newMods) { "$newMods $newKey" } else { $newKey }
        if ($newRaw -eq $r.raw) { continue }
        $changed += [pscustomobject]@{ section = $func; old = $r.raw; new = $newRaw; file = $r.file; line = $r.line }
    }

    if ($changed.Count -eq 0 -or $WhatIf) { return @{ dir = $dir; changed = $changed } }

    foreach ($c in $changed) {
        $lines = $model[$c.file]
        $orig = $lines[$c.line]
        if ($orig -match '^(\s*key\s*=\s*)(.+)$') {
            $lines[$c.line] = "$($Matches[1])$($c.new)"
        }
    }
    foreach ($f in $model.Keys) {
        Copy-Item -LiteralPath $f -Destination ($f + '.bak-keyopt') -Force
        [IO.File]::WriteAllLines($f, $model[$f], (New-Object Text.UTF8Encoding($false)))
    }
    return @{ dir = $dir; changed = $changed }
}

# ---- 目标收集 ----
$targets = @()
$label = ''
if ($AllLibrary) {
    $targets = @(Get-ChildItem -LiteralPath $SkinsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue
    })
    $label = "皮肤库（$($targets.Count) 套）"
} elseif ($Target) {
    if (-not (Test-Path -LiteralPath $Target)) { throw "路径不存在：$Target" }
    $targets = @(Get-Item -LiteralPath $Target)
    $label = $Target
} else {
    throw '请给 -Target <目录> 或 -AllLibrary'
}

Write-Host "===== 按键优化：$label ====="
if ($WhatIf) { Write-Host "（预演模式，不写文件）" -ForegroundColor Yellow }
Write-Host ""

$total = 0; $dirs = 0
foreach ($t in $targets) {
    $r = Optimize-Folder $t.FullName
    if ($r.changed.Count -gt 0) {
        $dirs++; $total += $r.changed.Count
        Write-Host ("📁 " + (Split-Path $r.dir -Leaf)) -ForegroundColor Cyan
        $r.changed | ForEach-Object { Write-Host ("   {0,-28} {1,-20} -> {2}" -f $_.section, $_.old, $_.new) }
    }
}
Write-Host ""
Write-Host "改动：$total 处，涉及 $dirs 个目录"
if (-not $WhatIf -and $total -gt 0) { Write-Host "原文件已备份为 *.bak-keyopt" }

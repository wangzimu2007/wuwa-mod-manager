# 去重：同一目录里「同一个键被多个功能占用」时，把后出现的功能改到空闲键
# 用法：.\修复重复按键.ps1 -Target <目录> [-WhatIf]
param([string]$Target, [switch]$WhatIf)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Pool = @('VK_UP', 'VK_DOWN', 'VK_LEFT', 'VK_RIGHT',
          'VK_OEM_COMMA', 'VK_OEM_2', '0', '9', '8', '7', '6',
          'm', 'n', 'k', 'j', 'u', 'i', 'o', 'l', 'p', 'b', 'v', 'g', 'h', 'y')

function Split-KeyLine([string]$raw) {
    $tokens = @($raw.Trim() -split '\s+')
    $mods = @()
    $i = 0
    while ($i -lt $tokens.Count - 1 -and ($tokens[$i] -match '^(?i)(no_)?(alt|ctrl|shift)$')) {
        $mods += $tokens[$i].ToLower(); $i++
    }
    return [pscustomobject]@{ mods = ($mods -join ' '); key = (($tokens[$i..($tokens.Count - 1)]) -join ' ').Trim() }
}

$files = Get-ChildItem -LiteralPath $Target -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '\.bak|_\d{4}-\d{2}-\d{2}' }
if (-not $files) { Write-Host "没有 ini"; exit 0 }

# 收集
$rows = @()
foreach ($f in $files) {
    $lines = [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
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
if ($rows.Count -eq 0) { Write-Host "没有 key 行"; exit 0 }

# 已有 (mods,key) 占用
$used = @{}
foreach ($r in $rows) { $used[(($r.file + '|' + $r.mods + '|' + $r.key).ToLower())] = $true }

# 找重复：(mods,key) 对应多个不同 section
$changed = @()
$firstOwner = @{}
foreach ($r in $rows) {
    $sig = ($r.file + '|' + $r.mods + '|' + $r.key).ToLower()
    if (-not $firstOwner.ContainsKey($sig)) { $firstOwner[$sig] = $r.section; continue }
    if ($firstOwner[$sig] -ieq $r.section) { continue }   # 同功能，保留
    if ($r.key -match '^(?i)VK_(L|R|M)BUTTON$') { continue }   # 鼠标键是 UI 操作，不动
    # 需要换键
    $pick = $null
    foreach ($c in $Pool) {
        $try = ($r.file + '|' + $c).ToLower()
        if (-not $used.ContainsKey($try)) { $pick = $c; break }
    }
    if (-not $pick) { continue }
    $used[($r.file + '|' + $pick).ToLower()] = $true
    $newRaw = $pick
    $changed += [pscustomobject]@{ section = $r.section; old = $r.raw; new = $newRaw; file = $r.file; line = $r.line }
}

if ($changed.Count -eq 0) { Write-Host "没有重复，无需修改"; exit 0 }
Write-Host "== 需要改 $($changed.Count) 处 =="
$changed | ForEach-Object { "  {0,-24} {1,-20} -> {2}" -f $_.section, $_.old, $_.new }
if ($WhatIf) { exit 0 }

# 落盘（按文件分组，行号从高到低避免影响）
$byFile = $changed | Group-Object file
foreach ($g in $byFile) {
    $path = $g.Name
    Copy-Item -LiteralPath $path -Destination ($path + '.bak-dedupe2') -Force
    $lines = [Collections.Generic.List[string]]::new()
    [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }
    foreach ($c in ($g.Group | Sort-Object line -Descending)) {
        if ($lines[$c.line] -match '^(\s*key\s*=\s*)(.+)$') { $lines[$c.line] = "$($Matches[1])$($c.new)" }
    }
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
}
Write-Host "已写入（备份 *.bak-dedupe2）"

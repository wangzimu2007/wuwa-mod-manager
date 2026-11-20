# 导入后处理：清理空调 → 合并角色别名 → 重新编号
# 用法：.\整理副库.ps1 [-WhatIf]
param([switch]$WhatIf)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$libRoot = 'F:\GameMods\WWMI-Mods\Skins'

# 别名 → 正式名（左边是要被合并掉的，右边保留）
$alias = @{
    '卡提西亚' = '卡提希娅'; '卡提希亚' = '卡提希娅'
    '今夕' = '今汐'
    '清霄' = '清宵'
    '锁冥' = '锁暝'
    '折纸' = '折枝'
    '坎特雷拉' = '坎特蕾拉'
    '桃祁' = '桃祈'
    '釉壶' = '釉瑚'
    '心(含大招)' = '心月狐'; '心' = '心月狐'
    '鉴心－青花瓷２.０' = '鉴心'
    '洛可可拉菲([]切换）' = '洛可可'
    '绯花令' = '清宵'
    '锁暝黑袍去披风（小键盘12）' = '锁暝'
    '维里奈恶毒兔子' = '维里奈'
    '长离时装' = '长离'
    '赞妮 西装女士 QOS' = '赞妮'
    '女漂' = '漂泊者女'
    '达妮娅' = '达妮亚'
    '爱弥丝' = '爱弥斯'
    '洛瑟拉' = '洛瑟菈'
}
# 这些不是角色 → 做成"配件/载具"分类
$bucket = @{
    '科考摩托（载具）' = '载具'; '摩托组件[小小救世主]' = '载具'
    '千咲的剪刀' = '配件'; '千古伏流' = '配件'; '海的呢喃' = '配件'
    '裁春' = '配件'; '鸣潮' = '其他'
}

if (-not (Test-Path -LiteralPath $libRoot)) { throw "副库不存在：$libRoot" }
    $dirs = @(Get-ChildItem -LiteralPath $libRoot -Directory | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
Write-Host "处理前角色目录：$($dirs.Count) 个"

# 1) 删除空目录
$removed = 0
foreach ($d in $dirs) {
    $n = @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue).Count
    if ($n -eq 0) {
        if (-not $WhatIf) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
        Write-Host "  删除空目录：$($d.Name)"
        $removed++
    }
}

# 2) 合并别名
    $dirs = @(Get-ChildItem -LiteralPath $libRoot -Directory | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
foreach ($d in $dirs) {
    $target = $null
    if ($alias.ContainsKey($d.Name)) { $target = $alias[$d.Name] }
    elseif ($bucket.ContainsKey($d.Name)) { $target = '_' + $bucket[$d.Name] }
    if (-not $target) { continue }
    $dst = Join-Path $libRoot $target
    Write-Host "  合并：$($d.Name) → $target"
    if ($WhatIf) { continue }
    if (-not (Test-Path -LiteralPath $dst)) {
        Move-Item -LiteralPath $d.FullName -Destination $dst -Force
    } else {
        Get-ChildItem -LiteralPath $d.FullName -Directory | ForEach-Object {
            $to = Join-Path $dst $_.Name
            if (Test-Path -LiteralPath $to) { $to = "$to`_dup" }
            Move-Item -LiteralPath $_.FullName -Destination $to -Force
        }
        Remove-Item -LiteralPath $d.FullName -Recurse -Force
    }
}

# 3) 重新编号（每个角色 001..N，按原编号排序）
    $dirs = @(Get-ChildItem -LiteralPath $libRoot -Directory | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
foreach ($d in $dirs) {
    $subs = @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($subs.Count -eq 0) { continue }
    $i = 0
    foreach ($s in $subs) {
        $i++
        $nameOnly = $s.Name -replace '^\d+_', ''
        $newName = '{0:D3}_{1}' -f $i, $nameOnly
        if ($newName -eq $s.Name) { continue }
        if ($WhatIf) { Write-Host "  $($d.Name)：$($s.Name) → $newName"; continue }
        $dst = Join-Path $d.FullName $newName
        if (Test-Path -LiteralPath $dst) { continue }
        Move-Item -LiteralPath $s.FullName -Destination $dst -Force
    }
}

Write-Host ""
    $dirs = @(Get-ChildItem -LiteralPath $libRoot -Directory | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
$total = 0
foreach ($d in $dirs) {
    $n = @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue).Count
    $total += $n
    if ($n -gt 0) { "  {0,-16} {1,3} 套" -f $d.Name, $n }
}
"  合计：$total 套，角色 $($dirs.Count) 个"

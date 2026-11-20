# 把 E 盘旧库合并进 F 盘主库（防重名冲突，自动重新编号）
# 用法：.\合并旧库到F.ps1 [-WhatIf]
param([switch]$WhatIf)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$srcRoot = 'E:\GameMods\WWMI-Mods\Skins'          # 旧库
$dstRoot = 'F:\GameMods\WWMI-Mods\Skins'          # 新主库
$backupName = '_原版备份'

if (-not (Test-Path -LiteralPath $srcRoot)) { throw "旧库不存在：$srcRoot" }
if (-not (Test-Path -LiteralPath $dstRoot)) { throw "新库不存在：$dstRoot" }

$moved = 0; $renamed = 0
$chars = @(Get-ChildItem -LiteralPath $srcRoot -Directory | Sort-Object Name)
Write-Host "旧库角色目录：$($chars.Count)"

foreach ($c in $chars) {
    if ($c.Name -eq $backupName) {
        # 原版备份单独合并
        $bdst = Join-Path $dstRoot $backupName
        if (-not (Test-Path -LiteralPath $bdst)) { $bdst = Join-Path $dstRoot ($backupName + '_fromE') }
        Write-Host "  原版备份 → $bdst"
        if (-not $WhatIf) {
            if (-not (Test-Path -LiteralPath $bdst)) { New-Item -ItemType Directory -Path $bdst -Force | Out-Null }
            Get-ChildItem -LiteralPath $c.FullName | ForEach-Object {
                $to = Join-Path $bdst $_.Name
                if (Test-Path -LiteralPath $to) { $to = $to + '_fromE' }
                Move-Item -LiteralPath $_.FullName -Destination $to -Force
            }
        }
        continue
    }

    $charDst = Join-Path $dstRoot $c.Name
    if (-not (Test-Path -LiteralPath $charDst)) {
        Write-Host "  整目录迁移：$($c.Name)"
        if (-not $WhatIf) { Move-Item -LiteralPath $c.FullName -Destination $charDst -Force }
        $moved++
        continue
    }

    # 目标已有同名角色：重新编号后搬入
    $max = 0
    Get-ChildItem -LiteralPath $charDst -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^(\d+)_') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
    }
    $subs = @(Get-ChildItem -LiteralPath $c.FullName -Directory | Sort-Object Name)
    Write-Host "  合并角色：$($c.Name)（新库已有 $max 套，追加 $($subs.Count) 套）"
    foreach ($s in $subs) {
        $max++
        $nameOnly = $s.Name -replace '^\d+_', ''
        $newName = '{0:D3}_{1}' -f $max, $nameOnly
        if ($WhatIf) { Write-Host "    $($s.Name) → $newName"; continue }
        $to = Join-Path $charDst $newName
        while (Test-Path -LiteralPath $to) { $max++; $newName = '{0:D3}_{1}' -f $max, $nameOnly; $to = Join-Path $charDst $newName }
        Move-Item -LiteralPath $s.FullName -Destination $to -Force
        $renamed++
    }
    if (-not $WhatIf) {
        $left = @(Get-ChildItem -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { Remove-Item -LiteralPath $c.FullName -Recurse -Force }
    }
}

Write-Host ""
Write-Host "合并完成：整目录 $moved 个，重编号 $renamed 套"
if (-not $WhatIf) {
    $total = 0
    Get-ChildItem -LiteralPath $dstRoot -Directory | Sort-Object Name | ForEach-Object {
        $n = @(Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue).Count
        if ($n -gt 0) { $total += $n; "  {0,-16} {1,3} 套" -f $_.Name, $n }
    }
    "  F 盘主库合计：$total 套"
}

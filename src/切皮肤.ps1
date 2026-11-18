param(
    [string]$Char = "卡提希娅",
    [string]$Name,
    [switch]$List,
    [switch]$Restore,
    [string]$SkinsRoot = "",
    [string]$Mods = ""
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '_config.ps1')
$cfg = Get-Cfg
if (-not $SkinsRoot) { $SkinsRoot = $cfg.skinsDir }
if (-not $Mods) { $Mods = $cfg.modsDir }

$targetDir = Join-Path $SkinsRoot $Char
$backupRoot = Join-Path $SkinsRoot "_原版备份"
if (-not (Test-Path -LiteralPath $targetDir)) { throw "没有找到皮肤目录：$targetDir" }
$skins = Get-ChildItem -LiteralPath $targetDir -Directory | Sort-Object Name

function Restore-Original {
    if (-not (Test-Path -LiteralPath $backupRoot)) { Write-Host "没有备份可恢复"; return }
    $items = Get-ChildItem -LiteralPath $backupRoot -Directory
    foreach ($b in $items) {
        $dst = Join-Path $Mods $b.Name
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath $b.FullName -Destination $dst -Recurse -Force
        Write-Host "  已恢复 $($b.Name)"
    }
    Write-Host "`n恢复完成。回游戏按 F10。"
}

if ($Restore) { Restore-Original; exit 0 }

if ($List -or -not $Name) {
    Write-Host "== $Char 可选皮肤（$($skins.Count) 套）=="
    $i = 0
    foreach ($s in $skins) { $i++; Write-Host ("  {0,3}. {1}" -f $i, $s.Name) }
    Write-Host "`n  0. 【恢复原版】（备份的 Arelewd 等）"
    if (-not $Name) {
        $pick = Read-Host "`n输入编号或名称片段（直接回车退出）"
        if (-not $pick) { exit 0 }
        $Name = $pick
    }
}

if ($Name -eq '0' -or $Name -eq 'restore') { Restore-Original; exit 0 }

$sel = $null
if ($Name -match '^\d+$') {
    $num = ([int]$Name).ToString('000')
    $byNum = $skins | Where-Object { $_.Name.StartsWith($num + '_') } | Select-Object -First 1
    if ($byNum) { $sel = $byNum }
    elseif ([int]$Name -ge 1 -and [int]$Name -le $skins.Count) { $sel = $skins[[int]$Name - 1] }
    else { throw "编号 $Name 超出范围（可选 1~$($skins.Count)，或用总览图上的编号）" }
}
else {
    $cands = $skins | Where-Object { $_.Name -like "*$Name*" }
    if ($cands.Count -eq 1) { $sel = $cands[0] }
    elseif ($cands.Count -gt 1) {
        Write-Host "匹配到多个："
        $i = 0; foreach ($c in $cands) { $i++; Write-Host ("  {0}. {1}" -f $i, $c.Name) }
        $k = Read-Host "编号"
        $sel = $cands[[int]$k - 1]
    }
}
if (-not $sel) { throw "没找到匹配的皮肤：$Name" }
Write-Host "`n已选择：$($sel.Name)"

$map = @{ '211575' = 'Cartethyia'; '255876' = 'Fleurdelys' }
$buckets = @{}
$inis = Get-ChildItem -LiteralPath $sel.FullName -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue
$found = @{}
foreach ($ini in $inis) {
    $m = Select-String -LiteralPath $ini.FullName -Pattern 'object_guid\s*=\s*(\d+)' | Select-Object -First 1
    if (-not $m) { continue }
    $guid = $m.Matches[0].Groups[1].Value
    $bucket = $map[$guid]
    if (-not $bucket) { continue }
    $modDir = if ($ini.Name -eq 'mod.ini') { $ini.Directory } else { $ini.Directory }
    $k = "$bucket|$($modDir.FullName)"
    if (-not $found.ContainsKey($k)) {
        $found[$k] = $true
        if (-not $buckets.ContainsKey($bucket)) { $buckets[$bucket] = @() }
        $buckets[$bucket] += $modDir
    }
}
if ($buckets.Count -eq 0) {
    Write-Host "  [提示] 这套里没找到带 object_guid 的 ini（可能是纯贴图包或第三方格式）"
}
if ($buckets.Count -eq 0) { throw "这套皮肤里没有可用的 mod.ini（或目标角色不匹配）" }

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
foreach ($b in $buckets.Keys) {
    $cur = Join-Path $Mods $b
    $bak = Join-Path $backupRoot $b
    if ((Test-Path -LiteralPath $cur) -and -not (Test-Path -LiteralPath $bak)) {
        Copy-Item -LiteralPath $cur -Destination $bak -Recurse -Force
        Write-Host "  已备份原 $b → $bak"
    }
}
foreach ($b in $buckets.Keys) {
    $cur = Join-Path $Mods $b
    if (Test-Path -LiteralPath $cur) { Remove-Item -LiteralPath $cur -Recurse -Force }
    New-Item -ItemType Directory -Path $cur -Force | Out-Null
    $bucketList = $buckets[$b]
    if ($bucketList.Count -eq 1) {
        $d = $bucketList[0]
        foreach ($item in Get-ChildItem -LiteralPath $d.FullName) {
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $cur $item.Name) -Recurse -Force
        }
        Write-Host "  已放入 $b\（打平：$($d.Name)）"
    }
    else {
        foreach ($d in $bucketList) {
            Copy-Item -LiteralPath $d.FullName -Destination (Join-Path $cur $d.Name) -Recurse -Force
            Write-Host "  已放入 $b\$($d.Name)"
        }
    }
}
Write-Host "`n== 当前两形态状态 =="
foreach ($form in @('Cartethyia','Fleurdelys')) {
    $p = Join-Path $Mods $form
    if (Test-Path -LiteralPath $p) {
        $n = (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue).Count
        $tag = if ($buckets.ContainsKey($form)) { '← 本次切换' } else { '（未改动）' }
        Write-Host ("  {0,-12} {1,4} 文件  {2}" -f $form, $n, $tag)
    } else { Write-Host ("  {0,-12} 无 Mod" -f $form) }
}
Write-Host "`n完成。回到游戏按 F10 重载即可生效（不用重启）。"
Write-Host "提示：卡提希娅/芙露德莉斯是双形态，两个文件夹可同时有 Mod，开大时各显各的。"
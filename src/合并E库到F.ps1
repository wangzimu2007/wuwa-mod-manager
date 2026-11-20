# 把 E 盘旧库合并进 F 盘（同名跳过，不同名追加编号）
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$srcRoot = 'E:\GameMods\WWMI-Mods\Skins'
$dstRoot = 'F:\GameMods\WWMI-Mods\Skins'
$log = 'E:\GameMods\WWMI-Mods\使用记录\鸣潮\_E库合并日志.csv'
'"时间","角色","目录","结果"' | Set-Content -LiteralPath $log -Encoding UTF8

$chars = @(Get-ChildItem -LiteralPath $srcRoot -Directory | Where-Object { $_.Name -notlike '_*' })
$copied = 0; $skipped = 0
foreach ($c in $chars) {
    $dstChar = Join-Path $dstRoot $c.Name
    if (-not (Test-Path -LiteralPath $dstChar)) { New-Item -ItemType Directory -Path $dstChar -Force | Out-Null }

    # 目标已有名字集合 + 最大编号
    $have = New-Object System.Collections.Generic.HashSet[string]
    $max = 0
    foreach ($s in @(Get-ChildItem -LiteralPath $dstChar -Directory -ErrorAction SilentlyContinue)) {
        [void]$have.Add(($s.Name -replace '^\d+_', ''))
        if ($s.Name -match '^(\d+)_') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
    }

    foreach ($s in @(Get-ChildItem -LiteralPath $c.FullName -Directory | Sort-Object Name)) {
        $name = $s.Name -replace '^\d+_', ''
        if ($have.Contains($name)) {
            $skipped++
            ('"{0}","{1}","{2}","同名跳过"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $c.Name, $s.Name) | Add-Content -LiteralPath $log -Encoding UTF8
            continue
        }
        $max++
        $target = Join-Path $dstChar ('{0:D3}_{1}' -f $max, $name)
        $null = & robocopy $s.FullName $target /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
        $srcN = @(Get-ChildItem -LiteralPath $s.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        $dstN = @(Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($LASTEXITCODE -lt 8 -and $srcN -eq $dstN) {
            $copied++
            [void]$have.Add($name)
            ('"{0}","{1}","{2}","已复制"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $c.Name, $s.Name) | Add-Content -LiteralPath $log -Encoding UTF8
        } else {
            ('"{0}","{1}","{2}","失败 src=$srcN dst=$dstN"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $c.Name, $s.Name) | Add-Content -LiteralPath $log -Encoding UTF8
        }
    }
    Write-Host ("[{0}] 完成，累计复制 {1} / 跳过 {2}" -f $c.Name, $copied, $skipped)
}
Write-Host ""
Write-Host "合并完成：复制 $copied，同名跳过 $skipped"

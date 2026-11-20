# 去重：同角色下同名（忽略编号）只保留最新一个，其余移到 _重复/<角色>/
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$lib = 'F:\GameMods\WWMI-Mods\Skins'
$dupRoot = Join-Path $lib '_重复'
$log = 'E:\GameMods\WWMI-Mods\使用记录\鸣潮\_去重日志.csv'
'"时间","角色","目录","动作"' | Set-Content -LiteralPath $log -Encoding UTF8

$chars = @(Get-ChildItem -LiteralPath $lib -Directory | Where-Object { $_.Name -ne '_重复' -and $_.Name -notlike '_*' })
$moved = 0
foreach ($c in $chars) {
    $subs = @(Get-ChildItem -LiteralPath $c.FullName -Directory -ErrorAction SilentlyContinue)
    if ($subs.Count -le 1) { continue }
    $groups = $subs | Group-Object { $_.Name -replace '^\d+_', '' } | Where-Object Count -gt 1
    if (-not $groups) { continue }
    $target = Join-Path $dupRoot $c.Name
    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
    foreach ($g in $groups) {
        $keep = $g.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $others = $g.Group | Where-Object { $_.FullName -ne $keep.FullName }
        foreach ($o in $others) {
            $dest = Join-Path $target $o.Name
            $n = 1
            while (Test-Path -LiteralPath $dest) { $dest = Join-Path $target ("{0}_dup{1}" -f $o.Name, $n); $n++ }
            try {
                Move-Item -LiteralPath $o.FullName -Destination $dest -ErrorAction Stop
                $moved++
                ('"{0}","{1}","{2}","移到重复"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $c.Name, $o.Name) |
                    Add-Content -LiteralPath $log -Encoding UTF8
            } catch {
                ('"{0}","{1}","{2}","失败:{3}"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $c.Name, $o.Name, ($_.Exception.Message -replace '"', "'")) |
                    Add-Content -LiteralPath $log -Encoding UTF8
            }
        }
    }
    Write-Host ("[{0}] 处理完，累计移除 {1}" -f $c.Name, $moved)
}
Write-Host ""
Write-Host "去重完成：移走 $moved 套（在 $dupRoot）"

# 重新编号（每个角色 001..N）
$renamed = 0
foreach ($c in $chars) {
    $subs = @(Get-ChildItem -LiteralPath $c.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    $i = 0
    foreach ($s in $subs) {
        $i++
        $nameOnly = $s.Name -replace '^\d+_', ''
        $newName = '{0:D3}_{1}' -f $i, $nameOnly
        if ($newName -eq $s.Name) { continue }
        $dest = Join-Path $c.FullName $newName
        if (Test-Path -LiteralPath $dest) { continue }
        try { Move-Item -LiteralPath $s.FullName -Destination $dest -ErrorAction Stop; $renamed++ } catch { }
    }
}
Write-Host "重新编号：改了几 $renamed 个目录"

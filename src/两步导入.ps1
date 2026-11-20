# 两步导入：E 盘解压 → 每 N 套批量搬 F 盘（顺序大块写，避开 USB 小文件随机写）
# 跳过：按包名判断（不看编号），已导入的不再重复
param([int]$Batch = 20, [int]$StartAt = 0)

$ErrorActionPreference = 'Continue'
$script:startTime = Get-Date
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$packMods = 'E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮\mods'
$thumbDir = 'E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮\thumbnail'
$lib      = 'F:\GameMods\WWMI-Mods\Skins'
$stage    = 'E:\GameMods\WWMI-Mods\_stage'
$7za      = 'D:\tools\7zr\7za.exe'
$pw       = 'Neon2014611332'
$log      = 'E:\GameMods\WWMI-Mods\使用记录\鸣潮\_导入进度2.csv'

$charFix = @{ '心' = '心月狐'; '洛瑟拉' = '洛瑟菈'; '爱弥丝' = '爱弥斯'; '科考摩托' = '科考摩托（载具）' }

function Sanitize([string]$s) {
    $t = $s -replace '[\\/:*?"<>|]', '_'
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt 56) { $t = $t.Substring(0, 56) }
    if (-not $t) { $t = 'mod' }
    return $t
}

# 1) 现有清单：角色 → 名字集合 + 已用最大编号
$existing = @{}
$maxNum = @{}
$chars = @(Get-ChildItem -LiteralPath $lib -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike '_*' })
foreach ($c in $chars) {
    if (-not $existing.ContainsKey($c.Name)) { $existing[$c.Name] = New-Object System.Collections.Generic.HashSet[string] }
    $max = 0
    foreach ($s in @(Get-ChildItem -LiteralPath $c.FullName -Directory -ErrorAction SilentlyContinue)) {
        $nm = $s.Name -replace '^\d+_', ''
        [void]$existing[$c.Name].Add($nm)
        if ($s.Name -match '^(\d+)_') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
    }
    $maxNum[$c.Name] = $max
}
$alreadyCount = ($existing.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
Write-Host "现有库：$($chars.Count) 个角色 / $alreadyCount 套"

# 2) 待导包列表
$packs = @(Get-ChildItem -LiteralPath $packMods -File -Filter '*.7z' | Sort-Object Name)
$todo = @()
$now = (Get-Date).AddMinutes(-5)
foreach ($f in $packs) {
    $base = $f.BaseName
    $char = ($base -split '[-_]')[0].Trim()
    if ($charFix.ContainsKey($char)) { $char = $charFix[$char] }
    if ($char -match '(?i)^RabbitFX|前置|管理器|Fixer') { continue }
    if (-not $char) { continue }
    $nm = Sanitize $base
    if ($existing.ContainsKey($char) -and $existing[$char].Contains($nm)) { continue }
    $todo += [pscustomobject]@{ file = $f.FullName; base = $base; char = $char; name = $nm }
}
Write-Host "待导：$($todo.Count) 个（已跳过已导入的）"

if (-not (Test-Path -LiteralPath $stage)) { New-Item -ItemType Directory -Path $stage -Force | Out-Null }
if (-not (Test-Path -LiteralPath $log)) {
    '"时间","包","角色","目标","结果"' | Set-Content -LiteralPath $log -Encoding UTF8
}

$batchItems = @()
$okTotal = 0; $failTotal = 0; $idx = 0

function Test-LinkBad {
    $since = if ($script:startTime) { $script:startTime } else { (Get-Date).AddMinutes(-5) }
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue |
          Where-Object { $_.ProviderName -match 'UASPStor|disk' -and $_.Id -in @(129, 153) }
    return ($ev -and @($ev).Count -ge 3)
}

function Flush-Batch {
    param($items)
    if (-not $items -or $items.Count -eq 0) { return }
    Write-Host "== 搬运 $($items.Count) 套到 F 盘 =="
    foreach ($it in $items) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $null = & robocopy $it.staged $it.target /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
        $code = $LASTEXITCODE
        $sw.Stop()
        $srcN = @(Get-ChildItem -LiteralPath $it.staged -Recurse -File -ErrorAction SilentlyContinue).Count
        $dstN = @(Get-ChildItem -LiteralPath $it.target -Recurse -File -ErrorAction SilentlyContinue).Count
        $res = if ($code -lt 8 -and $srcN -eq $dstN) { 'OK' } else { "失败(code=$code src=$srcN dst=$dstN)" }
        Write-Host ("   {0,-46} {1,6:N0} 文件 {2,5:N1}s {3}" -f $it.name, $srcN, $sw.Elapsed.TotalSeconds, $res)
        ('"{0}","{1}","{2}","{3}","{4}"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $it.base, $it.char, $it.target, $res) |
            Add-Content -LiteralPath $log -Encoding UTF8
        if ($res -eq 'OK') {
            $script:okTotal++
            # 自动优化按键（小键盘/字母 → 方向键/标点/Ctrl）
            try {
                $opt = Join-Path $PSScriptRoot '优化按键.ps1'
                if (Test-Path -LiteralPath $opt) { $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $opt -Target $it.target 2>&1 }
            } catch { }
            Remove-Item -LiteralPath $it.staged -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $script:failTotal++
        }
    }
}

foreach ($t in $todo) {
    $idx++
    # 链路体检
    if (Test-LinkBad) {
        Write-Host "⚠ 检测到 USB 链路报错，暂停。已导 $okTotal，失败 $failTotal"
        Flush-Batch $batchItems
        break
    }

    $work = Join-Path $stage ('p' + $idx)
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work -Force | Out-Null

    $null = & $7za x $t.file "-o$work" "-p$pw" -y 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failTotal++
        ('"{0}","{1}","{2}","","解压失败"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $t.base, $t.char) |
            Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }

    # 内容根：含 ini 的目录
    $inis = @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter '*.ini' -ErrorAction SilentlyContinue)
    if ($inis.Count -eq 0) {
        $failTotal++
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }
    $roots = @($inis | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
    $srcDir = $work
    if ($roots.Count -eq 1) { $srcDir = $roots[0] }
    elseif ((Get-ChildItem -LiteralPath $work).Count -eq 1) { $srcDir = (Get-ChildItem -LiteralPath $work)[0].FullName }

    $main = Get-ChildItem -LiteralPath $srcDir -File -Filter 'mod.ini' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $main) {
        $auto = Get-ChildItem -LiteralPath $srcDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'mod*.ini' } | Select-Object -First 1
        if ($auto) { Copy-Item -LiteralPath $auto.FullName -Destination (Join-Path $srcDir 'mod.ini') -Force }
    }

    # 目标路径（E 盘 staging 里先建好结构）
    $char = $t.char
    if (-not $maxNum.ContainsKey($char)) { $maxNum[$char] = 0 }
    $maxNum[$char]++
    $num = $maxNum[$char]
    $staged = Join-Path $stage ('out_' + $idx)
    if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force }
    New-Item -ItemType Directory -Path $staged -Force | Out-Null
    $null = & robocopy $srcDir $staged /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

    # 缩略图
    $th = Join-Path $thumbDir ($t.base + '.png')
    if (Test-Path -LiteralPath $th) { Copy-Item -LiteralPath $th -Destination (Join-Path $staged 'preview.png') -Force }
    # 清 .BAK
    Get-ChildItem -LiteralPath $staged -Recurse -File -Filter '*.BAK' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    $target = Join-Path (Join-Path $lib $char) ('{0:D3}_{1}' -f $num, $t.name)
    $batchItems += [pscustomobject]@{ staged = $staged; target = $target; name = $t.name; char = $char; base = $t.base }

    if ($batchItems.Count -ge $Batch) {
        Flush-Batch $batchItems
        $batchItems = @()
    }
}

if ($batchItems.Count -gt 0) { Flush-Batch $batchItems }

Write-Host ""
Write-Host "导入结束：成功 $okTotal，失败 $failTotal，计划 $($todo.Count)"
Write-Host "日志：$log"

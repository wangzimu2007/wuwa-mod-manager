# 并行导入整合包 Mod → F 盘副库
# 主进程：规划（角色/编号/目标路径），过滤非 Mod 包，跳过已导入
# 子进程：按分配清单解压 + 复制（4 路并行）
param([int]$Workers = 4)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$packRoot = 'E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮'
$srcMods  = Join-Path $packRoot 'mods'
$srcThumb = Join-Path $packRoot 'thumbnail'
$libRoot  = 'F:\GameMods\WWMI-Mods\Skins'
$7za      = 'D:\tools\7zr\7za.exe'
$packPw   = 'Neon2014611332'

$charFix = @{ '心' = '心月狐'; '洛瑟拉' = '洛瑟菈'; '爱弥丝' = '爱弥斯'; '科考摩托' = '科考摩托（载具）' }
$skipChars = @('RabbitFX反虚化+发光前置v8.3.2','RabbitFX反虚化+发光前置v8.5.0')

function Sanitize([string]$s) {
    $t = $s -replace '[\\/:*?"<>|]', '_'
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt 56) { $t = $t.Substring(0, 56) }
    if (-not $t) { $t = 'mod' }
    return $t
}

if (-not (Test-Path -LiteralPath $libRoot)) { New-Item -ItemType Directory -Path $libRoot -Force | Out-Null }

# ---------- 规划 ----------
$files = @(Get-ChildItem -LiteralPath $srcMods -File -Filter '*.7z' | Sort-Object Name)
$plan = New-Object System.Collections.ArrayList
$counters = @{}
$skipped = 0
foreach ($f in $files) {
    $base = $f.BaseName
    $char = ($base -split '[-_]')[0].Trim()
    if ($skipChars -contains $char) { $skipped++; continue }
    if ($char -match '(?i)^RabbitFX|前置|管理器|Fixer') { $skipped++; continue }
    if ($charFix.ContainsKey($char)) { $char = $charFix[$char] }
    if (-not $char) { $char = '其他' }

    $charDir = Join-Path $libRoot $char
    if (-not (Test-Path -LiteralPath $charDir)) { New-Item -ItemType Directory -Path $charDir -Force | Out-Null }
    if (-not $counters.ContainsKey($char)) {
        $max = 0
        Get-ChildItem -LiteralPath $charDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^(\d+)_') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
        }
        $counters[$char] = $max
    }
    $counters[$char]++
    $num = $counters[$char]
    $dst = Join-Path $charDir ('{0:D3}_{1}' -f $num, (Sanitize $base))
    if (Test-Path -LiteralPath $dst) { $skipped++; $counters[$char]--; continue }   # 已导入过

    [void]$plan.Add([pscustomobject]@{ file = $f.FullName; base = $base; char = $char; dst = $dst })
}
Write-Host "规划完成：待导 $($plan.Count) 个，跳过 $skipped 个"

# ---------- 子进程脚本 ----------
$workerPath = Join-Path $env:TEMP 'import_worker.ps1'
$workerBody = @'
param([string]$JobFile, [string]$7za, [string]$Pw, [string]$ThumbDir, [string]$Index)
$ErrorActionPreference = 'Stop'
$items = Import-Csv -LiteralPath $JobFile
$tmp = Join-Path $env:TEMP ("imp_w" + $Index)
$log = Join-Path $env:TEMP ("imp_w" + $Index + ".log")
"" | Set-Content -LiteralPath $log -Encoding UTF8
foreach ($it in $items) {
    try {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $null = & $7za x $it.file "-o$tmp" "-p$Pw" -y 2>&1
        if ($LASTEXITCODE -ne 0) { throw "7za $LASTEXITCODE" }
        $inis = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter '*.ini' -ErrorAction SilentlyContinue)
        if ($inis.Count -eq 0) { throw 'no ini' }
        $roots = @($inis | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
        $src = $tmp
        if ($roots.Count -eq 1) { $src = $roots[0] }
        elseif ((Get-ChildItem -LiteralPath $tmp).Count -eq 1) { $src = (Get-ChildItem -LiteralPath $tmp)[0].FullName }
        $main = Get-ChildItem -LiteralPath $src -File -Filter 'mod.ini' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $main) {
            $auto = Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^mod.*\.ini$' } | Select-Object -First 1
            if ($auto) { Copy-Item -LiteralPath $auto.FullName -Destination (Join-Path $src 'mod.ini') -Force }
        }
        New-Item -ItemType Directory -Path $it.dst -Force | Out-Null
        Get-ChildItem -LiteralPath $src | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $it.dst -Recurse -Force }
        $th = Join-Path $ThumbDir ($it.base + '.png')
        if (Test-Path -LiteralPath $th) { Copy-Item -LiteralPath $th -Destination (Join-Path $it.dst 'preview.png') -Force }
        Get-ChildItem -LiteralPath $it.dst -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.BAK$' } | Remove-Item -Force -ErrorAction SilentlyContinue
        Add-Content -LiteralPath $log -Value "OK`t$($it.base)" -Encoding UTF8
    } catch {
        Add-Content -LiteralPath $log -Value "FAIL`t$($it.base)`t$($_.Exception.Message)" -Encoding UTF8
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
'@
[IO.File]::WriteAllText($workerPath, $workerBody, (New-Object Text.UTF8Encoding($true)))

# ---------- 分片并行 ----------
$chunkSize = [Math]::Ceiling($plan.Count / $Workers)
$procs = @()
for ($i = 0; $i -lt $Workers; $i++) {
    $start = $i * $chunkSize
    if ($start -ge $plan.Count) { break }
    $end = [Math]::Min($start + $chunkSize - 1, $plan.Count - 1)
    $chunk = $plan[$start..$end]
    $jobFile = Join-Path $env:TEMP ("imp_job_$i.csv")
    $chunk | Export-Csv -LiteralPath $jobFile -NoTypeInformation -Encoding UTF8
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$workerPath`" -JobFile `"$jobFile`" -7za `"$7za`" -Pw `"$packPw`" -ThumbDir `"$srcThumb`" -Index $i"
    $procs += Start-Process powershell -ArgumentList $args -PassThru -WindowStyle Hidden
    Write-Host "启动 worker $i：$($chunk.Count) 个包"
}

Write-Host "等待 $($procs.Count) 个 worker 完成…"
foreach ($p in $procs) { $p.WaitForExit() }

# ---------- 汇总 ----------
$ok = 0; $fail = 0
for ($i = 0; $i -lt $Workers; $i++) {
    $log = Join-Path $env:TEMP ("imp_w$i.log")
    if (-not (Test-Path -LiteralPath $log)) { continue }
    $lines = Get-Content -LiteralPath $log -Encoding UTF8
    $ok += @($lines | Where-Object { $_ -like 'OK*' }).Count
    $bad = @($lines | Where-Object { $_ -like 'FAIL*' })
    $fail += $bad.Count
    if ($bad.Count -gt 0) { $bad | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_)" } }
}
Write-Host "完成：成功 $ok，失败 $fail，规划 $($plan.Count)"

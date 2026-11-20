# 批量下载晨星系列（先下到 E 盘临时目录，成功后再搬到 F 盘）
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$tmp  = 'E:\GameMods\WWMI-Mods\_temp_下载\晨星系列'
$final = 'F:\GameMods\WWMI-Mods\Downloads\_晨星系列'
$plan  = "$env:TEMP\morning_plan.json"
$ua    = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126 Safari/537.36'
$proxy = 'http://127.0.0.1:7890'

if (-not (Test-Path -LiteralPath $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }
$items = Get-Content -LiteralPath $plan -Raw -Encoding UTF8 | ConvertFrom-Json
$log = Join-Path $tmp '_下载记录.csv'
'"时间","名称","文件","大小MB","状态"' | Set-Content -LiteralPath $log -Encoding UTF8

$okCount = 0; $failCount = 0
foreach ($p in $items) {
    $safe = ($p.name -replace '[\\/:*?"<>|]', '_')
    $dir = Join-Path $tmp ("{0}_{1}" -f $p.id, $safe)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $out = Join-Path $dir $p.file

    $have = if (Test-Path -LiteralPath $out) { [Math]::Round((Get-Item -LiteralPath $out).Length/1MB, 2) } else { 0 }
    if ($have -ge ($p.sizeMB * 0.95)) {
        Write-Host "[跳过] $($p.name)  已有 ${have} MB"
        $okCount++
        continue
    }

    Write-Host "[下载] $($p.name)  $($p.sizeMB) MB -> $out"
    $args = @(
        '-sS', '-L', '--retry', '3', '--retry-delay', '5', '-C', '-',
        '--limit-rate', '12M', '--max-time', '900',
        '-A', $ua, '-x', $proxy,
        '-o', $out, '-w', '%{http_code}'
    )
    $code = & curl.exe @args $p.url 2>&1
    $codeStr = ($code | Select-Object -Last 1).ToString().Trim()
    $now = if (Test-Path -LiteralPath $out) { [Math]::Round((Get-Item -LiteralPath $out).Length/1MB, 2) } else { 0 }
    $status = if ($now -ge ($p.sizeMB * 0.95)) { 'OK' } else { "不完整($codeStr)" }
    if ($status -eq 'OK') { $okCount++ } else { $failCount++ }
    Write-Host "        落盘 $now MB  状态=$status"
    ('"{0}","{1}","{2}",{3},"{4}"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $p.name, $p.file, $now, $status) |
        Add-Content -LiteralPath $log -Encoding UTF8
}

Write-Host ""
Write-Host "== 下载完成：成功 $okCount / 失败 $failCount / 共 $($items.Count) =="

# 搬到 F 盘
if ($okCount -gt 0) {
    Write-Host "== 搬到 F 盘：$final =="
    if (-not (Test-Path -LiteralPath $final)) { New-Item -ItemType Directory -Path $final -Force | Out-Null }
    $null = & robocopy $tmp $final /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
    Write-Host "  robocopy 退出码：$LASTEXITCODE"
}

Get-ChildItem -LiteralPath $tmp -Directory | ForEach-Object {
    $f = Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-Host ("  {0,-46} {1,8:N1} MB" -f $_.Name, $(if ($f) { $f.Length / 1MB } else { 0 }))
}
Write-Host "临时目录：$tmp"

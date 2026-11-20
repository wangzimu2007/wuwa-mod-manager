# F 盘 USB 链路压测：写 200MB → 读回校验 → 统计期间 UASP/disk 报错
param([int]$MB = 200, [string]$TestDir = 'F:\GameMods\WWMI-Mods\_链路压测')

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$start = Get-Date
if (-not (Test-Path -LiteralPath $TestDir)) { New-Item -ItemType Directory -Path $TestDir -Force | Out-Null }

$file = Join-Path $TestDir ('test_%dMB.bin' -f $MB)

# 1) 顺序写
$sw = [Diagnostics.Stopwatch]::StartNew()
$buf = New-Object byte[] (1MB)
(New-Object Random).NextBytes($buf)
$fs = [IO.File]::Create($file)
try {
    for ($i = 0; $i -lt $MB; $i++) { $fs.Write($buf, 0, $buf.Length) }
    $fs.Flush($true)
} finally { $fs.Dispose() }
$writeSec = $sw.Elapsed.TotalSeconds

# 2) 顺序读 + 校验长度
$sw.Restart()
$len = (Get-Item -LiteralPath $file).Length
$read = 0
$rs = [IO.File]::OpenRead($file)
try {
    $rb = New-Object byte[] (1MB)
    while (($n = $rs.Read($rb, 0, $rb.Length)) -gt 0) { $read += $n }
} finally { $rs.Dispose() }
$readSec = $sw.Elapsed.TotalSeconds

# 3) 统计本次压测期间的链路报错
Start-Sleep -Seconds 5
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $start } -ErrorAction SilentlyContinue |
      Where-Object { $_.ProviderName -match 'UASPStor|disk' -and $_.Id -in @(129, 153) }

Write-Host ""
Write-Host ("写入 {0} MB：{1:N1} 秒（{2:N1} MB/s）" -f $MB, $writeSec, ($MB / $writeSec))
Write-Host ("读取 {0:N0} 字节：{1:N1} 秒（{2:N1} MB/s）" -f $read, $readSec, (($read / 1MB) / $readSec))
Write-Host ("文件大小一致：{0}" -f ($read -eq $len -and $len -eq ($MB * 1MB)))
Write-Host ("压测期间链路报错：{0} 条" -f @($ev).Count)
if (@($ev).Count -gt 0) {
    $ev | Select-Object -First 5 | ForEach-Object { Write-Host ("   [{0}] {1} id={2}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.ProviderName, $_.Id) }
}

Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
if ((Get-ChildItem -LiteralPath $TestDir -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
    Remove-Item -LiteralPath $TestDir -Force -ErrorAction SilentlyContinue
}

if (@($ev).Count -eq 0) { Write-Host "结果：链路稳定 ✅" } else { Write-Host "结果：仍有 USB 链路重置 ❌" }

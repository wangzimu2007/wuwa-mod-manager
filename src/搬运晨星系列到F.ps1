# 逐目录搬到 F 盘：每个目录独立 robocopy，120 秒超时，超时就跳过并记录
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$src = 'E:\GameMods\WWMI-Mods\_temp_下载\晨星系列'
$dst = 'F:\GameMods\WWMI-Mods\Downloads\_晨星系列'
$log = 'E:\GameMods\WWMI-Mods\_temp_下载\_搬运日志.csv'
'"时间","目录","结果","耗时秒"' | Set-Content -LiteralPath $log -Encoding UTF8

# 先确保目标根目录能建（给 60 秒）
try {
    if (-not (Test-Path -LiteralPath 'F:\GameMods\WWMI-Mods\Downloads')) {
        New-Item -ItemType Directory -Path 'F:\GameMods\WWMI-Mods\Downloads' -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }
    Write-Host "目标目录就绪：$dst"
} catch {
    Write-Host "目标目录创建失败：$($_.Exception.Message)"
    exit 1
}

$dirs = @(Get-ChildItem -LiteralPath $src -Directory | Sort-Object Name)
$okCount = 0; $skipCount = 0
foreach ($d in $dirs) {
    $target = Join-Path $dst $d.Name
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList @($d.FullName, $target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/R:0', '/W:0') -PassThru -WindowStyle Hidden
    $finished = $p.WaitForExit(120000)
    if (-not $finished) {
        try { $p.Kill() } catch { }
        $sw.Stop()
        $skipCount++
        $res = '超时跳过'
        Write-Host "[超时] $($d.Name)"
    } else {
        $sw.Stop()
        if ($p.ExitCode -ge 8) { $skipCount++; $res = "失败($($p.ExitCode))"; Write-Host "[失败] $($d.Name) code=$($p.ExitCode)" }
        else { $okCount++; $res = 'OK'; Write-Host ("[OK]   {0,-44} {1:N0}s" -f $d.Name, $sw.Elapsed.TotalSeconds) }
    }
    ('"{0}","{1}","{2}",{3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $d.Name, $res, [Math]::Round($sw.Elapsed.TotalSeconds)) |
        Add-Content -LiteralPath $log -Encoding UTF8
}

Write-Host ""
Write-Host "搬运完成：成功 $okCount，跳过/失败 $skipCount，共 $($dirs.Count)"
Write-Host "F 盘目录：$dst"

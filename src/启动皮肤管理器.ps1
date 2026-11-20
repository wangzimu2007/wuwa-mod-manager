# 鸣潮 Mod 皮肤管理器启动器
$ErrorActionPreference = 'SilentlyContinue'
$py = "D:\deepseek harness\resources\runtime\primary-runtime\dependencies\python\pythonw.exe"
if (-not (Test-Path -LiteralPath $py)) { $py = "D:\deepseek harness\resources\runtime\primary-runtime\dependencies\python\python.exe" }
$srv = "E:\GameMods\WWMI-Mods\工具\skin_server.py"
$port = 8791
$alive = $false
try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $port); $alive = $true; $c.Close() } catch {}
if (-not $alive) {
    Start-Process -FilePath $py -ArgumentList "`"$srv`"", "--no-browser" -WindowStyle Hidden
    Start-Sleep -Seconds 3
}
Start-Process "http://127.0.0.1:$port/"
# 反虚化开关（局外控制）
# 双击 = 弹出菜单选择；也支持命令行参数 -On / -Off / -Status
# 状态真源：E:\GameMods\WWMI-Mods\.state\反虚化.json
# 启动器每次启动前会把它同步进 WuwaTFR.ini
param(
    [switch]$On,
    [switch]$Off,
    [switch]$Status,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot '反虚化状态.ps1')

function Show-Status {
    $cur = Get-TfrEnabled
    $word = if ($cur) { '开（移除贴身淡出）' } else { '关（保留游戏默认淡出）' }
    Write-Host "当前状态：$word"
    if (Test-Path -LiteralPath $script:TfrIni) {
        $m = Select-String -LiteralPath $script:TfrIni -Pattern '^\s*EnableTFR\s*=\s*(\d)' | Select-Object -First 1
        $ini = if ($m) { $m.Matches[0].Groups[1].Value } else { '?' }
        Write-Host "WuwaTFR.ini：EnableTFR=$ini"
        if ((($ini -eq '1') -ne $cur)) { Write-Host "（ini 与状态文件不一致，下次启动会自动同步）" }
    } else {
        Write-Host "WuwaTFR：未安装"
    }
    Write-Host "游戏进程：$(if (Test-GameRunning) { '运行中' } else { '未运行' })"
    return $cur
}

function Apply([bool]$target) {
    $r = Set-Tfr $target
    $word = if ($r.enabled) { '已开启' } else { '已关闭' }
    Write-Host ""
    Write-Host "—— 反虚化 $word ——"
    Write-Host "  $($r.sync.msg)"
    if ($r.running) {
        Write-Host "  游戏正在运行：本次修改已记录，下次启动自动生效"
    } else {
        Write-Host "  下次进游戏即为该状态"
    }
}

if ($Status) { $null = Show-Status; exit 0 }
if ($On) { Apply $true; exit 0 }
if ($Off) { Apply $false; exit 0 }

# 交互菜单
Write-Host "========== 反虚化开关 =========="
$cur = [bool](Show-Status | Select-Object -Last 1)
Write-Host ""
Write-Host "  [1] 开启"
Write-Host "  [2] 关闭"
Write-Host "  [3] 只看状态（不改）"
Write-Host "  [回车] 切换（当前：$(if ($cur) { '关掉' } else { '打开' })）"
Write-Host ""
$choice = (Read-Host "请选择") -replace "^\uFEFF", ""

switch (($choice -replace [char]0xFEFF,'').Trim()) {
    '1' { Apply $true }
    '2' { Apply $false }
    '3' { Write-Host ""; Write-Host "（未做任何修改）" }
    ''  { Apply (-not $cur) }
    default { Write-Host "输入无效，未做任何修改" }
}

if (-not $NoPause) {
    Write-Host ""
    Write-Host "按任意键关闭…"
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { Start-Sleep -Seconds 2 }
}

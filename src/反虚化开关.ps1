# 反虚化开关（局外控制）
# 双击运行 = 弹出菜单；也支持命令行 -On / -Off / -Status
#
# 控制的是 WuwaTFR（ReShade 插件）的 EnableTFR：
#   1 = 移除"镜头贴近角色时的透明滤镜"
#   0 = 恢复游戏默认
# 注意：EnableTFR 是插件加载时读的，改完要重启游戏才生效。
#
# 与 Mod 的关系：RabbitFX 会先改写着色器，WuwaTFR 的结构匹配就失效，
# 所以反虚化只在「不带 Mod」的光追模式下有效（详见 docs/反虚化与模式切换.md）。

param(
    [switch]$On,
    [switch]$Off,
    [switch]$Status,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '_config.ps1')
. (Join-Path $PSScriptRoot '反虚化状态.ps1')

$cfg = Get-Cfg
$TfrIni = if ($cfg.gameBin) { Join-Path $cfg.gameBin 'WuwaTFR.ini' } else { '' }
$StateFile = Join-Path $script:RootDir '.state\反虚化.json'

function Show-Status {
    $cur = Get-TfrEnabled $StateFile $TfrIni
    $word = if ($cur) { '开（移除贴身淡出）' } else { '关（保留游戏默认淡出）' }
    Write-Host "当前状态：$word"
    if ($TfrIni -and (Test-Path -LiteralPath $TfrIni)) {
        $m = Select-String -LiteralPath $TfrIni -Pattern '^\s*EnableTFR\s*=\s*(\d)' | Select-Object -First 1
        $ini = if ($m) { $m.Matches[0].Groups[1].Value } else { '?' }
        Write-Host "WuwaTFR.ini：EnableTFR=$ini"
        if ((($ini -eq '1') -ne $cur)) { Write-Host "（ini 与状态文件不一致，下次启动会自动同步）" }
    } else {
        Write-Host "WuwaTFR：未安装（找不到 WuwaTFR.ini）"
    }
    Write-Host "游戏进程：$(if (Test-GameRunning) { '运行中' } else { '未运行' })"
    return $cur
}

function Apply([bool]$target) {
    $r = Set-TfrState $StateFile $TfrIni $target
    $word = if ($r.enabled) { '已开启' } else { '已关闭' }
    Write-Host ""
    Write-Host "—— 反虚化 $word ——"
    Write-Host "  $($r.sync.msg)"
    if ($r.running) { Write-Host "  游戏正在运行：本次修改已记录，下次启动自动生效" }
    else { Write-Host "  下次进游戏即为该状态" }
}

if ($Status) { $null = Show-Status; exit 0 }
if ($On) { Apply $true; exit 0 }
if ($Off) { Apply $false; exit 0 }

Write-Host "========== 反虚化开关 =========="
$cur = [bool](Show-Status | Select-Object -Last 1)
Write-Host ""
Write-Host "  [1] 开启"
Write-Host "  [2] 关闭"
Write-Host "  [3] 只看状态（不改）"
Write-Host "  [回车] 切换（当前：$(if ($cur) { '关掉' } else { '打开' })）"
Write-Host ""
$choice = (Read-Host "请选择") -replace [char]0xFEFF, ''

switch ($choice.Trim()) {
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

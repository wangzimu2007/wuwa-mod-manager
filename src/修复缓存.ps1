# 修复贴图/着色器缓存（对应社区流传的「MOD 修复脚本」）
#
# 背景：wwmi-dx12 会把「着色器补丁」和「贴图匹配」的结果缓存到磁盘。
# 游戏大版本更新后（如 3.8.1），旧的缓存和新版本的 hash 对不上，
# 表现就是 Mod 错乱、贴图串位、角色变成别人的皮肤。
#
# 本脚本做一件事：把 wwmi_dx12.ini 的 clear_cache 设为 1，
# 下次启动游戏时 wwmi 会先删掉旧缓存再重建，然后自动改回 0。
#
# ⚠ 只在本工具没有问题时不要跑——它会清掉所有已学习的匹配，
#   首次进游戏会有一段时间"重新学习"，属正常现象。

param(
    [switch]$Check      # 只看当前状态，不改
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$win = 'E:\鸣潮\Wuthering Waves\Wuthering Waves Game\Client\Binaries\Win64'
$ini = Join-Path $win 'wwmi_dx12.ini'

if (-not (Test-Path -LiteralPath $ini)) {
    Write-Host "❌ 找不到 $ini" -ForegroundColor Red
    exit 1
}

function Get-Value {
    $m = Select-String -LiteralPath $ini -Pattern '^\s*clear_cache\s*=\s*(\d)' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return '?'
}

$cur = Get-Value
$game = Get-Process -Name 'Client-Win64-Shipping' -ErrorAction SilentlyContinue

Write-Host "========== wwmi 缓存修复 =========="
Write-Host "  配置文件：$ini"
Write-Host "  clear_cache 当前值：$cur"
Write-Host "  游戏进程：$(if ($game) { '运行中（本次设置会在下次启动生效）' } else { '未运行' })"
Write-Host ""

if ($Check) {
    if ($cur -eq '1') { Write-Host "  状态：已标记为「下次启动清缓存」" }
    else { Write-Host "  状态：正常（未标记清理）" }
    exit 0
}

if ($cur -eq '1') {
    Write-Host "  已经是待清理状态，无需重复设置。"
} else {
    Copy-Item -LiteralPath $ini -Destination ($ini + '.bak-cache') -Force
    $lines = [Collections.Generic.List[string]]::new()
    [IO.File]::ReadAllLines($ini, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*clear_cache\s*=') { $lines[$i] = 'clear_cache = 1'; $done = $true; break }
    }
    if (-not $done) { $lines.Add('clear_cache = 1') }
    [IO.File]::WriteAllLines($ini, $lines, (New-Object Text.UTF8Encoding($false)))
    Write-Host "  ✅ 已设置 clear_cache = 1" -ForegroundColor Green
}

Write-Host ""
Write-Host "接下来："
Write-Host "  1. 用「鸣潮 启动器」正常启动游戏（Mod 模式）"
Write-Host "  2. wwmi 启动时会删掉旧缓存并重建，然后自动把 clear_cache 改回 0"
Write-Host "  3. 首次进游戏可能有一小段时间贴图在重新学习，属正常"
Write-Host ""
Write-Host "替代做法（等价）：游戏内按 Insert 打开 wwmi 面板 → 勾「A11 Clear caches at next launch」"
Write-Host ""
if (-not $game) { Start-Sleep -Seconds 3 }

# 反虚化开关（局外控制，不进游戏按键）
# 用法： 无参数 = 切换；-On 开；-Off 关；-Status 只看状态
param(
    [switch]$On,
    [switch]$Off,
    [switch]$Status
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '_config.ps1')
$cfg = Get-Cfg
$FxIni = Join-Path $cfg.modsDir "RabbitFX\RabbitFX.ini"
$UserIni = Join-Path (Split-Path $cfg.modsDir -Parent) "d3dx_user.ini"
$TfrIni = Join-Path $cfg.gameBin "WuwaTFR.ini"

function Get-TfrCurrent {
    if (-not (Test-Path -LiteralPath $TfrIni)) { return "-" }
    $m = Select-String -LiteralPath $TfrIni -Pattern "^\s*EnableTFR\s*=\s*(\d)" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return "-"
}

function Set-Tfr([int]$value) {
    if (-not (Test-Path -LiteralPath $TfrIni)) { return $false }
    Copy-Item -LiteralPath $TfrIni -Destination ($TfrIni + ".bak") -Force
    $l = [Collections.Generic.List[string]]::new()
    Get-Content -LiteralPath $TfrIni | ForEach-Object { $l.Add($_) }
    $ok = $false
    for ($i = 0; $i -lt $l.Count; $i++) {
        if ($l[$i] -match "^\s*EnableTFR\s*=") { $l[$i] = "EnableTFR=$value"; $ok = $true }
    }
    if (-not $ok) { $l.Add("EnableTFR=$value") }
    [IO.File]::WriteAllLines($TfrIni, $l, (New-Object Text.UTF8Encoding($false)))
    return $true
}

function Get-Current {
    $v = "?"
    if (Test-Path -LiteralPath $FxIni) {
        $m = Select-String -LiteralPath $FxIni -Pattern '^\s*persist global \$censor\s*=\s*(\d)' | Select-Object -First 1
        if ($m) { $v = $m.Matches[0].Groups[1].Value }
    }
    return $v
}

function Set-Censor([int]$value) {
    if (-not (Test-Path -LiteralPath $FxIni)) { throw "找不到 RabbitFX.ini：$FxIni" }
    $bak = "$FxIni.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $FxIni -Destination $bak -Force
    $lines = [Collections.Generic.List[string]]::new()
    Get-Content -LiteralPath $FxIni | ForEach-Object { $lines.Add($_) }
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*persist global \$censor\s*=') {
            $lines[$i] = "persist global `$censor = $value"
            $done = $true
            break
        }
    }
    if (-not $done) { throw "RabbitFX.ini 里没找到 persist global `$censor" }
    [IO.File]::WriteAllLines($FxIni, $lines, (New-Object Text.UTF8Encoding($false)))
    # 同步持久化变量，避免被旧的 d3dx_user.ini 覆盖
    if (Test-Path -LiteralPath $UserIni) {
        Copy-Item -LiteralPath $UserIni -Destination ($UserIni + '.bak') -Force
        $u = [Collections.Generic.List[string]]::new()
        Get-Content -LiteralPath $UserIni | ForEach-Object { $u.Add($_) }
        $hit = $false
        for ($j = 0; $j -lt $u.Count; $j++) {
            if ($u[$j] -match '^\s*\$\\rabbitfx\\censor\s*=') { $u[$j] = "`$`\rabbitfx`\censor = $value"; $hit = $true }
        }
        if (-not $hit) { $u.Add("`$`\rabbitfx`\censor = $value") }
        [IO.File]::WriteAllLines($UserIni, $u, (New-Object Text.UTF8Encoding($false)))
    }
    return $bak
}

if ($Status) {
    $c = Get-Current
    $t2 = Get-TfrCurrent
    $s1 = if ($c -eq '1') { '开' } elseif ($c -eq '0') { '关' } else { '?' }
    $s2 = if ($t2 -eq '1') { '开' } elseif ($t2 -eq '0') { '关' } else { '未安装' }
    Write-Host "反虚化   Mod 模式(RabbitFX)：$s1    光追模式(WuwaTFR)：$s2"
    exit 0
}

$cur = Get-Current
$target = if ($On) { 1 } elseif ($Off) { 0 } elseif ($cur -eq '1') { 0 } else { 1 }
$bak = Set-Censor $target
$tfrDone = Set-Tfr $target
$word = if ($target -eq 1) { '已开启' } else { '已关闭' }
Write-Host ""
Write-Host "反虚化 $word （RabbitFX $cur → $target）"
if ($tfrDone) { Write-Host "光追模式 WuwaTFR 同步设为 $target" } else { Write-Host "WuwaTFR 未安装，跳过光追模式" }
Write-Host "备份：$(Split-Path $bak -Leaf)"
Write-Host ""
Write-Host "生效方式：游戏内按 F10 重载；若没反应，重启游戏。"
Write-Host "（按键已从 RabbitFX 移除，不会占用 \ 键）"
Start-Sleep -Seconds 2

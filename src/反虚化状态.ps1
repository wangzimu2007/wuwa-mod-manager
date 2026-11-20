# 反虚化状态（单一真源）
# 状态文件：E:\GameMods\WWMI-Mods\.state\反虚化.json
# 语义：enabled=true 表示"要反虚化"，启动器每次启动前把它写入 WuwaTFR.ini

$script:TfrStateFile = 'E:\GameMods\WWMI-Mods\.state\反虚化.json'
$script:TfrIni = 'E:\鸣潮\Wuthering Waves\Wuthering Waves Game\Client\Binaries\Win64\WuwaTFR.ini'

function Test-GameRunning {
    $p = Get-Process -Name 'Client-Win64-Shipping' -ErrorAction SilentlyContinue
    return [bool]$p
}

function Get-TfrEnabled {
    if (Test-Path -LiteralPath $script:TfrStateFile) {
        try {
            $o = Get-Content -LiteralPath $script:TfrStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return [bool]$o.enabled
        } catch { }
    }
    # 没有状态文件：从 ini 推断一次
    if (Test-Path -LiteralPath $script:TfrIni) {
        $m = Select-String -LiteralPath $script:TfrIni -Pattern '^\s*EnableTFR\s*=\s*(\d)' | Select-Object -First 1
        if ($m) { return ($m.Matches[0].Groups[1].Value -eq '1') }
    }
    return $true
}

function Save-TfrState([bool]$enabled) {
    $dir = Split-Path $script:TfrStateFile -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{
        enabled   = $enabled
        updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        by        = $env:COMPUTERNAME + '/' + $env:USERNAME
    }
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $script:TfrStateFile -Encoding UTF8
    return $obj
}

function Sync-TfrIni {
    # 把状态写入 WuwaTFR.ini（启动器启动前调用）
    $enabled = Get-TfrEnabled
    if (-not (Test-Path -LiteralPath $script:TfrIni)) {
        return @{ ok = $false; msg = "找不到 WuwaTFR.ini（插件未安装）" }
    }
    $v = if ($enabled) { 1 } else { 0 }
    $lines = [Collections.Generic.List[string]]::new()
    [IO.File]::ReadAllLines($script:TfrIni, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*EnableTFR\s*=') {
            if ($lines[$i] -ne "EnableTFR=$v") {
                Copy-Item -LiteralPath $script:TfrIni -Destination ($script:TfrIni + '.bak-sync') -Force
                $lines[$i] = "EnableTFR=$v"
            }
            $done = $true
            break
        }
    }
    if (-not $done) {
        Copy-Item -LiteralPath $script:TfrIni -Destination ($script:TfrIni + '.bak-sync') -Force
        $lines.Add("EnableTFR=$v")
    }
    [IO.File]::WriteAllLines($script:TfrIni, $lines, (New-Object Text.UTF8Encoding($false)))
    return @{ ok = $true; msg = ("已同步 WuwaTFR.ini → EnableTFR=$v") }
}

function Set-Tfr([bool]$enabled) {
    $info = Save-TfrState $enabled
    $running = Test-GameRunning
    # 游戏没在跑 → 立刻写 ini；在跑 → 只记状态，交给下次启动同步
    if (-not $running) { $sync = Sync-TfrIni } else { $sync = @{ ok = $true; msg = "游戏运行中，留待下次启动生效" } }
    return @{
        enabled = $enabled
        running = $running
        sync    = $sync
    }
}

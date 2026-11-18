# 反虚化状态（单一真源）
# 状态文件记录「用户想要的状态」，WuwaTFR.ini 是「实际生效值」。
# 启动器每次启动前调用 Sync-TfrIni，把状态写进 ini，避免"改了没生效"的错觉。
#
# 为什么不直接改 ini：WuwaTFR 的 EnableTFR 是插件加载时读的，
# 游戏运行中改 ini 不会热更新，所以必须"启动前写"。

function Test-GameRunning {
    $p = Get-Process -Name 'Client-Win64-Shipping' -ErrorAction SilentlyContinue
    return [bool]$p
}

function Get-TfrEnabled([string]$StateFile, [string]$TfrIni) {
    if ($StateFile -and (Test-Path -LiteralPath $StateFile)) {
        try {
            $o = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return [bool]$o.enabled
        } catch { }
    }
    if ($TfrIni -and (Test-Path -LiteralPath $TfrIni)) {
        $m = Select-String -LiteralPath $TfrIni -Pattern '^\s*EnableTFR\s*=\s*(\d)' | Select-Object -First 1
        if ($m) { return ($m.Matches[0].Groups[1].Value -eq '1') }
    }
    return $true
}

function Save-TfrState([string]$StateFile, [bool]$Enabled) {
    $dir = Split-Path $StateFile -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{
        enabled   = $Enabled
        updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        by        = $env:COMPUTERNAME + '/' + $env:USERNAME
    }
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $StateFile -Encoding UTF8
    return $obj
}

function Sync-TfrIni([string]$StateFile, [string]$TfrIni) {
    $enabled = Get-TfrEnabled $StateFile $TfrIni
    if (-not (Test-Path -LiteralPath $TfrIni)) {
        return @{ ok = $false; msg = "找不到 WuwaTFR.ini（插件未安装）" }
    }
    $v = if ($enabled) { 1 } else { 0 }
    $lines = [Collections.Generic.List[string]]::new()
    [IO.File]::ReadAllLines($TfrIni, [Text.Encoding]::UTF8) | ForEach-Object { $lines.Add($_) }
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*EnableTFR\s*=') {
            if ($lines[$i] -ne "EnableTFR=$v") {
                Copy-Item -LiteralPath $TfrIni -Destination ($TfrIni + '.bak-sync') -Force
                $lines[$i] = "EnableTFR=$v"
            }
            $done = $true
            break
        }
    }
    if (-not $done) {
        Copy-Item -LiteralPath $TfrIni -Destination ($TfrIni + '.bak-sync') -Force
        $lines.Add("EnableTFR=$v")
    }
    [IO.File]::WriteAllLines($TfrIni, $lines, (New-Object Text.UTF8Encoding($false)))
    return @{ ok = $true; msg = ("已同步 WuwaTFR.ini -> EnableTFR=$v") }
}

function Set-TfrState([string]$StateFile, [string]$TfrIni, [bool]$Enabled) {
    $null = Save-TfrState $StateFile $Enabled
    $running = Test-GameRunning
    if (-not $running) { $sync = Sync-TfrIni $StateFile $TfrIni }
    else { $sync = @{ ok = $true; msg = "游戏运行中，留待下次启动生效" } }
    return @{ enabled = $Enabled; running = $running; sync = $sync }
}

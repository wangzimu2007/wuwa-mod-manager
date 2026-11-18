# 公共配置读取（被各脚本 dot-source）
# 配置文件：<仓库根>\config.json；不存在时自动按 config.example.json 生成一份

$script:RootDir = Split-Path $PSScriptRoot -Parent
$script:ConfigFile = Join-Path $script:RootDir 'config.json'

$script:DefaultConfig = [ordered]@{
    # 游戏可执行文件所在目录（里面有 dxgi.dll / wwmi_dx12.addon64 / WuwaTFR.ini）
    gameBin    = 'C:\Program Files\Wuthering Waves\Wuthering Waves Game\Client\Binaries\Win64'
    # XXMI Launcher 的 WWMI Mods 目录
    modsDir    = '%APPDATA%\XXMI Launcher\WWMI\Mods'
    # 皮肤库根目录（本工具管理的地方）
    skinsDir   = '%USERPROFILE%\Documents\WuwaMods\Skins'
    # 整合包解压出的角色目录（仅 carve/解压 脚本用到）
    packDir    = ''
    # 模式切换脚本（启动器用；留空则启动器隐藏该功能）
    switchScript = ''
    # 记录目录（启动器「打开记录目录」用）
    recordsDir = ''
}

function Get-Cfg {
    $cfg = @{}
    foreach ($k in $script:DefaultConfig.Keys) { $cfg[$k] = $script:DefaultConfig[$k] }
    if (Test-Path -LiteralPath $script:ConfigFile) {
        try {
            $user = Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $user.PSObject.Properties) {
                if ($p.Value -ne $null -and "$($p.Value)" -ne '') { $cfg[$p.Name] = [string]$p.Value }
            }
        } catch {
            Write-Host "[config] config.json 解析失败，使用默认值：$($_.Exception.Message)"
        }
    } else {
        $obj = [ordered]@{}
        foreach ($k in $script:DefaultConfig.Keys) { $obj[$k] = $script:DefaultConfig[$k] }
        try {
            ($obj | ConvertTo-Json) | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8
            Write-Host "[config] 已生成配置模板：$script:ConfigFile（请按实际路径修改）"
        } catch { }
    }
    foreach ($k in @($cfg.Keys)) {
        $cfg[$k] = [Environment]::ExpandEnvironmentVariables($cfg[$k])
    }
    return $cfg
}

function Assert-CfgPath([string]$path, [string]$name) {
    if (-not $path) { throw "配置项 $name 为空，请编辑 $script:ConfigFile" }
    if (-not (Test-Path -LiteralPath $path)) { throw "配置项 $name 指向的路径不存在：$path（请编辑 $script:ConfigFile）" }
    return $path
}

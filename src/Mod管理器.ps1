# 鸣潮 Mod 管理器（WPF 桌面版）
# 参考 Vortex / Mod Organizer 2 的三栏布局：左角色、中卡片网格、右详情
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# 主库：F 盘（大容量仓库，以后 Mod 都下到这里）
$SkinsRoot = "F:\GameMods\WWMI-Mods\Skins"
$script:ForceRebuild = $false
# 副库：E 盘旧库（等搬迁合并完可以清空这个数组）
$ExtraSkinsRoots = @()   # 已合并到 F 盘单库
$BackupRoot = Join-Path $SkinsRoot "_原版备份"
$ModsRoot = Join-Path $env:APPDATA "XXMI Launcher\WWMI\Mods"
$CacheFile = Join-Path $SkinsRoot "_index_cache.json"
# guid -> 显示名。除角色本体外，配套部件也映射到所属角色：
#   4392/336 = Arelewd Lily 包的配件（面纱影子 / 头部）
#   31764    = KanouSakura 卡提希娅包的武器外观
$GuidMap = @{
    '211575' = '卡提希娅'; '255876' = '芙露德莉斯'
    '296013' = '清宵'
    '273786' = '莉莉'; '4392' = '莉莉'; '336' = '莉莉'
    '31764' = '卡提希娅'
    '301545' = '琳奈'
    '107904' = '洛瑟菈'; '156957' = '洛瑟菈'; '69402' = '洛瑟菈'; '264861' = '洛瑟菈'
    '355443' = '心月狐'; '306723' = '心月狐'
}
. (Join-Path $PSScriptRoot '反虚化状态.ps1')

function Get-IniGuids([string]$dir) {
    $guids = New-Object System.Collections.Generic.List[string]
    $keys = 0
    $keyTexts = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue | ForEach-Object {
        $txt = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
        $m = [regex]::Match($txt, 'object_guid\s*=\s*(\d+)')
        if ($m.Success -and -not $guids.Contains($m.Groups[1].Value)) { $guids.Add($m.Groups[1].Value) }
        $keys += ([regex]::Matches($txt, '(?m)^\s*\[Key')).Count
        foreach ($km in [regex]::Matches($txt, '(?m)^\s*key\s*=\s*(.+?)\s*$')) {
            $kv = $km.Groups[1].Value.Trim()
            if ($keyTexts.Count -lt 120 -and -not $keyTexts.Contains($kv)) { $keyTexts.Add($kv) }
        }
    }
    return @{ guids = $guids; keys = $keys; keyText = ($keyTexts -join ' ') }
}

# 界面状态（筛选条件记忆）
$UiStateFile = 'E:\GameMods\WWMI-Mods\.state\manager_ui.json'
function Save-UiState {
    try {
        $dir = Split-Path $UiStateFile -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        @{
            forms = $FForms.SelectedIndex
            keys  = $FKeys.SelectedIndex
            panel = $FPanel.SelectedIndex
        } | ConvertTo-Json | Set-Content -LiteralPath $UiStateFile -Encoding UTF8
    } catch { }
}
function Load-UiState {
    try {
        if (-not (Test-Path -LiteralPath $UiStateFile)) { return }
        $s = Get-Content -LiteralPath $UiStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $s.forms -and $s.forms -ge 0 -and $s.forms -lt $FForms.Items.Count) { $FForms.SelectedIndex = [int]$s.forms }
        if ($null -ne $s.keys -and $s.keys -ge 0 -and $s.keys -lt $FKeys.Items.Count) { $FKeys.SelectedIndex = [int]$s.keys }
        if ($null -ne $s.panel -and $s.panel -ge 0 -and $s.panel -lt $FPanel.Items.Count) { $FPanel.SelectedIndex = [int]$s.panel }
    } catch { }
}

function Find-Preview([string]$dir) {
    $imgs = @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(jpg|png|jpeg|webp)$?' })
    if ($imgs.Count -eq 0) { return $null }
    # 1) 名字像预览图的（兼容 preivew 这种拼写错误、中文「预览/封面/海报」）
    $byName = @($imgs | Where-Object { $_.Name -match '(?i)(prei?view|cover|preview|海报|预览|封面)' } |
        Sort-Object Length -Descending)
    if ($byName.Count -gt 0) { return $byName[0].FullName }
    # 2) 退而求其次：排除 Textures 目录后取最大的一张（作者常把宣传图放根目录）
    $noTex = @($imgs | Where-Object { $_.FullName -notmatch '(?i)\\textures\\' } | Sort-Object Length -Descending)
    if ($noTex.Count -gt 0) { return $noTex[0].FullName }
    # 3) 实在没有就返回 null，卡片会显示占位文字
    return $null
}

$script:ReadmeCache = @{}
$script:KeyCache = @{}

function Get-NormKey([string]$s) {
    if (-not $s) { return '' }
    return (($s -replace '\s+', ' ').Trim().ToLower())
}

function Get-FreeKey($used, $index) {
    # 与「优化按键.ps1」同一套规则：方向键 → , / → 6~0 → Ctrl+字母
    $pool = @('VK_UP','VK_DOWN','VK_LEFT','VK_RIGHT',
              'VK_OEM_2','VK_OEM_PERIOD','VK_OEM_COMMA',
              '0','9','8','7','6')
    foreach ($ch in @('m','n','k','j','u','i','o','l','p','b','v','g','h','y')) {
        $pool += "ctrl $ch"
    }
    $normUsed = @{}
    foreach ($u in $used) { $normUsed[(Get-NormKey $u)] = $true }
    foreach ($c in $pool) { if (-not $normUsed.ContainsKey((Get-NormKey $c))) { return $c } }
    return "ctrl $([char](97 + ([int]$index % 20)))"
}

function Get-KeyEntries([string]$dir) {
    $out = New-Object System.Collections.ArrayList
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notmatch '(?i)\.bak|\.bak_|_\d{4}-\d{2}-\d{2}' } | ForEach-Object {
        $path = $_.FullName
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue)
        $cur = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[Key(.+?)\]\s*$') { $cur = $Matches[1].Trim(); continue }
            if ($lines[$i] -match '^\s*\[') { $cur = $null; continue }
            if ($cur -and $lines[$i] -match '^(\s*key\s*=\s*)(.+)$') {
                [void]$out.Add([pscustomobject]@{ section = $cur; spec = $Matches[2].Trim(); path = $path; line = $i; prefix = $Matches[1] })
                $cur = $null
            }
        }
    }
    return $out
}

function Get-KeyList([string]$dir) {
    if ($script:KeyCache.ContainsKey($dir)) { return $script:KeyCache[$dir] }
    $entries = Get-KeyEntries $dir
    $r = (($entries | ForEach-Object { "{0}  →  {1}" -f $_.section, $_.spec }) | Select-Object -Unique) -join "`r`n"
    $script:KeyCache[$dir] = $r
    return $r
}

function Find-Readme([string]$dir) {
    if ($script:ReadmeCache.ContainsKey($dir)) { return $script:ReadmeCache[$dir] }
    $all = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.txt -ErrorAction SilentlyContinue)
    $f = $all | Where-Object { $_.Name -match 'read|toggle|说明|切换|列表|注意' } |
         Sort-Object { $_.Name -match 'readme' } -Descending | Select-Object -First 1
    if (-not $f) { $f = $all | Select-Object -First 1 }
    $txt = ""
    if ($f) {
        $txt = (Get-Content -LiteralPath $f.FullName -TotalCount 40 -Encoding UTF8 | Where-Object { $_.Trim() }) -join "`r`n"
    }
    $script:ReadmeCache[$dir] = $txt
    return $txt
}

function Build-Index {
    $chars = @{}
    Get-ChildItem -LiteralPath $SkinsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_*' } | ForEach-Object {
            $char = $_.Name
            $list = New-Object System.Collections.ArrayList
            Get-ChildItem -LiteralPath $_.FullName -Directory | Sort-Object Name | ForEach-Object {
                if ($_.Name -notmatch '^(\d+)_(.+)$') { return }
                $num = $Matches[1]; $name = $Matches[2]
                $info = Get-IniGuids $_.FullName
                [void]$list.Add([pscustomobject]@{
                    num = $num; name = $name; dir = $_.FullName
                    guids = @($info.guids); keys = $info.keys; keyText = $info.keyText
                    thumb = (Find-Preview $_.FullName)
                })
            }
            if ($list.Count -gt 0) { $chars[$char] = $list }
        }
    # 副库（整合包导入区）：编号加 F 前缀，避免和主库编号撞
    foreach ($extra in $ExtraSkinsRoots) {
        if (-not (Test-Path -LiteralPath $extra)) { continue }
        Get-ChildItem -LiteralPath $extra -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_*' } | ForEach-Object {
                $char = $_.Name
                if (-not $chars.ContainsKey($char)) { $chars[$char] = New-Object System.Collections.ArrayList }
                Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
                    if ($_.Name -notmatch '^(\d+)_(.+)$') { return }
                    $num = 'F' + $Matches[1]; $name = $Matches[2]
                    $info = Get-IniGuids $_.FullName
                    $chars[$char].Add([pscustomobject]@{
                        num = $num; name = $name; dir = $_.FullName
                        guids = @($info.guids); keys = $info.keys; keyText = $info.keyText
                        thumb = (Find-Preview $_.FullName); external = $false; fromExtra = $true
                    }) | Out-Null
                }
                if ($chars[$char].Count -eq 0) { $chars.Remove($char) }
            }
    }
    # 收养：已装在 Mods 里、但皮肤库里没有的角色，也放进列表（external 条目，不复制文件）
    $known = @{}
    foreach ($c in $chars.Keys) { foreach ($e in $chars[$c]) { foreach ($g in $e.guids) { $known[$g] = $c } } }
    if (Test-Path -LiteralPath $ModsRoot) {
        Get-ChildItem -LiteralPath $ModsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $folder = $_
            if ($folder.Name -like 'DISABLED*') { return }
            if ($folder.Name -match 'RabbitFX') { return }
            $info = Get-IniGuids $folder.FullName
            if ($info.guids.Count -eq 0) { return }
            $g0 = @($info.guids)[0]
            if ($known.ContainsKey($g0)) { return }
            $charName = if ($GuidMap.ContainsKey($g0)) { $GuidMap[$g0] } else { $folder.Name }
            if (-not $chars.ContainsKey($charName)) { $chars[$charName] = New-Object System.Collections.ArrayList }
            $chars[$charName].Add([pscustomobject]@{
                num = '已装'; name = $folder.Name; dir = $folder.FullName
                guids = @($info.guids); keys = $info.keys; keyText = $info.keyText
                thumb = (Find-Preview $folder.FullName); external = $true
            }) | Out-Null
            foreach ($g in $info.guids) { $known[$g] = $charName }
        }
    }
    return $chars
}

function Get-Index {
    # 只要缓存存在就直接用（不再按 30 分钟过期），避免启动时扫描几千个目录把界面卡死。
    # 需要重建时点「刷新索引」（会带 -Force）。
    if (-not $script:ForceRebuild -and (Test-Path -LiteralPath $CacheFile)) {
        try {
            $raw = Get-Content -LiteralPath $CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $out = @{}
            foreach ($p in $raw.PSObject.Properties) { $out[$p.Name] = @($p.Value) }
            if ($out.Count -gt 0) { return $out }
        } catch { }
    }
    $idx = Build-Index
    try {
        $obj = @{}
        foreach ($k in $idx.Keys) { $obj[$k] = $idx[$k] }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $CacheFile -Encoding UTF8
    } catch { }
    return $idx
}

$FxIni = Join-Path $env:APPDATA "XXMI Launcher\WWMI\Mods\RabbitFX\RabbitFX.ini"
$UserIni = Join-Path $env:APPDATA "XXMI Launcher\WWMI\d3dx_user.ini"
$TfrIni = "E:\鸣潮\Wuthering Waves\Wuthering Waves Game\Client\Binaries\Win64\WuwaTFR.ini"

function Get-TfrState {
    $a = 0; $b = 0
    if (Test-Path -LiteralPath $FxIni) {
        $m = Select-String -LiteralPath $FxIni -Pattern '^\s*persist global \$censor\s*=\s*(\d)' | Select-Object -First 1
        if ($m) { $a = [int]$m.Matches[0].Groups[1].Value }
    }
    if (Test-Path -LiteralPath $TfrIni) {
        $m2 = Select-String -LiteralPath $TfrIni -Pattern '^\s*EnableTFR\s*=\s*(\d)' | Select-Object -First 1
        if ($m2) { $b = [int]$m2.Matches[0].Groups[1].Value }
    }
    return @{ fx = $a; tfr = $b; hasTfr = (Test-Path -LiteralPath $TfrIni) }
}

function Set-TfrState([int]$v) {
    $msg = @()
    if (Test-Path -LiteralPath $TfrIni) {
        Copy-Item -LiteralPath $TfrIni -Destination ($TfrIni + '.bak-tgl') -Force
        $t2 = [Collections.Generic.List[string]]::new()
        [IO.File]::ReadAllLines($TfrIni, [Text.Encoding]::UTF8) | ForEach-Object { $t2.Add($_) }
        $ok = $false
        for ($k = 0; $k -lt $t2.Count; $k++) {
            if ($t2[$k] -match '^\s*EnableTFR\s*=') { $t2[$k] = "EnableTFR=$v"; $ok = $true }
        }
        if (-not $ok) { $t2.Add("EnableTFR=$v") }
        [IO.File]::WriteAllLines($TfrIni, $t2, (New-Object Text.UTF8Encoding($false)))
        $msg += "WuwaTFR=$v"
    }
    return ($msg -join '，')
}

function Get-InstalledMap {
    $map = @{}
    Get-ChildItem -LiteralPath $ModsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $info = Get-IniGuids $_.FullName
        foreach ($g in $info.guids) { if (-not $map.ContainsKey($g)) { $map[$g] = $_.Name } }
    }
    return $map
}

function Copy-Flat([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    # robocopy 比 Copy-Item 快很多，避免安装时界面卡死
    $null = & robocopy $src $dst /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
    if ($LASTEXITCODE -ge 8) { throw "robocopy 失败（$LASTEXITCODE）：$src → $dst" }
}

function Install-Skin($skin, [string]$targetGuid) {
    $sources = @{}
    Get-ChildItem -LiteralPath $skin.dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue | ForEach-Object {
        $txt = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
        $m = [regex]::Match($txt, 'object_guid\s*=\s*(\d+)')
        if (-not $m.Success) { return }
        $g = $m.Groups[1].Value
        if ($targetGuid -ne 'all' -and $g -ne $targetGuid) { return }
        if (-not $sources.ContainsKey($g)) { $sources[$g] = New-Object System.Collections.Generic.List[string] }
        if (-not $sources[$g].Contains($_.DirectoryName)) { $sources[$g].Add($_.DirectoryName) }
    }
    if ($sources.Count -eq 0) { return "❌ 这套没有覆盖目标形态" }
    # 清掉同角色其它形态的旧 Mod（避免两个 guid 各留一套导致贴图错乱）
    $targetNames = @()
    foreach ($g in $sources.Keys) {
        $nm = if ($GuidMap.ContainsKey($g)) { $GuidMap[$g] } else { $null }
        if ($nm) { $targetNames += $nm }
    }
    if ($targetNames.Count -gt 0) {
        Get-ChildItem -LiteralPath $ModsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'DISABLED*' } | ForEach-Object {
            $iniF = Join-Path $_.FullName 'mod.ini'
            if (-not (Test-Path -LiteralPath $iniF)) { return }
            $h = Select-String -LiteralPath $iniF -Pattern 'object_guid\s*=\s*(\d+)' | Select-Object -First 1
            if (-not $h) { return }
            $og = $h.Matches[0].Groups[1].Value
            if ($sources.ContainsKey($og)) { return }
            $on = if ($GuidMap.ContainsKey($og)) { $GuidMap[$og] } else { $null }
            if ($on -and ($targetNames -contains $on)) {
                Rename-Item -LiteralPath $_.FullName -NewName ('DISABLED ' + $_.Name) -ErrorAction SilentlyContinue
            }
        }
    }
    $map = Get-InstalledMap
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $done = @()
    foreach ($g in $sources.Keys) {
        $folder = if ($map.ContainsKey($g)) { $map[$g] } else { "Skin_" + $g }
        $cur = Join-Path $ModsRoot $folder
        $bak = Join-Path $BackupRoot $folder
        if ((Test-Path -LiteralPath $cur) -and -not (Test-Path -LiteralPath $bak)) {
            Copy-Item -LiteralPath $cur -Destination $bak -Recurse -Force
        }
        if (Test-Path -LiteralPath $cur) { Remove-Item -LiteralPath $cur -Recurse -Force }
        New-Item -ItemType Directory -Path $cur -Force | Out-Null
        $dirs = $sources[$g]
        if ($dirs.Count -eq 1) { Copy-Flat $dirs[0] $cur }
        else { foreach ($d in $dirs) { Copy-Flat $d (Join-Path $cur (Split-Path $d -Leaf)) } }
        $done += $folder
    }
    return ("✅ 已装：" + ($done -join ' / ') + "　回游戏按 F10")
function Start-Install($skin, [string]$targetGuid) {
    if ($script:InstallJob) { return "⚠ 上一次安装还没完成" }
    $map = Get-InstalledMap
    $job = Start-Job -ScriptBlock {
        param($skinDir, $targetGuid, $modsRoot, $backupRoot, $map, $guidMap)
        $log = New-Object System.Collections.ArrayList
        $sources = @{}
        Get-ChildItem -LiteralPath $skinDir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue | ForEach-Object {
            $txt = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
            $m = [regex]::Match($txt, 'object_guid\s*=\s*(\d+)')
            if (-not $m.Success) { return }
            $g = $m.Groups[1].Value
            if ($targetGuid -ne 'all' -and $g -ne $targetGuid) { return }
            if (-not $sources.ContainsKey($g)) { $sources[$g] = New-Object System.Collections.Generic.List[string] }
            if (-not $sources[$g].Contains($_.DirectoryName)) { $sources[$g].Add($_.DirectoryName) }
        }
        if ($sources.Count -eq 0) { return "❌ 这套没有覆盖目标形态" }

        # 同角色其它形态 → 停用
        $targetNames = @()
        foreach ($g in $sources.Keys) { if ($guidMap.ContainsKey($g)) { $targetNames += $guidMap[$g] } }
        if ($targetNames.Count -gt 0) {
            Get-ChildItem -LiteralPath $modsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'DISABLED*' } | ForEach-Object {
                $iniF = Join-Path $_.FullName 'mod.ini'
                if (-not (Test-Path -LiteralPath $iniF)) { return }
                $h = Select-String -LiteralPath $iniF -Pattern 'object_guid\s*=\s*(\d+)' | Select-Object -First 1
                if (-not $h) { return }
                $og = $h.Matches[0].Groups[1].Value
                if ($sources.ContainsKey($og)) { return }
                if ($guidMap.ContainsKey($og) -and ($targetNames -contains $guidMap[$og])) {
                    Rename-Item -LiteralPath $_.FullName -NewName ('DISABLED ' + $_.Name) -ErrorAction SilentlyContinue
                }
            }
        }

        if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
        $done = @()
        foreach ($g in $sources.Keys) {
            $folder = if ($map.ContainsKey($g)) { $map[$g] } else { "Skin_" + $g }
            $cur = Join-Path $modsRoot $folder
            $bak = Join-Path $backupRoot $folder
            if ((Test-Path -LiteralPath $cur) -and -not (Test-Path -LiteralPath $bak)) {
                $null = & robocopy $cur $bak /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
            }
            if (Test-Path -LiteralPath $cur) { Remove-Item -LiteralPath $cur -Recurse -Force }
            New-Item -ItemType Directory -Path $cur -Force | Out-Null
            $dirs = $sources[$g]
            foreach ($d in $dirs) {
                if ($dirs.Count -eq 1) { $null = & robocopy $d $cur /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 }
                else { $null = & robocopy $d (Join-Path $cur (Split-Path $d -Leaf)) /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 }
            }
            $done += $folder
        }
        return ("✅ 已装：" + ($done -join ' / ') + "　回游戏按 F10")
    } -ArgumentList $skin.dir, $targetGuid, $ModsRoot, $BackupRoot, $map, $GuidMap
    $script:InstallJob = $job
    if (-not $script:InstallTimer) {
        $script:InstallTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:InstallTimer.Interval = [TimeSpan]::FromMilliseconds(600)
        $script:InstallTimer.Add_Tick({
            if (-not $script:InstallJob) { return }
            if ($script:InstallJob.State -in @('Completed','Failed','Stopped')) {
                $script:InstallTimer.Stop()
                $msg = ''
                try { $msg = Receive-Job -Job $script:InstallJob -ErrorAction SilentlyContinue | Select-Object -Last 1 } catch { }
                if (-not $msg) { $msg = "❌ 安装失败" }
                Remove-Job -Job $script:InstallJob -Force -ErrorAction SilentlyContinue
                $script:InstallJob = $null
                $Status.Text = $msg
                try { $script:Installed = Get-InstalledMap } catch { }
            }
        })
    }
    $script:InstallTimer.Start()
    return '⏳ 已在后台安装…（可继续操作，完成后状态栏会提示）'
}
}

function Restore-Original {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { return "❌ 没有备份" }
    $n = 0
    Get-ChildItem -LiteralPath $BackupRoot -Directory | ForEach-Object {
        $dst = Join-Path $ModsRoot $_.Name
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force
        $n++
    }
    if ($n -eq 0) { return "❌ 备份是空的" }
    return "✅ 已恢复 $n 个原版 Mod　回游戏按 F10"
}

function Import-Skin([string]$char, [string]$srcPath) {
    if (-not (Test-Path -LiteralPath $srcPath)) { return "❌ 路径不存在" }
    $dir = Join-Path $SkinsRoot $char
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $nums = Get-ChildItem -LiteralPath $dir -Directory | Where-Object { $_.Name -match '^(\d+)_' } |
        ForEach-Object { [int]($_.Name -split '_')[0] }
    $next = if ($nums) { ($nums | Measure-Object -Maximum).Maximum + 1 } else { 1 }
    $base = Split-Path $srcPath -Leaf
    $dst = Join-Path $dir ("{0:D3}_{1}" -f $next, $base)
    Copy-Item -LiteralPath $srcPath -Destination $dst -Recurse -Force
    # 新增：自动优化按键（小键盘/字母单键 → 方向键/标点/Ctrl 组合）
    try {
        $optScript = Join-Path $PSScriptRoot '优化按键.ps1'
        if (Test-Path -LiteralPath $optScript) {
            $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $optScript -Target $dst 2>&1
        }
    } catch { }
    $info = Get-IniGuids $dst
    if ($info.guids.Count -eq 0) { Remove-Item -LiteralPath $dst -Recurse -Force; return "❌ 没有 object_guid，看起来不是 WWMI Mod" }
    Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
    return "✅ 已导入 {0:D3}_{1}（形态 {2}）" -f $next, $base, ($info.guids -join ',')
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="鸣潮 Mod 管理器" Height="900" Width="1460"
        WindowStartupLocation="CenterScreen" Background="#101218"
        FontFamily="Microsoft YaHei">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#161922"/>
    <SolidColorBrush x:Key="Line" Color="#242936"/>
    <SolidColorBrush x:Key="Accent" Color="#4a9eff"/>
    <SolidColorBrush x:Key="Text2" Color="#8b93a3"/>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="#1f3350"/>
      <Setter Property="Foreground" Value="#cfe6ff"/>
      <Setter Property="BorderBrush" Value="#2f5b8a"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#2a4a72"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#1b1f2a"/>
      <Setter Property="BorderBrush" Value="#2a2f3d"/>
      <Setter Property="Foreground" Value="#b8c0cf"/>
    </Style>
    <Style x:Key="TglSwitch" TargetType="ToggleButton">
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="24"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="track" CornerRadius="12" Background="#1c2029" BorderBrush="#2c313d" BorderThickness="1"/>
              <Ellipse x:Name="knob" Width="18" Height="18" Fill="#6b7280"
                       HorizontalAlignment="Left" VerticalAlignment="Center" Margin="3,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="#2b5f4a"/>
                <Setter TargetName="track" Property="BorderBrush" Value="#3f8a68"/>
                <Setter TargetName="knob" Property="Fill" Value="#d9f2e3"/>
                <Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="track" Property="Opacity" Value="0.85"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Tgl" TargetType="ToggleButton">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="tb" CornerRadius="6"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="tb" Property="Opacity" Value="0.8"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Tab" TargetType="ListBoxItem">
      <Setter Property="Padding" Value="14,9"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
      <Setter Property="Foreground" Value="#aab2c2"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="bd" Background="Transparent" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1c212c"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1d3350"/>
                <Setter Property="Foreground" Value="#bfe0ff"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- 暗色滚动条：细、无箭头、圆角滑块，悬停/拖动高亮 -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="9"/>
      <Setter Property="MinWidth" Value="9"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb MinHeight="28">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="Th" Background="#3a4560" CornerRadius="4.5" Margin="1,0"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Th" Property="Background" Value="#5b7099"/>
                          </Trigger>
                          <Trigger Property="IsDragging" Value="True">
                            <Setter TargetName="Th" Property="Background" Value="#6f8ec4"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- 深色下拉框：解决默认模板白底白字 -->
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#dfe4ee"/>
      <Setter Property="Background" Value="#171b24"/>
      <Setter Property="BorderBrush" Value="#2a3040"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6"/>
              <ContentPresenter x:Name="cp" Margin="10,0,26,0" VerticalAlignment="Center" HorizontalAlignment="Left"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                TextElement.Foreground="#dfe4ee"/>
              <Path x:Name="arrow" Data="M0,0 L4,4 L8,0" Stroke="#8b93a3" StrokeThickness="1.4"
                    HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <ToggleButton x:Name="tb" Opacity="0" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
              <Popup x:Name="pop" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                     AllowsTransparency="True" PopupAnimation="Fade" Focusable="False">
                <Border Background="#171b24" BorderBrush="#2a3040" BorderThickness="1" CornerRadius="6" Margin="0,4,0,0">
                  <ScrollViewer MaxHeight="240" VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#3a4560"/>
              </Trigger>
              <Trigger Property="IsDropDownOpen" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#4a9eff"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#c9cedb"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="4" Margin="4,2">
              <ContentPresenter Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#22304a"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1d3350"/>
                <Setter Property="Foreground" Value="#bfe0ff"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="210"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="390"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
      <StackPanel Margin="14,18,14,14">
        <TextBlock Text="鸣潮 Mod" Foreground="#9fd0ff" FontSize="18" FontWeight="SemiBold"/>
        <TextBlock Text="管理器" Foreground="#5d6675" FontSize="12" Margin="0,0,0,18"/>
        <Border Background="#171b24" BorderBrush="#242936" BorderThickness="1" CornerRadius="10" Padding="10" Margin="0,0,0,16">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Grid.Column="0" Text="反虚化" Foreground="#dfe4ee" FontSize="13" VerticalAlignment="Center"/>
              <ToggleButton Grid.Column="1" x:Name="TfrToggle" Style="{StaticResource TglSwitch}"
                            HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock x:Name="TfrHint" Text="Mod 模式 + 光追模式" Foreground="#6f7787" FontSize="10.5" Margin="0,7,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <TextBlock Text="角色" Foreground="#6f7787" FontSize="11" Margin="2,0,0,6"/>
        <TextBox x:Name="CharSearch" Height="26" Background="#101218" Foreground="#dfe4ee"
                 BorderBrush="#2a2f3d" Padding="6,0" FontSize="11" VerticalContentAlignment="Center"
                 Margin="0,0,0,6" ToolTip="输入角色名 / 别名 / 拼音首字母，如 ktxy、心月、清霄"/>
        <ListBox x:Name="CharList" Background="Transparent" BorderThickness="0"
                 ItemContainerStyle="{StaticResource Tab}" Foreground="#aab2c2"
                 MaxHeight="240" ScrollViewer.VerticalScrollBarVisibility="Visible"/>
        <Button x:Name="RefreshBtn" Content="刷新索引" Style="{StaticResource Ghost}" Margin="0,18,0,0"/>
        <Button x:Name="NewCharBtn" Content="新建角色" Style="{StaticResource Ghost}" Margin="0,8,0,0"/>
        <TextBlock Text="导入外部 Mod" Foreground="#6f7787" FontSize="11" Margin="2,18,0,6"/>
        <TextBox x:Name="ImpPath" Height="30" Background="#101218" Foreground="#dfe4ee"
                 BorderBrush="#2a2f3d" Padding="6,0" FontSize="11" VerticalContentAlignment="Center"/>
        <Button x:Name="ImpBtn" Content="导入到当前角色" Style="{StaticResource Ghost}" Margin="0,8,0,0"/>
      </StackPanel>
    </Border>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Grid Grid.Row="0" Margin="18,16,18,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border Background="#171b24" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="8" Height="36" VerticalAlignment="Center">
          <Grid>
            <TextBlock Text="搜索：全库角色 / 编号 / 名称 / 按键（如 VK_UP、ctrl m）" Foreground="#5d6675" FontSize="12" Margin="12,0,0,0" VerticalAlignment="Center" x:Name="SearchHint"/>
            <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" Foreground="#e3e7ef"
                     FontSize="13" Margin="10,0" VerticalContentAlignment="Center"/>
          </Grid>
        </Border>
        <TextBlock x:Name="Stats" Grid.Column="1" Foreground="#6f7787" FontSize="12" VerticalAlignment="Center" Margin="16,0,0,0"/>
        <StackPanel Grid.Row="1" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,10,0,0">
          <TextBlock Text="筛选：" Foreground="#6f7787" FontSize="12" VerticalAlignment="Center" Margin="0,0,8,0"/>
          <ComboBox x:Name="FForms" Width="108" Height="28">
            <ComboBoxItem IsSelected="True" Content="形态：全部"/>
            <ComboBoxItem Content="形态：单"/>
            <ComboBoxItem Content="形态：双"/>
            <ComboBoxItem Content="形态：三+"/>
          </ComboBox>
          <ComboBox x:Name="FKeys" Width="116" Height="28" Margin="8,0,0,0">
            <ComboBoxItem IsSelected="True" Content="按键：全部"/>
            <ComboBoxItem Content="按键：无"/>
            <ComboBoxItem Content="按键：1~5"/>
            <ComboBoxItem Content="按键：6~10"/>
            <ComboBoxItem Content="按键：10+"/>
          </ComboBox>
          <ComboBox x:Name="FPanel" Width="108" Height="28" Margin="8,0,0,0">
            <ComboBoxItem IsSelected="True" Content="面板：全部"/>
            <ComboBoxItem Content="面板：有"/>
          </ComboBox>
          <Button x:Name="FClear" Content="清空筛选" Height="28" Margin="8,0,0,0" Background="#1b2333" Foreground="#b8c0cf" BorderThickness="0" Padding="10,0"/>
        </StackPanel>
      </Grid>

      <ScrollViewer x:Name="CardsScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="14,0,10,10">
        <WrapPanel x:Name="Cards"/>
      </ScrollViewer>
    </Grid>

    <Border Grid.Column="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1,0,0,0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Height="250" Background="#0b0d12" CornerRadius="0">
          <Image x:Name="BigPreview" Stretch="UniformToFill"/>
        </Border>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="18,14,18,0">
          <StackPanel>
            <TextBlock x:Name="DetailName" Foreground="#9fd0ff" FontSize="16" FontWeight="SemiBold" TextWrapping="Wrap"/>
            <TextBlock x:Name="DetailMeta" Foreground="#8b93a3" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap"/>
            <WrapPanel x:Name="TagPanel" Margin="0,10,0,0"/>
            <TextBlock Text="作者说明" Foreground="#6f7787" FontSize="11" Margin="0,14,0,6"/>
            <Border Background="#0d0f15" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="8" Padding="10">
              <TextBlock x:Name="DetailReadme" Foreground="#9aa4b5" FontSize="11.5" TextWrapping="Wrap" MaxHeight="160" LineHeight="18"/>
            </Border>
            <TextBlock Text="切换按键（自动识别，可改；改完点「装到…」生效）" Foreground="#6f7787" FontSize="11" Margin="0,14,0,6"/>
            <StackPanel x:Name="KeyPanel"/>
            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
              <Button x:Name="SaveKeys" Content="保存按键到皮肤库" Style="{StaticResource Ghost}" Margin="0,0,8,0"/>
              <Button x:Name="FixKeys" Content="自动修复冲突" Style="{StaticResource Ghost}"/>
            </StackPanel>
          </StackPanel>
        </ScrollViewer>
        <StackPanel Grid.Row="2" Margin="18,12,18,16">
          <WrapPanel x:Name="ActionPanel"/>
          <TextBlock x:Name="Status" Foreground="#7fd18a" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,0"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$CharList = $win.FindName('CharList')
$CharSearch = $win.FindName('CharSearch')
$NewCharBtn = $win.FindName('NewCharBtn')
$TfrToggle = $win.FindName('TfrToggle')
$TfrHint = $win.FindName('TfrHint')
$Cards = $win.FindName('Cards')
$Search = $win.FindName('Search')
$FForms = $win.FindName('FForms')
$FKeys = $win.FindName('FKeys')
$FPanel = $win.FindName('FPanel')
$FClear = $win.FindName('FClear')
$CardsScroll = $win.FindName('CardsScroll')
$Stats = $win.FindName('Stats')
$BigPreview = $win.FindName('BigPreview')
$DetailName = $win.FindName('DetailName')
$DetailMeta = $win.FindName('DetailMeta')
$TagPanel = $win.FindName('TagPanel')
$DetailReadme = $win.FindName('DetailReadme')
$KeyPanel = $win.FindName('KeyPanel')
$SaveKeys = $win.FindName('SaveKeys')
$FixKeys = $win.FindName('FixKeys')
$ActionPanel = $win.FindName('ActionPanel')
$Status = $win.FindName('Status')
$RefreshBtn = $win.FindName('RefreshBtn')
$ImpPath = $win.FindName('ImpPath')
$ImpBtn = $win.FindName('ImpBtn')

$script:Index = Get-Index
$script:CurChar = ($script:Index.Keys | Select-Object -First 1)
$script:CurSkin = $null
$script:Installed = Get-InstalledMap

function New-Tag([string]$text, [string]$bg, [string]$fg) {
    $b = New-Object System.Windows.Controls.Border
    $b.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($bg)))
    $b.CornerRadius = New-Object System.Windows.CornerRadius 5
    $b.Padding = New-Object System.Windows.Thickness 8,3,8,3
    $b.Margin = New-Object System.Windows.Thickness 0,0,6,6
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontSize = 11
    $t.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($fg)))
    $b.Child = $t
    return $b
}

function Show-Detail($skin) {
    $script:CurSkin = $skin
    $DetailName.Text = $skin.name
    $mine = @($skin.guids | ForEach-Object { if ($GuidMap.ContainsKey($_)) { $GuidMap[$_] } else { "形态 $_" } })
    $DetailMeta.Text = "编号 $($skin.num)"
    $TagPanel.Children.Clear()
    foreach ($m in $mine) { [void]$TagPanel.Children.Add((New-Tag $m '#1b2b3d' '#8ec2ff')) }
    if ($skin.keys -gt 0) { [void]$TagPanel.Children.Add((New-Tag ("可按键切 $($skin.keys) 段") '#1d3d24' '#8ee29a')) }
    else { [void]$TagPanel.Children.Add((New-Tag '外观固定' '#232733' '#9aa4b5')) }
    if ($mine.Count -gt 1) { [void]$TagPanel.Children.Add((New-Tag '双形态' '#3d2a1b' '#ffc078')) }
    # F 盘条目在导入期间读 ini/readme 会卡死：走轻量详情
    $light = ($skin.dir -like 'F:\*')
    if ($light) {
        $DetailReadme.Text = "（这套在 F 盘副库，导入期间不扫描 ini/readme 以免卡顿）`r`n`r`n名称：$($skin.name)`r`n形态：$(($skin.guids) -join ',')`r`n目录：$($skin.dir)"
    } else {
        $rd = Find-Readme $skin.dir
        $kl = Get-KeyList $skin.dir
        $parts = @()
        if ($rd) { $parts += "── 作者说明 ──`r`n$rd" }
        if ($kl) { $parts += "── 自动解析的按键（来自 mod.ini）──`r`n$kl" }
        $DetailReadme.Text = if ($parts.Count) { $parts -join "`r`n`r`n" } else { '（这个包既没有说明文件，也没有 [Key] 段 → 外观固定）' }
    }
    if ($skin.thumb -and -not $light) {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.UriSource = (New-Object Uri $skin.thumb); $bi.EndInit()
        $BigPreview.Source = $bi
    } else { $BigPreview.Source = $null }

    $ActionPanel.Children.Clear()
    if ($skin.external) {
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = '这个条目来自 Mods 目录（已安装状态，不是皮肤库里的套装）'
        $lbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#8b93a3')))
        $lbl.FontSize = 11.5
        $lbl.TextWrapping = 'Wrap'
        $lbl.Margin = New-Object System.Windows.Thickness 0,0,0,6
        [void]$ActionPanel.Children.Add($lbl)
    }
    # guid 互为同一显示的（如 双形态但都叫「心月狐」）只显示一个按钮
    $formGroups = @{}
    foreach ($g in $(if ($skin.external) { @() } else { $skin.guids })) {
        $label = if ($GuidMap.ContainsKey($g)) { $GuidMap[$g] } else { "形态 $g" }
        if (-not $formGroups.ContainsKey($label)) { $formGroups[$label] = New-Object System.Collections.ArrayList }
        [void]$formGroups[$label].Add($g)
    }
    foreach ($label in ($formGroups.Keys | Sort-Object)) {
        $gs = @($formGroups[$label])
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = "装到 $label"
        $btn.Style = $win.Resources['Btn']
        $btn.Tag = @{ g = $(if ($gs.Count -gt 1) { 'all' } else { $gs[0] }); s = $skin }
        $btn.Add_Click({ param($s, $e) $Status.Text = Start-Install $s.Tag.s $s.Tag.g })
        [void]$ActionPanel.Children.Add($btn)
    }
    $btnRestore = New-Object System.Windows.Controls.Button
    $btnRestore.Content = '恢复原版'
    $btnRestore.Style = $win.Resources['Ghost']
    $btnRestore.Add_Click({ param($s, $e) $Status.Text = Restore-Original; $script:Installed = Get-InstalledMap })
    [void]$ActionPanel.Children.Add($btnRestore)

    $btnOpen = New-Object System.Windows.Controls.Button
    $btnOpen.Content = '打开文件夹'
    $btnOpen.Style = $win.Resources['Ghost']
    $btnOpen.Tag = $skin.dir
    $btnOpen.Add_Click({ param($s, $e) Start-Process explorer.exe $s.Tag })
    [void]$ActionPanel.Children.Add($btnOpen)

    # 按键编辑区
    $KeyPanel.Children.Clear()
    $entries = @(Get-KeyEntries $skin.dir)
    $script:KeyRows = New-Object System.Collections.ArrayList
    if ($entries.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = '（这个包没有任何 [Key] 段 → 外观固定，无按键）'
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6f7787'))
        $tb.FontSize = 11; $tb.Margin = New-Object System.Windows.Thickness 0,2,0,0
        [void]$KeyPanel.Children.Add($tb)
        $SaveKeys.IsEnabled = $false
    }
    else {
        $SaveKeys.IsEnabled = $true
        foreach ($e in $entries) {
            $row = New-Object System.Windows.Controls.Grid
            $row.Margin = New-Object System.Windows.Thickness 0,0,0,5
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 150
            $c2 = New-Object System.Windows.Controls.ColumnDefinition
            [void]$row.ColumnDefinitions.Add($c1); [void]$row.ColumnDefinitions.Add($c2)
            $lb = New-Object System.Windows.Controls.TextBlock
            $lb.Text = $e.section
            $lb.FontSize = 11.5
            $lb.VerticalAlignment = 'Center'
            $lb.TextTrimming = 'CharacterEllipsis'
            $lb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9aa4b5'))
            [System.Windows.Controls.Grid]::SetColumn($lb, 0)
            [void]$row.Children.Add($lb)
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.Text = $e.spec
            $tb.FontFamily = 'Consolas'
            $tb.FontSize = 11.5
            $tb.Height = 24
            $tb.Padding = New-Object System.Windows.Thickness 5,0,5,0
            $tb.VerticalContentAlignment = 'Center'
            $tb.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0d0f15'))
            $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#dfe4ee'))
            $tb.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2a2f3d'))
            [System.Windows.Controls.Grid]::SetColumn($tb, 1)
            [void]$row.Children.Add($tb)
            $tb.Add_TextChanged({ Update-KeyConflicts })
            [void]$KeyPanel.Children.Add($row)
            [void]$script:KeyRows.Add([pscustomobject]@{ entry = $e; box = $tb; label = $lb; conflict = $false; suggest = ''; orig = $e.spec })
        }
        Update-KeyConflicts
    }
}

function Update-KeyConflicts {
    # 鼠标键（UI 拖动/点击）与总开关不参与冲突修复
    $isProtected = {
        param($row)
        ($row.entry.spec -match '(?i)VK_(L|R|M)BUTTON') -or ($row.entry.section -match '(?i)enable_mods')
    }
    if (-not $script:KeyRows -or $script:KeyRows.Count -eq 0) { return }
    $seen = @{}
    foreach ($r in $script:KeyRows) {
        $n = Get-NormKey $r.box.Text
        $r.conflict = $false
        $r.suggest = ''
        if (-not $n) { continue }
        if (& $isProtected $r) { continue }
        if ($seen.ContainsKey($n)) { $r.conflict = $true }
        else { $seen[$n] = $true }
    }
    # 标记第一个出现者也算冲突（同键多人用）
    $dups = @{}
    foreach ($r in $script:KeyRows) {
        $n = Get-NormKey $r.box.Text
        if (-not $n) { continue }
        if (& $isProtected $r) { continue }
        $k = $r.entry.path + '|' + $n
        if (-not $dups.ContainsKey($k)) { $dups[$k] = 0 }
        $dups[$k]++
    }
    foreach ($r in $script:KeyRows) {
        $n = Get-NormKey $r.box.Text
        if (-not $n) { continue }
        $k = $r.entry.path + '|' + $n
        if (& $isProtected $r) { continue }
        if ($dups[$k] -gt 1) { $r.conflict = $true }
    }
    $i = 0
    foreach ($r in $script:KeyRows) {
        $i++
        if ($r.conflict) {
            $sameFile = @($script:KeyRows | Where-Object { $_.entry.path -eq $r.entry.path } | ForEach-Object { $_.box.Text })
            $r.suggest = Get-FreeKey $sameFile $i
            $r.label.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#ff8f8f'))
            $r.box.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#c04a4a'))
            $r.label.ToolTip = "冲突：多个功能用同一个键 → 建议改为 $($r.suggest)"
        }
        else {
            $r.label.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9aa4b5'))
            $r.box.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2a2f3d'))
            $r.label.ToolTip = $null
        }
    }
    # 实时更新冲突计数
    $nConf = @($script:KeyRows | Where-Object { $_.conflict }).Count
    $script:ConflictText = if ($nConf -gt 0) { "⚠ $nConf 处按键冲突（红色标记）" } else { '' }
    $Status.Text = if ($nConf -gt 0) { "⚠ 检测到 $nConf 处按键冲突，可点「自动修复冲突」" } else { $Status.Text }
}

function Render-Cards {
    $Cards.Children.Clear()
    # 全库模式不需要先选角色
    $kw = $Search.Text.Trim()
    $fi = if ($FForms.SelectedIndex -gt 0) { $FForms.SelectedIndex } else { 0 }
    $ki = if ($FKeys.SelectedIndex -gt 0) { $FKeys.SelectedIndex } else { 0 }
    $pi = if ($FPanel.SelectedIndex -gt 0) { $FPanel.SelectedIndex } else { 0 }
    $isGlobal = ($kw -ne '') -or ($fi -ne 0) -or ($ki -ne 0) -or ($pi -ne 0) -or ($script:CurChar -eq '★ 全部角色')

    # 组装候选列表
    $list = @()
    if ($isGlobal) {
        foreach ($ch in ($script:Index.Keys | Sort-Object)) {
            foreach ($s in @($script:Index[$ch])) {
                $s | Add-Member -NotePropertyName ownerChar -NotePropertyValue $ch -Force
                $list += $s
            }
        }
    } else {
        if (-not $script:CurChar) { $Stats.Text = '输入关键字或选择筛选条件，即可全库搜索'; return }
        $list = @($script:Index[$script:CurChar] | ForEach-Object { $_ | Add-Member -NotePropertyName ownerChar -NotePropertyValue $script:CurChar -Force -PassThru })
    }

    # 关键字（名称/编号/角色）
    if ($kw) {
        $kwl = $kw.ToLower()
        $list = @($list | Where-Object {
            ($_.name -and $_.name.ToLower().Contains($kwl)) -or
            ([string]$_.num).Contains($kwl) -or
            ($_.ownerChar -and $_.ownerChar.ToLower().Contains($kwl)) -or ($_.keyText -and $_.keyText.ToLower().Contains($kwl))
        })
    }
    # 形态筛选
    if ($fi -eq 1) { $list = @($list | Where-Object { @($_.guids).Count -eq 1 }) }
    elseif ($fi -eq 2) { $list = @($list | Where-Object { @($_.guids).Count -eq 2 }) }
    elseif ($fi -eq 3) { $list = @($list | Where-Object { @($_.guids).Count -ge 3 }) }
    # 按键数筛选
    if ($ki -eq 1) { $list = @($list | Where-Object { [int]$_.keys -eq 0 }) }
    elseif ($ki -eq 2) { $list = @($list | Where-Object { [int]$_.keys -ge 1 -and [int]$_.keys -le 5 }) }
    elseif ($ki -eq 3) { $list = @($list | Where-Object { [int]$_.keys -ge 6 -and [int]$_.keys -le 10 }) }
    elseif ($ki -eq 4) { $list = @($list | Where-Object { [int]$_.keys -gt 10 }) }
    # 面板筛选（按目录里是否有 UI ini 判断，只对候选做）
    if ($pi -eq 1) {
        $list = @($list | Where-Object {
            $u = Get-ChildItem -LiteralPath $_.dir -Recurse -File -Filter '*UI*.ini' -ErrorAction SilentlyContinue | Select-Object -First 1
            $u -ne $null
        })
    }

    $total = $list.Count
    $script:LastTotal = $total
    if (-not $script:ShowLimit -or $script:ShowLimit -lt 1) { $script:ShowLimit = 40 }
    $maxCards = $script:ShowLimit
    $shown = if ($list.Count -gt $maxCards) { @($list | Select-Object -First $maxCards) } else { $list }
    if ($list.Count -gt $maxCards) {
        $Stats.Text = "共 $total 套（已显示 $($shown.Count)，点下方「加载更多」）"
    } else {
        $Stats.Text = "共 $total 套"
    }
    if ($isGlobal) { $Stats.Text += " · 全库模式" }
    foreach ($s in $shown) {
        $border = New-Object System.Windows.Controls.Border
        $border.Width = 188; $border.Height = 214
        $border.Margin = New-Object System.Windows.Thickness 0,0,12,12
        $border.CornerRadius = New-Object System.Windows.CornerRadius 10
        $border.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#171b24')))
        $border.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#242936')))
        $border.BorderThickness = New-Object System.Windows.Thickness 1
        $border.Cursor = 'Hand'
        $border.Tag = $s

        $grid = New-Object System.Windows.Controls.Grid
        $row1 = New-Object System.Windows.Controls.RowDefinition; $row1.Height = 152
        $row2 = New-Object System.Windows.Controls.RowDefinition
        [void]$grid.RowDefinitions.Add($row1); [void]$grid.RowDefinitions.Add($row2)

        $imgBorder = New-Object System.Windows.Controls.Border
        $imgBorder.CornerRadius = New-Object System.Windows.CornerRadius 9,9,0,0
        $imgBorder.ClipToBounds = $true
        $imgBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0b0d12')))
        # 缩略图正常加载（F 盘已修复，读图不再卡）
        $thumbOk = [bool]$s.thumb
        if (-not $thumbOk) {
            $ph = New-Object System.Windows.Controls.TextBlock
            $ph.Text = "无预览图`n$($s.name)"
            $ph.FontSize = 11
            $ph.TextAlignment = 'Center'
            $ph.TextWrapping = 'Wrap'
            $ph.HorizontalAlignment = 'Center'
            $ph.VerticalAlignment = 'Center'
            $ph.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#4c5566')))
            $imgBorder.Child = $ph
        }
        if ($thumbOk) {
            $img = New-Object System.Windows.Controls.Image
            $img.Stretch = 'UniformToFill'
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.DecodePixelWidth = 260; $bi.UriSource = (New-Object Uri $s.thumb); $bi.EndInit()
            $img.Source = $bi
            $imgBorder.Child = $img
        }
        [System.Windows.Controls.Grid]::SetRow($imgBorder, 0)
        [void]$grid.Children.Add($imgBorder)

        $numTb = New-Object System.Windows.Controls.TextBlock
        $numTb.Text = if ($s.external) { '已装' } else { $s.num }
        $numTb.FontFamily = 'Consolas'
        $numTb.FontSize = 11
        $numTb.FontWeight = 'Bold'
        $numTb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#7fe08a')))
        $numTb.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#CC000000')))
        $numTb.Padding = New-Object System.Windows.Thickness 5,1,5,1
        $numTb.Margin = New-Object System.Windows.Thickness 6
        $numTb.HorizontalAlignment = 'Left'; $numTb.VerticalAlignment = 'Top'
        $imgChild = $imgBorder.Child
        $imgBorder.Child = $null
        $g2 = New-Object System.Windows.Controls.Grid
        if ($imgChild) { [void]$g2.Children.Add($imgChild) }
        [void]$g2.Children.Add($numTb)
        $imgBorder.Child = $g2

        if ($s.guids.Count -gt 1) {
            $badge = New-Object System.Windows.Controls.TextBlock
            $badge.Text = '双形态'
            $badge.FontSize = 10
            $badge.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#bfe0ff')))
            $badge.Margin = New-Object System.Windows.Thickness 6
            $badge.HorizontalAlignment = 'Right'; $badge.VerticalAlignment = 'Top'
            if ($imgBorder.Child -is [System.Windows.Controls.Grid]) { [void]$imgBorder.Child.Children.Add($badge) }
        }

        $nameTb = New-Object System.Windows.Controls.TextBlock
        $nameTb.Text = if ($isGlobal) { "$($s.ownerChar) · $($s.name)" } else { $s.name }
        $nameTb.FontSize = 11.5
        $nameTb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#c9cedb')))
        $nameTb.TextTrimming = 'CharacterEllipsis'
        $nameTb.Margin = New-Object System.Windows.Thickness 9,7,9,7
        $nameTb.TextWrapping = 'Wrap'
        $nameTb.MaxHeight = 48
        [System.Windows.Controls.Grid]::SetRow($nameTb, 1)
        [void]$grid.Children.Add($nameTb)

        $border.Child = $grid
        $border.Add_MouseLeftButtonUp({
            param($s2, $e2)
            $b = $s2
            foreach ($c in $Cards.Children) {
                $c.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#242936')))
                $c.BorderThickness = New-Object System.Windows.Thickness 1
            }
            $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#4a9eff')))
            $b.BorderThickness = New-Object System.Windows.Thickness 2
            Show-Detail $b.Tag
        })
        [void]$Cards.Children.Add($border)
    }
    # 还有更多 → 加载更多
    if ($list.Count -gt $shown.Count) {
        $remain = $list.Count - $shown.Count
        $moreBtn = New-Object System.Windows.Controls.Button
        $moreBtn.Content = "加载更多（还有 $remain 套）"
        $moreBtn.Width = 188; $moreBtn.Height = 60
        $moreBtn.Margin = New-Object System.Windows.Thickness 0,0,12,12
        $moreBtn.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1b2333'))
        $moreBtn.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9fc6ff'))
        $moreBtn.BorderThickness = 0
        $moreBtn.Cursor = 'Hand'
        $moreBtn.Add_Click({ $script:ShowLimit = $script:ShowLimit + 60; try { Render-Cards } catch { } })
        [void]$Cards.Children.Add($moreBtn)
    }
    if ($Cards.Children.Count -gt 0) {
        $first = $Cards.Children[0]
        if ($first -and -not $script:KeepSelection) {
            $first.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#4a9eff')))
            $first.BorderThickness = New-Object System.Windows.Thickness 2
            $script:CurSkin = $first.Tag   # 不自动读详情，避免切角色卡顿
        }
    }
    $script:KeepSelection = $false
}

$NewCharBtn.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $name = [Microsoft.VisualBasic.Interaction]::InputBox(
        "输入新角色的名字（会建立 Skins\<名字> 目录，名字建议用游戏内角色名）",
        "新建角色", "")
    if (-not $name) { return }
    $name = $name.Trim()
    if ($name -match '[\\/:*?"<>|]') { $Status.Text = "❌ 名字里不能有 \ / : * ? `" < > |"; return }
    $dir = Join-Path $SkinsRoot $name
    if (Test-Path -LiteralPath $dir) { $Status.Text = "该角色已存在：$dir"; return }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
    $script:Index = Get-Index
    $CharList.Items.Clear()
    [void]$CharList.Items.Add('★ 全部角色')
    foreach ($k in ($script:Index.Keys | Sort-Object)) { [void]$CharList.Items.Add($k) }
    $i = $CharList.Items.IndexOf($name)
    if ($i -ge 0) { $CharList.SelectedIndex = $i }
    $Status.Text = "✅ 已新建角色「$name」。用「导入外部 Mod」把皮肤导进来，或把文件夹放进 $dir"
})

# 角色别名 / 拼音（用于搜索；没列的走子串匹配）
$script:CharAlias = @{
    '卡提希娅' = '卡提西亚 卡提希亚 卡提 ktxy katixiya cartethyia'
    '芙露德莉斯' = '芙露德莉丝 大卡 芙露 fldls fleurdelys'
    '心月狐' = '心月 月狐 心 xinyuehu xyh hsin'
    '洛瑟菈' = '洛瑟拉 洛瑟 瑟菈 lsl luosela rosella lucilla'
    '清宵' = '清霄 宵 qingxiao qx'
    '琳奈' = '琳纳 琳 ln linnai lynae'
    '莉莉' = '莉莉 丽丽 ll lily'
    '爱弥斯' = '爱弥丝 爱米斯 弥斯 ams aimisi'
    '吟霖' = '吟林 yl yinlin'
    '今汐' = '今夕 汐 jx jinxi'
    '长离' = '长璃 cl changli'
    '守岸人' = '守岸 岸人 sar shorekeeper'
    '椿' = '春 chun camellya'
    '珂莱塔' = '珂莱 莱塔 klt carlotta'
    '赞妮' = '赞尼 zn zani'
    '坎特蕾拉' = '坎特雷拉 坎特 ktl cantarella'
    '折枝' = '折纸 zz zhezhi'
    '弗洛洛' = '弗洛 fll phrolova'
    '绯雪' = '菲雪 绯 fx hiyuki'
    '千咲' = '千笑 qx chisa'
    '散华' = '散花 sh sanhua'
    '白芷' = '白纸 bz baizhi'
    '鉴心' = '鉴芯 jx jianxin'
    '赤霞' = '炽霞 赤 cxia chixia'
    '桃祈' = '桃祁 tq taoqi'
    '釉瑚' = '釉壶 yh youhu'
    '秧秧' = '央央 yy yangyang'
    '凌阳' = '凌杨 ly lingyang'
    '忌炎' = '忌焰 jy jiyan'
    '卡卡罗' = '卡卡 kkl calcharo'
    '秋水' = '秋 qs qiushui'
    '丹瑾' = '丹谨 dj danjin'
    '莫特斐' = '莫特 mtf mortefi'
    '维里奈' = '维丽奈 维里 wln verina'
    '安可' = '安珂 ak encore'
    '露帕' = '鲁帕 lp lupa'
    '洛可可' = '洛可 lkk roccia'
    '布兰特' = '布兰 b lt brant'
    '坎特雷拉' = '坎特蕾拉 ktl'
    '相里要' = '相里 xly xiangliyao'
    '尤诺' = '尤娜 yn iuno'
    '夏空' = '夏 xk ciaccona'
    '菲比' = '绯比 fb phoebe'
    '西格莉卡' = '西格 莉卡 xglk sigrika'
    '奥古斯塔' = '奥古 古斯塔 agst augusta'
    '嘉贝莉娜' = '嘉贝 贝莉娜 jbln galbrena'
    '露西' = '露茜 lx lucy'
    '锁暝' = '锁冥 sm suoming'
    '莫宁' = '莫柠 mn morning'
    '达妮娅' = '达妮亚 dny damia'
    '卜灵' = '卜玲 bl buling'
    '灯灯' = '灯 dd dengdeng'
    '渊武' = '渊 wu yuanwu'
}

function Test-CharMatch([string]$name, [string]$q) {
    if (-not $q) { return $true }
    $q = $q.Trim().ToLower()
    if ($name.ToLower().Contains($q)) { return $true }
    if ($script:CharAlias.ContainsKey($name)) {
        foreach ($a in ($script:CharAlias[$name] -split '\s+')) {
            if ($a -and $a.ToLower().Contains($q)) { return $true }
        }
    }
    return $false
}

function Refresh-CharList([string]$q) {
    $CharList.Items.Clear()
    [void]$CharList.Items.Add('★ 全部角色')
    foreach ($k in ($script:Index.Keys | Sort-Object)) {
        if (Test-CharMatch $k $q) { [void]$CharList.Items.Add($k) }
    }
    if ($CharList.Items.Count -gt 0) { $CharList.SelectedIndex = 0 }
    else { $script:CurChar = $null; $Cards.Children.Clear() }
}

$CharSearch.Add_TextChanged({ $script:ShowLimit = 40; Refresh-CharList $CharSearch.Text })

$CharList.Add_SelectionChanged({
    if ($CharList.SelectedItem) {
        $script:CurChar = $CharList.SelectedItem; $script:ShownCount = $script:PageSize; $script:ShowLimit = 40
        try { Render-Cards } catch { $Status.Text = "渲染出错：$($_.Exception.Message)" }
    }
})
$Search.Add_TextChanged({ $script:ShownCount = $script:PageSize; $script:ShowLimit = 40; Render-Cards })
$script:UiReady = $false
$FForms.Add_SelectionChanged({ if (-not $script:UiReady) { return }; $script:ShowLimit = 40; Save-UiState; try { Render-Cards } catch { } })
$FKeys.Add_SelectionChanged({ if (-not $script:UiReady) { return }; $script:ShowLimit = 40; Save-UiState; try { Render-Cards } catch { } })
$FPanel.Add_SelectionChanged({ if (-not $script:UiReady) { return }; $script:ShowLimit = 40; Save-UiState; try { Render-Cards } catch { } })
$FClear.Add_Click({
    $Search.Text = ''
    $FForms.SelectedIndex = 0
    $FKeys.SelectedIndex = 0
    $FPanel.SelectedIndex = 0
    Save-UiState
    try { Render-Cards } catch { }
})

$script:AutoLoading = $false
$CardsScroll.Add_ScrollChanged({
    if ($script:AutoLoading) { return }
    $sv = $CardsScroll
    if ($sv.ScrollableHeight -le 0) { return }
    if (($sv.VerticalOffset + $sv.ViewportHeight) -lt ($sv.ScrollableHeight - 80)) { return }
    if ($script:LastTotal -and $script:ShowLimit -lt $script:LastTotal) {
        $script:AutoLoading = $true
        $script:ShowLimit = $script:ShowLimit + 60
        try { Render-Cards } catch { }
        $script:AutoLoading = $false
    }
})
$FixKeys.Add_Click({
    if (-not $script:KeyRows) { return }
    Update-KeyConflicts
    $fixed = 0
    foreach ($r in $script:KeyRows) {
        if ($r.conflict -and $r.suggest) {
            $r.box.Text = $r.suggest
            $fixed++
        }
    }
    if ($fixed -eq 0) { $Status.Text = "没有需要修复的冲突"; return }
    Update-KeyConflicts
    $Status.Text = "✅ 已为 $fixed 处冲突填入推荐按键（检查后点「保存按键到皮肤库」）"
})

$SaveKeys.Add_Click({
    if (-not $script:KeyRows -or $script:KeyRows.Count -eq 0) { return }
    $changed = 0
    $byFile = @{}
    foreach ($r in $script:KeyRows) {
        $newSpec = $r.box.Text.Trim()
        if (-not $newSpec -or $newSpec -eq $r.entry.spec) { continue }
        $p = $r.entry.path
        if (-not $byFile.ContainsKey($p)) {
            $byFile[$p] = @(Get-Content -LiteralPath $p -Encoding UTF8)
        }
        $byFile[$p][$r.entry.line] = $r.entry.prefix + $newSpec
        $r.entry.spec = $newSpec
        $changed++
    }
    if ($changed -eq 0) { $Status.Text = "没有改动"; return }
    foreach ($p in $byFile.Keys) {
        Copy-Item -LiteralPath $p -Destination ($p + '.bak') -Force
        [IO.File]::WriteAllLines($p, [string[]]$byFile[$p], (New-Object Text.UTF8Encoding($false)))
    }
    $script:KeyCache = @{}
    $Status.Text = "✅ 已保存 $changed 处按键改动（原文件已备份 .bak）。点「装到…」重装后生效。"
})

$ImpBtn.Add_Click({
    $p = $ImpPath.Text.Trim()
    if (-not $p) { $Status.Text = "请先粘贴外部 Mod 的文件夹路径"; return }
    $r = Import-Skin $script:CurChar $p
    $Status.Text = $r
    if ($r -like '✅*') {
        $script:Index = Get-Index
        Render-Cards
        $ImpPath.Text = ""
    }
})

$RefreshBtn.Add_Click({
    $Status.Text = "正在重建索引…（皮肤多时需要几十秒，请勿关闭窗口）"
    try { $Status.Dispatcher.Invoke([Action] { }, 'Background') } catch { }
    Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
    $script:ForceRebuild = $true
    try {
        $script:Index = Get-Index
    } finally {
        $script:ForceRebuild = $false
    }
    $script:Installed = Get-InstalledMap
    try {
        $CharList.Items.Clear()
    [void]$CharList.Items.Add('★ 全部角色')
        $script:CurChar = $null
$script:PageSize = 60
$script:ShownCount = 60
        foreach ($k in ($script:Index.Keys | Sort-Object)) { [void]$CharList.Items.Add($k) }
        if ($CharList.Items.Count -gt 0) { $CharList.SelectedIndex = 0 }
    } catch { }
    Render-Cards
    $Status.Text = "索引已刷新：$($script:Index.Keys.Count) 个角色 / $(($script:Index.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) 套"
})

    [void]$CharList.Items.Add('★ 全部角色')
foreach ($k in ($script:Index.Keys | Sort-Object)) { [void]$CharList.Items.Add($k) }
# 启动不自动选角色，避免一开就渲染导致卡顿（点角色后才渲染）

function Set-ToggleVisual([bool]$on) { }

$script:TfrReady = $false
$tfrNow = Get-TfrEnabled
Set-ToggleVisual $tfrNow
$TfrToggle.IsChecked = $tfrNow
$script:TfrReady = $true
Load-UiState
$script:UiReady = $true
# 启动后默认选中「★ 全部角色」，直接显示全库
if ($CharList.Items.Count -gt 0) {
    $CharList.SelectedIndex = 0
    try { Render-Cards } catch { }
}
$TfrHint.Text = if (Test-Path -LiteralPath $script:TfrIni) { "WuwaTFR · 下次启动生效" } else { "未检测到 WuwaTFR" }

$TfrToggle.Add_Checked({
    if (-not $script:TfrReady) { return }
    Set-ToggleVisual $true
    $r = Set-Tfr $true
    $TfrHint.Text = "已开启 · 下次启动生效"
    $Status.Text = "反虚化：" + $r.sync.msg
})
$TfrToggle.Add_Unchecked({
    if (-not $script:TfrReady) { return }
    Set-ToggleVisual $false
    $r = Set-Tfr $false
    $TfrHint.Text = "已关闭 · 下次启动生效"
    $Status.Text = "反虚化：" + $r.sync.msg
})

$Status.Text = "就绪。左上可开关反虚化；左侧选角色，中间选皮肤，右侧看详情与安装。"
[void]$win.ShowDialog()

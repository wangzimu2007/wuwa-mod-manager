# 批量导入整合包 Mod → 副库（F 盘）
# 源：E:\...\整合包_现在或者以后\_解压\鸣潮mod\鸣潮\mods\*.7z（内层加密，密码 Neon2014611332）
# 目标：F:\GameMods\WWMI-Mods\Skins\<角色>\<NNN>_<包名>\（带 preview.png）
# 日志：源目录下 _import_log2.csv

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$packRoot  = 'E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮'
$srcMods   = Join-Path $packRoot 'mods'
$srcThumb  = Join-Path $packRoot 'thumbnail'
$libRoot   = 'F:\GameMods\WWMI-Mods\Skins'
$tmpRoot   = "$env:TEMP\pack_import2"
$7za       = 'D:\tools\7zr\7za.exe'
$packPw    = 'Neon2014611332'
$logPath   = Join-Path $srcMods '_import_log2.csv'
$minFreeGb = 30

# 角色名归一化（包内前缀 → 正式名）
$charFix = @{
    '心' = '心月狐'; '洛瑟拉' = '洛瑟菈'; '爱弥丝' = '爱弥斯'
    '科考摩托' = '科考摩托（载具）'; '锁暝' = '锁暝'; '莫宁' = '莫宁'
}

if (-not (Test-Path -LiteralPath $libRoot)) { New-Item -ItemType Directory -Path $libRoot -Force | Out-Null }
if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

function Sanitize([string]$s) {
    $t = $s -replace '[\\/:*?"<>|]', '_'
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt 56) { $t = $t.Substring(0, 56) }
    if (-not $t) { $t = 'mod' }
    return $t
}

$counters = @{}
function Next-Num([string]$char) {
    if (-not $counters.ContainsKey($char)) {
        $dir = Join-Path $libRoot $char
        $max = 0
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match '^(\d+)_') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
            }
        }
        $counters[$char] = $max
    }
    $counters[$char]++
    return $counters[$char]
}

$files = @(Get-ChildItem -LiteralPath $srcMods -File -Filter '*.7z' | Sort-Object Name)
[IO.File]::WriteAllText($logPath, "name,char,guid,status,size_mb`r`n", (New-Object Text.UTF8Encoding($true)))

$ok = 0; $fail = 0; $idx = 0
foreach ($f in $files) {
    $idx++
    $freeGb = [Math]::Round((Get-PSDrive -Name F).Free / 1GB, 1)
    if ($freeGb -lt $minFreeGb) {
        Write-Host "F 盘剩余 $freeGb GB，低于 $minFreeGb GB，停止导入"
        break
    }
    $base = $f.BaseName
    $char = ($base -split '[-_]')[0].Trim()
    if ($charFix.ContainsKey($char)) { $char = $charFix[$char] }
    if (-not $char) { $char = '其他' }
    $work = Join-Path $tmpRoot ("p" + $idx)
    $status = 'fail'; $guid = ''
    try {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $null = & $7za x $f.FullName "-o$work" "-p$packPw" -y 2>&1
        if ($LASTEXITCODE -ne 0) { throw "7za 失败($LASTEXITCODE)" }

        # 内容根：优先找含 mod.ini 的目录（最多下探两层）
        $inis = @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter '*.ini' -ErrorAction SilentlyContinue)
        if ($inis.Count -eq 0) { throw '没有 ini' }
        $roots = @($inis | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
        $src = $work
        if ($roots.Count -eq 1) {
            $src = $roots[0]
        } elseif ((Get-ChildItem -LiteralPath $work).Count -eq 1) {
            $src = (Get-ChildItem -LiteralPath $work)[0].FullName
        }
        # 若 src 下没有 mod.ini 但有 mod-自动生成.ini → 造一个 mod.ini
        $mainIni = Get-ChildItem -LiteralPath $src -File -Filter 'mod.ini' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $mainIni) {
            $auto = Get-ChildItem -LiteralPath $src -File -Include 'mod-自动生成.ini','mod*.ini' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($auto) {
                Copy-Item -LiteralPath $auto.FullName -Destination (Join-Path $src 'mod.ini') -Force
                $mainIni = Get-Item -LiteralPath (Join-Path $src 'mod.ini')
            }
        }
        if ($mainIni) {
            $m = Select-String -LiteralPath $mainIni.FullName -Pattern 'object_guid\s*=\s*(\d+)' | Select-Object -First 1
            if ($m) { $guid = $m.Matches[0].Groups[1].Value }
        }

        $charDir = Join-Path $libRoot $char
        if (-not (Test-Path -LiteralPath $charDir)) { New-Item -ItemType Directory -Path $charDir -Force | Out-Null }
        $num = Next-Num $char
        $dst = Join-Path $charDir ('{0:D3}_{1}' -f $num, (Sanitize $base))
        if (Test-Path -LiteralPath $dst) { $dst = $dst + '_' + $idx }
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Get-ChildItem -LiteralPath $src | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force }

        $thumb = Join-Path $srcThumb ($base + '.png')
        if (Test-Path -LiteralPath $thumb) { Copy-Item -LiteralPath $thumb -Destination (Join-Path $dst 'preview.png') -Force }

        Get-ChildItem -LiteralPath $dst -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.BAK$' } | Remove-Item -Force -ErrorAction SilentlyContinue

        # 检测 ini 里是否有 "../" 这类跨目录引用（若有，贴图可能不全，标记 needmerge）
        $iniAtRoot = Join-Path $dst 'mod.ini'
        if (Test-Path -LiteralPath $iniAtRoot) {
            $upRefs = (Select-String -LiteralPath $iniAtRoot -Pattern '\.\./' -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($upRefs -gt 0) { $status = 'needmerge' } else { $status = 'ok' }
        } else { $status = 'ok' }
        $ok++
    } catch {
        $status = 'fail'; $fail++
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Add-Content -LiteralPath $logPath -Value ('"{0}","{1}","{2}","{3}",{4}' -f ($base -replace '"', "'"), $char, $guid, $status, [Math]::Round($f.Length / 1MB, 1)) -Encoding UTF8
    if ($idx % 20 -eq 0) { Write-Host "进度 $idx/$($files.Count)  成功 $ok  失败 $fail  F盘剩余 $freeGb GB" }
}

Write-Host "完成：共 $($files.Count)，成功 $ok，失败 $fail"
Write-Host "日志：$logPath"

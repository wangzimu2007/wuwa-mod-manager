# 批量导入整合包里的 Mod 到皮肤库
# 输入：E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮\mods\*.7z
# 输出：Skins\<角色>\<NNN>_<包名>\  （带 preview.png）
# 日志：同一目录下的 _import_log.csv

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$packMods = 'E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮\mods'
$packThumb = 'E:\GameMods\WWMI-Mods\Downloads\整合包_现在或者以后\_解压\鸣潮mod\鸣潮\thumbnail'
$libRoot = 'E:\GameMods\WWMI-Mods\Skins'
$tmpRoot = "$env:TEMP\pack_import"
$7za = 'D:\tools\7zr\7za.exe'
$logPath = Join-Path $packMods '_import_log.csv'

if (-not (Test-Path -LiteralPath $libRoot)) { throw "皮肤库不存在：$libRoot" }
if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

function Sanitize([string]$s) {
    $t = $s -replace '[\\/:*?"<>|]', '_'
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt 60) { $t = $t.Substring(0, 60) }
    if (-not $t) { $t = 'mod' }
    return $t
}

# 每个角色目录维护下一个编号
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

$files = Get-ChildItem -LiteralPath $packMods -File -Filter '*.7z' | Sort-Object Name
[IO.File]::WriteAllText($logPath, "name,char,guid,status,size_mb`r`n", (New-Object Text.UTF8Encoding($true)))

$ok = 0; $fail = 0; $skip = 0
$idx = 0
foreach ($f in $files) {
    $idx++
    $base = $f.BaseName
    $char = ($base -split '[-_]')[0].Trim()
    if (-not $char) { $char = '其他' }
    $work = Join-Path $tmpRoot ("p" + $idx)
    $status = 'fail'; $guid = ''
    try {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $null = & $7za x $f.FullName "-o$work" -y 2>&1
        if ($LASTEXITCODE -ne 0) { throw "7za 解压失败($LASTEXITCODE)" }

        # 找内容根：若只有一个子目录则进一层
        $tops = @(Get-ChildItem -LiteralPath $work)
        $root = $work
        if ($tops.Count -eq 1 -and $tops[0].PSIsContainer) { $root = $tops[0].FullName }

        # 找 ini
        $inis = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ini' -ErrorAction SilentlyContinue)
        if ($inis.Count -eq 0) { throw '没有 ini，不是 WWMI Mod' }
        $mainIni = $inis | Where-Object { $_.Name -eq 'mod.ini' } | Select-Object -First 1
        if (-not $mainIni) {
            $auto = $inis | Where-Object { $_.Name -match '^mod.*\.ini$' } | Select-Object -First 1
            if ($auto) {
                Copy-Item -LiteralPath $auto.FullName -Destination (Join-Path $root 'mod.ini') -Force
                $mainIni = Get-Item -LiteralPath (Join-Path $root 'mod.ini')
            } else { throw '没有 mod.ini / mod-自动生成.ini' }
        }
        $m = Select-String -LiteralPath $mainIni.FullName -Pattern 'object_guid\s*=\s*(\d+)' | Select-Object -First 1
        if ($m) { $guid = $m.Matches[0].Groups[1].Value }

        # 目标目录
        $charDir = Join-Path $libRoot $char
        if (-not (Test-Path -LiteralPath $charDir)) { New-Item -ItemType Directory -Path $charDir -Force | Out-Null }
        $num = Next-Num $char
        $dst = Join-Path $charDir ('{0:D3}_{1}' -f $num, (Sanitize $base))
        if (Test-Path -LiteralPath $dst) { $dst = $dst + '_' + $idx }
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Get-ChildItem -LiteralPath $root | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force }

        # 预览图
        $thumb = Join-Path $packThumb ($base + '.png')
        if (Test-Path -LiteralPath $thumb) { Copy-Item -LiteralPath $thumb -Destination (Join-Path $dst 'preview.png') -Force }

        # 清理作者 BAK
        Get-ChildItem -LiteralPath $dst -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.BAK$' } | Remove-Item -Force -ErrorAction SilentlyContinue

        $status = 'ok'; $ok++
    } catch {
        $status = 'fail'; $fail++
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $sizeMb = [Math]::Round($f.Length / 1MB, 1)
    Add-Content -LiteralPath $logPath -Value ('"{0}","{1}","{2}","{3}",{4}' -f ($base -replace '"', "'"), $char, $guid, $status, $sizeMb) -Encoding UTF8
    if ($idx % 25 -eq 0) { Write-Host "进度 $idx/$($files.Count)  成功 $ok  失败 $fail" }
}

Write-Host "完成：$($files.Count) 个，成功 $ok，失败 $fail"
Write-Host "日志：$logPath"

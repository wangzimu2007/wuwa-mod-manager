param(
    [string]$Char = "卡提希娅",
    [string]$Root = "F:\QuarkDownload\鸣潮美化包\d3dx版\【可选增量】\【往期】v1.0~3.6增量合集\【往期】v1.0~3.6增量合集",
    [string]$OutDir = "E:\GameMods\WWMI-Mods\使用记录\鸣潮\整合包预览\卡提希娅"
)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.IO;
public class Scan7zB {
    static readonly byte[] M = { 0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C };
    public static List<long> Scan(string path) {
        var hits = new List<long>();
        int bufSize = 8 * 1024 * 1024;
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1<<20, FileOptions.SequentialScan)) {
            var buf = new byte[bufSize + 8];
            long baseOff = 0; int read;
            while ((read = fs.Read(buf, 0, bufSize)) > 0) {
                for (int i = 0; i <= read - 6; i++)
                    if (buf[i]==M[0]&&buf[i+1]==M[1]&&buf[i+2]==M[2]&&buf[i+3]==M[3]&&buf[i+4]==M[4]&&buf[i+5]==M[5])
                        hits.Add(baseOff + i);
                baseOff += read;
            }
        }
        return hits;
    }
}
"@
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(65001)
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$picDir = Join-Path $OutDir "previews"
$readDir = Join-Path $OutDir "readmes"
New-Item -ItemType Directory -Path $picDir -Force | Out-Null
New-Item -ItemType Directory -Path $readDir -Force | Out-Null
$log = Join-Path $OutDir "_log.txt"
$sevenZr = "D:\tools\7zr\7zr.exe"
$tmpWin = Join-Path $env:TEMP "_cwin.7z"
$tmpEx = Join-Path $env:TEMP "_cext"
$idx = 0
$index = @()

$c = Get-Item (Join-Path $Root $Char)
foreach ($bin in (Get-ChildItem $c.FullName -Filter *.bin | Sort-Object Name)) {
    $hits = [Scan7zB]::Scan($bin.FullName)
    for ($i = 0; $i -lt $hits.Count; $i++) {
        $start = [long]$hits[$i]
        $stop = if ($i + 1 -lt $hits.Count) { [long]$hits[$i+1] + 2MB } else { [long]$bin.Length }
        $len = [Math]::Min($stop - $start, 512MB)
        $src = [IO.File]::OpenRead($bin.FullName); [void]$src.Seek($start,'Begin')
        $dst = [IO.File]::Create($tmpWin); $remain = $len; $buf = New-Object byte[] (4MB)
        while ($remain -gt 0) { $n = $src.Read($buf,0,[Math]::Min($buf.Length,$remain)); if ($n -le 0) { break }; $dst.Write($buf,0,$n); $remain -= $n }
        $dst.Close(); $src.Close()
        # 取名字
        $list = & $sevenZr l $tmpWin 2>$null
        $name = ""
        foreach ($line in $list) {
            if ($line -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+D\.\.\.\.') {
                $nm = ($line -replace '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+D\.\.\.\.\s+\d+\s+\d+\s+', '').Trim()
                if ($nm -and $nm -notmatch '\\') { $name = $nm; break }
            }
        }
        if (-not $name) { continue }
        $idx++
        $safe = ($name -replace '[\\/:*?"<>|]', '_')
        if ($safe.Length -gt 80) { $safe = $safe.Substring(0,80) }
        # 解任意 preview.* 与 read.txt / 说明
        Remove-Item $tmpEx -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $tmpEx -Force | Out-Null
        & $sevenZr x $tmpWin "-o$tmpEx" "*.jpg" "*.png" "*.txt" -r -y 2>$null | Out-Null
        $prev = Get-ChildItem $tmpEx -Recurse -File -Include *.jpg,*.png | Where-Object { $_.Name -match 'preview' } | Select-Object -First 1
        if ($prev) { Copy-Item $prev.FullName (Join-Path $picDir ("{0:D3}_{1}{2}" -f $idx, $safe, $prev.Extension)) -Force }
        $rd = Get-ChildItem $tmpEx -Recurse -File -Include *.txt | Select-Object -First 1
        if ($rd) { Copy-Item $rd.FullName (Join-Path $readDir ("{0:D3}_{1}.txt" -f $idx, $safe)) -Force }
        $index += [pscustomobject]@{ Index=$idx; Name=$name; Preview=[bool]$prev; Readme=[bool]$rd }
    }
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'HH:mm:ss') $($bin.Name) 完成，累计 $idx"
}
$index | Export-Csv (Join-Path $OutDir "_index.csv") -Encoding UTF8
Remove-Item $tmpWin,$tmpEx -Recurse -Force -ErrorAction SilentlyContinue
Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'HH:mm:ss') 全部完成：$idx 个"
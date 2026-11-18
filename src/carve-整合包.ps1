param(
    [switch]$All,
    [string[]]$Chars,
    [string]$Root = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_config.ps1')
$cfg = Get-Cfg
if (-not $Root) { $Root = $cfg.packDir }
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'skin-lists' }
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.IO;
public class Scan7z {
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

[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)
$OutputEncoding = [Text.Encoding]::GetEncoding(936)

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$log = Join-Path $OutDir "_log.txt"
function Log([string]$m) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $m"
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}
$sevenZr = "D:\tools\7zr\7zr.exe"
$tmp = Join-Path $env:TEMP "_carve_win.7z"

$targets = if ($All) { Get-ChildItem $Root -Directory | Sort-Object { (Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum } } else {
  $Chars | ForEach-Object { Get-Item (Join-Path $Root $_) }
}

foreach ($c in $targets) {
    $outFile = Join-Path $OutDir ($c.Name + ".txt")
    if (Test-Path $outFile) { Log "[跳过] $($c.Name) 已有清单"; continue }
    $bins = Get-ChildItem $c.FullName -Filter *.bin | Sort-Object Name
    if (-not $bins) { Log "[跳过] $($c.Name) 无 bin"; continue }
    Log "[开始] $($c.Name)  bins=$($bins.Count)"
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($bin in $bins) {
        $hits = [Scan7z]::Scan($bin.FullName)
        for ($i = 0; $i -lt $hits.Count; $i++) {
            $start = [long]$hits[$i]
            $stop = if ($i + 1 -lt $hits.Count) { [long]$hits[$i+1] + 2MB } else { [long]$bin.Length }
            $len = [Math]::Min($stop - $start, 512MB)
            try {
                $src = [IO.File]::OpenRead($bin.FullName)
                [void]$src.Seek($start, 'Begin')
                $dst = [IO.File]::Create($tmp)
                $remain = $len; $buf = New-Object byte[] (4MB)
                while ($remain -gt 0) {
                    $n = $src.Read($buf, 0, [Math]::Min($buf.Length, $remain))
                    if ($n -le 0) { break }
                    $dst.Write($buf, 0, $n); $remain -= $n
                }
                $dst.Close(); $src.Close()
                $list = & $sevenZr l $tmp 2>$null
                foreach ($line in $list) {
                    if ($line -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+D\.\.\.\.') {
                        $name = ($line -replace '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+D\.\.\.\.\s+\d+\s+\d+\s+', '').Trim()
                        if ($name -and $name -notmatch '\\' -and -not $names.Contains($name)) { $names.Add($name) }
                    }
                }
            } catch { Log "  错误 偏移 $start : $($_.Exception.Message)" }
        }
        Log "  bin $($bin.Name) 完成，累计 $($names.Count)"
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $names | Sort-Object -Unique | Set-Content -LiteralPath $outFile -Encoding UTF8
    Log "[完成] $($c.Name) -> $($names.Count) 条"
}
Log "全部结束"
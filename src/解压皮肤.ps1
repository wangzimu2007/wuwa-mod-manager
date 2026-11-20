param(
    [string]$Char = "卡提希娅",
    [string]$Root = "F:\QuarkDownload\鸣潮美化包\d3dx版\【可选增量】\【往期】v1.0~3.6增量合集\【往期】v1.0~3.6增量合集",
    [string]$OutDir = "E:\GameMods\WWMI-Mods\Skins"
)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.IO;
public class S9 {
    static readonly byte[] M = { 0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C };
    public static List<long> Scan(string p) {
        var h = new List<long>(); int bs = 8*1024*1024;
        using (var fs = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.Read, 1<<20, FileOptions.SequentialScan)) {
            var b = new byte[bs+8]; long o = 0; int r;
            while ((r = fs.Read(b,0,bs)) > 0) {
                for (int i=0;i<=r-6;i++) if (b[i]==M[0]&&b[i+1]==M[1]&&b[i+2]==M[2]&&b[i+3]==M[3]&&b[i+4]==M[4]&&b[i+5]==M[5]) h.Add(o+i);
                o += r;
            }
        }
        return h;
    }
}
"@
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)
$target = Join-Path $OutDir $Char
New-Item -ItemType Directory -Path $target -Force | Out-Null
$log = Join-Path $OutDir "_extract_log.txt"
$sevenZr = "D:\tools\7zr\7zr.exe"
$tmpWin = Join-Path $env:TEMP "_ewin.7z"
$tmpDir = Join-Path $env:TEMP "_eext"
$idx = 0
$junk = @('Meshes','Textures','UI','Shader','preview','Text','res','0','daka','xiaka','xk','carte','puppet','Weapon','weapon','sword','Main','Picture')
$c = Get-Item (Join-Path $Root $Char)
foreach ($bin in (Get-ChildItem $c.FullName -Filter *.bin | Sort-Object Name)) {
    $hits = [S9]::Scan($bin.FullName)
    for ($i = 0; $i -lt $hits.Count; $i++) {
        $start = [long]$hits[$i]
        $stop = if ($i + 1 -lt $hits.Count) { [long]$hits[$i+1] + 2MB } else { [long]$bin.Length }
        $len = [Math]::Min($stop - $start, 512MB)
        $src = [IO.File]::OpenRead($bin.FullName); [void]$src.Seek($start,'Begin')
        $dst = [IO.File]::Create($tmpWin); $remain = $len; $buf = New-Object byte[] (4MB)
        while ($remain -gt 0) { $n = $src.Read($buf,0,[Math]::Min($buf.Length,$remain)); if ($n -le 0) { break }; $dst.Write($buf,0,$n); $remain -= $n }
        $dst.Close(); $src.Close()
        $list = & $sevenZr l $tmpWin 2>$null
        $name = ""
        foreach ($line in $list) {
            if ($line -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+D\.\.\.\.') {
                $nm = ($line -replace '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+D\.\.\.\.\s+\d+\s+\d+\s+', '').Trim()
                if ($nm -and $nm -notmatch '\\') { $name = $nm; break }
            }
        }
        if (-not $name -or $junk -contains $name) { continue }
        $idx++
        $safe = ($name -replace '[\\/:*?"<>|]', '_'); if ($safe.Length -gt 70) { $safe = $safe.Substring(0,70) }
        $destDir = Join-Path $target ("{0:D3}_{1}" -f $idx, $safe)
        if ((Test-Path -LiteralPath $destDir) -and ((Get-ChildItem -LiteralPath $destDir -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0)) { continue }
        if (Test-Path -LiteralPath $destDir) { Remove-Item -LiteralPath $destDir -Recurse -Force }
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        & $sevenZr x $tmpWin "-o$tmpDir" -y 2>$null | Out-Null
        [IO.Directory]::Move($tmpDir, $destDir)
        Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'HH:mm:ss') $idx $name"
    }
}
Remove-Item $tmpWin -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'HH:mm:ss') done $idx"
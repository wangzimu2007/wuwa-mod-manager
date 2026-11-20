# 生成皮肤总表：CSV + 可搜索 HTML
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$lib  = 'F:\GameMods\WWMI-Mods\Skins'
$outDir = 'E:\GameMods\WWMI-Mods\使用记录\鸣潮'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$rows = New-Object System.Collections.ArrayList
$chars = @(Get-ChildItem -LiteralPath $lib -Directory | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)

foreach ($c in $chars) {
    $subs = @(Get-ChildItem -LiteralPath $c.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($s in $subs) {
        $inis = @(Get-ChildItem -LiteralPath $s.FullName -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notmatch '\.bak|\.off|\.bak-' })
        $guids = New-Object System.Collections.Generic.HashSet[string]
        $keyCount = 0
        $keyList = New-Object System.Collections.ArrayList
        $hasPanel = $false
        $hasRabbitFX = $false
        $wwmiVer = ''
        foreach ($ini in $inis) {
            $txt = [IO.File]::ReadAllText($ini.FullName, [Text.Encoding]::UTF8)
            foreach ($m in [regex]::Matches($txt, 'object_guid\s*=\s*(\d+)')) { [void]$guids.Add($m.Groups[1].Value) }
            if ($txt -match 'RabbitFX\\SetTextures|RabbitFX\s*=|\bRabbitFX\b') { $hasRabbitFX = $true }
            if (-not $wwmiVer -and $txt -match 'required_wwmi_version\s*=\s*([\d.]+)') { $wwmiVer = $Matches[1] }
            if ($ini.Name -match '(?i)ui') { $hasPanel = $true }
            # 统计 Key 段里的 key 行
            $sec = ''
            foreach ($ln in ($txt -split "`r?`n")) {
                $t = $ln.Trim()
                if ($t -match '^\[(.+?)\]') { $sec = $Matches[1]; continue }
                if ($sec -match '(?i)^key' -and $t -match '^key\s*=\s*(.+)$') {
                    $keyCount++
                    $k = $Matches[1].Trim()
                    if ($keyList.Count -lt 12 -and -not $keyList.Contains($k)) { [void]$keyList.Add($k) }
                }
            }
            if (-not $hasPanel -and $txt -match 'enable_mods') {
                # 有开关变量但没有 ButtonUI 的情况不算面板
            }
        }
        $panelIni = Get-ChildItem -LiteralPath $s.FullName -Recurse -File -Filter '*.ini' -ErrorAction SilentlyContinue |
                    Where-Object { $_.DirectoryName -match '(?i)UI' -and $_.Name -notmatch '\.bak|\.off' } | Select-Object -First 1
        if ($panelIni) { $hasPanel = $true }

        $sizeMB = [Math]::Round(((Get-ChildItem -LiteralPath $s.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)/1MB, 1)
        $num = 0
        if ($s.Name -match '^(\d+)_') { $num = [int]$Matches[1] }
        $nameOnly = $s.Name -replace '^\d+_', ''

        [void]$rows.Add([pscustomobject]@{
            char    = $c.Name
            num     = '{0:D3}' -f $num
            name    = $nameOnly
            forms   = $guids.Count
            keys    = $keyCount
            panel   = $(if ($hasPanel) { '有' } else { '' })
            rabbitfx = $(if ($hasRabbitFX) { '有' } else { '' })
            wwmi    = $wwmiVer
            sizeMB  = $sizeMB
            keysPreview = ($keyList -join ' ')
            dir     = $s.FullName
        })
    }
    Write-Host ("[{0}] 完成，累计 {1} 条" -f $c.Name, $rows.Count)
}

# CSV（带 BOM，Excel 直接打开不乱码）
$csv = Join-Path $outDir '皮肤总表.csv'
$rows | Select-Object char, num, name, forms, keys, panel, rabbitfx, wwmi, sizeMB, keysPreview, dir |
    Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Host "CSV：$csv"

# HTML（可搜索/排序/筛选）
$json = ($rows | Select-Object char, num, name, forms, keys, panel, rabbitfx, sizeMB, keysPreview, dir |
         ConvertTo-Json -Depth 4 -Compress)
$html = @'
<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>鸣潮 Mod 皮肤总表</title>
<style>
  body{background:#0f1116;color:#e6eaf2;font:14px/1.6 "Microsoft YaHei",system-ui;margin:0;padding:18px}
  h1{font-size:20px;margin:0 0 12px;color:#9fd0ff}
  .bar{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px;align-items:center}
  input,select{background:#171b24;color:#e6eaf2;border:1px solid #2a3040;border-radius:6px;padding:6px 10px;font-size:13px}
  input[type=text]{width:280px}
  .stat{color:#8b93a3;font-size:12px;margin-left:auto}
  table{border-collapse:collapse;width:100%}
  th,td{border-bottom:1px solid #222836;padding:6px 8px;text-align:left;vertical-align:top}
  th{position:sticky;top:0;background:#161a23;color:#9fd0ff;cursor:pointer;user-select:none;font-weight:600}
  tr:hover td{background:#151a24}
  .tag{display:inline-block;padding:1px 6px;border-radius:4px;font-size:11px;margin-right:4px}
  .t-form{background:#1d3350;color:#9fc6ff}
  .t-key{background:#1d3d24;color:#8ee29a}
  .t-panel{background:#3d2a1b;color:#ffc078}
  .t-fx{background:#33203d;color:#d9a6ff}
  .mono{font-family:Consolas,monospace;font-size:12px;color:#a7b1c2}
  .dir{color:#5d6577;font-size:11px}
</style></head><body>
<h1>鸣潮 Mod 皮肤总表</h1>
<div class="bar">
  <input type="text" id="q" placeholder="搜索：角色 / 名称 / 按键，例如 心月狐、双形态、VK_UP">
  <select id="fc"><option value="">全部角色</option></select>
  <select id="ff"><option value="">全部形态</option><option value="1">单形态</option><option value="2">双形态</option><option value="3">三形态+</option></select>
  <select id="fk"><option value="">按键</option><option value="0">无按键</option><option value="1">1~5 键</option><option value="2">6~10 键</option><option value="3">10+ 键</option></select>
  <select id="fp"><option value="">面板</option><option value="1">有面板</option></select>
  <span class="stat" id="stat"></span>
</div>
<table><thead><tr>
  <th data-k="char">角色</th><th data-k="num">编号</th><th data-k="name">名称</th>
  <th data-k="forms">形态</th><th data-k="keys">按键数</th><th data-k="panel">面板</th>
  <th data-k="sizeMB">大小MB</th><th data-k="keysPreview">按键预览</th>
</tr></thead><tbody id="tb"></tbody></table>
<script>
const DATA = __DATA__;
const tb = document.getElementById('tb'), stat = document.getElementById('stat');
const q = document.getElementById('q'), fc = document.getElementById('fc'), ff = document.getElementById('ff'), fk = document.getElementById('fk'), fp = document.getElementById('fp');
let sortKey = 'char', sortAsc = true;

// 角色下拉
[...new Set(DATA.map(d => d.char))].sort().forEach(c => {
  const o = document.createElement('option'); o.value = c; o.textContent = c; fc.appendChild(o);
});

function esc(s){ return String(s ?? '').replace(/[&<>]/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[m])); }

function render(){
  const kw = q.value.trim().toLowerCase();
  let list = DATA.filter(d => {
    if (fc.value && d.char !== fc.value) return false;
    if (ff.value === '1' && d.forms !== 1) return false;
    if (ff.value === '2' && d.forms !== 2) return false;
    if (ff.value === '3' && d.forms < 3) return false;
    if (fk.value === '0' && d.keys !== 0) return false;
    if (fk.value === '1' && (d.keys < 1 || d.keys > 5)) return false;
    if (fk.value === '2' && (d.keys < 6 || d.keys > 10)) return false;
    if (fk.value === '3' && d.keys <= 10) return false;
    if (fp.value === '1' && d.panel !== '有') return false;
    if (kw) {
      const hay = (d.char + ' ' + d.name + ' ' + d.keysPreview).toLowerCase();
      if (!hay.includes(kw)) return false;
    }
    return true;
  });
  list.sort((a,b) => {
    let x = a[sortKey], y = b[sortKey];
    if (typeof x === 'number' && typeof y === 'number') return sortAsc ? x-y : y-x;
    x = String(x); y = String(y);
    return sortAsc ? x.localeCompare(y,'zh') : y.localeCompare(x,'zh');
  });
  stat.textContent = `显示 ${list.length} / 共 ${DATA.length} 套`;
  tb.innerHTML = list.map(d => `<tr>
    <td>${esc(d.char)}</td><td class="mono">${esc(d.num)}</td><td>${esc(d.name)}</td>
    <td>${d.forms>1?`<span class="tag t-form">${d.forms} 形态</span>`:''}</td>
    <td>${d.keys>0?`<span class="tag t-key">${d.keys} 键</span>`:'<span class="mono">无</span>'}</td>
    <td>${d.panel?`<span class="tag t-panel">面板</span>`:''}</td>
    <td class="mono">${d.sizeMB}</td>
    <td class="mono">${esc(d.keysPreview)}</td>
  </tr>`).join('');
}
document.querySelectorAll('th').forEach(th => th.onclick = () => {
  const k = th.dataset.k;
  if (sortKey === k) sortAsc = !sortAsc; else { sortKey = k; sortAsc = true; }
  render();
});
[q,fc,ff,fk,fp].forEach(el => el.oninput = render);
render();
</script></body></html>
'@
$html = $html.Replace('__DATA__', $json)
$htmlPath = Join-Path $outDir '皮肤总表.html'
[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
Write-Host "HTML：$htmlPath"
Write-Host ("总条数：{0}" -f $rows.Count)

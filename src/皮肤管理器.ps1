Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$SkinsRoot = "E:\GameMods\WWMI-Mods\Skins"
$Char = "卡提希娅"
$Mods = "$env:APPDATA\XXMI Launcher\WWMI\Mods"
$CsvPath = Join-Path $SkinsRoot "卡提希娅\_gui_index.csv"
$Backup = Join-Path $SkinsRoot "_原版备份"
$map = @{ '211575' = 'Cartethyia'; '255876' = 'Fleurdelys' }

function Get-SkinInfo([string]$folder) {
    $dir = Join-Path (Join-Path $SkinsRoot $Char) $folder
    $prev = Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'preview' } | Select-Object -First 1
    $txt = Get-ChildItem -LiteralPath $dir -Recurse -File -Include *.txt -ErrorAction SilentlyContinue | Select-Object -First 1
    $body = ""
    if ($txt) { $body = (Get-Content -LiteralPath $txt.FullName -TotalCount 18 | Where-Object { $_.Trim() }) -join "`r`n" }
    return [pscustomobject]@{ Dir = $dir; Preview = $(if ($prev) { $prev.FullName } else { "" }); Text = $body }
}

function Install-Skin([string]$folder, [string]$bucket) {
    $dir = Join-Path (Join-Path $SkinsRoot $Char) $folder
    if (-not (Test-Path -LiteralPath $dir)) { return "找不到皮肤目录" }
    $inis = Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue
    $buckets = @{}
    foreach ($ini in $inis) {
        $m = Select-String -LiteralPath $ini.FullName -Pattern 'object_guid\s*=\s*(\d+)' | Select-Object -First 1
        if (-not $m) { continue }
        $b = $map[$m.Matches[0].Groups[1].Value]
        if (-not $b) { continue }
        if ($bucket -ne 'both' -and $b -ne $bucket) { continue }
        $k = "$b|$($ini.Directory.FullName)"
        if (-not $buckets.ContainsKey($k)) { $buckets[$k] = [pscustomobject]@{ Bucket = $b; Source = $ini.Directory } }
    }
    if ($buckets.Count -eq 0) { return "这套没有覆盖「$bucket」形态" }
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    $grouped = @{}
    foreach ($v in $buckets.Values) {
        if (-not $grouped.ContainsKey($v.Bucket)) { $grouped[$v.Bucket] = @() }
        $grouped[$v.Bucket] += $v.Source
    }
    foreach ($b in $grouped.Keys) {
        $cur = Join-Path $Mods $b
        $bak = Join-Path $Backup $b
        if ((Test-Path -LiteralPath $cur) -and -not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $cur -Destination $bak -Recurse -Force }
        if (Test-Path -LiteralPath $cur) { Remove-Item -LiteralPath $cur -Recurse -Force }
        New-Item -ItemType Directory -Path $cur -Force | Out-Null
        $src = $grouped[$b]
        if ($src.Count -eq 1) {
            foreach ($item in Get-ChildItem -LiteralPath $src[0].FullName) {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $cur $item.Name) -Recurse -Force
            }
        }
        else {
            foreach ($s in $src) { Copy-Item -LiteralPath $s.FullName -Destination (Join-Path $cur $s.Name) -Recurse -Force }
        }
    }
    return ("已安装：" + (($grouped.Keys | ForEach-Object { "$_($($grouped[$_].Count))" }) -join " + ") + "  → 回游戏按 F10")
}

function Restore-Original {
    if (-not (Test-Path -LiteralPath $Backup)) { return "没有备份" }
    foreach ($b in (Get-ChildItem -LiteralPath $Backup -Directory)) {
        $dst = Join-Path $Mods $b.Name
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath $b.FullName -Destination $dst -Recurse -Force
    }
    return "已恢复原版（Arelewd 等）→ 回游戏按 F10"
}

function Get-CurrentState {
    $parts = @()
    foreach ($f in @('Cartethyia', 'Fleurdelys')) {
        $p = Join-Path $Mods $f
        if (Test-Path -LiteralPath $p) {
            $n = (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue).Count
            $parts += "$f=$n 文件"
        }
        else { $parts += "$f=空" }
    }
    return ($parts -join "   ")
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "鸣潮皮肤管理器 - $Char"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 34)
$form.ForeColor = [System.Drawing.Color]::White

$search = New-Object System.Windows.Forms.TextBox
$search.Location = New-Object System.Drawing.Point(10, 10)
$search.Size = New-Object System.Drawing.Size(600, 26)
$search.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 46)
$search.ForeColor = [System.Drawing.Color]::White
$search.Font = New-Object System.Drawing.Font("Microsoft YaHei", 10)
$form.Controls.Add($search)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(10, 42)
$list.Size = New-Object System.Drawing.Size(600, 588)
$list.View = 'Details'
$list.FullRowSelect = $true
$list.MultiSelect = $false
$list.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 46)
$list.ForeColor = [System.Drawing.Color]::White
[void]$list.Columns.Add("编号", 56)
[void]$list.Columns.Add("名称", 330)
[void]$list.Columns.Add("形态", 90)
[void]$list.Columns.Add("档位", 90)
$form.Controls.Add($list)

$pic = New-Object System.Windows.Forms.PictureBox
$pic.Location = New-Object System.Drawing.Point(620, 10)
$pic.Size = New-Object System.Drawing.Size(530, 300)
$pic.SizeMode = 'Zoom'
$pic.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 22)
$form.Controls.Add($pic)

$info = New-Object System.Windows.Forms.TextBox
$info.Location = New-Object System.Drawing.Point(620, 318)
$info.Size = New-Object System.Drawing.Size(530, 250)
$info.Multiline = $true
$info.ScrollBars = 'Vertical'
$info.ReadOnly = $true
$info.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 46)
$info.ForeColor = [System.Drawing.Color]::White
$info.Font = New-Object System.Drawing.Font("Microsoft YaHei", 9)
$form.Controls.Add($info)

$btnC = New-Object System.Windows.Forms.Button
$btnC.Text = "应用到 卡提希娅"
$btnC.Location = New-Object System.Drawing.Point(620, 580)
$btnC.Size = New-Object System.Drawing.Size(170, 40)
$form.Controls.Add($btnC)

$btnF = New-Object System.Windows.Forms.Button
$btnF.Text = "应用到 芙露德莉斯"
$btnF.Location = New-Object System.Drawing.Point(800, 580)
$btnF.Size = New-Object System.Drawing.Size(170, 40)
$form.Controls.Add($btnF)

$btnB = New-Object System.Windows.Forms.Button
$btnB.Text = "双形态一起装"
$btnB.Location = New-Object System.Drawing.Point(980, 580)
$btnB.Size = New-Object System.Drawing.Size(170, 40)
$form.Controls.Add($btnB)

$btnR = New-Object System.Windows.Forms.Button
$btnR.Text = "恢复原版"
$btnR.Location = New-Object System.Drawing.Point(620, 628)
$btnR.Size = New-Object System.Drawing.Size(170, 36)
$form.Controls.Add($btnR)

$btnO = New-Object System.Windows.Forms.Button
$btnO.Text = "打开皮肤文件夹"
$btnO.Location = New-Object System.Drawing.Point(800, 628)
$btnO.Size = New-Object System.Drawing.Size(170, 36)
$form.Controls.Add($btnO)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(10, 640)
$status.Size = New-Object System.Drawing.Size(600, 60)
$status.ForeColor = [System.Drawing.Color]::LightGreen
$status.Font = New-Object System.Drawing.Font("Microsoft YaHei", 9)
$form.Controls.Add($status)

$rows = Import-Csv -LiteralPath $CsvPath
$i = 0
foreach ($r in $rows) {
    $lv = New-Object System.Windows.Forms.ListViewItem($r.编号)
    [void]$lv.SubItems.Add($r.名称)
    [void]$lv.SubItems.Add($r.覆盖)
    [void]$lv.SubItems.Add($(if ([int]$r.按键段 -gt 0) { "可调($($r.按键段))" } else { "固定" }))
    $lv.Tag = $r.编号
    [void]$list.Items.Add($lv)
    $i++
}

$script:currentRow = $null
$list.add_SelectedIndexChanged({
    if ($list.SelectedItems.Count -eq 0) { return }
    $num = $list.SelectedItems[0].Tag
    $row = $rows | Where-Object { $_.编号 -eq $num } | Select-Object -First 1
    $script:currentRow = $row
    $folder = (Get-ChildItem -LiteralPath (Join-Path $SkinsRoot $Char) -Directory | Where-Object { $_.Name -match "^$num" } | Select-Object -First 1).Name
    $inf = Get-SkinInfo $folder
    if ($inf.Preview) { try { $pic.Image = [System.Drawing.Image]::FromFile($inf.Preview) } catch { $pic.Image = $null } } else { $pic.Image = $null }
    $txt = "编号：$($row.编号)`r`n名称：$($row.名称)`r`n形态覆盖：$($row.覆盖)`r`n格式：$($row.格式)`r`n可调档位：$($row.按键段) 段`r`n`r`n"
    if ($row.覆盖 -eq '双形态') { $txt += "★ 这套同时包含两个形态，建议用「双形态一起装」`r`n`r`n" }
    elseif ($row.覆盖 -eq '卡提希娅') { $txt += "◇ 只覆盖小卡（卡提希娅形态）；开大时芙露德莉斯仍用原 Mod`r`n`r`n" }
    elseif ($row.覆盖 -eq '芙露德莉斯') { $txt += "◇ 只覆盖大卡（芙露德莉斯形态）`r`n`r`n" }
    if ($inf.Text) { $txt += "── 作者说明 ──`r`n$($inf.Text)" }
    $info.Text = $txt
})

$btnC.add_Click({
    if (-not $script:currentRow) { return }
    $num = $script:currentRow.编号
    $folder = (Get-ChildItem -LiteralPath (Join-Path $SkinsRoot $Char) -Directory | Where-Object { $_.Name -match "^$num" } | Select-Object -First 1).Name
    $status.Text = Install-Skin $folder 'Cartethyia'
    $status.Text += "`r`n当前：$(Get-CurrentState)"
})
$btnF.add_Click({
    if (-not $script:currentRow) { return }
    $num = $script:currentRow.编号
    $folder = (Get-ChildItem -LiteralPath (Join-Path $SkinsRoot $Char) -Directory | Where-Object { $_.Name -match "^$num" } | Select-Object -First 1).Name
    $status.Text = Install-Skin $folder 'Fleurdelys'
    $status.Text += "`r`n当前：$(Get-CurrentState)"
})
$btnB.add_Click({
    if (-not $script:currentRow) { return }
    $num = $script:currentRow.编号
    $folder = (Get-ChildItem -LiteralPath (Join-Path $SkinsRoot $Char) -Directory | Where-Object { $_.Name -match "^$num" } | Select-Object -First 1).Name
    $status.Text = Install-Skin $folder 'both'
    $status.Text += "`r`n当前：$(Get-CurrentState)"
})
$btnR.add_Click({ $status.Text = Restore-Original + "`r`n当前：" + (Get-CurrentState) })
$btnO.add_Click({
    if (-not $script:currentRow) { return }
    $num = $script:currentRow.编号
    $folder = (Get-ChildItem -LiteralPath (Join-Path $SkinsRoot $Char) -Directory | Where-Object { $_.Name -match "^$num" } | Select-Object -First 1).Name
    Start-Process explorer.exe (Join-Path (Join-Path $SkinsRoot $Char) $folder)
})

$search.add_TextChanged({
    $kw = $search.Text.Trim()
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($r in $rows) {
        if ($kw -ne '' -and $r.名称 -notmatch [regex]::Escape($kw) -and $r.编号 -notmatch [regex]::Escape($kw) -and $r.覆盖 -notmatch [regex]::Escape($kw)) { continue }
        $lv = New-Object System.Windows.Forms.ListViewItem($r.编号)
        [void]$lv.SubItems.Add($r.名称)
        [void]$lv.SubItems.Add($r.覆盖)
        [void]$lv.SubItems.Add($(if ([int]$r.按键段 -gt 0) { "可调($($r.按键段))" } else { "固定" }))
        $lv.Tag = $r.编号
        [void]$list.Items.Add($lv)
    }
    $list.EndUpdate()
})

$status.Text = "共 $($rows.Count) 套。上方可搜索名称/编号/形态。`r`n当前：$(Get-CurrentState)"
if ($list.Items.Count -gt 0) { $list.Items[0].Selected = $true; $list.Select() }
[void]$form.ShowDialog()
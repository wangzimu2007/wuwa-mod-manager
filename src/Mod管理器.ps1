# 鸣潮 Mod 管理器（WPF 桌面版）
# 参考 Vortex / Mod Organizer 2 的三栏布局：左角色、中卡片网格、右详情
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

. (Join-Path $PSScriptRoot '_config.ps1')
$cfg = Get-Cfg
$SkinsRoot = $cfg.skinsDir
$BackupRoot = Join-Path $SkinsRoot "_原版备份"
$ModsRoot = $cfg.modsDir
$CacheFile = Join-Path $SkinsRoot "_index_cache.json"
$GuidMap = @{ '211575' = '卡提希娅'; '255876' = '芙露德莉斯' }

function Get-IniGuids([string]$dir) {
    $guids = New-Object System.Collections.Generic.List[string]
    $keys = 0
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue | ForEach-Object {
        $txt = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
        $m = [regex]::Match($txt, 'object_guid\s*=\s*(\d+)')
        if ($m.Success -and -not $guids.Contains($m.Groups[1].Value)) { $guids.Add($m.Groups[1].Value) }
        $keys += ([regex]::Matches($txt, '(?m)^\s*\[Key')).Count
    }
    return @{ guids = $guids; keys = $keys }
}

function Find-Preview([string]$dir) {
    Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^preview' -and $_.Extension -match '\.(jpg|png|jpeg|webp)$' } |
        Select-Object -First 1 -ExpandProperty FullName
}

$script:ReadmeCache = @{}
$script:KeyCache = @{}

function Get-NormKey([string]$s) {
    if (-not $s) { return '' }
    return (($s -replace '\s+', ' ').Trim().ToLower())
}

function Get-FreeKey($used, $index) {
    $pool = @('0','1','2','3','4','5','6','7','8','9',
              'F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12',
              'Up','Down','Left','Right','Insert','Delete','Home','End','PageUp','PageDown',
              'Alt + 0','Alt + 1','Alt + 2','Alt + 3','Alt + 4','Alt + 5','Alt + 6','Alt + 7','Alt + 8','Alt + 9',
              'Ctrl + 0','Ctrl + 1','Ctrl + 2','Ctrl + 3','Ctrl + 4','Ctrl + 5')
    $normUsed = @{}
    foreach ($u in $used) { $normUsed[(Get-NormKey $u)] = $true }
    foreach ($c in $pool) { if (-not $normUsed.ContainsKey((Get-NormKey $c))) { return $c } }
    return "F$(([int]$index % 12) + 1)"
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
                    guids = @($info.guids); keys = $info.keys
                    thumb = (Find-Preview $_.FullName)
                })
            }
            if ($list.Count -gt 0) { $chars[$char] = $list }
        }
    return $chars
}

function Get-Index {
    if (Test-Path -LiteralPath $CacheFile) {
        $age = (Get-Date) - (Get-Item -LiteralPath $CacheFile).LastWriteTime
        if ($age.TotalMinutes -lt 30) {
            $raw = Get-Content -LiteralPath $CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $out = @{}
            foreach ($p in $raw.PSObject.Properties) { $out[$p.Name] = @($p.Value) }
            return $out
        }
    }
    $idx = Build-Index
    $obj = @{}
    foreach ($k in $idx.Keys) { $obj[$k] = $idx[$k] }
    ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $CacheFile -Encoding UTF8
    return $idx
}

$FxIni = Join-Path $ModsRoot "RabbitFX\RabbitFX.ini"
$UserIni = Join-Path (Split-Path $ModsRoot -Parent) "d3dx_user.ini"
$TfrIni = Join-Path $cfg.gameBin 'WuwaTFR.ini'

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
    if (Test-Path -LiteralPath $FxIni) {
        Copy-Item -LiteralPath $FxIni -Destination ($FxIni + '.bak-tgl') -Force
        $l = [Collections.Generic.List[string]]::new()
        [IO.File]::ReadAllLines($FxIni, [Text.Encoding]::UTF8) | ForEach-Object { $l.Add($_) }
        for ($i = 0; $i -lt $l.Count; $i++) {
            if ($l[$i] -match '^\s*persist global \$censor\s*=') { $l[$i] = "persist global `$censor = $v" }
        }
        [IO.File]::WriteAllLines($FxIni, $l, (New-Object Text.UTF8Encoding($false)))
        $msg += "RabbitFX=$v"
    }
    if (Test-Path -LiteralPath $UserIni) {
        $u = [Collections.Generic.List[string]]::new()
        [IO.File]::ReadAllLines($UserIni, [Text.Encoding]::UTF8) | ForEach-Object { $u.Add($_) }
        $hit = $false
        for ($j = 0; $j -lt $u.Count; $j++) {
            if ($u[$j] -match '^\s*\$\\rabbitfx\\censor\s*=') { $u[$j] = "`$`\rabbitfx`\censor = $v"; $hit = $true }
        }
        if (-not $hit) { $u.Add("`$`\rabbitfx`\censor = $v") }
        [IO.File]::WriteAllLines($UserIni, $u, (New-Object Text.UTF8Encoding($false)))
    }
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
    Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
        $d = Join-Path $dst $_.Name
        if ($_.PSIsContainer) { Copy-Item -LiteralPath $_.FullName -Destination $d -Recurse -Force }
        else { Copy-Item -LiteralPath $_.FullName -Destination $d -Force }
    }
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
        <TextBlock Text="角色" Foreground="#6f7787" FontSize="11" Margin="2,0,0,8"/>
        <ListBox x:Name="CharList" Background="Transparent" BorderThickness="0"
                 ItemContainerStyle="{StaticResource Tab}" Foreground="#aab2c2"/>
        <Button x:Name="RefreshBtn" Content="刷新索引" Style="{StaticResource Ghost}" Margin="0,18,0,0"/>
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
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border Background="#171b24" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="8" Height="36" VerticalAlignment="Center">
          <Grid>
            <TextBlock Text="搜索：编号 / 名称 / 形态" Foreground="#5d6675" FontSize="12" Margin="12,0,0,0" VerticalAlignment="Center" x:Name="SearchHint"/>
            <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" Foreground="#e3e7ef"
                     FontSize="13" Margin="10,0" VerticalContentAlignment="Center"
                     />
          </Grid>
        </Border>
        <TextBlock x:Name="Stats" Grid.Column="1" Foreground="#6f7787" FontSize="12" VerticalAlignment="Center" Margin="16,0,0,0"/>
      </Grid>

      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="14,0,10,10">
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
$TfrToggle = $win.FindName('TfrToggle')
$TfrHint = $win.FindName('TfrHint')
$Cards = $win.FindName('Cards')
$Search = $win.FindName('Search')
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
    $rd = Find-Readme $skin.dir
    $kl = Get-KeyList $skin.dir
    $parts = @()
    if ($rd) { $parts += "── 作者说明 ──`r`n$rd" }
    if ($kl) { $parts += "── 自动解析的按键（来自 mod.ini）──`r`n$kl" }
    $DetailReadme.Text = if ($parts.Count) { $parts -join "`r`n`r`n" } else { '（这个包既没有说明文件，也没有 [Key] 段 → 外观固定）' }
    if ($skin.thumb) {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.UriSource = (New-Object Uri $skin.thumb); $bi.EndInit()
        $BigPreview.Source = $bi
    } else { $BigPreview.Source = $null }

    $ActionPanel.Children.Clear()
    foreach ($g in $skin.guids) {
        $label = if ($GuidMap.ContainsKey($g)) { $GuidMap[$g] } else { "形态 $g" }
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = "装到 $label"
        $btn.Style = $win.Resources['Btn']
        $btn.Tag = @{ g = $g; s = $skin }
        $btn.Add_Click({ param($s, $e) $Status.Text = Install-Skin $s.Tag.s $s.Tag.g; $script:Installed = Get-InstalledMap })
        [void]$ActionPanel.Children.Add($btn)
    }
    if ($skin.guids.Count -gt 1) {
        $btnAll = New-Object System.Windows.Controls.Button
        $btnAll.Content = '全部形态一起装'
        $btnAll.Style = $win.Resources['Btn']
        $btnAll.Tag = $skin
        $btnAll.Add_Click({ param($s, $e) $Status.Text = Install-Skin $s.Tag 'all'; $script:Installed = Get-InstalledMap })
        [void]$ActionPanel.Children.Add($btnAll)
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
    if (-not $script:KeyRows -or $script:KeyRows.Count -eq 0) { return }
    $seen = @{}
    foreach ($r in $script:KeyRows) {
        $n = Get-NormKey $r.box.Text
        $r.conflict = $false
        $r.suggest = ''
        if (-not $n) { continue }
        if ($seen.ContainsKey($n)) { $r.conflict = $true }
        else { $seen[$n] = $true }
    }
    # 标记第一个出现者也算冲突（同键多人用）
    $dups = @{}
    foreach ($r in $script:KeyRows) {
        $n = Get-NormKey $r.box.Text
        if (-not $n) { continue }
        $k = $r.entry.path + '|' + $n
        if (-not $dups.ContainsKey($k)) { $dups[$k] = 0 }
        $dups[$k]++
    }
    foreach ($r in $script:KeyRows) {
        $n = Get-NormKey $r.box.Text
        if (-not $n) { continue }
        $k = $r.entry.path + '|' + $n
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
    if (-not $script:CurChar) { return }
    $kw = $Search.Text.Trim()
    $list = @($script:Index[$script:CurChar])
    if ($kw) { $list = @($list | Where-Object { $_.num -like "*$kw*" -or $_.name -like "*$kw*" }) }
    $Stats.Text = "共 $($list.Count) 套"
    foreach ($s in $list) {
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
        if ($s.thumb) {
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
        $numTb.Text = $s.num
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
        $nameTb.Text = $s.name
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
    if ($Cards.Children.Count -gt 0) {
        $first = $Cards.Children[0]
        if ($first -and -not $script:KeepSelection) {
            $first.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#4a9eff')))
            $first.BorderThickness = New-Object System.Windows.Thickness 2
            Show-Detail $first.Tag
        }
    }
    $script:KeepSelection = $false
}

$CharList.Add_SelectionChanged({
    if ($CharList.SelectedItem) {
        $script:CurChar = $CharList.SelectedItem
        Render-Cards
    }
})
$Search.Add_TextChanged({ Render-Cards })
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
    Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
    $script:Index = Get-Index
    $script:Installed = Get-InstalledMap
    Render-Cards
    $Status.Text = "索引已刷新"
})

foreach ($k in ($script:Index.Keys | Sort-Object)) { [void]$CharList.Items.Add($k) }
if ($CharList.Items.Count -gt 0) { $CharList.SelectedIndex = 0 }

function Set-ToggleVisual([bool]$on) { }

$script:TfrReady = $false
$tfrNow = Get-TfrState
Set-ToggleVisual ($tfrNow.fx -eq 1)
$TfrToggle.IsChecked = ($tfrNow.fx -eq 1)
$script:TfrReady = $true
$TfrHint.Text = if ($tfrNow.hasTfr) { "双模式同开同关" } else { "仅 Mod 模式" }

$TfrToggle.Add_Checked({
    if (-not $script:TfrReady) { return }
    Set-ToggleVisual $true
    $r = Set-TfrState 1
    $TfrHint.Text = "已开启（Mod 按 F10 / 光追需重启）"
    $Status.Text = "反虚化已开启（$r）"
})
$TfrToggle.Add_Unchecked({
    if (-not $script:TfrReady) { return }
    Set-ToggleVisual $false
    $r = Set-TfrState 0
    $TfrHint.Text = "已关闭（Mod 按 F10 / 光追需重启）"
    $Status.Text = "反虚化已关闭（$r）"
})

$Status.Text = "就绪。左上可开关反虚化；左侧选角色，中间选皮肤，右侧看详情与安装。"
[void]$win.ShowDialog()

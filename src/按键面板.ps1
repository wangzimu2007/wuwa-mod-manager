# Mod 按键面板（通用）
# 读任意 Mod 的 [Key*] 段，列出可切换项；点按钮 = 向游戏发送对应按键。
# 面板置顶且不抢焦点（WS_EX_NOACTIVATE），所以点按钮时游戏仍是前台，模拟按键能生效。
#
# 用法：双击运行 → 选择 Mod → 点按钮切换
# 说明：状态值来自 d3dx_user.ini（persist 变量），游戏内改完退出游戏才会写回

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ModsDir = Join-Path $env:APPDATA 'XXMI Launcher\WWMI\Mods'
$UserIni = Join-Path $env:APPDATA 'XXMI Launcher\WWMI\d3dx_user.ini'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Native {
    [DllImport("user32.dll")] public static extern IntPtr SendInput(uint n, INPUT[] p, int cb);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    public static void KeyDown(ushort vk) {
        INPUT[] a = new INPUT[1];
        a[0].type = 1; a[0].ki.wVk = vk;
        SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void KeyUp(ushort vk) {
        INPUT[] a = new INPUT[1];
        a[0].type = 1; a[0].ki.wVk = vk; a[0].ki.dwFlags = 2;
        SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void Press(ushort vk, bool ctrl, bool alt, bool shift) {
        if (ctrl) KeyDown(0x11);
        if (alt) KeyDown(0x12);
        if (shift) KeyDown(0x10);
        KeyDown(vk); System.Threading.Thread.Sleep(40); KeyUp(vk);
        if (shift) KeyUp(0x10);
        if (alt) KeyUp(0x12);
        if (ctrl) KeyUp(0x11);
    }
}
'@

function Get-VkCode([string]$name) {
    $n = $name.Trim().ToUpper()
    $map = @{
        'VK_UP'=0x26; 'VK_DOWN'=0x28; 'VK_LEFT'=0x25; 'VK_RIGHT'=0x27
        'VK_INSERT'=0x2D; 'VK_DELETE'=0x2E; 'VK_HOME'=0x24; 'VK_END'=0x23
        'VK_PRIOR'=0x21; 'VK_NEXT'=0x22; 'VK_OEM_COMMA'=0xBC; 'VK_OEM_2'=0xBF
        'VK_OEM_5'=0xDC; 'VK_OEM_PERIOD'=0xBE; 'VK_OEM_1'=0xBA; 'VK_OEM_3'=0xC0
        'VK_OEM_MINUS'=0xBD; 'VK_OEM_PLUS'=0xBB; 'VK_SPACE'=0x20; 'VK_RETURN'=0x0D
        'VK_TAB'=0x09; 'VK_ESCAPE'=0x1B; 'VK_LBUTTON'=0x01; 'VK_RBUTTON'=0x02
    }
    if ($map.ContainsKey($n)) { return $map[$n] }
    if ($n -match '^VK_F(\d+)$') { return (0x6F + [int]$Matches[1]) }
    if ($n -match '^VK_NUMPAD(\d)$') { return (0x60 + [int]$Matches[1]) }
    if ($n.Length -eq 1) {
        if ($n -match '^[0-9A-Z]$') { return [int][char]$n }
    }
    return 0
}

function Parse-ModKeys([string]$dir) {
    $rows = @()
    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.ini -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.bak|\.off|_\d{4}-' })
    foreach ($f in $files) {
        $lines = Get-Content -LiteralPath $f.FullName
        $sec = ''
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t -match '^\[(.+?)\]') { $sec = $Matches[1]; continue }
            if ($sec -notmatch '^Key') { continue }
            if ($t -notmatch '^key\s*=\s*(.+)$') { continue }
            $raw = $Matches[1].Trim()
            $ctrl = $raw -match '(?i)(^|\s)ctrl(\s|$)'
            $alt = $raw -match '(?i)(^|\s)alt(\s|$)'
            $shift = $raw -match '(?i)(^|\s)shift(\s|$)'
            $keyTok = (($raw -split '\s+') | Where-Object { $_ -notmatch '^(?i)(no_)?(alt|ctrl|shift)$' } | Select-Object -Last 1)
            $type = ''; $varLine = ''
            for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $lines.Count); $j++) {
                $nt = $lines[$j].Trim()
                if ($nt -match '^type\s*=\s*(\w+)') { $type = $Matches[1] }
                if ($nt -match '^\$(\w+)\s*=\s*(.+)$') { $varLine = "$($Matches[1]) = $($Matches[2])" }
                if ($nt -match '^\[') { break }
            }
            $rows += [pscustomobject]@{
                ini = $f.FullName; section = $sec; file = $f.Name
                rawKey = $raw; keyTok = $keyTok; type = $type
                ctrl = $ctrl; alt = $alt; shift = $shift
                varLine = $varLine; vk = (Get-VkCode $keyTok)
            }
        }
    }
    return $rows
}

# 常见段名 → 中文说明（没收录的直接显示段名）
function Get-FriendlyName([string]$sec, [string]$varLine) {
    $map = @{
        'Key key'   = '部件组 1'
        'Key key1'  = '骨架 / 体型'
        'Key key2'  = '部件组 2'
        'Key key3'  = '部件组 3'
        'Key key4'  = '部件组 4'
        'KeyMenu'   = '打开面板'
        'Key enable_mods' = '面板开关'
    }
    if ($map.ContainsKey($sec)) { return $map[$sec] }
    if ($sec -match '(?i)menu|panel') { return '面板' }
    if ($sec -match '(?i)enable') { return '总开关' }
    return $sec
}

function Get-PersistState([string]$varName, [string]$ns) {
    if (-not (Test-Path -LiteralPath $UserIni)) { return '' }
    $pat = [regex]::Escape("$ns\$varName")
    $m = Select-String -LiteralPath $UserIni -Pattern "=\s*(\d+)\s*$" -ErrorAction SilentlyContinue |
        Where-Object { $_.Line -match $pat }
    if ($m) { return ($m.Line -split '=')[-1].Trim() }
    return ''
}

$mods = @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'DISABLED*' -and $_.Name -ne 'RabbitFX' } | Sort-Object Name)

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mod 按键面板" Height="620" Width="560"
        WindowStartupLocation="Manual" Left="40" Top="120"
        Topmost="True" ShowActivated="False" Background="#101218"
        FontFamily="Microsoft YaHei" WindowStyle="ToolWindow">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Mod 按键面板" Foreground="#9fd0ff" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="0" Text="点击按钮 = 向游戏发送对应按键（面板不抢焦点）" Foreground="#6f7787" FontSize="11" Margin="0,26,0,0"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,8">
      <ComboBox x:Name="ModBox" Width="300" Height="28" Background="#171b24" Foreground="#dfe4ee" BorderBrush="#2a2f3d"/>
      <Button x:Name="LoadBtn" Content="载入" Width="70" Height="28" Margin="8,0,0,0" Background="#22304a" Foreground="#cfe3ff" BorderThickness="0"/>
      <Button x:Name="RefreshBtn" Content="刷新状态" Width="80" Height="28" Margin="8,0,0,0" Background="#1b2333" Foreground="#b8c0cf" BorderThickness="0"/>
    </StackPanel>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="Rows"/>
    </ScrollViewer>
    <TextBlock Grid.Row="3" x:Name="Status" Foreground="#7fd18a" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)
$ModBox = $win.FindName('ModBox'); $Rows = $win.FindName('Rows')
$LoadBtn = $win.FindName('LoadBtn'); $RefreshBtn = $win.FindName('RefreshBtn')
$Status = $win.FindName('Status')

# 不抢焦点
$win.Add_SourceInitialized({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
    $ex = [Native]::GetWindowLong($h, -20)
    [void][Native]::SetWindowLong($h, -20, $ex -bor 0x08000000 -bor 0x00000080)  # NOACTIVATE | TOOLWINDOW
})

foreach ($m in $mods) { [void]$ModBox.Items.Add($m.Name) }
if ($ModBox.Items.Count -gt 0) { $ModBox.SelectedIndex = 0 }

$script:RowsData = @()
function Render {
    $Rows.Children.Clear()
    if (-not $script:RowsData) { return }
    foreach ($r in $script:RowsData) {
        $b = New-Object System.Windows.Controls.Border
        $b.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#171b24'))
        $b.CornerRadius = New-Object System.Windows.CornerRadius 6
        $b.Margin = New-Object System.Windows.Thickness 0,0,0,6
        $b.Padding = New-Object System.Windows.Thickness 10,8,10,8
        $g = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, 'Star')
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(110)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = New-Object System.Windows.GridLength(90)
        [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2); [void]$g.ColumnDefinitions.Add($c3)

        $info = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock
        $t1.Text = (Get-FriendlyName $r.section $r.varLine)
        $t1.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#dfe4ee'))
        $t1.FontSize = 12.5
        $t2 = New-Object System.Windows.Controls.TextBlock
        $stateTxt = if ($r.state) { "当前：$($r.state)" } else { '当前：—' }
        $t2.Text = "$($r.rawKey)   ·   $($r.varLine)   ·   $stateTxt"
        $t2.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6f7787'))
        $t2.FontSize = 10.5
        $t2.TextWrapping = 'Wrap'
        [void]$info.Children.Add($t1); [void]$info.Children.Add($t2)
        [System.Windows.Controls.Grid]::SetColumn($info, 0)
        [void]$g.Children.Add($info)

        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = '发送按键'
        $btn.Height = 26
        $btn.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#22304a'))
        $btn.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#cfe3ff'))
        $btn.BorderThickness = 0
        $btn.IsEnabled = ($r.vk -gt 0)
        $rowRef = $r
        $btn.Add_Click({
            param($s, $e)
            if ($rowRef.vk -le 0) { return }
            [Native]::Press([uint16]$rowRef.vk, $rowRef.ctrl, $rowRef.alt, $rowRef.shift)
            $Status.Text = "已发送：$($rowRef.rawKey)（$($rowRef.section)）"
        })
        [System.Windows.Controls.Grid]::SetColumn($btn, 2)
        [void]$g.Children.Add($btn)

        $b.Child = $g
        [void]$Rows.Children.Add($b)
    }
}

function Load-Mod {
    $name = $ModBox.SelectedItem
    if (-not $name) { return }
    $dir = Join-Path $ModsDir $name
    $rows = @(Parse-ModKeys $dir)
    # 补状态
    foreach ($r in $rows) {
        $r | Add-Member -NotePropertyName state -NotePropertyValue '' -Force
    }
    $script:RowsData = $rows
    Render
    $Status.Text = "已载入 $name：$($rows.Count) 个按键项"
}

$LoadBtn.Add_Click({ Load-Mod })
$RefreshBtn.Add_Click({ Load-Mod })
$win.Add_Loaded({ Load-Mod })
[void]$win.ShowDialog()

# 鸣潮启动器（统一入口）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$Switch = "C:\Users\wangzimu\Desktop\mod预设管理\鸣潮\鸣潮模式切换.ps1"
$Manager = "E:\GameMods\WWMI-Mods\工具\Mod管理器.ps1"
$Records = "E:\GameMods\WWMI-Mods\使用记录\鸣潮"
$PS = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="鸣潮启动器" Height="600" Width="780"
        WindowStartupLocation="CenterScreen" Background="#101218"
        FontFamily="Microsoft YaHei" ResizeMode="NoResize">
  <Window.Resources>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#171b24"/>
      <Setter Property="BorderBrush" Value="#242936"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Grid Margin="24,20,24,20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0">
      <TextBlock Text="鸣潮启动器" Foreground="#9fd0ff" FontSize="22" FontWeight="SemiBold"/>
      <TextBlock Text="双击卡片启动（会自动写好对应的画质预设与注入开关）" Foreground="#6f7787" FontSize="12" Margin="0,6,0,0"/>
    </StackPanel>

    <Grid Grid.Row="1" Margin="0,20,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border x:Name="CardMod" Grid.Column="0" Style="{StaticResource Card}">
        <StackPanel Margin="18">
          <TextBlock Text="MOD" Foreground="#7fe08a" FontFamily="Consolas" FontSize="13" FontWeight="Bold"/>
          <TextBlock Text="Mod 模式" Foreground="#e3e7ef" FontSize="18" FontWeight="SemiBold" Margin="0,8,0,0"/>
          <TextBlock Text="角色皮肤 / 反虚化 / DLSS 帧生成" Foreground="#8b93a3" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
          <TextBlock Text="光追：自动关&#x0a;注入：ReShade + GITC + WWMI" Foreground="#5d6675" FontSize="11" Margin="0,14,0,0" LineHeight="18"/>
        </StackPanel>
      </Border>

      <Border x:Name="CardRt" Grid.Column="1" Style="{StaticResource Card}">
        <StackPanel Margin="18">
          <TextBlock Text="RT" Foreground="#ffc078" FontFamily="Consolas" FontSize="13" FontWeight="Bold"/>
          <TextBlock Text="光追模式" Foreground="#e3e7ef" FontSize="18" FontWeight="SemiBold" Margin="0,8,0,0"/>
          <TextBlock Text="DLSS5 + 光线追踪（直连启动）" Foreground="#8b93a3" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
          <TextBlock Text="光追：自动开 + 4x 帧生成&#x0a;注入：ReShade + GITC（不含 Mod）" Foreground="#5d6675" FontSize="11" Margin="0,14,0,0" LineHeight="18"/>
        </StackPanel>
      </Border>

      <Border x:Name="CardClean" Grid.Column="2" Style="{StaticResource Card}" Margin="0">
        <StackPanel Margin="18">
          <TextBlock Text="SAFE" Foreground="#8ec2ff" FontFamily="Consolas" FontSize="13" FontWeight="Bold"/>
          <TextBlock Text="干净模式" Foreground="#e3e7ef" FontSize="18" FontWeight="SemiBold" Margin="0,8,0,0"/>
          <TextBlock Text="排查用：全部注入关闭，还原原版画面" Foreground="#8b93a3" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
          <TextBlock Text="光追：不动&#x0a;注入：全部卸载（含 ReShade）" Foreground="#5d6675" FontSize="11" Margin="0,14,0,0" LineHeight="18"/>
        </StackPanel>
      </Border>
    </Grid>

    <StackPanel Grid.Row="2" Margin="0,18,0,0">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="BtnManager" Content="打开 Mod 管理器" Width="150" Height="34"
                Background="#1b1f2a" Foreground="#b8c0cf" BorderBrush="#2a2f3d" Margin="0,0,10,0" Cursor="Hand"/>
        <Button x:Name="BtnRecords" Content="打开记录目录" Width="130" Height="34"
                Background="#1b1f2a" Foreground="#b8c0cf" BorderBrush="#2a2f3d" Cursor="Hand"/>
      </StackPanel>
      <TextBlock x:Name="Status" Foreground="#7fd18a" FontSize="12" Margin="0,12,0,0" TextWrapping="Wrap"/>
    </StackPanel>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)
$Status = $win.FindName('Status')
$CardMod = $win.FindName('CardMod')
$CardRt = $win.FindName('CardRt')
$CardClean = $win.FindName('CardClean')
$BtnManager = $win.FindName('BtnManager')
$BtnRecords = $win.FindName('BtnRecords')

. (Join-Path $PSScriptRoot '反虚化状态.ps1')

function Get-LingeringGame {
    @(Get-Process -Name 'Client-Win64-Shipping', 'Wuthering Waves', 'launcher' -ErrorAction SilentlyContinue)
}

function Stop-LingeringGame {
    $p = Get-LingeringGame
    if ($p.Count -eq 0) { return $true }

    # 先自动等它自己退干净（最多 90 秒），避免强杀导致设置没保存
    $Status.Text = "检测到游戏仍在退出中，等待其完全关闭…"
    try { $Status.Dispatcher.Invoke([Action] { }, 'Background') } catch { }
    for ($i = 1; $i -le 45; $i++) {
        Start-Sleep -Seconds 2
        $p = Get-LingeringGame
        if ($p.Count -eq 0) {
            $Status.Text = "游戏已完全退出，继续启动…"
            try { $Status.Dispatcher.Invoke([Action] { }, 'Background') } catch { }
            return $true
        }
        $Status.Text = ("等待游戏退出… {0} 秒" -f ($i * 2))
        try { $Status.Dispatcher.Invoke([Action] { }, 'Background') } catch { }
    }
    # 90 秒还没退，才询问是否强杀
    $p = Get-LingeringGame
    $names = ($p | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join '、'
    $ans = [System.Windows.MessageBox]::Show(
        "检测到游戏进程仍在后台运行：`n`n$names`n`n按 X 关闭游戏后，进程可能还要几十秒才真正退出。`n是否结束它们后再启动？",
        "鸣潮启动器", 'YesNo', 'Question')
    if ($ans -ne 'Yes') {
        $Status.Text = "已取消。请等待游戏完全退出（启动器关闭后）再试。"
        return $false
    }
    foreach ($x in $p) {
        try { Stop-Process -Id $x.Id -Force -ErrorAction Stop } catch { }
    }
    Start-Sleep -Seconds 2
    $left = Get-LingeringGame
    if ($left.Count -gt 0) {
        $Status.Text = "⚠ 仍有进程未结束，请用任务管理器手动关闭"
        return $false
    }
    return $true
}

function Start-Mode([string]$mode, [string]$label) {
    if (-not (Test-Path -LiteralPath $Switch)) { $Status.Text = "❌ 找不到模式切换脚本：$Switch"; return }
    if (-not (Stop-LingeringGame)) { return }
    # 启动前把「反虚化」状态同步进 WuwaTFR.ini（保证每次进游戏都是你想要的状态）
    $sync = Sync-TfrIni
    $tfrWord = if (Get-TfrEnabled) { '开' } else { '关' }
    Write-Host "[启动器] 反虚化=$tfrWord　$($sync.msg)"
    $Status.Text = "正在启动 [$label] …（会先写画质预设，再启动游戏）"
    Start-Process -FilePath $PS -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Switch`"", '-Mode', $mode -WorkingDirectory (Split-Path $Switch -Parent)
    $win.Close()
}

function Invoke-OnDoubleClick([object]$card, [scriptblock]$action, [string]$label) {
    # WPF 的 ClickCount 只在 MouseDown 系列的 e 里有可靠值，Up 事件恒为 1
    # GetNewClosure 让脚本块捕获 $label / $action（否则事件触发时变量已出作用域）
    $handler = {
        param($s, $e)
        if ($e.ClickCount -ge 2) {
            $Status.Text = "正在启动 [$label] …"
            & $action
        } else {
            $Status.Text = "已选中 [$label]，再点一次即启动（双击）"
        }
    }.GetNewClosure()
    $card.Add_MouseLeftButtonDown($handler)
}
Invoke-OnDoubleClick $CardMod { Start-Mode 'mod' 'Mod 模式' } 'Mod 模式'
Invoke-OnDoubleClick $CardRt { Start-Mode 'rt' '光追模式' } '光追模式'
Invoke-OnDoubleClick $CardClean { Start-Mode 'clean' '干净模式' } '干净模式'
$CardMod.Add_MouseEnter({ $CardMod.BorderBrush = [System.Windows.Media.Brushes]::SeaGreen })
$CardMod.Add_MouseLeave({ $CardMod.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#242936'))) })
$CardRt.Add_MouseEnter({ $CardRt.BorderBrush = [System.Windows.Media.Brushes]::Goldenrod })
$CardRt.Add_MouseLeave({ $CardRt.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#242936'))) })
$CardClean.Add_MouseEnter({ $CardClean.BorderBrush = [System.Windows.Media.Brushes]::SteelBlue })
$CardClean.Add_MouseLeave({ $CardClean.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#242936'))) })

$BtnManager.Add_Click({
    if (Test-Path -LiteralPath $Manager) {
        Start-Process -FilePath $PS -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$Manager`""
        $Status.Text = "已打开 Mod 管理器"
    } else { $Status.Text = "❌ 找不到管理器脚本" }
})
$BtnRecords.Add_Click({ if (Test-Path -LiteralPath $Records) { Start-Process explorer.exe $Records } })

$Status.Text = "双击上面任意一张卡片即可启动（单击不会触发）"
[void]$win.ShowDialog()

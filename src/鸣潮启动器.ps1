# 鸣潮启动器（统一入口）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

. (Join-Path $PSScriptRoot '_config.ps1')
$cfg = Get-Cfg
$Switch = $cfg.switchScript
$Manager = Join-Path $PSScriptRoot 'Mod管理器.ps1'
$Records = $cfg.recordsDir
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
      <TextBlock Text="选择启动模式（会自动写好对应的画质预设与注入开关）" Foreground="#6f7787" FontSize="12" Margin="0,6,0,0"/>
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
          <TextBlock Text="DLSS5 + 光线追踪（官方启动器）" Foreground="#8b93a3" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
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

function Start-Mode([string]$mode, [string]$label) {
    if (-not (Test-Path -LiteralPath $Switch)) { $Status.Text = "❌ 找不到模式切换脚本：$Switch"; return }
    $Status.Text = "正在启动 [$label] …（会先写画质预设，再启动游戏）"
    Start-Process -FilePath $PS -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Switch`"", '-Mode', $mode -WorkingDirectory (Split-Path $Switch -Parent)
    $win.Close()
}

$CardMod.Add_MouseLeftButtonUp({ Start-Mode 'mod' 'Mod 模式' })
$CardRt.Add_MouseLeftButtonUp({ Start-Mode 'rt' '光追模式' })
$CardClean.Add_MouseLeftButtonUp({ Start-Mode 'clean' '干净模式' })
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

$Status.Text = "点上面任意一张卡片即可启动游戏"
[void]$win.ShowDialog()

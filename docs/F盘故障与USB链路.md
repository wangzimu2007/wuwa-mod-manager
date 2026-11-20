# F 盘（WDC WD40EFZZ 4TB HDD）故障记录

记录时间：2026-11-20 03:22

## 现象

- F 盘目录/文件操作会长时间挂起（实测一次 Test-Path 卡 17 分钟）
- 03:00 之后持续写日志：每 90 秒一条 IO 重试
- 系统日志（System）来源 disk，磁盘 2（PDO \\Device\\000000c0）
  在 LBA 0x5babf8 ~ 0x5bac08 区间反复重试 IO
- 该 LBA 区域持续失败 → 典型坏道表现

## 影响

- F 盘上的皮肤库（F:\\GameMods\\WWMI-Mods\\Skins）读取会卡住管理器
- 任何写入 F 盘的操作都会挂死，不能再用它做下载目标

## 已做的处置

- 停止所有对 F 盘的写入（搬运脚本已终止）
- 晨星系列 18 个包（1.5 GB）暂存 E 盘：
  E:\\GameMods\\WWMI-Mods\\_temp_下载\\晨星系列\\

## 待办（重启后执行）

1. 重启电脑，先把挂住的 IO 队列清掉
2. 立刻备份 F 盘上重要的东西（Mod 库、下载包）到 E 盘
3. 跑坏道检测：chkdsk F: /scan （管理员 PowerShell）
4. 如果坏道确认，这块盘不要再当主力存储；
   Mod 库建议放 E 盘（NVMe，剩余 125 GB）或另配新盘
5. 检查 SMART：Get-PhysicalDisk | Get-StorageReliabilityCounter

## 注意

- 别再往 F 盘跑批量下载/解压，会再次把系统拖死
- 管理器启动时若索引指向 F 盘，读取仍可能卡（可临时改 SkinsRoot 到 E 盘）


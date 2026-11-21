# tools/ — 抓取、下载、补齐脚本

这些脚本是给「爱发电 / 香蕉网 → 本地皮肤库 → 游戏 Mods」这条流水线用的，
在 Windows + PowerShell 5.1 + Python 3.12 下实测通过。

> ⚠️ **本目录不含任何解压密码。**
> 付费模组的压缩包密码由使用者自己在对应帖子获取，脚本只读取本地 CSV。

---

## 依赖

| 依赖 | 用途 | 说明 |
|---|---|---|
| Python 3.10+ | 运行所有 `.py` | 需要 `websocket-client`（`pip install websocket-client`） |
| UnRAR | 解 `.rar`（含 RAR5 加密包） | RARLAB 官方，`tools` 目录外自备；7-Zip 的 7zr 不支持 RAR5 |
| 7za | 解 `.zip` / `.7z` | 可选 |
| curl.exe | 断点续传下载 | Windows 10+ 自带（`C:\Windows\System32\curl.exe`） |
| Edge / Chrome | 抓爱发电帖子 | 需以 `--remote-debugging-port=9222` 启动并登录 |

代理：脚本内默认 `http://127.0.0.1:7890`，按需改成你的本地代理端口。

---

## 脚本一览

| 脚本 | 作用 |
|---|---|
| `抓帖子与合集.py` | 通过 CDP 连本机浏览器，抓作者全部帖子 + 合集里的帖子，提取「图片名称为：…」与各类网盘链接，输出 JSON |
| `抓全部帖子2.py` | 同上，单帖模式（更快，适合只要帖子和密码） |
| `生成密码存档.py` | 把「模组 / 压缩包密码 / workupload / 百度网盘」整理成 md + csv 存档 |
| `下载器Curl.py` | 处理 workupload：Python 过站点验证拿直链 + 导出 Cookie，交给 curl 断点续传 |
| `下载文件.py` | 旧版纯 Python 下载器（无 curl 依赖时用） |
| `批量完整版3.py` | 读密码表 CSV → 下载 → 用密码解压 → 处理「套娃包」→ 按 guid 装进 Mods → 入库 |
| `补齐早期作品2.py` | 从香蕉网批量下载作者旧作（免费、无密码）并可选择安装 |
| `修复坏包.py` | 下载不完整导致 checksum error 时，按 Content-Length 校验重下再装 |
| `验证完整版.py` | 校验已装模组：文件数、大小、UI 图标缺失、开关实现数量 |
| `分析作者榜.py` | 拉 GameBanana 某游戏的模组列表，按作者统计总赞，并检测 Patreon/爱发电/Ko-fi 等付费渠道 |
| `作者代表作.py` | 取每位作者赞数最高的代表作，附文件与下载链接 |
| `下载样本作者.py` | 下载指定作者的代表作样本到皮肤库，可选激活 |
| `生成补齐清单.py` | 生成「补齐清单」md/csv（香蕉网链接、guid、库内目录、是否生效） |

---

## 典型流程

```text
1) 抓帖子
   edge --remote-debugging-port=9222 --user-data-dir=<临时配置> 打开 afdian.com 并登录
   python 抓帖子与合集.py            → _afdian_all_posts.json

2) 整理密码
   把「模组, workuploadID, 压缩包密码」写成 CSV（_晨星完整版密码表.csv）
   python 生成密码存档.py            → 存档 md/csv

3) 批量下载安装
   python 批量完整版3.py             → 下载 → 解压 → 装 Mods → 入库
   （已装过的按日志自动跳过）

4) 补齐香蕉网旧作
   python 补齐早期作品2.py
   python 修复坏包.py                （下载不完整时）

5) 验证
   python 验证完整版.py
```

---

## 关键坑（实测）

- **workupload**：站点密码是站点级的，压缩包还有一层密码；直链需要带着会话 Cookie，直接 curl 会被 302 回文件页。
- **RAR5**：7za 打不开，必须 UnRAR；密码含中文时要用正确编码传参（Python `subprocess` 列表参数最稳，别走 `cmd` 拼接）。
- **套娃包**：部分包解压后里面还是 rar（如 `清宵058`、`清宵060`），需要再解一层。
- **香蕉网下载不完整**：会出现 `checksum error / Unexpected end of archive`，务必按 `Content-Length` 校验后重下。
- **同 guid 冲突**：同一角色同 `object_guid` 只能生效一套，脚本检测到已装则「只入库不覆盖」。

---

## 免责

脚本仅做「本地整理」，不下发任何付费内容；模组版权归作者，请遵守作者的授权与分发规则。

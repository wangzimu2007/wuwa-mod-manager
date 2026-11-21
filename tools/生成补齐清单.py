# -*- coding: utf-8 -*-
# 生成「晨星香蕉网补齐清单」markdown + csv
import json, os, re, time

LOG = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_晨星香蕉网补齐日志.csv"
MISSING = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_晨星缺清单.json"
LIB = r"F:\GameMods\WWMI-Mods\Skins"
MODS = os.path.join(os.environ["APPDATA"], r"XXMI Launcher\WWMI\Mods")
OUT_MD = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\晨星香蕉网补齐清单.md"
OUT_CSV = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\晨星香蕉网补齐清单.csv"

# 香蕉网 id / 链接
modinfo = {}
if os.path.exists(MISSING):
    for m in json.load(open(MISSING, encoding="utf-8")):
        modinfo[m["name"]] = {"id": m["id"], "likes": m.get("likes", 0)}

# 日志
rows = []
if os.path.exists(LOG):
    with open(LOG, encoding="utf-8-sig") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line or i == 0:
                continue
            p = line.split(",")
            if len(p) < 6:
                continue
            rows.append({"time": p[0], "name": p[1], "mb": p[2], "guids": [g for g in p[3].split(",") if g],
                         "libdir": p[4]})

# 已生效的 guid 集合
active = set()
for d in os.listdir(MODS):
    if d.startswith("DISABLED"):
        continue
    ini = os.path.join(MODS, d, "mod.ini")
    if os.path.isfile(ini):
        try:
            m = re.search(r"object_guid\s*=\s*(\d+)", open(ini, encoding="utf-8", errors="ignore").read())
            if m:
                active.add(m.group(1))
        except Exception:
            pass
    # 有些用 mod-自动生成.ini
    for fn in os.listdir(os.path.join(MODS, d)):
        if fn.lower().startswith("mod") and fn.lower().endswith(".ini"):
            try:
                t = open(os.path.join(MODS, d, fn), encoding="utf-8", errors="ignore").read()
                for g in re.findall(r"object_guid\s*=\s*(\d+)", t):
                    active.add(g)
            except Exception:
                pass

def num(s):
    m = re.search(r"(?:序列|num|Num)\s*[☆]?\s*0*(\d{1,3})", s)
    return int(m.group(1)) if m else 999

def locate(name):
    # 找库内目录
    for ch in os.listdir(LIB):
        d = os.path.join(LIB, ch)
        if not os.path.isdir(d):
            continue
        for sub in os.listdir(d):
            if sub == name or sub.endswith(name) or name[:12] in sub:
                return ch, sub
    return "", ""

rows.sort(key=lambda r: num(r["name"]))
lines = ["# 晨星 · 香蕉网补齐清单", ""]
lines.append("来源：GameBanana 作者主页 https://gamebanana.com/members/2798606 （免费，无解压密码）")
lines.append("")
lines.append(f"统计：共 {len(rows)} 个模组；存档时间 {time.strftime('%Y-%m-%d %H:%M')}")
lines.append("")
lines.append("| 序列 | 模组 | 香蕉网 | 文件 MB | guid | 库内目录 | 状态 |")
lines.append("|---|---|---|---|---|---|---|")
csv = ["序列,模组,香蕉网链接,MB,guid,库内目录,状态"]
for r in rows:
    n = num(r["name"])
    info = modinfo.get(r["name"], {})
    url = f"https://gamebanana.com/mods/{info['id']}" if info.get("id") else ""
    ch, sub = locate(r["name"])
    live = any(g in active for g in r["guids"])
    status = "🟢 同 guid 已生效" if live else "⚪ 未生效（可手动装）"
    libpath = (ch + "/" + sub) if ch else (r["libdir"] or "")
    lines.append(f"| {n if n != 999 else '-'} | {r['name']} | {url} | {r['mb']} | {','.join(r['guids'])} | {libpath} | {status} |")
    csv.append(','.join([str(n if n != 999 else ""), '"%s"' % r["name"].replace('"', '""'),
                         url, r["mb"], '"%s"' % ",".join(r["guids"]), '"%s"' % libpath, status]))

lines.append("")
lines.append("## 说明")
lines.append("")
lines.append("- 这些文件来自香蕉网，**免费、无解压密码**；付费完整版在作者爱发电/Patreon。")
lines.append("- 状态「🟢 同 guid 已生效」只表示这个 guid 当前有生效的 Mod；同角色同 guid 可能生效的是另一套，切换请在管理器里点「装到」。")
lines.append("- 爱发电付费版密码见 `晨星完整版-密码与链接存档.md`。")

open(OUT_MD, "w", encoding="utf-8").write("\n".join(lines))
open(OUT_CSV, "w", encoding="utf-8-sig").write("\n".join(csv))
print("MD:", OUT_MD)
print("CSV:", OUT_CSV)
print("条目:", len(rows))

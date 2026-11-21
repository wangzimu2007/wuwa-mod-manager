# -*- coding: utf-8 -*-
# 验证晨星完整版安装：文件数/大小/guid/面板图标/开关实现
import os, re, json, sys

MODS = os.path.join(os.environ["APPDATA"], r"XXMI Launcher\WWMI\Mods")
LIB = r"F:\GameMods\WWMI-Mods\Skins"
LOG = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_完整版批量日志.csv"

rows = []
if os.path.exists(LOG):
    with open(LOG, encoding="utf-8-sig") as f:
        lines = [l.strip() for l in f if l.strip()]
    for line in lines[1:]:
        parts = line.split(",")
        if len(parts) >= 6 and parts[5] == "OK":
            rows.append({"mod": parts[1], "guid": parts[3], "dir": parts[4], "mb": parts[2]})

seen = set()
print(f"{'模组':<32}{'目录':<20}{'文件':>6}{'MB':>8}{'图标缺':>7}{'开关':>5}  结果")
print("-" * 92)
for r in rows:
    key = (r["guid"], r["dir"])
    if key in seen:
        continue
    seen.add(key)
    p = os.path.join(MODS, r["dir"])
    if not os.path.isdir(p):
        print(f"{r['mod'][:30]:<32}{r['dir']:<20}{'—':>6}{'—':>8}{'—':>7}{'—':>5}  ❌目录不存在")
        continue
    files = 0
    size = 0
    for dp, _, fs in os.walk(p):
        for fn in fs:
            files += 1
            try:
                size += os.path.getsize(os.path.join(dp, fn))
            except OSError:
                pass
    # 图标缺失
    ui = None
    for dp, _, fs in os.walk(p):
        for fn in fs:
            if re.search(r"(?i)out\s*ui.*\.ini$", fn):
                ui = os.path.join(dp, fn); break
        if ui: break
    missing = 0; refs = 0
    if ui:
        txt = open(ui, encoding="utf-8", errors="ignore").read()
        names = set(re.findall(r"(?i)filename\s*=\s*([^\s\r\n]+\.(?:dds|png))", txt))
        refs = len(names)
        for n in names:
            if not os.path.exists(os.path.join(os.path.dirname(ui), n)):
                missing += 1
    # 开关实现
    items = 0
    for dp, _, fs in os.walk(p):
        for fn in fs:
            if re.match(r"(?i)^mod.*\.ini$", fn) and ".bak" not in fn.lower():
                t = open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()
                idx = set(int(x) for x in re.findall(r"\$key_(\d+)\b", t))
                items = max(items, len(idx))
    ok = files > 0 and missing == 0
    flag = "✅" if ok else ("⚠ 图标缺%d" % missing)
    print(f"{r['mod'][:30]:<32}{r['dir']:<20}{files:>6}{size/1048576:>8.1f}{missing:>7}{items:>5}  {flag}")

print()
print("说明：图标缺 = UI 引用了但文件不存在（模板空位属正常，>14 的编号通常是空位）")

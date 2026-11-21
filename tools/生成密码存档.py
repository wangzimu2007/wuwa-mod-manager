# -*- coding: utf-8 -*-
# 生成「晨星完整版 · 密码与链接存档」
import json, os, re, time

TABLE = r"E:\GameMods\WWMI-Mods\工具\_晨星完整版密码表.csv"
PARSED = r"E:\GameMods\WWMI-Mods\工具\_afdian_parsed.json"
README = r"E:\GameMods\WWMI-Mods\_blog_extract\Stars-at-dawn.github.io-main\README.md"
OUT_MD = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\晨星完整版-密码与链接存档.md"
OUT_CSV = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\晨星完整版-密码与链接存档.csv"

# 解析博客 README 的百度链接
baidu = {}
rd = open(README, encoding="utf-8", errors="ignore").read().splitlines()
cur = None
for line in rd:
    t = line.strip()
    if t.startswith("### "):
        cur = t[4:].strip()
        baidu.setdefault(cur, {})
        continue
    if not cur:
        continue
    m = re.search(r"链接①[:：]\s*(\S+?)\s*提取码[:：]?\s*(\S+)", t)
    if m:
        baidu[cur]["baidu"] = m.group(1)
        baidu[cur]["baidu_pwd"] = m.group(2)
    m2 = re.search(r"链接②[:：]\s*(\S+?)\s*提取码[:：]?\s*(\S+)", t)
    if m2:
        baidu[cur]["wu"] = m2.group(1)
        baidu[cur]["wu_pwd"] = m2.group(2)

def num(s):
    m = re.search(r"(?:序列|num)?\s*(\d{3})", s, re.I)
    return m.group(1) if m else None

# 表格（含 workupload 链接与压缩包密码）
rows = []
with open(TABLE, encoding="utf-8-sig") as f:
    for i, line in enumerate(f):
        line = line.strip()
        if not line or i == 0:
            continue
        p = line.split(",", 2)
        if len(p) < 3:
            continue
        rows.append({"name": p[0], "fid": p[1], "pw": p[2]})

# 帖子（标题 / post_id）
posts = {}
if os.path.exists(PARSED):
    for r in json.load(open(PARSED, encoding="utf-8")):
        n = num(r["title"])
        if n:
            posts[n] = r

# 百度链接按编号对齐
baidu_by_num = {}
for title, v in baidu.items():
    n = num(title)
    if n:
        baidu_by_num[n] = v

lines = []
lines.append("# 晨星（Morning_Star）完整版 · 密码与链接存档")
lines.append("")
lines.append("作者渠道：")
lines.append("- 爱发电：https://afdian.com/a/MorningStar")
lines.append("- Patreon：https://www.patreon.com/cw/Morning__Star")
lines.append("- 香蕉网：https://gamebanana.com/members/2798606")
lines.append("- 博客（链接集中地）：https://github.com/Stars-at-dawn/Stars-at-dawn.github.io （README.md 里有全部下载链接）")
lines.append("- QQ 群：1029406436")
lines.append("")
lines.append("规则：**压缩包解压密码 = 对应爱发电帖子里的「此图片名称为：…」整句**（含标点，一字不差）。")
lines.append("")
lines.append("---")
lines.append("")
lines.append("| 序列 | 模组 | 压缩包密码（图片名称） | workupload | 网盘提取码 | 百度网盘 | 百度提取码 |")
lines.append("|---|---|---|---|---|---|---|")
for r in rows:
    n = num(r["name"])
    v = baidu_by_num.get(n, {})
    wu = f"https://workupload.com/file/{r['fid']}" if r["fid"] else ""
    bd = v.get("baidu", "")
    lines.append("| {n} | {name} | `{pw}` | {wu} | star | {bd} | {bp} |".format(
        n=n, name=r["name"], pw=r["pw"], wu=wu, bd=bd, bp=v.get("baidu_pwd", "")))
lines.append("")
lines.append("---")
lines.append("")
lines.append("## 已知补充")
lines.append("")
lines.append("- workupload 站点密码统一是 `star`；百度网盘提取码见表格。")
lines.append("- 060 清宵邪剑仙、058 清宵夏日清风 是「套娃包」：外层解压后里面还有 2 个 rar，密码相同。")
lines.append("- 089 及以后的新作品不一定在博客 README 里，需直接去爱发电找帖子。")
lines.append("")
lines.append(f"存档时间：{time.strftime('%Y-%m-%d %H:%M')}")

os.makedirs(os.path.dirname(OUT_MD), exist_ok=True)
open(OUT_MD, "w", encoding="utf-8").write("\n".join(lines))

# CSV 版（便于程序读取）
csv = ["序列,模组,压缩包密码,workupload_id,workupload链接,百度链接,百度提取码"]
for r in rows:
    n = num(r["name"])
    v = baidu_by_num.get(n, {})
    csv.append(",".join([
        n or "", r["name"], '"%s"' % r["pw"].replace('"', '""'),
        r["fid"], f"https://workupload.com/file/{r['fid']}" if r["fid"] else "",
        v.get("baidu", ""), v.get("baidu_pwd", ""),
    ]))
open(OUT_CSV, "w", encoding="utf-8-sig").write("\n".join(csv))

print("MD:", OUT_MD)
print("CSV:", OUT_CSV)
print("条目:", len(rows))

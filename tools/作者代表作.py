# -*- coding: utf-8 -*-
# 从作者榜里挑代表作 + 发布渠道 + 免费/付费判定
import json, re, time, urllib.request

PROXY = "http://127.0.0.1:7890"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
SRC = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_作者榜.json"
OUT = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_作者代表作.json"

op = urllib.request.build_opener(urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}))
op.addheaders = [("User-Agent", UA), ("Accept", "application/json")]


def get(url, timeout=60):
    with op.open(url, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


data = json.load(open(SRC, encoding="utf-8"))
mods = data["mods"]

FOCUS = ["SpacePig", "Melodiq", "Alunoop", "B0ringMgx", "KatTheDev", "---Invalid---",
         "Arelewd", "scoob1098", "nope111110", "Nait3D", "_SlugCat", "PebbleRox", "theovanua"]

out = []
for author in FOCUS:
    ms = sorted([m for m in mods if m["author"] == author], key=lambda x: -x["likes"])
    if not ms:
        continue
    best = ms[0]
    try:
        p = json.loads(get(f"https://gamebanana.com/apiv11/Mod/{best['id']}/ProfilePage"))
        files = p.get("_aFiles") or []
        desc = re.sub(r"<[^>]+>", " ", p.get("_sText") or "")
        desc = re.sub(r"\s+", " ", desc)[:180]
        paid = bool(re.search(r"(?i)(full version|paid|patreon|afdian|爱发电|boosty|ko-fi|subscribe)", desc))
        out.append({
            "author": author,
            "mods": len(ms),
            "total_likes": sum(m["likes"] for m in ms),
            "best_name": best["name"],
            "best_id": best["id"],
            "best_likes": best["likes"],
            "files": len(files),
            "dl": (files[0].get("_sDownloadUrl") if files else ""),
            "paid_hint": paid,
            "desc": desc,
        })
        print(f"  {author:<14} 代表作《{best['name'][:30]}》 赞{best['likes']:>5} 文件{len(files)} 付费提示={paid}")
    except Exception as e:
        print(f"  {author:<14} 失败 {e}")
    time.sleep(0.4)

json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("\nSAVED:", OUT)

# -*- coding: utf-8 -*-
# 分析 GameBanana 鸣潮模组作者榜（按总点赞），并检测付费渠道
import json, re, time, urllib.request

PROXY = "http://127.0.0.1:7890"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
GAME = 20357
OUT = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_作者榜.json"

op = urllib.request.build_opener(urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}))
op.addheaders = [("User-Agent", UA), ("Accept", "application/json")]


def get(url, timeout=60):
    with op.open(url, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


mods = []
for page in range(1, 9):
    url = f"https://gamebanana.com/apiv11/Mod/Index?_nPerpage=50&_nPage={page}&_aFilters%5BGeneric_Game%5D={GAME}"
    try:
        d = json.loads(get(url))
    except Exception as e:
        print("page", page, "err", e)
        break
    recs = d.get("_aRecords") or []
    print(f"  page {page}: {len(recs)}")
    if not recs:
        break
    for m in recs:
        sub = m.get("_aSubmitter") or {}
        mods.append({
            "id": m.get("_idRow"),
            "name": m.get("_sName"),
            "likes": m.get("_nLikeCount") or 0,
            "views": m.get("_nViewCount") or 0,
            "author": sub.get("_sName") or "?",
            "author_id": sub.get("_idRow"),
        })
    time.sleep(0.5)

print("总模组:", len(mods))
by_author = {}
for m in mods:
    a = m["author"]
    s = by_author.setdefault(a, {"id": m["author_id"], "count": 0, "likes": 0, "mods": []})
    s["count"] += 1
    s["likes"] += m["likes"]
    s["mods"].append(m["name"])

top = sorted(by_author.items(), key=lambda kv: (-kv[1]["likes"], -kv[1]["count"]))[:20]
print("\n== 作者榜（按总点赞）==")
for name, s in top:
    print(f"  {name:<24} {s['count']:>3} 个模组  总赞 {s['likes']:>5}   id={s['id']}")

# 检测付费渠道
PAY = re.compile(r"(?i)(patreon\.com/[\w\-/]+|afdian\.com/a/[\w\-]+|afdian\.net/a/[\w\-]+|ko-fi\.com/[\w\-]+|fanbox\.cc/[\w\-]+|boosty\.to/[\w\-]+|gumroad\.com/[\w\-]+)")
info = {}
for name, s in top[:15]:
    if not s["id"]:
        continue
    try:
        p = json.loads(get(f"https://gamebanana.com/apiv11/Member/{s['id']}/ProfilePage"))
        text = json.dumps(p, ensure_ascii=False)
        links = sorted(set(PAY.findall(text)))
        info[name] = {"id": s["id"], "links": links, "mods": s["count"], "likes": s["likes"]}
        print(f"  {name:<24} 付费链接: {', '.join(links) if links else '无'}")
    except Exception as e:
        print(f"  {name:<24} 档案读取失败 {e}")
    time.sleep(0.4)

json.dump({"mods": mods, "authors": {k: v for k, v in top}, "contact": info},
          open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("\nSAVED:", OUT)

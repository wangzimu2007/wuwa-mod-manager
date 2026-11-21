# -*- coding: utf-8 -*-
# 抓取：直接帖子 + 所有合集内帖子（含图片名称与链接）
import json, re, time, urllib.request
import websocket

BASE = "http://127.0.0.1:9222"
UID = "9471f3349f5e11f0836652540025c377"
AUTHOR = "https://afdian.com/a/MorningStar"
OUT = r"E:\GameMods\WWMI-Mods\工具\_afdian_all_posts.json"


def new_tab(url):
    req = urllib.request.Request(BASE + "/json/new?" + url, method="PUT")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


class CDP:
    def __init__(self, ws):
        self.ws = websocket.create_connection(ws, timeout=90, suppress_origin=True)
        self.mid = 0

    def call(self, m, **p):
        self.mid += 1
        self.ws.send(json.dumps({"id": self.mid, "method": m, "params": p}))
        end = time.time() + 90
        while time.time() < end:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.mid:
                return msg
        return {}

    def ev(self, expr, retries=3):
        for i in range(retries):
            try:
                r = self.call("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
                v = (r.get("result") or {}).get("result", {}).get("value")
                if v is not None:
                    return v
            except Exception:
                time.sleep(2)
        return None

    def fetch(self, path):
        raw = self.ev("fetch(" + json.dumps(path) + ",{credentials:'include'}).then(r=>r.text())")
        try:
            return json.loads(raw) if raw else None
        except Exception:
            return None


def strip_html(s):
    s = re.sub(r"(?is)<(script|style).*?</\1>", "", s)
    s = re.sub(r"(?i)<br\s*/?>", "\n", s)
    s = re.sub(r"(?i)</p>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    return (s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<")
             .replace("&gt;", ">").replace("&quot;", '"').replace("&#39;", "'"))


def collect(c):
    posts = {}
    sn = 0
    for i in range(40):
        d = c.fetch(f"/api/post/get-list?user_id={UID}&type=old&publish_sn={sn}"
                    f"&per_page=20&group_id=&all=1&is_public=&plan_id=&title=&name=")
        lst = ((d or {}).get("data") or {}).get("list") or []
        new = 0
        for p in lst:
            if p.get("post_id") not in posts:
                posts[p["post_id"]] = p
                new += 1
        if not lst or not new:
            break
        sn = lst[-1].get("publish_sn") or 0
        if not sn:
            break
        time.sleep(0.3)
    print("直接帖子:", len(posts), flush=True)

    albums = []
    d = c.fetch(f"/api/user/get-album-list?user_id={UID}&page=1&per_page=50")
    for a in ((d or {}).get("data") or {}).get("list") or []:
        albums.append(a)
    print("合集数:", len(albums), flush=True)

    for a in albums:
        aid = a.get("album_id")
        title = a.get("title")
        page = 1
        got = 0
        while page <= 20:
            d2 = c.fetch(f"/api/user/get-album-post?album_id={aid}&page={page}&per_page=20")
            lst = ((d2 or {}).get("data") or {}).get("list") or []
            if not lst:
                break
            for p in lst:
                pid = p.get("post_id")
                if pid and pid not in posts:
                    posts[pid] = p
                    got += 1
            page += 1
            time.sleep(0.3)
        print(f"  合集《{title}》新增 {got} 帖", flush=True)
    print("去重后帖子总数:", len(posts), flush=True)
    return posts


def main():
    t = new_tab(AUTHOR)
    c = CDP(t["webSocketDebuggerUrl"])
    c.call("Runtime.enable")
    time.sleep(6)
    ck = c.ev("document.cookie") or ""
    print("auth_token:", "auth_token" in ck)
    posts = collect(c)

    rows = []
    for i, (pid, p) in enumerate(posts.items()):
        d = c.fetch(f"/api/post/get-detail?post_id={pid}")
        det = ((d or {}).get("data") or {}).get("post") or {}
        title = ((det.get("title") or p.get("title") or "")).strip()
        content = strip_html(det.get("content") or "")
        m = re.search(r"图片名称\s*为?\s*[：:]\s*([^\n]+)", content)
        image = m.group(1).strip() if m else ""
        links = {
            "baidu": sorted(set(re.findall(r"https?://pan\.baidu\.com/s/[\w\-]+[^\s)）]*", content))),
            "workupload": sorted(set(re.findall(r"https?://workupload\.com/file/[\w\-]+", content))),
            "other": sorted(set(re.findall(r"https?://(?:www\.)?(?:123pan|lanzou\w*|mega|drive\.google|workupload\.com/d)[^\s)）]*", content))),
        }
        rows.append({"post_id": pid, "title": title, "image_name": image,
                     "links": links, "time": p.get("publish_time"), "len": len(content)})
        if image or any(links.values()):
            print(f"  {'OK ' if image else 'LINK'}{title[:46]}", flush=True)
            if image:
                print(f"       {image}", flush=True)
        time.sleep(0.25)

    json.dump(rows, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    hit = sum(1 for r in rows if r["image_name"])
    lk = sum(1 for r in rows if any(r["links"].values()))
    print(f"\n共 {len(rows)} 帖；有密码 {hit}；有链接 {lk}")
    print("SAVED:", OUT)


if __name__ == "__main__":
    main()

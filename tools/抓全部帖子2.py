# -*- coding: utf-8 -*-
# 完整抓取爱发电（稳健版：重连 / 定位标签页 / 超时重试）
import json, re, time, urllib.request
import websocket

BASE = "http://127.0.0.1:9222"
UID = "9471f3349f5e11f0836652540025c377"
AUTHOR = "https://afdian.com/a/MorningStar"
OUT = r"E:\GameMods\WWMI-Mods\工具\_afdian_all_posts.json"


def http_get(p):
    with urllib.request.urlopen(urllib.request.Request(BASE + p), timeout=15) as r:
        return json.loads(r.read().decode())


def pick_page():
    pages = [t for t in http_get("/json/list") if t.get("type") == "page"]
    for t in pages:
        if "afdian.com" in t.get("url", ""):
            return t
    return pages[0] if pages else None


class CDP:
    def __init__(self, ws):
        self.ws = websocket.create_connection(ws, timeout=90, suppress_origin=True)
        self.mid = 0
        self.ws.settimeout(90)

    def call(self, m, **p):
        self.mid += 1
        self.ws.send(json.dumps({"id": self.mid, "method": m, "params": p}))
        deadline = time.time() + 90
        while time.time() < deadline:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.mid:
                return msg
        return {}

    def evaluate(self, expr, retries=3):
        for i in range(retries):
            try:
                r = self.call("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
                v = (r.get("result") or {}).get("result", {}).get("value")
                if v is not None:
                    return v
            except Exception as e:
                print(f"    eval 重试{i+1}: {e}", flush=True)
                time.sleep(2)
        return None


def strip_html(s):
    s = re.sub(r"(?is)<(script|style).*?</\1>", "", s)
    s = re.sub(r"(?i)<br\s*/?>", "\n", s)
    s = re.sub(r"(?i)</p>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    return (s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<")
             .replace("&gt;", ">").replace("&quot;", '"').replace("&#39;", "'"))


def new_tab(url):
    req = urllib.request.Request(BASE + "/json/new?" + url, method="PUT")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


def main():
    try:
        page = new_tab(AUTHOR)
        print("新标签:", page.get("url"))
    except Exception as e:
        print("新建标签失败，复用现有:", e)
        page = pick_page()
    print("TARGET:", page.get("url"))
    c = CDP(page["webSocketDebuggerUrl"])
    c.call("Runtime.enable")
    c.call("Page.enable")
    if "afdian.com" not in (page.get("url") or ""):
        c.call("Page.navigate", url=AUTHOR)
        time.sleep(10)
    c.evaluate("location.href")

    names = [x.split("=")[0] for x in (c.evaluate("document.cookie") or "").split("; ") if x]
    print("COOKIES:", names)
    if "auth_token" not in names:
        print("未登录")
        return

    posts, seen, sn = [], set(), 0
    for page_no in range(40):
        url = (f"/api/post/get-list?user_id={UID}&type=old&publish_sn={sn}"
               f"&per_page=20&group_id=&all=1&is_public=&plan_id=&title=&name=")
        raw = c.evaluate("fetch(" + json.dumps(url) + ",{credentials:'include'}).then(r=>r.text())")
        if not raw:
            print("page", page_no, "无返回，停止"); break
        try:
            d = json.loads(raw)
        except Exception:
            print("page", page_no, "解析失败", raw[:100]); break
        lst = (d.get("data") or {}).get("list") or []
        new = [p for p in lst if p.get("post_id") not in seen]
        print(f"  page {page_no}: {len(lst)} 条，新增 {len(new)}", flush=True)
        if not lst or not new:
            break
        for p in lst:
            if p.get("post_id") in seen:
                continue
            seen.add(p.get("post_id"))
            posts.append(p)
        sn = lst[-1].get("publish_sn") or 0
        if not sn:
            break
        time.sleep(0.4)

    print("帖子总数:", len(posts), flush=True)

    rows = []
    for i, p in enumerate(posts):
        pid = p["post_id"]
        raw = c.evaluate("fetch(" + json.dumps(f"/api/post/get-detail?post_id={pid}") +
                         ",{credentials:'include'}).then(r=>r.text())")
        title = (p.get("title") or "").strip()
        content = ""
        if raw:
            try:
                det = ((json.loads(raw).get("data") or {}).get("post") or {})
                title = (det.get("title") or title).strip()
                content = strip_html(det.get("content") or "")
            except Exception:
                pass
        m = re.search(r"图片名称\s*为?\s*[：:]\s*([^\n]+)", content)
        image = m.group(1).strip() if m else ""
        links = {
            "baidu": re.findall(r"https?://pan\.baidu\.com/s/[\w\-]+[^\s)）]*", content),
            "workupload": re.findall(r"https?://workupload\.com/file/[\w\-]+", content),
            "other": re.findall(r"https?://(?:www\.)?(?:123pan|lanzou\w*|mega|drive\.google|workupload\.com/d)[^\s)）]*", content),
        }
        rows.append({"post_id": pid, "title": title, "image_name": image,
                     "links": links, "time": p.get("publish_time"), "len": len(content)})
        flag = "OK " if image else ("LINK" if any(links.values()) else "-- ")
        print(f"  {flag}{title[:46]}", flush=True)
        if image:
            print(f"       {image}", flush=True)
        time.sleep(0.3)

    json.dump(rows, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    hit = sum(1 for r in rows if r["image_name"])
    print(f"\n共 {len(rows)} 帖；有密码 {hit}；有链接 {sum(1 for r in rows if any(r['links'].values()))}")
    print("SAVED:", OUT)


if __name__ == "__main__":
    main()

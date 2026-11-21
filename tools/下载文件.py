# -*- coding: utf-8 -*-
# workupload 通用下载器：python 下载文件.py <fileId> [输出目录]
import hashlib, http.cookiejar, json, os, re, sys, time, urllib.parse, urllib.request

BASE = "https://workupload.com"
PROXY = "http://127.0.0.1:7890"
SITE_PW = "star"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
OUTDIR = r"F:\GameMods\WWMI-Mods\Downloads\_晨星_full"

fid = sys.argv[1] if len(sys.argv) > 1 else ""
if len(sys.argv) > 2:
    OUTDIR = sys.argv[2]
if not fid:
    print("用法: python 下载文件.py <fileId>")
    sys.exit(1)

cj = http.cookiejar.CookieJar()
op = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(cj),
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}),
)
op.addheaders = [("User-Agent", UA), ("Accept-Language", "zh-CN,zh;q=0.9")]

def req(u, d=None, t=120, referer=None):
    if d is not None:
        d = urllib.parse.urlencode(d).encode()
    hdr = {"Referer": referer} if referer else {}
    with op.open(urllib.request.Request(u, data=d, headers=hdr), timeout=t) as r:
        return r.read().decode("utf-8", "replace")

def solve():
    d = json.loads(req(BASE + "/puzzle"))["data"]
    pz, fd, rg = d["puzzle"], d["find"], int(d["range"])
    got = {}
    for i in range(rg):
        h = hashlib.sha256((pz + str(i)).encode()).hexdigest()
        if h in fd:
            got[h] = i
            if len(got) == len(fd):
                break
    req(BASE + "/captcha", {"captcha": " ".join(str(got[x]) for x in fd) + " "})
    time.sleep(2)

file_url = f"{BASE}/file/{fid}"
h = req(file_url)
if "Are you a human" in h or "Security Check" in h:
    solve(); h = req(file_url)
if "Password protected" in h:
    req(file_url, {"passwordprotected_file[password]": SITE_PW, "passwordprotected_file[key]": fid})
    h = req(file_url)

t = re.search(r"(?is)<title>(.*?)</title>", h)
name = re.sub(r"\s+", " ", t.group(1)).strip() if t else fid
size = re.search(r"(?i)([\d\.,]+\s*(?:MB|GB|KB))", h)
print("NAME:", name)
print("SIZE:", size.group(1) if size else "?")

req(f"{BASE}/start/{fid}", t=60, referer=file_url)
info = json.loads(req(f"{BASE}/api/file/getDownloadServer/{fid}", t=90, referer=file_url))
url = (info.get("data") or {}).get("url") or ""
if not url:
    print("NO_URL", json.dumps(info, ensure_ascii=False)[:200]); sys.exit(2)

os.makedirs(OUTDIR, exist_ok=True)
safe = re.sub(r'[\\/:*?"<>|]', "_", name)[:120]
out = os.path.join(OUTDIR, f"{fid}_{safe}")
if not out.lower().endswith((".rar", ".zip", ".7z")):
    out += ".rar"
print("OUT:", out)
with op.open(urllib.request.Request(url, headers={"Referer": f"{BASE}/start/{fid}", "User-Agent": UA}), timeout=300) as r:
    total = int(r.headers.get("Content-Length") or 0)
    done = 0
    with open(out, "wb") as f:
        while True:
            c = r.read(1024 * 1024)
            if not c:
                break
            f.write(c); done += len(c)
print("DONE:", out, f"{os.path.getsize(out)/1048576:.1f} MB")

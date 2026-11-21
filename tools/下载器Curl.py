# -*- coding: utf-8 -*-
# 用 curl 下载 workupload：Python 负责过验证/拿直链并导出 cookie，curl 负责断点续传
import hashlib, http.cookiejar, json, os, re, subprocess, sys, time, urllib.parse, urllib.request

BASE = "https://workupload.com"
PROXY = "http://127.0.0.1:7890"
SITE_PW = "star"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
CURL = r"C:\Windows\System32\curl.exe"


def session():
    cj = http.cookiejar.MozillaCookieJar()
    op = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}),
    )
    op.addheaders = [("User-Agent", UA), ("Accept-Language", "zh-CN,zh;q=0.9")]
    return cj, op


def req(op, u, d=None, t=120, referer=None):
    if d is not None:
        d = urllib.parse.urlencode(d).encode()
    hdr = {"Referer": referer} if referer else {}
    with op.open(urllib.request.Request(u, data=d, headers=hdr), timeout=t) as r:
        return r.read().decode("utf-8", "replace")


def solve(op):
    d = json.loads(req(op, BASE + "/puzzle"))["data"]
    pz, fd, rg = d["puzzle"], d["find"], int(d["range"])
    got = {}
    for i in range(rg):
        h = hashlib.sha256((pz + str(i)).encode()).hexdigest()
        if h in fd:
            got[h] = i
            if len(got) == len(fd):
                break
    req(op, BASE + "/captcha", {"captcha": " ".join(str(got[x]) for x in fd) + " "})
    time.sleep(2)


def prepare(fid, out_dir):
    cj, op = session()
    url_page = f"{BASE}/file/{fid}"
    h = req(op, url_page)
    if "Are you a human" in h or "Security Check" in h:
        solve(op); h = req(op, url_page)
    if "Password protected" in h:
        req(op, url_page, {"passwordprotected_file[password]": SITE_PW, "passwordprotected_file[key]": fid})
        h = req(op, url_page)
    t = re.search(r"(?is)<title>(.*?)</title>", h)
    name = re.sub(r"\s+", " ", t.group(1)).strip() if t else fid
    req(op, f"{BASE}/start/{fid}", t=60, referer=url_page)
    info = json.loads(req(op, f"{BASE}/api/file/getDownloadServer/{fid}", referer=url_page))
    url = (info.get("data") or {}).get("url") or ""
    if not url:
        raise RuntimeError("no direct url")
    os.makedirs(out_dir, exist_ok=True)
    safe = re.sub(r'[\\/:*?"<>|]', "_", name)[:100]
    out = os.path.join(out_dir, f"{fid}_{safe}")
    if not out.lower().endswith((".rar", ".zip", ".7z")):
        out += ".rar"
    jar = os.path.join(out_dir, f"{fid}.cookies.txt")
    cj.save(jar, ignore_discard=True, ignore_expires=True)
    return url, jar, out, f"{BASE}/start/{fid}"


def download(fid, out_dir, tries=4):
    for attempt in range(tries):
        try:
            url, jar, out, referer = prepare(fid, out_dir)
            if os.path.exists(out) and os.path.getsize(out) > 1 << 20:
                return out
            tmp = out + ".part"
            cmd = [
                CURL, "-L", "--fail", "-x", PROXY, "-A", UA, "-e", referer,
                "-b", jar, "-C", "-", "--retry", "5", "--retry-delay", "3",
                "--connect-timeout", "30", "--max-time", "3600",
                "-o", tmp, url,
            ]
            subprocess.run(cmd, capture_output=True, timeout=3700)
            if os.path.exists(tmp) and os.path.getsize(tmp) > 1 << 20:
                with open(tmp, "rb") as f:
                    head = f.read(8)
                if head[:4] == b"Rar!" or head[:2] == b"PK":
                    os.replace(tmp, out)
                    return out
            print(f"    第{attempt+1}次未完成，重试…", flush=True)
        except Exception as e:
            print(f"    第{attempt+1}次异常：{e}", flush=True)
        time.sleep(4)
    raise RuntimeError("下载失败")


if __name__ == "__main__":
    fid = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else r"F:\GameMods\WWMI-Mods\Downloads\_晨星_full"
    print(download(fid, out_dir))

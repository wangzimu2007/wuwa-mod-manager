# -*- coding: utf-8 -*-
# 用 curl 重试下载失败的晨星旧作（比 urllib 更稳）
import json, os, re, shutil, subprocess, sys, time

PROXY = "http://127.0.0.1:7890"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
CURL = r"C:\Windows\System32\curl.exe"
DL = r"F:\GameMods\WWMI-Mods\Downloads\_晨星香蕉网"
STAGE = r"E:\GameMods\WWMI-Mods\_stage_gb"
LIB = r"F:\GameMods\WWMI-Mods\Skins"
MODS = os.path.join(os.environ["APPDATA"], r"XXMI Launcher\WWMI\Mods")
UNRAR = r"E:\GameMods\WWMI-Mods\工具\_rarlab\unrar\UnRAR.exe"
SEVEN = r"D:\tools\7zr\7za.exe"
MISSING = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_晨星缺清单.json"
LOG = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_晨星香蕉网补齐日志.csv"

CHARS = ["卡提希娅", "爱弥斯", "千咲", "穗穗", "清宵", "心月狐", "菲比", "今汐", "守岸人",
         "珂莱塔", "嘉贝莉娜", "洛瑟菈", "露西", "丽贝卡", "莫宁", "西格莉卡", "景燃", "琳奈",
         "莉莉", "锁暝", "秧秧", "女主", "漂泊者", "仇远", "白芷", "安可", "椿", "长离",
         "达妮娅", "奥古斯塔", "尤诺", "维利奈", "陆赫斯", "摩托", "宝箱怪", "钢铁", "绯雪", "玄翎"]

MAP = {"陆·赫斯": "陆赫斯", "男": "漂泊者", "女主": "漂泅者"}


def done_names():
    s = set()
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8-sig") as f:
            for line in f:
                p = line.strip().split(",")
                if len(p) > 5 and p[-1] == "OK":
                    s.add(p[1])
    return s


def curl_dl(url, out, referer="https://gamebanana.com/"):
    tmp = out + ".part"
    for i in range(4):
        resume = ["-C", "-"] if (os.path.exists(tmp) and os.path.getsize(tmp) > 0) else []
        cmd = [CURL, "-L", "-x", PROXY, "-A", UA, "-e", referer,
               "--retry", "5", "--retry-delay", "3", "--connect-timeout", "30",
               "--max-time", "2400"] + resume + ["-o", tmp, url]
        subprocess.run(cmd, capture_output=True, timeout=2500)
        if os.path.exists(tmp) and os.path.getsize(tmp) > 1 << 20:
            with open(tmp, "rb") as f:
                head = f.read(8)
            if head[:4] == b"Rar!" or head[:2] == b"PK" or head[:6] == b"7z\xbc\xaf\x27\x1c":
                os.replace(tmp, out)
                return os.path.getsize(out)
        print(f"    第{i+1}次未完成", flush=True)
        time.sleep(3)
    return 0


def extract(archive, dest):
    if archive.lower().endswith(".rar"):
        p = subprocess.run([UNRAR, "x", "-y", "-o+", archive, dest + "\\"], capture_output=True, timeout=3600)
    else:
        p = subprocess.run([SEVEN, "x", archive, "-o" + dest, "-y"], capture_output=True, timeout=3600)
    t = (p.stdout + p.stderr).decode("gbk", "replace") + (p.stdout + p.stderr).decode("utf-8", "replace")
    return ("All OK" in t) or ("No errors" in t) or ("Everything is Ok" in t), t[-150:]


def scan_guids(root):
    g = {}
    for dp, _, fs in os.walk(root):
        for fn in fs:
            if fn.lower().endswith(".ini") and ".bak" not in fn.lower():
                try:
                    t = open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()
                except Exception:
                    continue
                m = re.search(r"object_guid\s*=\s*(\d+)", t)
                if m:
                    g.setdefault(m.group(1), set()).add(dp)
    return g


def pick_char(name):
    for c in CHARS:
        if c in name:
            return MAP.get(c, c)
    return "_其他"


def install(root, guids):
    for g, dirs in guids.items():
        existing = None
        for d in os.listdir(MODS):
            ini = os.path.join(MODS, d, "mod.ini")
            if os.path.isfile(ini):
                try:
                    if re.search(r"object_guid\s*=\s*" + g, open(ini, encoding="utf-8", errors="ignore").read()):
                        existing = d
                        break
                except Exception:
                    pass
        if existing:
            print(f"      guid {g} 已在 {existing}，只入库", flush=True)
            continue
        dest = os.path.join(MODS, "Skin_" + g)
        os.makedirs(dest, exist_ok=True)
        for d in dirs:
            sub = dest if len(dirs) == 1 else os.path.join(dest, os.path.basename(d))
            subprocess.run(["robocopy", d, sub, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"], capture_output=True)
        print(f"      已安装 → Skin_{g}", flush=True)


def main():
    missing = json.load(open(MISSING, encoding="utf-8"))
    skip = done_names()
    todo = [m for m in missing if m["name"] not in skip]
    print("待重试:", len(todo), flush=True)
    op = None
    ok = bad = 0
    for m in todo:
        name = m["name"]
        print(f"\n== {name}", flush=True)
        # 用 curl 抓档案 JSON
        try:
            raw = subprocess.run([CURL, "-sL", "-x", PROXY, "-A", UA, "--max-time", "60",
                                  f"https://gamebanana.com/apiv11/Mod/{m['id']}/ProfilePage"],
                                 capture_output=True, timeout=90).stdout.decode("utf-8", "replace")
            prof = json.loads(raw)
        except Exception as e:
            print("  档案失败", e); bad += 1; continue
        files = prof.get("_aFiles") or []
        if not files:
            print("  无文件"); bad += 1; continue
        stage = os.path.join(STAGE, str(m["id"]))
        shutil.rmtree(stage, ignore_errors=True)
        os.makedirs(stage, exist_ok=True)
        good_any = False
        for fi, f in enumerate(files):
            url = f.get("_sDownloadUrl") or ("https://gamebanana.com/dl/%s" % f.get("_idRow"))
            fname = re.sub(r'[\\/:*?"<>|]', "_", f.get("_sFile") or f"{m['id']}_{fi}.rar")
            out = os.path.join(DL, fname)
            if not os.path.exists(out) or os.path.getsize(out) < 1 << 20:
                sz = curl_dl(url, out)
                if sz:
                    print(f"  下载 {sz/1048576:.1f} MB", flush=True)
                else:
                    print("  下载失败", flush=True); continue
            sub = os.path.join(stage, str(fi))
            os.makedirs(sub, exist_ok=True)
            okx, err = extract(out, sub)
            if not okx:
                print("  解压失败", err); continue
            good_any = True
        if not good_any:
            bad += 1; continue
        tops = [d for d in os.listdir(stage) if os.path.isdir(os.path.join(stage, d))]
        root = os.path.join(stage, tops[0]) if len(tops) == 1 else stage
        guids = scan_guids(root)
        print("  guid:", ",".join(guids.keys()) or "无", flush=True)
        char = pick_char(name)
        chdir = os.path.join(LIB, char)
        os.makedirs(chdir, exist_ok=True)
        mx = 0
        for d in os.listdir(chdir):
            mm = re.match(r"(\d+)_", d)
            if mm:
                mx = max(mx, int(mm.group(1)))
        libdst = os.path.join(chdir, "%03d_%s" % (mx + 1, re.sub(r'[\\/:*?"<>|]', "_", name)))
        subprocess.run(["robocopy", root, libdst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"], capture_output=True)
        size_mb = round(sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fs in os.walk(libdst) for fn in fs) / 1048576, 1)
        print(f"  入库：{os.path.basename(libdst)}  {size_mb} MB", flush=True)
        if guids:
            install(root, guids)
        with open(LOG, "a", encoding="utf-8-sig") as f:
            f.write("%s,%s,%s,%s,%s,OK\n" % (time.strftime("%Y-%m-%d %H:%M"), name, size_mb,
                                             ",".join(guids.keys()), os.path.basename(libdst)))
        shutil.rmtree(stage, ignore_errors=True)
        ok += 1

    print(f"\n重试完成：成功 {ok}，失败 {bad}", flush=True)


if __name__ == "__main__":
    main()

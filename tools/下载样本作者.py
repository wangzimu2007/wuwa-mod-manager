# -*- coding: utf-8 -*-
# 下载 3 个免费高赞样本：存库 + 可选激活
import json, os, re, shutil, subprocess, sys, time, urllib.request

PROXY = "http://127.0.0.1:7890"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
DL = r"F:\GameMods\WWMI-Mods\Downloads\_其他作者"
STAGE = r"E:\GameMods\WWMI-Mods\_stage_other"
LIB = r"F:\GameMods\WWMI-Mods\Skins"
MODS = os.path.join(os.environ["APPDATA"], r"XXMI Launcher\WWMI\Mods")
UNRAR = r"E:\GameMods\WWMI-Mods\工具\_rarlab\unrar\UnRAR.exe"
SEVEN = r"D:\tools\7zr\7za.exe"

REP = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_作者代表作.json"
_reps = {r["author"]: r for r in json.load(open(REP, encoding="utf-8"))}

# (作者, 代表作条目, 中文角色, 是否激活)
WANT = [
    ("SpacePig", "琳奈", True),
    ("Nait3D", "穗穗", False),
    ("B0ringMgx", "心月狐", False),
]
SAMPLES = []
for author, char, act in WANT:
    r = _reps.get(author)
    if not r:
        print("缺代表作数据:", author); continue
    SAMPLES.append((r["best_id"], author, r["best_name"], char, act))

os.makedirs(DL, exist_ok=True)
os.makedirs(STAGE, exist_ok=True)
op = urllib.request.build_opener(urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}))
op.addheaders = [("User-Agent", UA), ("Accept", "application/json")]


def get(url, t=60):
    with op.open(url, timeout=t) as r:
        return r.read().decode("utf-8", "replace")


def dl_file(url, out, t=600):
    req = urllib.request.Request(url, headers={"Referer": "https://gamebanana.com/", "User-Agent": UA})
    with op.open(req, timeout=t) as r, open(out, "wb") as f:
        while True:
            c = r.read(1 << 20)
            if not c:
                break
            f.write(c)
    return os.path.getsize(out)


def extract(archive, dest):
    if archive.lower().endswith(".rar"):
        p = subprocess.run([UNRAR, "x", "-y", "-o+", archive, dest + "\\"], capture_output=True, timeout=3600)
    else:
        p = subprocess.run([SEVEN, "x", archive, "-o" + dest, "-y"], capture_output=True, timeout=3600)
    t = (p.stdout + p.stderr).decode("gbk", "replace") + (p.stdout + p.stderr).decode("utf-8", "replace")
    return ("All OK" in t) or ("No errors" in t) or ("Everything is Ok" in t), t[-200:]


def scan_guids(root):
    guids = {}
    for dp, _, fs in os.walk(root):
        for fn in fs:
            if fn.lower().endswith(".ini") and ".bak" not in fn.lower():
                try:
                    t = open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()
                except Exception:
                    continue
                m = re.search(r"object_guid\s*=\s*(\d+)", t)
                if m:
                    guids.setdefault(m.group(1), set()).add(dp)
    return guids


def lib_add(char, root, name):
    chdir = os.path.join(LIB, char)
    os.makedirs(chdir, exist_ok=True)
    mx = 0
    for d in os.listdir(chdir):
        m = re.match(r"(\d+)_", d)
        if m:
            mx = max(mx, int(m.group(1)))
    dst = os.path.join(chdir, "%03d_%s_样品" % (mx + 1, re.sub(r'[\\/:*?"<>|]', "_", name)))
    subprocess.run(["robocopy", root, dst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"], capture_output=True)
    return dst


def activate(root, guids, tag):
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
        dest = os.path.join(MODS, existing) if existing else os.path.join(MODS, "Skin_" + g)
        if existing:
            bak = os.path.join(MODS, "DISABLED %s_%s" % (existing, tag))
            shutil.rmtree(bak, ignore_errors=True)
            try:
                os.rename(dest, bak)
            except Exception:
                pass
        os.makedirs(dest, exist_ok=True)
        for d in dirs:
            sub = dest if len(dirs) == 1 else os.path.join(dest, os.path.basename(d))
            subprocess.run(["robocopy", d, sub, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"], capture_output=True)
        print("      → 已激活:", os.path.basename(dest))


def main():
    for mod_id, author, name, char, do_activate in SAMPLES:
        print(f"\n== {author} / {name} ==", flush=True)
        try:
            p = json.loads(get(f"https://gamebanana.com/apimod/{mod_id}")) if False else None
        except Exception:
            p = None
        try:
            prof = json.loads(get(f"https://gamebanana.com/apiv11/Mod/{mod_id}/ProfilePage"))
        except Exception as e:
            print("  档案读取失败", e); continue
        files = prof.get("_aFiles") or []
        if not files:
            print("  没有文件"); continue
        f0 = files[0]
        url = f0.get("_sDownloadUrl")
        fname = re.sub(r'[\\/:*?"<>|]', "_", f0.get("_sFile") or (name + ".rar"))
        out = os.path.join(DL, f"{mod_id}_{fname}")
        if not os.path.exists(out) or os.path.getsize(out) < 1 << 20:
            try:
                size = dl_file(url, out)
                print(f"  下载 {size/1048576:.1f} MB")
            except Exception as e:
                print("  下载失败", e); continue
        else:
            print(f"  已存在 {os.path.getsize(out)/1048576:.1f} MB")
        stage = os.path.join(STAGE, str(mod_id))
        shutil.rmtree(stage, ignore_errors=True)
        os.makedirs(stage, exist_ok=True)
        ok, err = extract(out, stage)
        if not ok:
            print("  解压失败:", err); continue
        tops = [d for d in os.listdir(stage) if os.path.isdir(os.path.join(stage, d))]
        root = os.path.join(stage, tops[0]) if len(tops) == 1 else stage
        guids = scan_guids(root)
        print("  guid:", ",".join(guids.keys()) or "无")
        dst = lib_add(char, root, name)
        print("  入库:", os.path.basename(dst))
        if do_activate and guids:
            activate(root, guids, author)
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    main()

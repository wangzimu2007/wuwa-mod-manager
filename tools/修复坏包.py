# -*- coding: utf-8 -*-
# 修复 2 个损坏包：按 Content-Length 校验重下，再解压入库
import json, os, re, shutil, subprocess, sys, time

PROXY = "http://127.0.0.1:7890"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
CURL = r"C:\Windows\System32\curl.exe"
DL = r"F:\GameMods\WWMI-Mods\Downloads\_晨星香蕉网"
STAGE = r"E:\GameMods\WWMI-Mods\_stage_gb"
LIB = r"F:\GameMods\WWMI-Mods\Skins"
MODS = os.path.join(os.environ["APPDATA"], r"XXMI Launcher\WWMI\Mods")
UNRAR = r"E:\GameMods\WWMI-Mods\工具\_rarlab\unrar\UnRAR.exe"
LOG = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_晨星香蕉网补齐日志.csv"
MISSING = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_晨星缺清单.json"

TARGETS = ["Baizhi(白芷)-Crimson Bud Beyond Lab-Num016", "秧秧·玄翎-关山海-序列050", "白芷", "关山海"]


def head_size(url):
    out = subprocess.run([CURL, "-sIL", "-x", PROXY, "-A", UA, "-e", "https://gamebanana.com/",
                          "--max-time", "60", url], capture_output=True, timeout=90).stdout.decode("utf-8", "replace")
    sizes = re.findall(r"(?i)content-length:\s*(\d+)", out)
    return int(sizes[-1]) if sizes else 0


def download(url, out):
    total = head_size(url)
    for i in range(5):
        tmp = out + ".part"
        if os.path.exists(tmp):
            os.remove(tmp)
        subprocess.run([CURL, "-L", "-x", PROXY, "-A", UA, "-e", "https://gamebanana.com/",
                        "--retry", "5", "--retry-delay", "2", "--connect-timeout", "30",
                        "--max-time", "2400", "-o", tmp, url], capture_output=True, timeout=2500)
        if not os.path.exists(tmp):
            continue
        size = os.path.getsize(tmp)
        with open(tmp, "rb") as f:
            head = f.read(4)
        if head == b"Rar!" and (total == 0 or size == total):
            os.replace(tmp, out)
            return size, total
        print(f"    第{i+1}次：{size} / {total} 不符，重下", flush=True)
    return 0, total


def extract(archive, dest):
    p = subprocess.run([UNRAR, "x", "-y", "-o+", archive, dest + "\\"], capture_output=True, timeout=3600)
    t = (p.stdout + p.stderr).decode("gbk", "replace") + (p.stdout + p.stderr).decode("utf-8", "replace")
    return ("All OK" in t) or ("No errors" in t), t[-200:]


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
    todo = [m for m in missing if any(t in m["name"] for t in ["Num016", "序列050"])]
    print("待修复:", [m["name"] for m in todo], flush=True)
    for m in todo:
        print(f"\n== {m['name']}", flush=True)
        raw = subprocess.run([CURL, "-s", "-x", PROXY, "-A", UA, "--max-time", "60",
                              f"https://gamebanana.com/apiv11/Mod/{m['id']}/ProfilePage"],
                             capture_output=True, timeout=90).stdout.decode("utf-8", "replace")
        prof = json.loads(raw)
        files = prof.get("_aFiles") or []
        stage = os.path.join(STAGE, str(m["id"]))
        shutil.rmtree(stage, ignore_errors=True)
        os.makedirs(stage, exist_ok=True)
        okany = False
        for fi, f in enumerate(files):
            url = f.get("_sDownloadUrl") or f"https://gamebanana.com/dl/{f.get('_idRow')}"
            fname = re.sub(r'[\\/:*?"<>|]', "_", f.get("_sFile") or f"{m['id']}_{fi}.rar")
            out = os.path.join(DL, fname)
            if os.path.exists(out):
                os.remove(out)
            size, total = download(url, out)
            if not size:
                print("  下载仍失败", flush=True); continue
            print(f"  下载完整 {size/1048576:.1f} MB", flush=True)
            sub = os.path.join(stage, str(fi))
            os.makedirs(sub, exist_ok=True)
            good, err = extract(out, sub)
            if good:
                okany = True
            else:
                print("  解压失败", err, flush=True)
        if not okany:
            continue
        # 找内容根
        inis = []
        for dp, _, fs in os.walk(stage):
            for fn in fs:
                if fn.lower().endswith(".ini"):
                    inis.append(os.path.join(dp, fn))
        tops = [d for d in os.listdir(stage) if os.path.isdir(os.path.join(stage, d))]
        root = os.path.join(stage, tops[0]) if len(tops) == 1 else stage
        guids = scan_guids(root)
        char = "白芷" if "Num016" in m["name"] else "秧秧"
        chdir = os.path.join(LIB, char)
        os.makedirs(chdir, exist_ok=True)
        mx = 0
        for d in os.listdir(chdir):
            mm = re.match(r"(\d+)_", d)
            if mm:
                mx = max(mx, int(mm.group(1)))
        libdst = os.path.join(chdir, "%03d_%s" % (mx + 1, re.sub(r'[\\/:*?"<>|]', "_", m["name"])))
        subprocess.run(["robocopy", root, libdst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"], capture_output=True)
        size_mb = round(sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fs in os.walk(libdst) for fn in fs) / 1048576, 1)
        print(f"  入库：{os.path.basename(libdst)} {size_mb} MB  guid={','.join(guids.keys())}", flush=True)
        if guids:
            install(root, guids)
        with open(LOG, "a", encoding="utf-8-sig") as f:
            f.write("%s,%s,%s,%s,%s,OK\n" % (time.strftime("%Y-%m-%d %H:%M"), m["name"], size_mb,
                                             ",".join(guids.keys()), os.path.basename(libdst)))
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    main()

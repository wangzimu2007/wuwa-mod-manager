# -*- coding: utf-8 -*-
# 最终批量：curl 下载 + 嵌套包处理 + 跳过已装
import json, os, re, shutil, subprocess, sys, time

sys.path.insert(0, r"E:\GameMods\WWMI-Mods\工具")
import importlib.util
spec = importlib.util.spec_from_file_location("dl", r"E:\GameMods\WWMI-Mods\工具\下载器Curl.py")
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

DL_DIR = r"F:\GameMods\WWMI-Mods\Downloads\_晨星_full"
STAGE = r"E:\GameMods\WWMI-Mods\_stage_full"
UNRAR = r"E:\GameMods\WWMI-Mods\工具\_rarlab\unrar\UnRAR.exe"
MODS = os.path.join(os.environ["APPDATA"], r"XXMI Launcher\WWMI\Mods")
LIB = r"F:\GameMods\WWMI-Mods\Skins"
TABLE = r"E:\GameMods\WWMI-Mods\工具\_晨星完整版密码表.csv"
PARSED = r"E:\GameMods\WWMI-Mods\工具\_afdian_parsed.json"
LOG = r"E:\GameMods\WWMI-Mods\使用记录\鸣潮\_完整版批量日志.csv"
LIB_ONLY = {"058"}   # 已手动入库的（同 guid 冲突，放库内备用）

os.makedirs(DL_DIR, exist_ok=True)
os.makedirs(STAGE, exist_ok=True)


def extract(archive, password, dest):
    p = subprocess.run([UNRAR, "x", "-y", "-o+", "-p" + password, archive, dest + "\\"],
                       capture_output=True, timeout=3600)
    t = (p.stdout + p.stderr).decode("gbk", "replace") + (p.stdout + p.stderr).decode("utf-8", "replace")
    return (("All OK" in t) or ("No errors" in t)), t[-300:]


def scan_guids(root):
    guids = {}
    for dp, _, fs in os.walk(root):
        for fn in fs:
            if not fn.lower().endswith(".ini") or ".bak" in fn.lower():
                continue
            try:
                t = open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            m = re.search(r"object_guid\s*=\s*(\d+)", t)
            if m:
                guids.setdefault(m.group(1), set()).add(dp)
    return guids


def num_of(s):
    m = re.search(r"(?:序列|num)?\s*(\d{3})", s, re.I)
    return m.group(1) if m else None


def load_table():
    rows = []
    with open(TABLE, encoding="utf-8-sig") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line or i == 0:
                continue
            p = line.split(",", 2)
            if len(p) >= 3:
                rows.append({"name": p[0], "fid": p[1], "pw": p[2]})
    return rows


def done_mods():
    done = set(LIB_ONLY)
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8-sig") as f:
            for line in f:
                p = line.strip().split(",")
                if len(p) >= 6 and p[5] in ("OK", "LIB"):
                    done.add(num_of(p[1]))
    return done


def install_pack(root, guids, mod_name, size_mb, cache):
    for g, dirs in guids.items():
        existing = None
        for d in os.listdir(MODS):
            ini = os.path.join(MODS, d, "mod.ini")
            if os.path.isfile(ini):
                try:
                    if re.search(r"object_guid\s*=\s*" + g, open(ini, encoding="utf-8", errors="ignore").read()):
                        existing = d; break
                except Exception:
                    pass
        dest = os.path.join(MODS, existing) if existing else os.path.join(MODS, f"Skin_{g}")
        if existing:
            bak = os.path.join(MODS, f"DISABLED {existing}_old")
            shutil.rmtree(bak, ignore_errors=True)
            try:
                os.rename(dest, bak)
            except Exception:
                pass
        os.makedirs(dest, exist_ok=True)
        for d in dirs:
            sub = dest if len(dirs) == 1 else os.path.join(dest, os.path.basename(d))
            subprocess.run(["robocopy", d, sub, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"],
                           capture_output=True)
        print(f"      → {os.path.basename(dest)}", flush=True)
        with open(LOG, "a", encoding="utf-8-sig") as f:
            f.write("%s,%s,%s,%s,%s,OK\n" % (time.strftime("%Y-%m-%d %H:%M"), mod_name, size_mb, g, os.path.basename(dest)))
    ch = cache.get(next(iter(guids)))
    if ch:
        chdir = os.path.join(LIB, ch)
        os.makedirs(chdir, exist_ok=True)
        mx = 0
        for d in os.listdir(chdir):
            m = re.match(r"(\d+)_", d)
            if m:
                mx = max(mx, int(m.group(1)))
        libdst = os.path.join(chdir, "%03d_%s_FULL" % (mx + 1, re.sub(r'[\\/:*?"<>|]', "_", mod_name)))
        subprocess.run(["robocopy", root, libdst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/R:1", "/W:1"],
                       capture_output=True)
        print(f"      入库：{os.path.basename(libdst)}", flush=True)


def main():
    rows = load_table()
    parsed = json.load(open(PARSED, encoding="utf-8"))
    pw_by_num = {}
    for r in parsed:
        n = num_of(r["title"])
        if n and r["image_name"]:
            pw_by_num[n] = r["image_name"]
    done = done_mods()
    print(f"表格 {len(rows)}；已处理 {sorted(done)}", flush=True)

    cache = {}
    cp = os.path.join(LIB, "_index_cache.json")
    if os.path.exists(cp):
        try:
            j = json.load(open(cp, encoding="utf-8"))
            for ch, skins in j.items():
                for s in skins:
                    for g in s.get("guids") or []:
                        cache[g] = ch
        except Exception:
            pass

    ok = bad = skip = 0
    for r in rows:
        n = num_of(r["name"])
        if n in done:
            print(f"== {r['name']} 已处理，跳过", flush=True); skip += 1; continue
        pw = r["pw"].strip() or pw_by_num.get(n, "")
        print(f"\n== {r['name']} ({r['fid']})", flush=True)
        if not r["fid"] or r["fid"] == "-" or not pw:
            print("    跳过：缺链接或密码", flush=True); skip += 1; continue
        try:
            arc = dl.download(r["fid"], DL_DIR)
        except Exception as e:
            print(f"    下载失败：{e}", flush=True); bad += 1
            with open(LOG, "a", encoding="utf-8-sig") as f:
                f.write("%s,%s,,,,下载失败\n" % (time.strftime("%Y-%m-%d %H:%M"), r["name"]))
            continue
        size_mb = round(os.path.getsize(arc) / 1048576, 1)
        stage = os.path.join(STAGE, r["fid"])
        shutil.rmtree(stage, ignore_errors=True)
        os.makedirs(stage, exist_ok=True)
        good, err = extract(arc, pw, stage)
        if not good:
            print(f"    解压失败：{err}", flush=True); bad += 1
            continue
        tops = [d for d in os.listdir(stage) if os.path.isdir(os.path.join(stage, d))]
        root = os.path.join(stage, tops[0]) if len(tops) == 1 else stage
        guids = scan_guids(root)
        if not guids:
            # 嵌套包：解出内层 rar 再扫
            inner = []
            for dp, _, fs in os.walk(root):
                for fn in fs:
                    if fn.lower().endswith((".rar", ".7z", ".zip")):
                        inner.append(os.path.join(dp, fn))
            print(f"    嵌套包：内层 {len(inner)} 个", flush=True)
            for i, arc2 in enumerate(sorted(inner)):
                sub = os.path.join(stage, "inner_%d" % i)
                os.makedirs(sub, exist_ok=True)
                ok2, err2 = extract(arc2, pw, sub)
                if not ok2:
                    print(f"      内层失败：{err2}", flush=True); continue
                g2 = scan_guids(sub)
                if not g2:
                    continue
                print(f"      内层 {i}: guid {','.join(g2.keys())}", flush=True)
                install_pack(sub, g2, r["name"] + "-inner%d" % i, size_mb, cache)
            shutil.rmtree(stage, ignore_errors=True)
            ok += 1
            continue
        print(f"    guid：{','.join(guids.keys())}", flush=True)
        install_pack(root, guids, r["name"], size_mb, cache)
        shutil.rmtree(stage, ignore_errors=True)
        ok += 1

    print(f"\n本轮：新装 {ok}，失败 {bad}，跳过 {skip}", flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""鸣潮 Mod 皮肤管理器（本地网页版）
- 扫描 E:\\GameMods\\WWMI-Mods\\Skins\\<角色>\\<编号>_<名字>\\ 作为皮肤库
- 安装：按 ini 里的 object_guid 找到对应的 Mods 子目录，清空后扁平拷贝
- 恢复：从 Skins\\_原版备份\\<Mods子目录> 还原
- 导入：把任意 mod 文件夹拷进库并按序编号
"""
import json
import os
import re
import shutil
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

def _load_config():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "config.json")
    cfg = {
        "skinsDir": os.path.join(os.path.expanduser("~"), "Documents", "WuwaMods", "Skins"),
        "modsDir": os.path.join(os.environ.get("APPDATA", ""), "XXMI Launcher", "WWMI", "Mods"),
    }
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8-sig") as fh:
                data = json.load(fh)
            for k in ("skinsDir", "modsDir"):
                if data.get(k):
                    cfg[k] = os.path.expandvars(os.path.expanduser(data[k]))
        except Exception:
            pass
    return cfg


_CFG = _load_config()
SKINS = _CFG["skinsDir"]
BACKUP = os.path.join(SKINS, "_原版备份")
MODS = _CFG["modsDir"]
PORT = 8791

GUID_RE = re.compile(r"object_guid\s*=\s*(\d+)")
LOCK = threading.Lock()
CACHE = {"stamp": None, "data": None}


def scan_ini_guids(skin_dir):
    guids = []
    keys = 0
    for root, _dirs, files in os.walk(skin_dir):
        for fn in files:
            if not fn.lower().endswith(".ini"):
                continue
            path = os.path.join(root, fn)
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                    txt = fh.read()
            except OSError:
                continue
            m = GUID_RE.search(txt)
            if m and m.group(1) not in guids:
                guids.append(m.group(1))
            keys += len(re.findall(r"^\s*\[Key", txt, re.M))
    return guids, keys


def find_thumb(skin_dir):
    for root, _dirs, files in os.walk(skin_dir):
        for fn in files:
            low = fn.lower()
            if low.startswith("preview") and low.endswith((".jpg", ".png", ".jpeg", ".webp")):
                return os.path.join(root, fn)
    return None


def find_readme(skin_dir):
    for root, _dirs, files in os.walk(skin_dir):
        for fn in files:
            low = fn.lower()
            if low.endswith(".txt") and any(k in fn for k in ("read", "说明", "切换", "列表", "注意")):
                try:
                    with open(os.path.join(root, fn), "r", encoding="utf-8", errors="ignore") as fh:
                        return fh.read()[:1500]
                except OSError:
                    return ""
    return ""


def form_name(guid):
    for char, forms in FORM_MAP.items():
        for f in forms:
            if guid in f["guids"]:
                return f["label"]
    return "形态 " + guid


def installed_folders():
    """扫描 Mods，返回 guid -> 文件夹名 的映射（以已装 mod 为准）"""
    mapping = {}
    if not os.path.isdir(MODS):
        return mapping
    for name in os.listdir(MODS):
        path = os.path.join(MODS, name)
        if not os.path.isdir(path):
            continue
        guids, _ = scan_ini_guids(path)
        for g in guids:
            mapping.setdefault(g, name)
    return mapping


def build_index():
    """扫描皮肤库，返回 {character: [ {num,name,guids,keys,thumb,readme} ]}"""
    out = {}
    if not os.path.isdir(SKINS):
        return out
    for char in sorted(os.listdir(SKINS)):
        cdir = os.path.join(SKINS, char)
        if not os.path.isdir(cdir) or char.startswith("_"):
            continue
        items = []
        for name in sorted(os.listdir(cdir)):
            sdir = os.path.join(cdir, name)
            if not os.path.isdir(sdir):
                continue
            m = re.match(r"^(\d+)_(.*)$", name)
            if not m:
                continue
            guids, keys = scan_ini_guids(sdir)
            items.append({
                "num": m.group(1),
                "name": m.group(2),
                "guids": guids,
                "keys": keys,
                "hasThumb": bool(find_thumb(sdir)),
            })
        if items:
            out[char] = items
    return out


def get_index():
    stamp = []
    for char in os.listdir(SKINS) if os.path.isdir(SKINS) else []:
        cdir = os.path.join(SKINS, char)
        if os.path.isdir(cdir) and not char.startswith("_"):
            stamp.append((char, len(os.listdir(cdir))))
    sig = tuple(sorted(stamp))
    with LOCK:
        if CACHE["stamp"] != sig:
            CACHE["data"] = build_index()
            CACHE["stamp"] = sig
        return CACHE["data"]


def skin_dir(char, num):
    cdir = os.path.join(SKINS, char)
    if not os.path.isdir(cdir):
        return None
    for name in os.listdir(cdir):
        if name.startswith(num + "_"):
            return os.path.join(cdir, name)
    return None


def copy_mod(src_dir, dst_dir):
    """扁平拷贝：src_dir 内容拷到 dst_dir 根"""
    os.makedirs(dst_dir, exist_ok=True)
    for item in os.listdir(src_dir):
        s = os.path.join(src_dir, item)
        d = os.path.join(dst_dir, item)
        if os.path.isdir(s):
            shutil.copytree(s, d, dirs_exist_ok=True)
        else:
            shutil.copy2(s, d)


def install(char, num, target_guid):
    sdir = skin_dir(char, num)
    if not sdir:
        return {"ok": False, "msg": "找不到皮肤目录"}
    sources = {}
    for root, _dirs, files in os.walk(sdir):
        for fn in files:
            if not fn.lower().endswith(".ini"):
                continue
            try:
                txt = open(os.path.join(root, fn), "r", encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            m = GUID_RE.search(txt)
            if not m:
                continue
            g = m.group(1)
            if target_guid != "all" and g != target_guid:
                continue
            sources.setdefault(g, set()).add(root)
    if not sources:
        return {"ok": False, "msg": "这套皮肤没有覆盖目标形态"}
    mapping = installed_folders()
    done = []
    os.makedirs(BACKUP, exist_ok=True)
    for g, roots in sources.items():
        folder = mapping.get(g) or (char + "_" + g)
        cur = os.path.join(MODS, folder)
        bak = os.path.join(BACKUP, folder)
        if os.path.isdir(cur) and not os.path.isdir(bak):
            shutil.copytree(cur, bak, dirs_exist_ok=True)
        if os.path.isdir(cur):
            shutil.rmtree(cur)
        os.makedirs(cur, exist_ok=True)
        roots = sorted(roots)
        if len(roots) == 1:
            copy_mod(roots[0], cur)
        else:
            for r in roots:
                copy_mod(r, os.path.join(cur, os.path.basename(r)))
        done.append(folder)
    return {"ok": True, "msg": "已安装：" + " / ".join(done) + "　回游戏按 F10"}


def restore(char):
    if not os.path.isdir(BACKUP):
        return {"ok": False, "msg": "没有备份"}
    mapping = {v: k for k, v in installed_folders().items()}
    items = get_index().get(char, [])
    guids = set()
    for it in items:
        guids.update(it["guids"])
    restored = []
    for folder in os.listdir(BACKUP):
        src = os.path.join(BACKUP, folder)
        if not os.path.isdir(src):
            continue
        sg, _ = scan_ini_guids(src)
        if not (set(sg) & guids):
            continue
        dst = os.path.join(MODS, folder)
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        restored.append(folder)
    if not restored:
        return {"ok": False, "msg": "这个角色没有原版备份"}
    return {"ok": True, "msg": "已恢复：" + " / ".join(restored) + "　回游戏按 F10"}


def do_import(char, src_path):
    if not os.path.isdir(src_path):
        return {"ok": False, "msg": "路径不存在：" + src_path}
    cdir = os.path.join(SKINS, char)
    os.makedirs(cdir, exist_ok=True)
    nums = [int(n.split("_")[0]) for n in os.listdir(cdir) if re.match(r"^\d+_", n)]
    num = (max(nums) + 1) if nums else 1
    base = os.path.basename(src_path.rstrip("\\/")) or "imported"
    dst = os.path.join(cdir, "%03d_%s" % (num, base))
    shutil.copytree(src_path, dst)
    guids, _ = scan_ini_guids(dst)
    if not guids:
        shutil.rmtree(dst)
        return {"ok": False, "msg": "这个文件夹里没有带 object_guid 的 ini，不像是 WWMI Mod"}
    with LOCK:
        CACHE["stamp"] = None
    return {"ok": True, "msg": "已导入为 %03d_%s（形态 %s）" % (num, base, ",".join(guids))}


FORM_MAP = {}


def build_form_map():
    global FORM_MAP
    mapping = {}
    idx = get_index()
    for char, items in idx.items():
        forms = {}
        for it in items:
            for g in it["guids"]:
                forms.setdefault(g, 0)
                forms[g] += 1
        # 已知双形态命名
        labels = {"211575": "卡提希娅", "255876": "芙露德莉斯"}
        installed = installed_folders()
        picked = []
        for g, c in sorted(forms.items(), key=lambda kv: -kv[1]):
            # 只保留：已安装在 Mods 里的，或出现次数够多的（排除武器/特效的杂号）
            if g in labels or c >= max(5, int(len(items) * 0.4)):
                picked.append({"guid": g, "label": labels.get(g, "%s·%s" % (char, installed.get(g, g))), "count": c})
        FORM_MAP[char] = picked
    return FORM_MAP


HTML = r"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>鸣潮 Mod 管理器</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0e0f13;color:#e6e6ea;font-family:"Microsoft YaHei",system-ui,sans-serif;height:100vh;display:flex;flex-direction:column;overflow:hidden}
header{padding:14px 20px;background:linear-gradient(90deg,#171a22,#11131a);border-bottom:1px solid #23262f;display:flex;align-items:center;gap:18px;flex-wrap:wrap}
h1{font-size:17px;font-weight:600;letter-spacing:.5px;color:#9fd0ff}
.tabs{display:flex;gap:8px;flex-wrap:wrap}
.tab{padding:6px 14px;border-radius:999px;background:#1b1e27;border:1px solid #2a2e3a;cursor:pointer;font-size:13px;transition:.15s}
.tab:hover{border-color:#4a7fb5}
.tab.on{background:#204060;border-color:#4a9eff;color:#bfe0ff}
.spacer{flex:1}
.search{background:#1b1e27;border:1px solid #2a2e3a;border-radius:8px;padding:8px 12px;color:#e6e6ea;font-size:13px;width:260px;outline:none}
.search:focus{border-color:#4a9eff}
.status{font-size:12px;color:#7fd18a;padding:6px 20px;background:#12141a;border-bottom:1px solid #1e212a;min-height:30px}
main{flex:1;display:flex;overflow:hidden}
.grid{flex:1;overflow-y:auto;padding:16px;display:grid;grid-template-columns:repeat(auto-fill,minmax(168px,1fr));gap:12px;align-content:start}
.card{background:#171a22;border:1px solid #23262f;border-radius:10px;overflow:hidden;cursor:pointer;transition:.15s;position:relative}
.card:hover{border-color:#4a9eff;transform:translateY(-2px)}
.card.on{border-color:#4a9eff;box-shadow:0 0 0 2px #1d4b7a inset}
.card{height:200px} .card img{display:block;width:100%;height:148px;object-fit:cover;background:#0b0c10}
.card .no{position:absolute;top:6px;left:6px;background:#000a;color:#7fe08a;font:600 11px monospace;padding:2px 6px;border-radius:5px}
.card .badge{position:absolute;top:6px;right:6px;background:#1d4b7a;color:#bfe0ff;font-size:10px;padding:2px 6px;border-radius:5px}
.card .nm{padding:7px 8px;font-size:12px;line-height:1.35;height:46px;overflow:hidden;color:#c8c8d0}
.side{width:360px;border-left:1px solid #23262f;background:#12141a;display:flex;flex-direction:column}
.side img{width:100%;height:230px;object-fit:contain;background:#0b0c10} .side img:not([src]){visibility:hidden}
.side .body{padding:14px;overflow-y:auto;flex:1}
.side h2{font-size:15px;color:#9fd0ff;margin-bottom:8px;word-break:break-all}
.row{font-size:12px;color:#9aa0ad;margin:4px 0}
.row b{color:#d8dae0}
.tag{display:inline-block;background:#1b2b3d;color:#8ec2ff;border-radius:5px;padding:2px 8px;font-size:11px;margin:2px 4px 2px 0}
.tag.warn{background:#3d2a1b;color:#ffc078}
.tag.ok{background:#1d3d24;color:#8ee29a}
pre{background:#0b0c10;border:1px solid #1e212a;border-radius:8px;padding:10px;font-size:11px;color:#a8b0bc;white-space:pre-wrap;max-height:180px;overflow:auto;margin-top:8px}
.actions{padding:12px;border-top:1px solid #23262f;display:flex;flex-wrap:wrap;gap:8px}
button{background:#204060;border:1px solid #3a6f9e;color:#cfe6ff;border-radius:8px;padding:8px 12px;font-size:12.5px;cursor:pointer;transition:.15s}
button:hover{background:#2a5680}
button.ghost{background:#1b1e27;border-color:#2a2e3a;color:#b8bcc6}
button.ghost:hover{background:#232733}
.footer{padding:8px 14px;font-size:11px;color:#666c78;border-top:1px solid #1e212a}
</style></head><body>
<header>
  <h1>鸣潮 Mod 管理器</h1>
  <div class="tabs" id="tabs"></div>
  <div class="spacer"></div>
  <input class="search" id="q" placeholder="搜索：编号 / 名字 / 形态">
</header>
<div class="status" id="status">加载中…</div>
<main>
  <div class="grid" id="grid"></div>
  <div class="side">
    <img id="pv" alt="">
    <div class="body" id="detail"><div class="row">左侧选一套皮肤</div></div>
    <div class="actions" id="actions"></div>
    <div class="footer" id="foot"></div>
  </div>
</main>
<script>
let ST={chars:[],forms:{},skins:{},cur:null,sel:null,installed:{}};
const $=id=>document.getElementById(id);
function api(p,o){return fetch(p,o).then(r=>r.json())}
function esc(s){return (s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
async function load(){
  ST=await api('/api/state');
  $('status').textContent='已加载 '+(ST.skins[ST.cur]||[]).length+' 套皮肤 · 点击卡片查看详情';
  $('tabs').innerHTML=ST.chars.map(c=>`<div class="tab ${c===ST.cur?'on':''}" onclick="pickChar('${c}')">${esc(c)}</div>`).join('');
  render();
  const q0=new URLSearchParams(location.search).get('sel');
  const first=(ST.skins[ST.cur]||[])[0];
  if(first) sel(q0||first.num);
}
function pickChar(c){ST.cur=c;ST.sel=null;load()}
function render(){
  const kw=$('q').value.trim().toLowerCase();
  const list=(ST.skins[ST.cur]||[]).filter(s=>!kw||s.num.includes(kw)||s.name.toLowerCase().includes(kw));
  $('grid').innerHTML=list.map(s=>{
    const multi=s.guids.length>1;
    return `<div class="card ${ST.sel===s.num?'on':''}" onclick="sel('${s.num}')">
      <img src="/img?c=${encodeURIComponent(ST.cur)}&n=${s.num}&t=${Date.now()}">
      <div class="no">${s.num}</div>
      ${multi?'<div class="badge">双形态</div>':''}
      <div class="nm">${esc(s.name)}</div></div>`}).join('');
  $('foot').textContent=`共 ${list.length} 套　·　${ST.cur}`;
}
function sel(n){
  ST.sel=n;const s=(ST.skins[ST.cur]||[]).find(x=>x.num===n);if(!s)return;
  $('pv').src=`/img?c=${encodeURIComponent(ST.cur)}&n=${n}`;
  const forms=ST.forms[ST.cur]||[];
  const mine=forms.filter(f=>s.guids.includes(f.guid));
  let h=`<h2>${esc(s.name)}</h2>`;
  h+=`<div class="row">编号 <b>${s.num}</b></div>`;
  h+=`<div class="row">覆盖形态：`+(mine.length?mine.map(f=>`<span class="tag">${esc(f.label)}</span>`).join(''):'<span class="tag warn">未知</span>')+`</div>`;
  h+=`<div class="row">可调档位：`+(s.keys>0?`<span class="tag ok">可按键切 ${s.keys} 段</span>`:'<span class="tag">外观固定</span>')+`</div>`;
  if(s.guids.length>1) h+=`<div class="row"><span class="tag warn">这套同时包含多个形态，可一键全装</span></div>`;
  h+=`<div class="row" id="rd"></div>`;
  $('detail').innerHTML=h;
  api(`/api/readme?c=${encodeURIComponent(ST.cur)}&n=${n}`).then(r=>{
    if(r.text){$('rd').innerHTML='<pre>'+esc(r.text)+'</pre>'}
  });
  let btns='';
  mine.forEach(f=>{btns+=`<button onclick="inst('${n}','${f.guid}')">装到 ${esc(f.label)}</button>`});
  if(mine.length>1) btns+=`<button onclick="inst('${n}','all')">全部形态一起装</button>`;
  btns+=`<button class="ghost" onclick="restore()">恢复原版</button>`;
  btns+=`<button class="ghost" onclick="openDir('${n}')">打开文件夹</button>`;
  $('actions').innerHTML=btns;
  render();
}
async function inst(n,g){
  $('status').textContent='安装中…';
  const r=await api('/api/install',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({char:ST.cur,num:n,guid:g})});
  $('status').textContent=(r.ok?'✅ ':'❌ ')+r.msg;
}
async function restore(){
  $('status').textContent='恢复中…';
  const r=await api('/api/restore',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({char:ST.cur})});
  $('status').textContent=(r.ok?'✅ ':'❌ ')+r.msg;
}
async function openDir(n){
  await api('/api/open',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({char:ST.cur,num:n})});
}
async function doImport(){
  const p=$('imp').value.trim();
  if(!p)return;
  $('status').textContent='导入中…';
  const r=await api('/api/import',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({char:ST.cur,path:p})});
  $('status').textContent=(r.ok?'✅ ':'❌ ')+r.msg;
  if(r.ok){$('imp').value='';load()}
}
$('q').addEventListener('input',render);
load();
setInterval(async()=>{const s=await api('/api/installed');$('status').dataset.i=JSON.stringify(s)},15000);
</script>
<div style="padding:10px 20px;background:#12141a;border-top:1px solid #1e212a;display:flex;gap:8px;align-items:center">
  <input id="imp" class="search" style="width:520px" placeholder="导入外部 Mod：粘贴文件夹绝对路径，回车按序编号入库">
  <button onclick="doImport()">导入</button>
</div>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path in ("/", "/index.html"):
            return self._send(200, HTML, "text/html")
        if u.path == "/api/state":
            idx = get_index()
            fm = build_form_map()
            return self._send(200, {
                "chars": list(idx.keys()),
                "cur": list(idx.keys())[0] if idx else None,
                "forms": fm,
                "skins": idx,
                "installed": installed_folders(),
            })
        if u.path == "/api/readme":
            c = q.get("c", [""])[0]
            n = q.get("n", [""])[0]
            d = skin_dir(c, n)
            return self._send(200, {"text": find_readme(d) if d else ""})
        if u.path == "/api/installed":
            return self._send(200, installed_folders())
        if u.path == "/img":
            c = q.get("c", [""])[0]
            n = q.get("n", [""])[0]
            d = skin_dir(c, n)
            p = find_thumb(d) if d else None
            if not p:
                return self._send(404, b"", "image/png")
            with open(p, "rb") as fh:
                data = fh.read()
            ext = os.path.splitext(p)[1].lower()
            ctype = "image/png" if ext == ".png" else "image/jpeg"
            return self._send(200, data, ctype)
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            payload = {}
        if u.path == "/api/install":
            r = install(payload.get("char"), payload.get("num"), str(payload.get("guid", "all")))
            return self._send(200, r)
        if u.path == "/api/restore":
            return self._send(200, restore(payload.get("char")))
        if u.path == "/api/import":
            r = do_import(payload.get("char"), payload.get("path", ""))
            return self._send(200, r)
        if u.path == "/api/open":
            d = skin_dir(payload.get("char"), payload.get("num"))
            if d:
                os.startfile(d)
            return self._send(200, {"ok": True})
        return self._send(404, {"error": "not found"})


def main():
    if not os.path.isdir(SKINS):
        print("皮肤库不存在：", SKINS)
        sys.exit(1)
    try:
        t0 = __import__("time").time()
        idx = get_index()
        build_form_map()
        print("预热完成：%d 个角色，耗时 %.1fs" % (len(idx), __import__("time").time() - t0))
    except Exception as exc:
        print("预热失败：", exc)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("鸣潮 Mod 管理器： http://127.0.0.1:%d" % PORT)
    if "--no-browser" not in sys.argv:
        threading.Timer(1.0, lambda: webbrowser.open("http://127.0.0.1:%d" % PORT)).start()
    server.serve_forever()


if __name__ == "__main__":
    main()

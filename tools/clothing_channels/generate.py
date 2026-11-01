#!/usr/bin/env python3
"""Generate the clothing colour channels: strings/clothing_channels/generated.json.

  bash tools/clothing_channels/generate.sh

Reads every wearable type from the analyzer (`analyze sem clothing-dump`), gathers each type's item, worn and species art, and
splits its colours into at most 3 channels (OKLab clustering). The output is only "which source colour belongs to which channel, base
first"; the recolour itself is computed in DM (code/content/gear/clothing_channels.dm). Never edit generated.json:
strings/clothing_channels/overrides.json holds the hand fixes, this tool never writes it, and the game layers it on top.
"""
import argparse, collections, ctypes, json, math, re, sys, time, tomllib
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.cluster.hierarchy import fcluster, linkage

# ---------------------------------------------------------------- machine limits
def below_normal():
    if sys.platform == "win32":
        k = ctypes.windll.kernel32
        k.SetPriorityClass(k.GetCurrentProcess(), 0x4000)

def free_gb():
    class M(ctypes.Structure):
        _fields_ = [("l", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [
            (n, ctypes.c_ulonglong) for n in "tp ap tf af tv av ae".split()]
    m = M(); m.l = ctypes.sizeof(M)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m.ap / 2**30

def ram_gate():
    while free_gb() < 16:
        print(f"free RAM {free_gb():.1f} GB < 16, pausing", flush=True)
        time.sleep(30)

# ---------------------------------------------------------------- DM catalog
SLOT_RULES = [("/obj/item/clothing/under", "uniform"), ("/obj/item/clothing/suit", "suit"),
              ("/obj/item/clothing/head", "head"), ("/obj/item/clothing/mask", "face"),
              ("/obj/item/clothing/gloves", "hands"), ("/obj/item/clothing/shoes", "feet"),
              ("/obj/item/clothing/ears", "ears"), ("/obj/item/clothing/glasses", "eyes"),
              ("/obj/item/storage/belt", "belt"), ("/obj/item/storage/backpack", "back"),
              ("/obj/item/clothing/accessory", "accessory")]
_RES = re.compile(r'Resource\("([^"]+)"\)')
_STR = re.compile(r'^String\("((?:[^"\\]|\\.)*)"\)$')

def parse_dump(path):
    """analyze sem clothing-dump -> path: resolved vars. Values are the analyzer's debug text."""
    types = {}
    for line in Path(path).read_text("utf8").splitlines():
        row = json.loads(line)
        raw, v = row["vars"], {}
        for key in ("icon", "icon_override"):
            m = _RES.search(raw.get(key, ""))
            if m:
                v[key] = m.group(1)
        for key in ("icon_state", "item_state", "worn_state"):
            m = _STR.match(raw.get(key, ""))
            if m:
                v[key] = m.group(1)
        for key in ("item_icons", "sprite_sheets"):
            v[key] = _RES.findall(raw.get(key, ""))
        v["state_slots"] = re.findall(r'Some\(String\("([^"]+)"\)\)', raw.get("item_state_slots", ""))
        types[row["path"]] = v
    return types

def slot_of(path):
    for pref, s in SLOT_RULES:
        if path == pref or path.startswith(pref + "/"):
            return s
    return "other" if path.startswith("/obj/item/clothing") else None

# ---------------------------------------------------------------- sheets
class Sheets:
    def __init__(self, repo):
        self.repo, self.cache = repo, {}

    def load(self, rel):
        if rel in self.cache:
            return self.cache[rel]
        res = None
        base = self.repo / rel
        png, toml = base.with_suffix(".png"), Path(str(base) + ".toml")
        try:
            if png.exists() and toml.exists():
                d = tomllib.loads(toml.read_text("utf8"))
                res = self._index(png, d["width"], d["height"], d.get("cols", 1),
                                  [(s.get("name", ""), int(s.get("dirs", 1)), int(s.get("frames", 1)))
                                   for s in d.get("state", [])])
            elif base.exists():
                res = self._raw_dmi(base)
        except Exception as e:  # report, don't crash: a broken sheet is a data point
            print("sheet error", rel, e, flush=True)
        self.cache[rel] = res
        return res

    def _index(self, png, w, h, cols, states):
        arr = np.asarray(Image.open(png).convert("RGBA"))
        idx, i = {}, 0
        for name, dirs, frames in states:
            if name not in idx:
                idx[name] = (i, dirs, frames)
            i += dirs * frames
        return dict(arr=arr, w=w, h=h, cols=cols, states=idx)

    def _raw_dmi(self, path):
        img = Image.open(path)
        desc = img.info.get("Description", "")
        w = int(re.search(r"width\s*=\s*(\d+)", desc).group(1))
        h = int(re.search(r"height\s*=\s*(\d+)", desc).group(1))
        states = []
        for m in re.finditer(r'state\s*=\s*"([^"]*)"\s*\n\s*dirs\s*=\s*(\d+)\s*\n\s*frames\s*=\s*(\d+)', desc):
            states.append((m.group(1), int(m.group(2)), int(m.group(3))))
        return self._index(path, w, h, img.width // w, states)

    def cells(self, rel, state):
        s = self.load(rel)
        if not s or state not in s["states"]:
            return None
        i0, dirs, frames = s["states"][state]
        out = []
        for i in range(i0, i0 + dirs * frames):
            x, y = (i % s["cols"]) * s["w"], (i // s["cols"]) * s["h"]
            c = s["arr"][y:y + s["h"], x:x + s["w"]]
            if c.shape[:2] == (s["h"], s["w"]):
                out.append(c)
        return dict(cells=out, dirs=dirs, frames=frames) if out else None

def gather(path, v, slot, sheets, repo):
    """Item icon + every worn sheet that carries this item's worn state."""
    sprites = []
    icon = v.get("icon") or f"icons/inventory/{slot}/item.dmi"
    st = v.get("icon_state")
    if st is None:
        return sprites
    c = sheets.cells(icon, st)
    if c and any(x[..., 3].any() for x in c["cells"]):
        sprites.append(dict(tag="item", file=icon, state=st, **c))
    names = [n for n in [v.get("worn_state"), *v.get("state_slots", []), v.get("item_state"), st] if n]
    names = list(dict.fromkeys(names))
    default = f"icons/inventory/{slot}/mob.dmi"
    order = [v.get("icon_override"), *v.get("item_icons", []), v.get("worn_icon"), *v.get("sprite_sheets", []), default]
    # Legacy sheets often hold worn dirs in the same file as the item icon.
    order = list(dict.fromkeys(f for f in order if f))
    sib = sorted(p.name.replace(".png", ".dmi") for p in (repo / f"icons/inventory/{slot}").glob("mob*.png")) \
        if (repo / f"icons/inventory/{slot}").is_dir() else []
    order += [f"icons/inventory/{slot}/{n}" for n in sib if f"icons/inventory/{slot}/{n}" not in order]
    primary_done = False
    for f in order:
        for n in names:
            c = sheets.cells(f, n)
            if c and any(x[..., 3].any() for x in c["cells"]):
                is_sib = "/mob_" in f and f not in (v.get("icon_override"), v.get("worn_icon"))
                tag = "worn" if not primary_done and not is_sib else "species"
                primary_done = primary_done or tag == "worn"
                sprites.append(dict(tag=tag, file=f, state=n, **c))
                for suf in ("_d", "_r"):  # rolled uniforms in the same sheet
                    c2 = sheets.cells(f, n + suf)
                    if c2:
                        sprites.append(dict(tag="species", file=f, state=n + suf, **c2))
                break
    return sprites

# ---------------------------------------------------------------- colour
def s2l(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def l2s(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255

def lin2lab(l):
    m1 = np.array([[.4122214708, .5363325363, .0514459929], [.2119034982, .6806995451, .1073969566],
                   [.0883024619, .2817188376, .6299787005]])
    m2 = np.array([[.2104542553, .7936177850, -.0040720468], [1.9779984951, -2.4285922050, .4505937099],
                   [.0259040371, .7827717662, -.8086757660]])
    return np.cbrt(l @ m1.T) @ m2.T

def lab2lin(lab):
    m2i = np.array([[1, .3963377774, .2158037573], [1, -.1055613458, -.0638541728], [1, -.0894841775, -1.2914855480]])
    m1i = np.array([[4.0767416621, -3.3077115913, .2309699292], [-1.2684380046, 2.6097574011, -.3413193965],
                    [-.0041960863, -.7034186147, 1.7076147010]])
    return ((lab @ m2i.T) ** 3) @ m1i.T

def rgb2lab(rgb):
    return lin2lab(s2l(rgb.astype(float)))

def lab2rgb(lab):
    lin = lab2lin(lab)
    clipped = (lin < -1e-4) | (lin > 1 + 1e-4)
    return np.round(l2s(lin)).astype(int), clipped.any(axis=-1)

def hx(s):
    return np.array([int(s[i:i + 2], 16) for i in (1, 3, 5)], float)

def key(rgb):
    return (rgb[..., 0].astype(np.int64) << 16) | (rgb[..., 1].astype(np.int64) << 8) | rgb[..., 2]

PALETTES = {
    "extreme": ["#ff00d0", "#20ff30", "#00a0ff"],
    "dark": ["#2a1840", "#401c14", "#10302a"],
    "pale": ["#ffdcec", "#d8f0ff", "#f6f4cc"],
    "natural": ["#28406e", "#8a2f3c", "#c4a040"],
}

# Parameters fixed before the final sample is judged; see report for tuning history.
NEUTRAL_C = 0.035
SINGLE_LINK = 0.040
CENTROID_STOP = 0.065
DETAIL_SHARE = 0.015
SPECK_MERGE_SHARE = 0.20

# ---------------------------------------------------------------- split
def analyse(sprites):
    frames = [(s, c) for s in sprites for c in s["cells"]]
    all_px = np.concatenate([c[c[..., 3] > 0][:, :3] for _, c in frames])
    alpha = np.concatenate([c[c[..., 3] > 0][:, 3] for _, c in frames]) / 255.0
    keys = key(all_px)
    uk, inv = np.unique(keys, return_inverse=True)
    w = np.bincount(inv, alpha, len(uk))
    rgb = np.stack([(uk >> 16) & 255, (uk >> 8) & 255, uk & 255], 1)
    lab = rgb2lab(rgb)
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    share = w / w.sum()

    # per-colour edge fraction and colour adjacency
    edge = np.zeros(len(uk)); total = np.zeros(len(uk))
    adj = np.zeros((len(uk), len(uk))) if len(uk) <= 1500 else None
    idframes = []
    for s, c in frames:
        op = c[..., 3] > 0
        ids = np.full(op.shape, -1, int)
        ids[op] = np.searchsorted(uk, key(c[op][:, :3]))
        idframes.append((s, ids))
        er = ndimage.binary_erosion(op, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]], border_value=0)
        np.add.at(edge, ids[op & ~er], 1)
        np.add.at(total, ids[op], 1)
        if adj is not None:
            for a, b in ((ids[:-1], ids[1:]), (ids[:, :-1], ids[:, 1:])):
                m = (a >= 0) & (b >= 0) & (a != b)
                np.add.at(adj, (a[m], b[m]), 1)
                np.add.at(adj, (b[m], a[m]), 1)
    edgef = edge / np.maximum(total, 1)

    order = np.argsort(lab[:, 0]); cum = np.cumsum(share[order])
    Lmed = lab[order[np.searchsorted(cum, .5)], 0]
    outline = (edgef >= .5) & (lab[:, 0] < Lmed - .12) & (lab[:, 0] < .45)
    if share[outline].sum() > .35:
        outline[:] = False

    feat = np.c_[lab[:, 1], lab[:, 2], lab[:, 0] * .30]
    neutral = chroma < NEUTRAL_C
    feat[neutral, 1:2] = feat[neutral, 1:2] * .6  # low chroma hue is noise
    idx = np.where(~outline)[0]
    if len(idx) == 0:
        idx = np.arange(len(uk)); outline[:] = False
    labels = np.zeros(len(uk), int) - 1
    if len(idx) == 1:
        labels[idx] = 0
    else:
        labels[idx] = fcluster(linkage(feat[idx], "single"), SINGLE_LINK, "distance") - 1

    def groups():
        return [np.where(labels == g)[0] for g in np.unique(labels[labels >= 0])]

    def centroid(g):
        return np.average(feat[g], axis=0, weights=w[g])

    def dist(a, b):
        ca, cb = np.average(chroma[a], weights=w[a]), np.average(chroma[b], weights=w[b])
        if ca < NEUTRAL_C and cb < NEUTRAL_C:
            return abs(np.average(lab[a, 0], weights=w[a]) - np.average(lab[b, 0], weights=w[b])) * .45
        return float(np.linalg.norm(centroid(a) - centroid(b)))

    while True:  # merge by centroid to CENTROID_STOP
        gs = groups()
        if len(gs) < 2:
            break
        best, pair = 1e9, None
        for i in range(len(gs)):
            for j in range(i + 1, len(gs)):
                d = dist(gs[i], gs[j])
                if d < best:
                    best, pair = d, (i, j)
        if best > CENTROID_STOP:
            break
        labels[gs[pair[1]]] = labels[gs[pair[0]][0]]

    # detail locks
    locked = {}
    colored = share[~outline].sum()
    for g in groups():
        s = share[g].sum() / colored
        L, C = lab[g, 0], chroma[g]
        mc, ml = np.average(C, weights=w[g]), np.average(L, weights=w[g])
        hue = (math.degrees(math.atan2(np.average(lab[g, 2], weights=w[g]), np.average(lab[g, 1], weights=w[g])))) % 360
        why = None
        if s < .05 and mc > .18 and ml > .72:
            why = "emissive"
        elif s < .12 and L.max() - L.min() > .22 and (mc < .035 or (60 < hue < 110 and mc > .06)) and len(g) >= 3:
            why = "metal"
        elif s < .12 and 40 < hue < 75 and .04 < mc < .13 and .55 < ml < .85:
            why = "skin"
        elif s < DETAIL_SHARE:
            others = [o for o in groups() if o is not g and share[o].sum() / colored >= DETAIL_SHARE]
            if others and min(dist(g, o) for o in others) > .10:
                why = "detail"
        if why and len(groups()) - len(locked) > 1:
            locked[int(labels[g[0]])] = why

    # force to max 3 live channels, merging smallest into nearest
    while True:
        live = [g for g in groups() if int(labels[g[0]]) not in locked]
        if len(live) <= 3:
            break
        live.sort(key=lambda g: share[g].sum())
        sm = live[0]
        tgt = min(live[1:], key=lambda o: dist(sm, o))
        labels[sm] = labels[tgt[0]]

    # speckly small channels are usually anti-alias or shading in-betweens, not parts:
    # absorb into the nearest channel, or lock when no channel is close in colour.
    for _ in range(4):
        live = sorted((g for g in groups() if int(labels[g[0]]) not in locked), key=lambda g: share[g].sum())
        if len(live) < 2:
            break
        changed = False
        for g in live:
            if share[g].sum() / colored > SPECK_MERGE_SHARE:
                continue
            gset = np.isin(np.arange(len(uk)), g); tot = spk = 0
            for _s, ids in idframes:
                mask = (ids >= 0) & gset[np.maximum(ids, 0)]
                if mask.any():
                    l_, _k = ndimage.label(mask)
                    sz = np.bincount(l_.ravel())[1:]
                    tot += sz.sum(); spk += sz[sz <= 2].sum()
            if tot and spk / tot > .35:
                near = min((o for o in live if o is not g), key=lambda o: dist(g, o))
                if dist(g, near) <= .18:
                    labels[g] = labels[near[0]]
                else:
                    locked[int(labels[g[0]])] = "detail"
                changed = True
                break
        if not changed:
            break

    live = sorted((g for g in groups() if int(labels[g[0]]) not in locked), key=lambda g: -share[g].sum())
    channel = np.full(len(uk), 3, int)  # 3 == locked
    lock_reason = {}
    for g in groups():
        if int(labels[g[0]]) in locked:
            for i in g:
                lock_reason[int(i)] = locked[int(labels[g[0]])]
    for n, g in enumerate(live):
        channel[g] = n

    # outline colours: black ink stays, tinted lines follow the channel they touch
    for i in np.where(outline)[0]:
        if chroma[i] < .03 and lab[i, 0] < .3 or adj is None:
            channel[i] = 3; lock_reason[int(i)] = "ink"; continue
        votes = np.zeros(4)
        for j in np.where(adj[i] > 0)[0]:
            if not outline[j]:
                votes[channel[j]] += adj[i, j]
        votes[3] = 0
        if votes.sum() == 0:
            channel[i] = 3; lock_reason[int(i)] = "ink"
        else:
            channel[i] = int(np.argmax(votes))

    # bases: heaviest colour nearest the weighted median lightness of the channel's body colours
    n = len(live)
    bases = np.zeros((max(n, 1), 3)); baselab = np.zeros((max(n, 1), 3))
    for ch in range(n):
        g = np.where((channel == ch) & ~outline)[0]
        o = g[np.argsort(lab[g, 0])]; c = np.cumsum(share[o]); medL = lab[o[np.searchsorted(c, c[-1] / 2)], 0]
        near = g[np.abs(lab[g, 0] - medL) < .05]
        pick = near[np.argmax(share[near])] if len(near) else g[np.argmax(share[g])]
        bases[ch], baselab[ch] = rgb[pick], lab[pick]

    # the stored LUT: int16 deltas from base (int8 was tried first: 477 items missed +-2 RGB on 98% of pixels)
    dq = np.zeros((len(uk), 3))
    for i in range(len(uk)):
        if channel[i] < 3:
            d = lab[i] - baselab[channel[i]]
            dq[i] = np.round(d * 4096) / 4096

    return dict(uk=uk, rgb=rgb, lab=lab, chroma=chroma, share=share, channel=channel, outline=outline, n=n,
                bases=bases, baselab=baselab, dq=dq, lock=lock_reason, idframes=idframes, adj=adj)

def recolour(a, targets):
    """Colour LUT for target colours per channel; returns rgb per palette index."""
    out, clip = a["rgb"].copy().astype(int), np.zeros(len(a["uk"]), bool)
    for ch in range(a["n"]):
        idx = np.where(a["channel"] == ch)[0]
        T = rgb2lab(np.asarray(targets[ch], float)[None])[0]
        b = a["baselab"][ch]
        d = a["dq"][idx].copy()
        up, dn = max(d[:, 0].max(), 1e-6), max(-d[:, 0].min(), 1e-6)
        d[:, 0] *= np.where(d[:, 0] > 0, min(1, (1 - T[0]) / up), min(1, T[0] / dn))
        Tc, bc = math.hypot(T[1], T[2]), math.hypot(b[1], b[2])
        if bc > .02:
            scale = min(1.0, Tc / bc)
            rot = math.atan2(T[2], T[1]) - math.atan2(b[2], b[1]) if Tc > .01 else 0
            ca, sa = math.cos(rot), math.sin(rot)
            da, db = d[:, 1].copy(), d[:, 2].copy()
            d[:, 1], d[:, 2] = (ca * da - sa * db) * scale, (sa * da + ca * db) * scale
        o, cl = lab2rgb(T + d)
        out[idx], clip[idx] = o, cl
    return out, clip

def metrics(a, sprites):
    m = {}
    share, ch, lab = a["share"], a["channel"], a["lab"]
    m["palette"] = len(a["uk"]); m["channels"] = a["n"]
    m["locked_share"] = float(share[ch == 3].sum())
    m["outline_share"] = float(share[a["outline"]].sum())
    m["locks"] = dict(collections.Counter(a["lock"].values()))
    m["greyscale"] = bool(share[a["chroma"] > .02].sum() < .01)

    # neutrality through the int8 LUT, by pixel share
    lut, _ = recolour(a, a["bases"])
    d = np.abs(lut - a["rgb"]).max(1)
    dE = np.linalg.norm(rgb2lab(lut.astype(float)) - lab, axis=1) * 100
    m["neutral_mean_dE"] = float((dE * share).sum())
    m["neutral_max_dE"] = float(dE.max())
    m["neutral_exact"] = float(share[d == 0].sum())
    m["neutral_within2"] = float(share[d <= 2].sum())

    # tail-style reconstruction: base colour multiplied by a greyscale mask
    y = s2l(a["rgb"].astype(float)).dot([.2126, .7152, .0722])
    rec = a["rgb"].astype(float).copy()
    for c in range(a["n"]):
        idx = ch == c
        bl = s2l(a["bases"][c]); yb = max(bl.dot([.2126, .7152, .0722]), 1e-4)
        rec[idx] = l2s(bl[None] * np.minimum(y[idx] / yb, 1)[:, None])  # mask can't brighten past white
    m["mask_mean_dE"] = float((np.linalg.norm(rgb2lab(rec) - lab, axis=1) * 100 * share).sum())

    # fragmentation, excluding outline / ink
    px = spk = brd = pairs = checker = blocks = 0
    item_h, worn_h = np.zeros(4), np.zeros(4)
    for s, ids in a["idframes"]:
        cm = np.where(ids >= 0, ch[np.maximum(ids, 0)], -1)
        body = (ids >= 0) & ~a["outline"][np.maximum(ids, 0)] & (cm < 3)
        for c in range(a["n"]):
            mask = body & (cm == c)
            if mask.any():
                lab_, k = ndimage.label(mask)
                sizes = np.bincount(lab_.ravel())[1:]
                spk += sizes[sizes <= 2].sum()
        px += body.sum()
        for x, y2 in ((cm[:-1], cm[1:]), (cm[:, :-1], cm[:, 1:])):
            bm = (body[:-1] & body[1:]) if x.shape == cm[:-1].shape else (body[:, :-1] & body[:, 1:])
            pairs += bm.sum(); brd += (bm & (x != y2)).sum()
        p, q, r, t = ids[:-1, :-1], ids[:-1, 1:], ids[1:, :-1], ids[1:, 1:]
        valid = (p >= 0) & (q >= 0) & (r >= 0) & (t >= 0)
        blocks += valid.sum(); checker += (valid & (p == t) & (q == r) & (p != q)).sum()
        if s["tag"] in ("item", "worn"):
            h = np.bincount(cm[cm >= 0], minlength=4)[:4].astype(float)
            if s["tag"] == "item":
                item_h += h
            else:
                worn_h += h
    m["speck"] = float(spk / max(px, 1))
    m["boundary"] = float(brd / max(pairs, 1))
    m["checker"] = float(checker / max(blocks, 1))
    if item_h.sum() and worn_h.sum():
        m["item_worn_shift"] = float(np.abs(item_h / item_h.sum() - worn_h / worn_h.sum())[:3].sum() / 2)
    else:
        m["item_worn_shift"] = None
    m["sprite_tags"] = dict(collections.Counter(s["tag"] for s in sprites))
    m["frames"] = sum(len(s["cells"]) for s in sprites)

    # shading ramps
    corr, ret, rng, clipf = [], [], [], []
    for name, pal in PALETTES.items():
        o, cl = recolour(a, [hx(x) for x in pal])
        ol = rgb2lab(o.astype(float))
        clipf.append(float(share[cl].sum()))
        for c in range(a["n"]):
            idx = np.where((ch == c) & ~a["outline"])[0]
            if len(idx) < 3:
                continue
            if np.ptp(lab[idx, 0]) < .02:
                continue
            rs = np.argsort(np.argsort(lab[idx, 0])); ro = np.argsort(np.argsort(ol[idx, 0]))
            cc = np.corrcoef(rs, ro)[0, 1] if np.ptp(ro) else 0.0
            corr.append(float(cc))
            ret.append(len(np.unique(key(o[idx]))) / len(idx))
            rng.append(float(np.ptp(ol[idx, 0]) / np.ptp(lab[idx, 0])))
    m["ramp_corr_min"] = min(corr) if corr else None
    m["ramp_retained_min"] = min(ret) if ret else None
    m["ramp_range_min"] = min(rng) if rng else None
    m["gamut_clip_max"] = max(clipf) if clipf else 0.0

    # merged tones: a channel with a big lightness gap and weight on both sides
    merged = False
    for c in range(a["n"]):
        idx = np.where((ch == c) & ~a["outline"])[0]
        o = idx[np.argsort(lab[idx, 0])]
        if len(o) < 2:
            continue
        L = lab[o, 0]; cum = np.cumsum(share[o]) / share[o].sum()
        for i in np.where(np.diff(L) >= .16)[0]:
            if .15 <= cum[i] <= .85:
                merged = True
    m["merged_tones"] = merged
    m["lut_bytes_binary"] = int((ch < 3).sum() * 10 + (ch == 3).sum() * 4 + a["n"] * 3)
    return m

def classify(m):
    """Thresholds fixed before visual judging. cats = failure categories."""
    cats = []
    if m["greyscale"]:
        cats.append("already_greyscale")
    if m["checker"] > .06:
        cats.append("dithering")
    if m["palette"] > 48:
        cats.append("gradient_or_many_colours")
    if m["merged_tones"]:
        cats.append("same_hue_parts_merged")
    if m["channels"] == 1 and not m["greyscale"]:
        cats.append("single_channel_only")
    if m["speck"] > .08 or m["boundary"] > .35:
        cats.append("fragmented_split")
    if (m["item_worn_shift"] or 0) > .25:
        cats.append("item_worn_channel_mismatch")
    if (m["ramp_corr_min"] is not None and m["ramp_corr_min"] < .7) or (m["ramp_retained_min"] is not None and m["ramp_retained_min"] < .5):
        cats.append("shading_ramp_damage")
    if m["sprite_tags"].get("worn", 0) == 0:
        cats.append("no_worn_sprite_found")
    if m["sprite_tags"].get("item", 0) == 0:
        cats.append("no_item_sprite_found")
    if m["locked_share"] > .5:
        cats.append("mostly_locked")
    hard = {"dithering", "fragmented_split", "mostly_locked", "no_worn_sprite_found", "shading_ramp_damage"}
    soft = {"gradient_or_many_colours", "same_hue_parts_merged", "item_worn_channel_mismatch", "no_item_sprite_found"}
    if m["neutral_within2"] < .98 or hard & set(cats):
        outcome = "bad"
    elif soft & set(cats) or m["speck"] > .04 or m["boundary"] > .22:
        outcome = "usable"
    else:
        outcome = "good"
    m["cats"], m["outcome"] = cats, outcome
    # higher is better; used only to rank best/worst pages
    m["score"] = -(m["speck"] * 3 + m["boundary"] + m["checker"] * 3 + (m["item_worn_shift"] or 0)
                   + m["locked_share"] * .5 + (1 - (m["ramp_corr_min"] if m["ramp_corr_min"] is not None else 1))
                   + min(m["palette"], 80) / 160) + (.3 if m["channels"] >= 2 else 0)
    return m

# ---------------------------------------------------------------- pipeline
def family(sheets, icon, state):
    """Other states of the item's own sheet that belong to it (state_open, state_d): a garment toggles between these."""
    s = sheets.load(icon)
    if not s:
        return []
    return sorted(n for n in s["states"] if n.startswith(state + "_"))[:12]

def channel_strings(a):
    """Channel -> concatenated rrggbb, the base first. Locked colours appear nowhere."""
    out = []
    for ch in range(a["n"]):
        base = "%02x%02x%02x" % tuple(int(x) for x in a["bases"][ch])
        rest = sorted("%06x" % int(k) for k in a["uk"][a["channel"] == ch] if "%06x" % int(k) != base)
        out.append(base + "".join(rest))
    return out

def cmd_run(args):
    repo, out = Path(args.repo), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    types = parse_dump(args.dump)
    sheets = Sheets(repo)
    stats = collections.Counter(types_total=len(types))
    by_art, rows, luts, lut_ids, table = {}, [], [], {}, {}
    excluded = collections.defaultdict(list)
    t0 = time.time()
    for k, p in enumerate(sorted(types)):
        if k % 200 == 0:
            ram_gate(); print(k, len(types), f"{time.time() - t0:.0f}s", flush=True)
        v, slot = types[p], slot_of(p)
        if not v.get("icon_state"):
            excluded["no_icon_state (abstract parents)"].append(p); continue
        sprites = gather(p, v, slot if slot != "other" else "accessory", sheets, repo)
        if not sprites:
            excluded["state_not_on_any_sheet"].append(p); continue
        sig = tuple(sorted((s["file"], s["state"]) for s in sprites))
        if sig not in by_art:
            try:
                a = analyse(sprites)
                m = classify(metrics(a, sprites))
                strs = channel_strings(a)
            except Exception as e:
                print("ERR", p, repr(e), flush=True)
                by_art[sig] = None
            else:
                joined = "|".join(strs)
                if joined not in lut_ids:
                    lut_ids[joined] = len(luts); luts.append(strs)
                by_art[sig] = lut_ids[joined]
                m.update(path=p, slot=slot, files=sorted({s["file"] for s in sprites}))
                rows.append(m)
        lut = by_art[sig]
        if lut is None:
            excluded["tool_error"].append(p); continue
        if not luts[lut]:
            excluded["no_recolourable_colour"].append(p); continue
        fam = family(sheets, v["icon"], v["icon_state"]) if v.get("icon") else []
        table[p] = [lut] + fam
    stats.update(covered=len(table), luts=len(luts), art_groups=len(by_art))
    for why, paths in excluded.items():
        stats["excluded: " + why] = len(paths)
    dest = repo / "strings/clothing_channels/generated.json"
    body = ['{"luts":[', ",\n".join(json.dumps(l, separators=(",", ":")) for l in luts), '],\n"types":{',
            ",\n".join(json.dumps(p) + ":" + json.dumps(table[p], separators=(",", ":")) for p in sorted(table)), "}}\n"]
    dest.write_text("\n".join(body), "utf8", newline="\n")
    (out / "metrics_all.json").write_text(json.dumps(dict(stats=stats, excluded=excluded, rows=rows), indent=0))
    write_handfix(out, rows, table)
    print(json.dumps(stats, indent=1), f"{dest.stat().st_size / 1024:.0f} KiB", f"{time.time() - t0:.0f}s")

def write_handfix(out, rows, table):
    ranked = sorted((r for r in rows if r["path"] in table), key=lambda r: r["score"])
    lines = ["# Clothing channels: hand-fix candidates, worst first", "",
             "Ranked by the generator's score (fragments, dithering, item/worn mismatch, locked share, shading damage, palette size).",
             "The metric agreed with the eye on only 55% of a judged sample: this is an order to look in, not a verdict.",
             "One row is one art group; other types with the same art share its channels. Fix in strings/clothing_channels/overrides.json.", "",
             "| # | Type | Score | Metric | Channels | Palette | Flags |", "|---|---|---|---|---|---|---|"]
    for i, r in enumerate(ranked, 1):
        lines.append(f"| {i} | `{r['path']}` | {r['score']:.2f} | {r['outcome']} | {r['channels']} | {r['palette']} | {', '.join(r['cats'])} |")
    (out / "handfix-candidates.md").write_text("\n".join(lines) + "\n", "utf8")

if __name__ == "__main__":
    below_normal()
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--dump", required=True, help="output of `analyze sem clothing-dump`")
    ap.add_argument("--out", default="E:/dq-cache/clothing-channels/out")
    cmd_run(ap.parse_args())

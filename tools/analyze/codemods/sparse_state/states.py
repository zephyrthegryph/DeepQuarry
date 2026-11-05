#!/usr/bin/env python3
"""Writes the lazy state datums of a conversion wave (doc/rewrite/storage_contract.md).

  python3 tools/analyze/codemods/sparse_state/states.py --wave 1

For each feature of the wave: code/library/mob/states/<feature>_state.dm (library code reads them, and library may not name content) (the state type with one var per slot, and the holder's var), and the
`owns_one(nameof(feature), /datum/feature_state, lazy = TRUE)` entry in the holder's CAPABILITIES block. A list or weak slot is not part of the wave
(it needs hand work: groups.tsv wave 0). Run census.py first if the tree changed; groups.tsv is the input.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from census import census, ROOT

HERE = os.path.dirname(os.path.abspath(__file__))
HOLDER_DIR = {"/atom": "code/library/atom/states", "/atom/movable": "code/library/atom/states", "/obj": "code/library/atom/states", "/obj/item": "code/library/atom/states", "/obj/machinery": "code/library/atom/states", "/mob": "code/library/mob/states", "/mob/living": "code/library/mob/states", "/mob/living/carbon": "code/library/mob/states", "/mob/living/carbon/human": "code/library/mob/states"}
ROOT_BLOCK = {"/atom": "code/domains/world_model/atom/atom.dm", "/atom/movable": "code/domains/world_model/atom/atoms_movable.dm", "/obj": "code/domains/world_model/obj/objs.dm", "/obj/item": "code/domains/world_model/obj/items.dm", "/obj/machinery": "code/domains/world_model/machinery.dm", "/mob": "code/domains/world_model/mob/mob_defines.dm", "/mob/living": "code/domains/world_model/mob/living_defines.dm", "/mob/living/carbon": "code/domains/world_model/mob/carbon_defines.dm", "/mob/living/carbon/human": "code/domains/world_model/mob/human_defines.dm"}
VAR_TYPE = {"num": "", "text": "", "bool": "", "": ""}


def read_tsv():
    out = []
    for line in open(os.path.join(HERE, "groups.tsv"), encoding="utf8").read().split("\n"):
        if line:
            h, s, f, k, d, w = line.split("\t")
            out.append({"holder": h, "slot": s, "feature": f, "kind": k, "default": d, "wave": int(w)})
    return out


def main(wave):
    docs = {(v["holder"], v["slot"]): v["doc"] for v in census()}
    rows = [r for r in read_tsv() if r["wave"] == wave]
    by = {}
    for r in rows:
        by.setdefault((r["holder"], r["feature"]), []).append(r)
    entries = {}
    for (holder, feature), slots in sorted(by.items()):
        table = not holder.startswith("/mob")
        d = os.path.join(ROOT, HOLDER_DIR[holder])
        os.makedirs(d, exist_ok=True)
        if table:
            lines = [f"// {feature}: lazy state of {holder} (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.", f"// read a field with STATE_PEEK(A, {feature}, field), write with STATE_SET(A, {feature}, field, value), end it with {feature}_clear(A).", "", f"/datum/{feature}_state", "\tparent_type = /datum/lazy_state"]
        else:
            lines = [f"// {feature}: lazy owned state of {holder} (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;", f"// read a field with STATE_GET(M, {feature}, field), write with STATE_SET(M, {feature}, field, value), end it with {feature}_clear(M).", "", f"/datum/{feature}_state"]
        for r in slots:
            doc = docs.get((holder, r["slot"]))
            if doc:
                lines.append("\t/// " + doc)
            vt = r["kind"] if r["kind"].startswith("/") else ""
            decl = f"\tvar/{vt.lstrip('/') + '/' if vt else ''}{r['slot']}"
            if r["default"]:
                decl += f" = {r['default']}"
            lines.append(decl)
        lines += ["", holder, f"\tvar/datum/{feature}_state/{feature}", ""] if not table else [""]
        open(os.path.join(d, f"{feature}_state.dm"), "w", encoding="utf8", newline="\n").write("\n".join(lines))
        entries.setdefault(holder, []).append(feature)
    for holder, feats in entries.items():
        p = os.path.join(ROOT, ROOT_BLOCK[holder])
        text = open(p, encoding="utf8", newline="").read()
        nl = "\r\n" if "\r\n" in text else "\n"
        header = f"CAPABILITIES({holder}){nl}"
        assert header in text, (holder, p)
        if holder.startswith("/mob"):
            block = f'\tsection(lazy_state, "Rare state, one lazy datum per feature (storage contract): {", ".join(feats)}"){nl}' + "".join(f"\towns_one(nameof({f}), /datum/{f}_state, lazy = TRUE){nl}" for f in feats)
            marker = f"owns_one(nameof({feats[0]}), /datum/{feats[0]}_state, lazy = TRUE)"
        else:
            block = f'\tsection(lazy_state, "Rare state, one lazy row per feature in an engine table (storage contract): {", ".join(feats)}"){nl}' + "".join(f"\tlazy_state({f}, /datum/{f}_state){nl}" for f in feats)
            marker = f"lazy_state({feats[0]}, /datum/{feats[0]}_state)"
        if marker in text:
            continue
        text = text.replace(header, header + block, 1)
        open(p, "w", encoding="utf8", newline="").write(text)
    print(len(by), "features,", len(rows), "slots written for wave", wave)


if __name__ == "__main__":
    main(int(sys.argv[sys.argv.index("--wave") + 1]))

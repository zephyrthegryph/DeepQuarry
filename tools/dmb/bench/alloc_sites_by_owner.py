"""Summarise a `DMB_ALLOC_SITES_PATH` report (feature `allocation-sites`) by owner.

An owner is the innermost frame that names a compiler crate (dm_session, dm_tree, dm_preprocess, dmbc, ...), reduced to
`crate::module::function`. Usage:

    python alloc_sites_by_owner.py report.txt [--report N]   # N-th `retained.after_request` block (default: last)
    python alloc_sites_by_owner.py report.txt --diff A B     # owner growth from block A to block B
"""
import argparse
import re
import sys
from collections import Counter

CRATES = ("dm_session", "dm_tree", "dm_preprocess", "dm_ir", "dm_link", "dm_cache", "dm_codegen_byond", "dm_resources",
          "dm_query", "dm_analysis", "dm_syntax", "dmbc", "byond_dmb", "dm_exec", "dm_profile")
FRAME = re.compile(r"^\s*\d+:\s+(?P<name>\S.*?)(?:\s+at\s+|$)")


def owner_of(frames):
    for frame in frames:
        match = FRAME.match(frame)
        if not match:
            continue
        name = re.sub(r"<.*", "", match.group("name"))
        if name.split("::")[0] in CRATES and "closure" not in name.split("::")[-1]:
            parts = [p for p in name.split("::") if "closure" not in p and "impl$" not in p]
            return "::".join(parts[:3])
    return "(unattributed)"


def blocks(path):
    reports, current, size = [], None, None
    frames = []
    def flush():
        nonlocal frames, size
        if current is not None and size is not None:
            current[owner_of(frames)] += size
        frames, size = [], None
    for line in open(path, encoding="utf8", errors="replace"):
        if line.startswith("######## retained.after_request"):
            flush()
            current = Counter()
            reports.append((line.strip(), current))
        elif line.startswith("== "):
            flush()
            size = int(re.match(r"== (\d+) MB", line).group(1))
        elif current is not None and size is not None:
            frames.append(line)
    flush()
    return reports


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--report", type=int, default=-1)
    ap.add_argument("--diff", nargs=2, type=int)
    ap.add_argument("--top", type=int, default=40)
    args = ap.parse_args()
    reports = blocks(args.path)
    if not reports:
        sys.exit("no retained.after_request block")
    if args.diff:
        a, b = reports[args.diff[0]][1], reports[args.diff[1]][1]
        print(reports[args.diff[0]][0]); print(reports[args.diff[1]][0])
        delta = Counter({k: b.get(k, 0) - a.get(k, 0) for k in set(a) | set(b)})
        for owner, mb in sorted(delta.items(), key=lambda kv: -abs(kv[1]))[: args.top]:
            print(f"{mb:+8d} MB  {owner}")
        print(f"{sum(delta.values()):+8d} MB  total (top-site sample)")
        return
    header, counts = reports[args.report]
    print(header)
    for owner, mb in counts.most_common(args.top):
        print(f"{mb:8d} MB  {owner}")
    print(f"{sum(counts.values()):8d} MB  total (top-site sample)")


main()

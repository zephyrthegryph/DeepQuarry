"""Site-level growth between two `retained.after_request` blocks of a `DMB_ALLOC_SITES_PATH` report.

    python alloc_sites_diff.py report.txt A B [--match TEXT] [--top N] [--frames N]

Sites are keyed by their first `--frames` named frames (default 6), so equal call paths of the two blocks are compared even
when their deeper frames differ. `--match` keeps the sites with that text in any frame. Prints the growth in MB, then the
frames, so one owner's biggest allocation paths can be read off (alloc_sites_by_owner.py only names the owner).
"""
import argparse
import re
from collections import Counter

FRAME = re.compile(r"^\s*\d+:\s+(?P<name>\S.*?)(?:\s+at\s+|$)")


def sites(path):
    reports, current, size, frames = [], None, None, []

    def flush():
        nonlocal frames, size
        if current is not None and size is not None:
            current.append((size, frames))
        frames, size = [], None

    for line in open(path, encoding="utf8", errors="replace"):
        if line.startswith("######## retained.after_request"):
            flush()
            current = []
            reports.append(current)
        elif line.startswith("== "):
            flush()
            size = int(re.match(r"== (\d+) MB", line).group(1))
        elif current is not None and size is not None:
            frames.append(line.rstrip())
    flush()
    return reports


def key_of(frames, depth):
    names = []
    for frame in frames:
        match = FRAME.match(frame)
        if match:
            names.append(re.sub(r"<.*", "", match.group("name")))
    return tuple(names[:depth])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("a", type=int)
    ap.add_argument("b", type=int)
    ap.add_argument("--match", default="")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--frames", type=int, default=6)
    args = ap.parse_args()
    reports = sites(args.path)
    totals = []
    for index in (args.a, args.b):
        counts = Counter()
        for size, frames in reports[index]:
            key = key_of(frames, args.frames)
            if args.match in " ".join(key):
                counts[key] += size
        totals.append(counts)
    delta = Counter({k: totals[1].get(k, 0) - totals[0].get(k, 0) for k in set(totals[0]) | set(totals[1])})
    for key, mb in sorted(delta.items(), key=lambda kv: -kv[1])[: args.top]:
        print(f"{mb:+6d} MB")
        for name in key:
            print(f"        {name}")


main()

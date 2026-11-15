"""A stat-keyed per-file cache for the manifest generators (gen_dme.py, gen_mapping_dme.py, gen_test_includes.py).

The generators read every .dm file under code/ to learn a few facts about each (what it #includes, whether it holds a variant table,
the types it declares). A restart after a merge changes a handful of files, so the facts of every other file are kept in
`data/dme-gen-cache/<name>.pkl`, keyed by the file's path, size and mtime in nanoseconds: a file whose stat is unchanged is never opened.
A fact is a pure function of the file's text, so a hit gives exactly what a read would. The store carries a stamp (a hash of the
generator sources that compute the facts); a different stamp drops it. `DQ_DME_CACHE=0`, `--no-cache` or `CI` turns the cache off, and a
missing or corrupt store is a miss, never an error. Entries of files that no longer exist are dropped on save.
"""
from __future__ import annotations

import hashlib
import os
import pickle
import sys
import tempfile

DIR = os.path.join("data", "dme-gen-cache")


def enabled() -> bool:
    # CI always generates from scratch: the cache is a local convenience, never what a gate's verdict rests on.
    return os.environ.get("DQ_DME_CACHE", "1") != "0" and "--no-cache" not in sys.argv and not os.environ.get("CI")


def stamp_of(*paths: str) -> str:
    h = hashlib.sha256()
    for p in paths:
        with open(p, "rb") as fh:
            h.update(fh.read())
        h.update(b"\0")
    return h.hexdigest()


def walk(top: str, root: str, suffix: str = ".dm"):
    """Every file under `top` ending in `suffix`, as (path relative to root with `/`, absolute path, size, mtime_ns), in os.walk order
    (a directory's files in name order, then its subdirectories in name order). The stat comes with the directory listing."""
    out = []

    def one(d: str) -> list[str]:
        dirs = []
        try:
            entries = sorted(os.scandir(d), key=lambda e: e.name)
        except OSError:
            return []
        for e in entries:
            try:
                if e.is_dir(follow_symlinks=False):
                    dirs.append(e.path)
                elif e.name.endswith(suffix):
                    st = e.stat()
                    out.append((os.path.relpath(e.path, root).replace("\\", "/"), e.path, st.st_size, st.st_mtime_ns))
            except OSError:
                continue
        return dirs

    # os.walk order: this directory's files, then each subdirectory depth first
    def rec(d: str) -> None:
        for sub in one(d):
            rec(sub)

    rec(top)
    return out


class FileCache:
    """`get(key, size, mtime_ns, compute)`: the stored fact when (size, mtime_ns) match, else `compute()` (stored)."""

    def __init__(self, root: str, name: str, stamp: str, use: bool = True, force: bool = False):
        self.use = use and (force or enabled())
        self.path = os.path.join(root, DIR, name + ".pkl")
        self.stamp = stamp
        self.entries: dict = {}
        self.memo: dict = {}
        self.used: set = set()
        self.dirty = False
        self.hits = self.misses = 0
        if self.use:
            try:
                with open(self.path, "rb") as fh:
                    data = pickle.load(fh)
                if data.get("stamp") == stamp:
                    self.entries = data["entries"]
                    self.memo = data.get("memo", {})
            except Exception:
                self.entries = {}
                self.memo = {}

    def get(self, key, size: int, mtime_ns: int, compute):
        self.used.add(key)
        e = self.entries.get(key)
        if e is not None and e[0] == size and e[1] == mtime_ns:
            self.hits += 1
            return e[2]
        self.misses += 1
        value = compute()
        if self.use:
            self.entries[key] = (size, mtime_ns, value)
            self.dirty = True
        return value

    def memo_get(self, key: str):
        return self.memo.get(key) if self.use else None

    def memo_put(self, key: str, value) -> None:
        if self.use:
            self.memo = {key: value}  # one result: the last inputs
            self.dirty = True

    def save(self) -> None:
        if not self.use:
            return
        gone = [k for k in self.entries if k not in self.used]
        if gone:
            for k in gone:
                del self.entries[k]
            self.dirty = True
        if not self.dirty:
            return
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(self.path), suffix=".tmp")
            with os.fdopen(fd, "wb") as fh:
                pickle.dump({"stamp": self.stamp, "entries": self.entries, "memo": self.memo}, fh, protocol=pickle.HIGHEST_PROTOCOL)
            os.replace(tmp, self.path)
        except OSError:
            pass

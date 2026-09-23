"""Lifecycle lint (roadmap L2, doc/rewrite/state.md sections 6 and 10).

Initialize() sets up an object's own state. Registering with the world belongs
in on_materialize() (and its inverse in on_dematerialize()). For every
latent-safe type, and every ancestor whose Initialize() such a type runs, this
lint rejects these inside Initialize():

    global list writes     GLOB.x += / -= / |= / &= / ^= / [k] = / .Add( .Remove( .Insert( .Cut( .Swap(
    processing starts      START_PROCESSING(...) and friends
    global signals         RegisterSignal(SSdcs, ...)
    radio joins            SSradio.add_object(...), set_frequency(...)

It reads the source statically, so a call made through a helper proc is not
seen here; the dq_lifecycle_sandbox unit test catches those at runtime.

Usage:
    python tools/ci/lifecycle_lint.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import state_schema_lint as schema  # noqa: E402

FORBIDDEN = [
    ("global list write", re.compile(
        r"\bGLOB\.\w+\s*(?:\+=|-=|\|=|&=|\^=)"
        r"|\bGLOB\.\w+\s*\[[^\]]*\]\s*=(?!=)"
        r"|\bGLOB\.\w+\.(?:Add|Remove|Insert|Cut|Swap)\(")),
    ("processing start", re.compile(r"\bSTART_PROCESSING\w*\(")),
    ("global signal registration", re.compile(r"\bRegisterSignal\(\s*SSdcs\b")),
    ("radio join", re.compile(r"\bSSradio\.add_object\(|\bset_frequency\(")),
]

PROC_HEAD = re.compile(r"^(/[\w/]+?)/(?:proc/)?Initialize\(")


def initialize_bodies(path, text):
    """Yields (type, line number, body lines with their numbers) for every
    top-level Initialize() definition in the file."""
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = PROC_HEAD.match(lines[i])
        if not m:
            i += 1
            continue
        start = i
        body = []
        i += 1
        while i < len(lines) and (not lines[i].strip() or lines[i][0] in " \t"):
            body.append((i + 1, lines[i]))
            i += 1
        yield m.group(1), start + 1, body


def main():
    files = schema.dm_files()
    _, _, latent = schema.parse(files)
    safe_roots = [t for t in latent if schema.effective_latent(t, latent)]
    # An ancestor's Initialize() runs for every latent-safe descendant.
    ancestors = set()
    for t in safe_roots:
        ancestors.update(schema.chain(t))

    failures, checked = [], 0
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = schema.code_only(f.read())
        if "Initialize(" not in text:
            continue
        for owner, line, body in initialize_bodies(path, text):
            if owner not in ancestors and not schema.effective_latent(owner, latent):
                continue
            checked += 1
            rel = os.path.relpath(path, schema.ROOT)
            for number, source in body:
                for label, pattern in FORBIDDEN:
                    if pattern.search(source):
                        failures.append(f"{rel}:{number}: {label} in {owner}/Initialize(); "
                                        "move it to on_materialize() and undo it in on_dematerialize()")
    print(f"lifecycle lint: {checked} Initialize() procs on latent-safe types and their ancestors, "
          f"{len(failures)} problems")
    for f in failures:
        print(f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

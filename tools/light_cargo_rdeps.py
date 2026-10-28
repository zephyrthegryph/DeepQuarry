"""Reverse dependencies of changed cargo crates, for tools/dq_light_checks.sh.

    python3 tools/light_cargo_rdeps.py <Cargo.toml of a changed crate> [...]

Prints, one per line, the manifest of every crate of the same cargo workspace that depends on one of the
given crates, directly or through other workspace crates (path dependencies), relative to the current
directory. The given manifests themselves are not printed. A crate outside any workspace prints nothing.

28 October: compiler/share-link-tables changed the dm-link crate, the light check ran dm-link's tests only,
and dmbc (which depends on dm-link) shipped a bug its own suite would have caught.
"""
import json
import os
import subprocess
import sys


def norm(p):
    return os.path.normcase(os.path.abspath(p))


def metadata(manifest):
    r = subprocess.run(["cargo", "metadata", "--format-version", "1", "--no-deps", "--offline",
                        "--manifest-path", manifest], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)


def main(argv):
    seen_ws = {}
    out = []
    for manifest in argv:
        meta = metadata(manifest)
        if not meta:
            continue
        root = meta.get("workspace_root", "")
        if root in seen_ws:
            continue
        pkgs = meta.get("packages", [])
        by_dir = {norm(os.path.dirname(p["manifest_path"])): p for p in pkgs}
        dependents = {}  # crate dir -> dirs of workspace crates that depend on it
        for p in pkgs:
            me = norm(os.path.dirname(p["manifest_path"]))
            for d in p.get("dependencies", []):
                if d.get("path"):
                    dependents.setdefault(norm(d["path"]), set()).add(me)
        changed = {norm(os.path.dirname(m)) for m in argv}
        todo = [c for c in changed if c in by_dir]
        found = set()
        while todo:
            c = todo.pop()
            for dep in dependents.get(c, ()):
                if dep not in found and dep not in changed:
                    found.add(dep)
                    todo.append(dep)
        seen_ws[root] = True
        for d in sorted(found):
            out.append(os.path.relpath(by_dir[d]["manifest_path"]).replace("\\", "/"))
    for m in out:
        print(m)


if __name__ == "__main__":
    main(sys.argv[1:])

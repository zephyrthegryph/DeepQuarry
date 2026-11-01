"""May a light lane land on its light precheck, without repeating the checks? (tools/dq_train.sh light_trust)

    python3 tools/train/light_trust.py --repo R --base <precheck master> --master <current master> --tip <lane tip> --selftests "test_a.sh test_b.sh"

Exit 0: nothing the lane's checks read changed on master since its precheck. Exit 1: something did; the one line printed names it. Any
other exit (git failed, cargo metadata failed) is also "repeat the checks": the caller fails closed.

The verdict compares what master changed with what tools/dq_light_checks.sh READS for this lane, not with the lane's directories:

  - the lane's own files, and the checks themselves (dq_light_checks.sh, dq_light_paths.sh, light_cargo_rdeps.py);
  - its self-tests and everything they name: repository paths and bare dq_*/test_* script names in a script's non-comment lines, followed
    through scripts (.sh .py .js) under tools/. BARRIER directories are named but not followed: a tool that names tools/build/build.sh
    depends on that file, not on all the TypeScript behind it;
  - a Rust file: the crates cargo tests for it (the crate and its reverse dependencies) and all their path dependencies, the workspace manifest and the lock;
  - a lint input (the checks then run the ratchets, which read the whole tree): anything but docs;
  - a doc: a link target that master deleted or renamed.

1 November 03:13Z: tools/light-selftests-parallel changed tools/ci/test_light_checks.sh, master changed tools/ci/test_vg_bindings_key.sh, they
shared the directory tools/ci, and 473 s of self-tests ran again. The directory rule also missed real dependencies: a lane changing dq_train.sh
was not re-checked when master changed dq_merge_batch.sh, which the same self-tests run.

A dynamic path (a name built at run time) cannot be seen here. What such a miss costs is one self-test failing on master afterwards, never a game
build: the light path carries no DM.
"""
import argparse
import json
import os
import re
import subprocess
import sys

CHECKS = {"tools/dq_light_checks.sh", "tools/dq_light_paths.sh", "tools/light_cargo_rdeps.py"}
BARRIER = ("tools/build/", "tools/analyze/", "tools/dmb/", "verdigris/")
NOT_FOLLOWED = {"tools/ci/check_ratchets.sh", "tools/dq_focused_test.sh"}
SCRIPT = (".sh", ".py", ".js")
LINT = re.compile(r"\.dm$|^tools/analyze/|^tools/ci/(lint_scopes\.toml|check_[^/]*|[^/]*baseline[^/]*|[^/]*\.txt)$|^tgui/packages/tgui/interfaces/|^tgui/.*\.jsx$")  # dq_light_checks.sh's ratchet rule
PATH = re.compile(r"(?<![\w./-])((?:tools|doc|config)/[\w./-]*[\w/])")
BARE = re.compile(r"(?<![\w./-])((?:dq_|test_)\w+\.(?:sh|js|py))\b")
DOCS = re.compile(r"^doc/|^html/changelogs/|\.md$")


class Fail(Exception):
    pass


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise Fail("git %s: %s" % (" ".join(args), r.stderr.strip()[:200]))
    return r.stdout


def names(text):
    return [l.strip() for l in text.splitlines() if l.strip()]


def mentioned(text, tree, dirs):
    """Repository files a script's non-comment lines name."""
    out = set()
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        for p in PATH.findall(line):
            p = p.rstrip("./")
            if p in tree:
                out.add(p)
            elif p in dirs and p.startswith("tools/") and not (p + "/").startswith(BARRIER):
                out.update(f for f in tree if f.startswith(p + "/"))
        for b in BARE.findall(line):
            for d in ("tools/", "tools/ci/"):
                if d + b in tree:
                    out.add(d + b)
    return out


def script_closure(repo, commit, roots, tree, dirs):
    # one git process for all the reads: a git process per file was 27 s on this machine
    cat = subprocess.Popen(["git", "-C", repo, "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def read(path):
        cat.stdin.write(("%s:%s\n" % (commit, path)).encode())
        cat.stdin.flush()
        head = cat.stdout.readline().split()
        if len(head) != 3:
            raise Fail("cannot read %s" % path)
        body = cat.stdout.read(int(head[2]) + 1)
        return body.decode("utf-8", "replace")

    seen = set()
    root_set = {r for r in roots if r in tree}
    todo = list(root_set)
    while todo:
        f = todo.pop()
        if f in seen:
            continue
        seen.add(f)
        if not f.endswith(SCRIPT) or f in NOT_FOLLOWED or f.startswith(BARRIER):
            continue
        for m in mentioned(read(f), tree, dirs):
            # a BARRIER file counts when a root names it (a self-test that runs build.ts); not when a tool further down happens to
            # and a self-test is a root or nothing: dq_light_checks.sh names test files in its map, it does not read them
            if m.startswith("tools/ci/test_"):
                continue
            # a tool's message names a doc for the reader; only a self-test reads one
            if m.startswith("doc/") and not f.startswith("tools/ci/test_"):
                continue
            if m not in seen and (f in root_set or not m.startswith(BARRIER)):
                todo.append(m)
    cat.stdin.close()
    cat.wait()
    return seen


def manifest_above(f, tree):
    d = os.path.dirname(f)
    while d:
        if d + "/Cargo.toml" in tree:
            return d + "/Cargo.toml"
        d = os.path.dirname(d)
    return None


def cargo_reads(repo, manifests):
    """The directories and files cargo test reads for these crates: the crates, their reverse dependencies, all their path dependencies."""
    dirs, files = set(), set()
    repo_abs = os.path.abspath(repo)

    def rel(p):
        return os.path.relpath(p, repo_abs).replace("\\", "/")

    for m in manifests:
        r = subprocess.run(["cargo", "metadata", "--format-version", "1", "--no-deps", "--offline", "--manifest-path", os.path.join(repo_abs, m)],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0:
            raise Fail("cargo metadata %s failed" % m)
        meta = json.loads(r.stdout)
        root = meta["workspace_root"]
        files.update((rel(os.path.join(root, "Cargo.toml")), rel(os.path.join(root, "Cargo.lock"))))
        deps, rdeps = {}, {}
        for p in meta["packages"]:
            me = os.path.normcase(os.path.dirname(p["manifest_path"]))
            for d in p.get("dependencies", []):
                if d.get("path"):
                    t = os.path.normcase(d["path"])
                    deps.setdefault(me, set()).add(t)
                    rdeps.setdefault(t, set()).add(me)
        start = os.path.normcase(os.path.dirname(os.path.join(repo_abs, m)))
        tested, todo = {start}, [start]
        while todo:
            for x in rdeps.get(todo.pop(), ()):
                if x not in tested:
                    tested.add(x)
                    todo.append(x)
        read, todo = set(tested), list(tested)
        while todo:
            for x in deps.get(todo.pop(), ()):
                if x not in read:
                    read.add(x)
                    todo.append(x)
        dirs.update(rel(x) + "/" for x in read)
    return dirs, files


def verdict(a):
    repo = a.repo
    lane = names(git(repo, "diff", "--name-only", "%s...%s" % (a.master, a.tip)))
    changed = names(git(repo, "diff", "--name-only", a.base, a.master))
    if not changed:
        return None
    gone = names(git(repo, "diff", "--name-only", "--diff-filter=DR", "--no-renames", a.base, a.master))
    tree = set(names(git(repo, "ls-tree", "-r", "--name-only", a.master)))
    dirs = {os.path.dirname(f) for f in tree}
    d = set(dirs)
    for x in dirs:
        while x:
            d.add(x)
            x = os.path.dirname(x)
    dirs = d

    changed_set = set(changed)
    for f in sorted(changed_set & (set(lane) | CHECKS)):
        return "master changed %s, which the lane or the checks themselves read" % f

    lint = [f for f in lane if LINT.search(f)]
    if lint:
        for f in changed:
            if not DOCS.search(f):
                return "the lane changes a lint input (%s), so its checks read the whole tree, and master changed %s" % (lint[0], f)

    docs = [f for f in lane if f.endswith(".md") or (f.startswith("doc/") and f.endswith(".html"))]
    for doc in docs:
        if doc not in tree:
            continue
        text = git(repo, "show", "%s:%s" % (a.tip, doc))
        for f in gone:
            if os.path.basename(f) in text:
                return "master deleted or renamed %s, which the lane's %s may link to" % (f, doc)

    # TGUI checks read all of tgui/, and tsc reads types generated from the DM by the analyzer through the build
    if any(f.startswith("tgui/") and not f.endswith(".md") for f in lane):
        for f in changed:
            if f.startswith(("tgui/", "code/", "tools/analyze/", "tools/build/")) and not f.endswith(".md"):
                return "the lane changes TGUI, whose checks read %s" % f

    roots = {"tools/ci/" + s for s in a.selftests.split()} | {f for f in lane if f.endswith(SCRIPT)}
    reads = script_closure(repo, a.master, roots, tree, dirs)
    for f in changed:
        if f in reads:
            return "master changed %s, which the lane's checks read" % f

    for b in BARRIER:
        if b != "tools/dmb/" and b != "verdigris/" and any(f.startswith(b) for f in lane):
            for f in changed:
                if f.startswith(b):
                    return "the lane and master both changed %s" % b

    manifests = {manifest_above(f, tree) for f in lane if f.startswith(("tools/", "verdigris/"))} - {None}
    if manifests:
        cdirs, cfiles = cargo_reads(repo, sorted(manifests))
        for f in changed:
            if f in cfiles or any(f.startswith(c) for c in cdirs):
                return "master changed %s, which the lane's cargo tests build" % f
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--repo", required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--master", required=True)
    p.add_argument("--tip", required=True)
    p.add_argument("--selftests", default="")
    a = p.parse_args()
    try:
        why = verdict(a)
    except Fail as e:
        print("cannot tell: %s" % e)
        return 2
    if why:
        print(why)
        return 1
    print("master changed nothing these checks read")
    return 0


if __name__ == "__main__":
    sys.exit(main())

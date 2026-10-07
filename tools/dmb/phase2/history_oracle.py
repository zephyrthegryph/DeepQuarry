"""Replay real commits in a new disposable worktree through snapshot-fed verify.

This never runs DreamMaker, DreamDaemon or Rust tests. Evidence is retained;
the caller chooses a fresh scratch path and compiler executable.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--count", type=int, default=300)
    parser.add_argument("--manifest", default="deepquarry.dme")
    parser.add_argument("--define", action="append", default=[])
    args = parser.parse_args()
    repo, compiler, scratch = args.repo.resolve(), args.compiler.resolve(), args.scratch.resolve()
    if args.count < 1 or args.count > 300 or scratch.exists():
        parser.error("count must be 1..300 and scratch must not exist")
    scratch.mkdir(parents=True)
    tree = scratch / "worktree"
    commits = subprocess.check_output(
        ["git", "-C", str(repo), "rev-list", "--first-parent", f"--max-count={args.count}", args.ref], text=True
    ).splitlines()[::-1]
    if not commits:
        parser.error("no commits selected")
    subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(tree), commits[0]], check=True)
    # Generated icons are a separate build product. Record this fixed seed;
    # callers requiring historical icon provenance must repack per commit.
    seed = repo / "icons" / "gen"
    if seed.is_dir():
        shutil.copytree(seed, tree / "icons" / "gen", dirs_exist_ok=True)
    rows = []
    environment = os.environ.copy()
    environment["LOCALAPPDATA"] = str(scratch / "localappdata")
    environment["XDG_CACHE_HOME"] = str(scratch / "cache")
    for ordinal, commit in enumerate(commits):
        # This checkout was created above; never reset the caller's checkout.
        subprocess.run(["git", "-C", str(tree), "checkout", "--force", commit], check=True)
        log = scratch / f"{ordinal:03d}-{commit}.log"
        started = time.monotonic()
        command = [str(compiler), "compile", "--verify", "--no-daemon", "--workers", "2", str(tree / args.manifest)]
        command.extend("-D" + define for define in args.define)
        with log.open("wb") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, env=environment,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            try:
                code = process.wait(timeout=295)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                code = "watchdog"
        text = log.read_text(errors="replace")
        matched = "native verification passed:" in text
        rows.append({"ordinal":ordinal,"commit":commit,"exit_code":code,"oracle_matched":matched,
            "compiled":code == 0,"seconds":time.monotonic()-started,"log":str(log)})
        (scratch / "receipt.json").write_text(json.dumps({"rows":rows,"fixed_icon_seed":str(seed),
            "complete":len(rows) == len(commits),"selected_commits":len(commits)}, indent=2))
        if not matched:
            raise SystemExit(f"oracle failed at {commit}; evidence {log}")
    print(json.dumps({"commits":len(rows),"compiled":sum(row["compiled"] for row in rows),
        "matching_rejections":sum(not row["compiled"] for row in rows),"evidence":str(scratch)}))


if __name__ == "__main__":
    main()

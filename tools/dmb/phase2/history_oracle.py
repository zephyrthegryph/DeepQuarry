"""Replay archived commits through fresh-process, disk-cache snapshot verification.

No worktree mutation, DreamMaker, DreamDaemon, Cargo or Rust tests. This does
NOT exercise retained daemon history or certify historical asset closure.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import zipfile
from history_owned import archive_relative, run_owned, safe, succeeded


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for data in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def regular(path):
    if not path.is_file() or path.stat().st_nlink != 1:
        raise ValueError(f"nonregular or multiply linked file: {path}")


def synchronize(archive, tree, previous, max_bytes):
    roster = {}
    with zipfile.ZipFile(archive) as entries:
        members = entries.infolist()
        if sum(item.file_size for item in members) > max_bytes:
            raise ValueError("archive exceeds expanded source storage cap")
        names, files = set(), []
        for item in members:
            relative = archive_relative(item.filename)
            if stat.S_ISLNK(item.external_attr >> 16):
                raise ValueError("archive symlink rejected")
            if item.is_dir():
                continue
            name = relative.as_posix()
            if name.casefold() in names:
                raise ValueError("duplicate/case-aliased archive member")
            names.add(name.casefold())
            files.append((item, relative))
        # Release only the prior authenticated tracked roster, before writing
        # replacement entries. Generated assets/cache namespaces are preserved.
        current_names = {relative.as_posix() for _, relative in files}
        for name, expected in previous.items():
            if name not in current_names:
                target = safe(tree.joinpath(*archive_relative(name).parts), tree)
                regular(target)
                if sha(target) != expected:
                    raise ValueError("previous archived source changed before removal")
                target.unlink()
        for item, relative in files:
            target = safe(tree.joinpath(*relative.parts), tree)
            if target.exists():
                regular(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            with entries.open(item) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output, 1024 * 1024)
            roster[relative.as_posix()] = sha(target)
    return roster


def roster_matches(tree, roster):
    return all(sha(safe(tree.joinpath(*archive_relative(name).parts), tree)) == expected
               for name, expected in roster.items())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--compiler-sha256", required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--count", type=int, default=300)
    parser.add_argument("--manifest", default="deepquarry.dme")
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--seconds", type=int, default=300)
    parser.add_argument("--memory-bytes", type=int, default=4_000_000_000)
    parser.add_argument("--max-source-bytes", type=int, default=4_000_000_000)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("Windows owned Job containment is required")
    if not 1 <= args.count <= 300 or not 1 <= args.seconds <= 300:
        parser.error("count and child watchdog must be 1..300")
    if not 1 <= args.memory_bytes <= 4_000_000_000 or not 1 <= args.max_source_bytes <= 4_000_000_000:
        parser.error("memory/source bounds must be positive and at most 4e9")
    if not re.fullmatch(r"[0-9a-f]{64}", args.compiler_sha256):
        parser.error("explicit lowercase compiler SHA256 required")
    repo, compiler = args.repo.resolve(), args.compiler.resolve()
    if sha(compiler) != args.compiler_sha256:
        parser.error("compiler pin mismatch")
    allowed = Path("E:/dq-cache").resolve()
    scratch = safe(args.scratch, allowed)
    if scratch == allowed or scratch.exists():
        parser.error("fresh dedicated E:/dq-cache scratch required")
    manifest = archive_relative(args.manifest)
    scratch.mkdir(parents=True)
    tree = scratch / "source"
    tree.mkdir()
    environment = os.environ.copy()
    environment["LOCALAPPDATA"] = str(scratch / "localappdata")
    environment["XDG_CACHE_HOME"] = str(scratch / "cache")
    receipt = {"schema": 2, "scope": "fresh-process disk-cache history verification",
        "retained_session_history": False, "historical_asset_closure_authenticated": False,
        "compiler": {"path": str(compiler), "sha256": args.compiler_sha256},
        "defines": args.define, "manifest": args.manifest,
        "child_watchdog_seconds": args.seconds, "job_memory_bytes": args.memory_bytes,
        "memory_scope": "Windows owned Job commit; not private bytes",
        "source_storage_cap_bytes": args.max_source_bytes,
        "rows": [], "commands": [], "complete": False}
    def save():
        (scratch / "receipt.json").write_text(json.dumps(receipt, indent=2))
    def git(arguments, output):
        with output.open("wb") as stream:
            result = run_owned(["git", "-C", str(repo), *arguments], repo, environment,
                               stream, min(args.seconds, 60), args.memory_bytes)
        receipt["commands"].append(result)
        save()
        if not succeeded(result):
            raise RuntimeError("owned Git command failed; preserved receipt")
    try:
        refs = scratch / "commits.txt"
        git(["rev-list", "--first-parent", f"--max-count={args.count}", args.ref], refs)
        commits = refs.read_text().splitlines()[::-1]
        if not commits or any(not re.fullmatch(r"[0-9a-f]{40,64}", c) for c in commits):
            raise ValueError("no valid immutable commits selected")
        receipt["selected_commits"] = commits
        seed = repo / "icons" / "gen"
        receipt["fixed_icon_seed"] = {"path": str(seed), "files": {}}
        seed_bytes = 0
        if seed.is_dir():
            safe(seed, repo)
            for current, directories, files in os.walk(seed, followlinks=False):
                safe(current, repo)
                for name in directories:
                    safe(Path(current) / name, repo)
                for name in files:
                    source = safe(Path(current) / name, repo)
                    regular(source)
                    seed_bytes += source.stat().st_size
                    if seed_bytes > args.max_source_bytes:
                        raise ValueError("fixed icon seed exceeds source storage cap")
                    relative = source.relative_to(repo)
                    target = safe(tree / relative, tree)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    before = sha(source)
                    shutil.copyfile(source, target)
                    if sha(source) != before or sha(target) != before:
                        raise ValueError("icon seed changed during capture")
                    receipt["fixed_icon_seed"]["files"][relative.as_posix()] = before
        previous = {}
        for ordinal, commit in enumerate(commits):
            if not roster_matches(tree, previous):
                raise ValueError("previous source roster changed")
            archive = scratch / "current.zip"
            git(["archive", "--format=zip", commit], archive)
            archive_hash = sha(archive)
            row = {"ordinal": ordinal, "commit": commit, "archive_sha256": archive_hash,
                   "archive_bytes": archive.stat().st_size, "oracle_matched": False}
            receipt["rows"].append(row)
            save()
            try:
                if archive.stat().st_size > args.max_source_bytes:
                    raise ValueError("archive storage cap exceeded")
                roster = synchronize(archive, tree, previous, args.max_source_bytes - seed_bytes)
                row["source_roster"] = roster
            finally:
                archive.unlink()  # exclusive scratch archive; hash already preserved
            save()
            effective_seed = {name: digest for name, digest in
                              receipt["fixed_icon_seed"]["files"].items() if name not in roster}
            if not roster_matches(tree, effective_seed):
                raise ValueError("fixed icon seed changed before compile")
            if sha(compiler) != args.compiler_sha256:
                raise ValueError("compiler pin changed before compile")
            log = scratch / f"{ordinal:03d}-{commit}.log"
            command = [str(compiler), "compile", "--verify", "--no-daemon", "--workers", "2",
                       str(tree.joinpath(*manifest.parts))]
            command.extend("-D" + define for define in args.define)
            with log.open("wb") as output:
                result = run_owned(command, tree, environment, output, args.seconds,
                                   args.memory_bytes, combine_stderr=True)
            row.update(child=result, log=str(log))
            save()  # Preserve child cleanup even if a subsequent proof read fails.
            row.update(compiler_pin_after=sha(compiler),
                       source_roster_matches_after=roster_matches(tree, roster),
                       fixed_icon_seed_matches_after=roster_matches(tree, effective_seed))
            row["oracle_matched"] = (result["exit_code"] in (0, 2)
                and result["failure"] is None and result["cleanup"].get("reaped")
                and "native verification passed:" in log.read_text(errors="replace")
                and row["compiler_pin_after"] == args.compiler_sha256
                and row["source_roster_matches_after"] and row["fixed_icon_seed_matches_after"])
            save()
            if not row["oracle_matched"]:
                raise RuntimeError(f"oracle failed at {commit}; evidence {log}")
            previous = roster
        receipt["complete"] = True
    except Exception as error:
        receipt["failure"] = str(error)
        raise
    finally:
        save()
    print(json.dumps({"commits": len(receipt["rows"]), "evidence": str(scratch),
                      "scope": receipt["scope"]}))


if __name__ == "__main__":
    main()

"""Authenticate registered worktree roots before measured compiler requests."""
import os
from pathlib import Path
import subprocess
import time


def _canonical(value):
    return str(Path(value).resolve()).casefold()


def _run(root, arguments, timeout):
    environment = os.environ.copy()
    for name in list(environment):
        if name.upper().startswith("GIT_"):
            environment.pop(name)
    result = subprocess.run(["git", "-C", str(root), *arguments], capture_output=True,
                            timeout=timeout, check=False, env=environment,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    if len(result.stdout) > 1024 * 1024 or len(result.stderr) > 64 * 1024:
        raise ValueError("worktree authority output exceeded bound")
    if result.returncode:
        raise ValueError(f"Git worktree authority failed for {root}: {result.stderr.decode('utf-8', 'replace')[:1024]}")
    return result.stdout.decode("utf-8", "strict")


def _registrations(text):
    entries = []
    current = {}
    for field in text.split("\0"):
        if not field:
            if current:
                entries.append(current)
                current = {}
            continue
        key, _, value = field.partition(" ")
        if key in current:
            raise ValueError("duplicate worktree authority field")
        current[key] = value
    if current:
        entries.append(current)
    return entries


def authenticate(roots, run=_run):
    """No source cleanliness claim: isolated source hashing remains independent."""
    if len(roots) != 6 or len({_canonical(root) for root in roots}) != 6:
        raise ValueError("requires six distinct canonical worktree roots")
    deadline = time.monotonic() + 70

    def query(root, arguments):
        remaining = min(10, deadline - time.monotonic())
        if remaining <= 0:
            raise TimeoutError("worktree authority deadline exceeded")
        return run(root, arguments, remaining)

    records = []
    for root in roots:
        rows = query(root, ["rev-parse", "--path-format=absolute", "--show-toplevel",
                            "--git-common-dir", "--git-dir", "HEAD"]).splitlines()
        if len(rows) != 4 or _canonical(rows[0]) != _canonical(root):
            raise ValueError(f"source is not its own Git worktree toplevel: {root}")
        head = rows[3]
        if len(head) not in (40, 64) or any(character not in "0123456789abcdef" for character in head):
            raise ValueError("invalid worktree HEAD identity")
        records.append({"root": str(Path(root).resolve()), "common_git_dir": str(Path(rows[1]).resolve()),
                        "private_git_dir": str(Path(rows[2]).resolve()), "head": head})
    if len({_canonical(row["common_git_dir"]) for row in records}) != 1:
        raise ValueError("six worktrees must belong to one common repository")
    if len({_canonical(row["private_git_dir"]) for row in records}) != 6:
        raise ValueError("worktree roots alias the same private Git directory")
    registered = _registrations(query(roots[0], ["worktree", "list", "--porcelain", "-z"]))
    for record in records:
        matches = [row for row in registered if _canonical(row.get("worktree", "")) == _canonical(record["root"])]
        if len(matches) != 1 or matches[0].get("HEAD") != record["head"] or "prunable" in matches[0]:
            raise ValueError(f"worktree registration missing, stale or inconsistent: {record['root']}")
        record["branch"] = matches[0].get("branch")
        record["detached"] = "detached" in matches[0]
    return {"schema": "dm-six-worktree-authority-v1", "status": "passed", "worktrees": records,
            "scope": "registered Git roots and HEAD identities before isolation; not source cleanliness, continuous isolation or runtime parity"}

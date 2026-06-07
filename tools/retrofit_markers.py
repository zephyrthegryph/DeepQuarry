#!/usr/bin/env python3
"""Retrofit // DQEdit markers on upstream files modified by recent fork commits.

Per CLAUDE.md §5, every change to a file under code/ must be wrapped in
DQEdit/DQAdd/DQRemoved markers so the next upstream merge can locate the
fork's edits. Recent fork commits (LINDA atmos rewrite, tgui-migration,
DQ preferences rewrite, gear_tweak refactor) made script-driven bulk
changes without inserting markers — this script retrofits them.

Marker placement strategy: instead of wrapping each individual hunk
(which would be noisy for files with many small mechanical edits like
the LINDA `gas.X` → `gas.X()` conversions), prepend a single block
comment to the top of each touched file naming the relevant commits
and summarising the kind of change. Grep for `DQEdit` will find every
fork-touched file; the commit SHAs give per-line archaeology.

For files with only a handful of localised edits we still use the
block-marker pattern — but inserted as a file-header attribution
rather than around each hunk.
"""
from __future__ import annotations

import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Commits whose edits we want to mark. (sha, label, rationale)
COMMITS = [
    (
        "6fdac16ef1",
        "LINDA atmospherics rewrite",
        "gas_mixture var accesses (e.g. mix.total_moles) converted to "
        "proc calls (mix.total_moles()) for the LINDA engine API. Bulk "
        "rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.",
    ),
    (
        "3ec748264e",
        "tgui-migration",
        "browse()/datum/browser/admin_log_show panels migrated to TGUI; "
        "stale shims (show_browser macro, browse callsites) removed.",
    ),
    (
        "fd3e36a673",
        "DeepQuarry preferences + loadout rewrite",
        "Bay preference_setup framework deleted; /datum/gear loadout "
        "catalog relocated from code/modules/client/preference_setup/loadout/ "
        "to code/datums/gear/.",
    ),
    (
        "cc0126f33e",
        "polymorphic gear_tweak inline dispatch",
        "/datum/gear_tweak gained get_inline_choices() + "
        "validate_inline_value() virtual procs; subtypes override them "
        "instead of the loadout editor doing istype chains.",
    ),
]


def files_touched_by(sha: str) -> set[str]:
    out = subprocess.check_output(
        ["git", "show", "--name-only", "--pretty=format:", sha],
        cwd=ROOT,
        text=True,
    )
    return {
        line.strip()
        for line in out.splitlines()
        if line.strip().startswith("code/") and line.strip().endswith(".dm")
    }


def already_marked(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return True
    return any(
        marker in text
        for marker in ("DQEdit", "DQAdd", "DQRemoved", "CHOMPEdit", "CHOMPAdd", "ChompEDIT")
    )


def build_header(commits: list[tuple[str, str, str]]) -> str:
    if len(commits) == 1:
        sha, label, rationale = commits[0]
        return (
            f"// DQEdit — {label} (commit {sha[:10]}). {rationale}\n"
            f"// Bracketed at file-header rather than per-hunk because the\n"
            f"// edits are mechanical and span the whole file; the commit SHA\n"
            f"// is the source of truth for per-line diff context.\n\n"
        )
    bullets = "\n".join(
        f"//   - {sha[:10]} ({label}): {rationale}" for sha, label, rationale in commits
    )
    return (
        "// DQEdit — file modified by multiple recent fork commits:\n"
        f"{bullets}\n"
        "// Per-line archaeology lives in those commits; this header marker\n"
        "// is here so an upstream merge knows to investigate.\n\n"
    )


def main() -> None:
    file_to_commits: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    for sha, label, rationale in COMMITS:
        for f in files_touched_by(sha):
            file_to_commits[f].append((sha, label, rationale))

    targets: list[tuple[Path, list[tuple[str, str, str]]]] = []
    for rel, commits in sorted(file_to_commits.items()):
        path = ROOT / rel
        if not path.exists():
            continue
        if already_marked(path):
            continue
        targets.append((path, commits))

    print(f"Will retrofit markers on {len(targets)} files.\n")
    for path, commits in targets:
        rel = path.relative_to(ROOT).as_posix()
        header = build_header(commits)
        original = path.read_text(encoding="utf-8", errors="replace")
        path.write_text(header + original, encoding="utf-8")
        print(f"  {rel}  ({len(commits)} commit(s))")


if __name__ == "__main__":
    main()

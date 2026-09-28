# Worker brief: generic systems wave

You are a sub-worker of the `rewrite/sys` lead in the DeepQuarry codebase (BYOND/DM SS13).

Read first: `AGENTS.md`, `doc/rewrite/systems.md` (the API you implement is specified there,
section per system), `doc/rewrite/om_in_10_minutes.md`, `doc/rewrite/declarative_lifecycle.md`,
`doc/rewrite/caching.md`, `doc/rewrite/interactions.md`.

## Setup
- Create your worktree: `git -C E:/projects/dq-sys worktree add -b rewrite/sys-<name> E:/projects/dq-sys-<name> rewrite/sys`.
- Work only there. Set `DQ_PREBUILT_VERDIGRIS=1` for builds (copy `verdigris.dll` from
  `E:/projects/dq-sys` or `E:/projects/CHOMPStation2` if missing).
- BYOND compiler: see memory note (D: drive, not on PATH); `tools/build/build.sh` finds it.

## Process rule (from the user, mandatory)
- Implement first.
- Compile only a few times: at major milestones and at the end, not after each change.
- Do NOT run any tests, focused ones included, until everything is done. Then run a single
  focused test pass at the very end (`bash tools/dq_focused_test.sh /datum/unit_test/<yours>...`).
- Never run the full suite. Never merge to master or push. Don't touch `tools/dm-health`.
  Don't touch the live server on port 1337. Never remove debug tracing/logging.

## What "done" means
1. The primitive(s) for your system(s), exactly as `systems.md` specifies (you may refine the
   API; if you do, update `systems.md` in your branch).
2. **Every** site of the old pattern migrated. No half states, no compatibility aliases: the
   old proc/var/pattern is deleted when its last site goes. Sites that genuinely cannot convert
   carry `// ALLOW(sys_<rule>): <specific reason>` (keep these rare; justify each).
3. A lint module `tools/ci/sys_rules/<system>.py` (copy `_template.py`: `RULES` dict and
   `scan(files)`); `tools/ci/sys_lint.py` runs it (already wired into check_ratchets.sh).
   Seed with `python tools/ci/sys_lint.py --seed <system>`, shrink with `--update`. The keep
   annotation is `// ALLOW(sys_<rule>): <reason>`. Every rule's baseline must be empty (0) at
   the end.
4. A focused test `code/modules/unit_tests/dq_sys_<system>_tests.dm` (included in the dme test
   section like the other dq_ tests).
5. Compile clean; DreamChecker (`$USERPROFILE/SpacemanDMM/dreamchecker.exe`) 0 new errors;
   `tools/ci/check_ratchets.sh` and `tools/ci/check_grep.sh` pass.
6. Docs: update `systems.md` (as-built notes for your section) and AGENTS.md if a rule changed.
7. Commit logically on your branch; every message ends with
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Report back: API, sites migrated
   (counts before/after), lint status, checks, SHAs.

## Scale
If your site count is large (hundreds+), you may fan out with the Agent tool into sub-workers,
each with a disjoint directory scope and its own worktree branched from yours; give each this
brief verbatim plus its scope; merge them back into your branch. Keep the primitive in your own
branch first so sub-workers build on it.

## Coordination
- Other workers are editing the same tree for other systems concurrently. Keep edits to what
  your system needs; don't reformat unrelated code. Prefer adding new files over editing shared
  hubs; when you add a `.dm`, add its `#include` to `deepquarry.dme` in sorted position.
- References (handles, relations, rosters, weak lists) are owned by the `rewrite/own` lead:
  don't redesign them.

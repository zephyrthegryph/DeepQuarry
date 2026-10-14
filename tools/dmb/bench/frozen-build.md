# Frozen compiler build preparation

Run `python tools/dmb/bench/frozen-build.py --commit <commit>` from the compiler
worktree. It uses one Cargo worker and a 300-second watchdog.

The tool archives the exact commit and overlays an exclusively owned stable
source directory by byte comparison. Unchanged source timestamps survive, so
Cargo can reuse unchanged artifacts across snapshots. Existing unowned source
directories and reparse paths are rejected.

Each receipt pins the archive, command, profile and successful copied executable.
A timed-out build publishes no executable. Rerun the same commit to finish the
remaining crates. The prototype release profile disables LTO and is not a
revision-6 performance acceptance profile. Build preparation is excluded from
compiler benchmark measurements.

`--tree-opt-level` permits an explicitly recorded prototype optimization level
for `dm-tree` when its Rust build exceeds the watchdog. It does not alter the
compiler snapshot. The build command and receipt pin both package profiles;
benchmark admission exports them and remains outside performance acceptance.

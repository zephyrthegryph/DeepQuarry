# Generated-plan work-state handoff

Three `CHANGE_EXPLICIT` cache registrations in the generated-station tile plan
became zero. Hull coordinates, borrowed corner intents and the seal queue are
live state retained between generation slices, not recomputable caches. An
unrelated publication now preserves their identity, order and saved cursor.
The corner view declares `ref_many` over tile intents genuinely owned by the plan.

The three regressions use real plan creation, yielding producer steps and tile
custody. They check successful continuation after publication and that clearing
the borrowed view preserves its owned tiles. No constructor or tool-action code
was edited.

Lane-ready passed on `7d361f3ae611`, merged with master `f208564b45`:
32 tests passed, zero failures; production compile zero errors; DreamChecker zero
diagnostics; analyzer and ratchets clean. Both mandatory pins, all three new
regressions, smoke tests and incremental appearance checks ran. No full suite ran.

Only the specialized requirement pin was refreshed for master's `f5007aa10f`
menu fixes, using 29 guarded fresh captures. Cause classes and affected types are
documented in `intended_changes.md`. Conversion pins passed without refreshing.
Factoring preserved the exact expanded rows of unrelated files. No baseline was
raised and no `ALLOW` was added.

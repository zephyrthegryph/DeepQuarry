# AI law view handoff

Branch: `codex/ai-laws-native-1011`. Normal lane-ready stamp:
`d6c586f2ef7e`, tested against master `3bd7a6f329`.

Replaced the single `CHANGE_EXPLICIT`-backed sorted-law cache with a pure,
fresh ordered view. Removed its stored result and eight manual cache clears.
Inherent-law indexes come from actual ownership and current list order.
External consumers use the view; constructor/lifecycle code is unchanged.

This also fixes immediate unmasking, zero-law clearing and index changes after
deletion. Callers cannot mutate another caller's returned list. The causes are
documented in `intended_changes.md`; no golden rows were re-blessed.

**40 tests passed, zero failed**, including six real law-state regressions,
module configuration/click tests, law-manager buttons/refusals, lost-drone law
behavior, both required pins, incremental appearance checks and smoke tests.
Production compile had zero errors; DreamChecker found zero diagnostics;
analyzer and all ratchets passed. No full suite was run.

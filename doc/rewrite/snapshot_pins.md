# Snapshot pins: what is left

A snapshot pin stores a golden table and fails when the code no longer produces it; its only fix is to re-bless it, so it records change instead of
guarding behaviour. Most were deleted: the generated conversion pins (`dq_conversion_pin` and the i7, machinery, requirement and silicon subclasses with
`snapshots/pins/` and its factored `op_bases/`), the hit pins (`dq_hit_pin`), the loot, chem-math, factor, reagents-start, matter and compiler-behaviour
goldens. Write a test that drives public inputs and asserts the effect (`test_click()`, `test_ui()`, `test_time()`, state through adapters); one direct
assertion beats a stored table.

What remains, with the file layout of `dq_snapshot_files.dm` (one text file per type under `snapshots/<name>/`, `--bless` rewrites the rows):
the xform pins (`snapshots/xform/`), the physiology factors (`snapshots/factors/physiology.txt`) and the window data pins below.

## Look pins (deleted)

There are no look pins. `dq_look_pin`, `dq_look_tree_pin`, `dq_look_state_pin`, the human and profile look hashes and their snapshot files were deleted
on 2026-10-17: they cost too much time per merge, the rendering migration is mostly done and playtesting finds visual issues. Snapshot look pins are
never re-added. Test a draw's behaviour (`dq_fresh_look_default`, `dq_human_draw_deterministic`, a hand-written test of the one thing a conversion must keep).

## Window data pins

A pin of what a window host shows after a scripted set of state changes, for the window conversions (a hand `update_uis()` or `changed()` mark
deleted, the state the window reads tracked; `code/modules/unit_tests/dq_ui_pins.dm`). `bash tools/dq_pin.sh --ui /datum/foo_panel` records one host
(`snapshots/ui_pins/`, test `dq_ui_data_pin`). The host's driver is a `/datum/ui_pin` subtype in a `dq_ui_pins_*.dm` file: `script()` builds the host,
then alternates the changes the window's buttons and the world make with `snap("label")`, which writes one row per top-level key of the host's
`tgui_data()` (`<label> | <key>: <json>`, refs written as `[ref]`, keys sorted). Record the pins in one run on the unmodified code; after the
conversion every changed row is a visible change: bless it only with a documented cause in `intended_changes.md`. The driver also attaches a probe
window (`watch_host()`), so a push test can assert that a step that changed the data pushed the window exactly once.

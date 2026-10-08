# Snapshot pins: when a generated snapshot is enough

A conversion (legacy forms to `CAPABILITIES` ops) must not change what a player can do. Two tools prove it:

- **Generated pins** (`tools/dq_pin.sh`, test `dq_conversion_pin`): a recorded table of what each actor can do
  with the type, written before the conversion and checked after it. Cheap: one command, no test code.
- **Hand-written pins** (`dq_p2_*_behaviour.dm`): tests that drive public inputs and read the effects
  (`test_click()`, `test_ui()`, `test_time()`, state through adapters). Expensive, and the only way to
  pin effects.

## The routine

```sh
bash tools/dq_pin.sh /obj/machinery/foo /obj/machinery/foo/bar   # 1. before converting: record (empty files, then one run)
# 2. convert the types
bash tools/dq_focused_test.sh dq_conversion_pin                   # 3. every row that changed, "new or changed" / "missing"
bash tools/dq_focused_test.sh --bless dq_conversion_pin           # 4. only if each change is intended: rewrite the pins
git add code/modules/unit_tests/snapshots/pins/                   # 5. commit the pins with the conversion
```

Each type is one file, `code/modules/unit_tests/snapshots/pins/<type with / as .>.txt`. An empty file is a
type not recorded yet: the next run records it instead of failing. `bash tools/dq_pin.sh --rm /type` drops one.
The files are read at run time, so recording or blessing never recompiles.

## What a pin records

For a human, a cyborg, an AI and a ghost with an empty hand, and for the human holding each common tool
(screwdriver, crowbar, wrench, wirecutters, multitool, a lit welder, cable, steel, an ID) and each item a
legacy interaction of the type asks for:

| Row | Meaning |
|---|---|
| `human\|/obj/item/tool/crowbar menu: Deconstruct (refused: the maintenance panel is closed)` | the menu entry, greyed out, with its refusal |
| `human\|none menu: Eject Recharger` | an entry the menu offers |
| `human\|/obj/item/multitool click: Click: Rcon tag` | what a plain click with that hand does (`click: nothing`) |
| `wires: Failsafes, Grounding, Input, Output, RCon` | the wires behind the panel (duds left out) |
| `keys: add_cable, cut_terminal, ...` | the op keys and legacy interaction ids |

Rows are keyed by what the player sees (labels and refusal text), not by ids, so a faithful conversion keeps
them. `keys:` is the exception: it changes on every conversion by design; check that each legacy id has
an op, then bless. A label that changes wording (`Open maintenance panel` to `Open panel`) is a visible change:
keep the old wording in the op's `label()` or say why in the commit.

## When a generated pin is enough

All of these hold:

- The conversion moves declarations: the same actions, offered to the same actors with the same tools, refused
  for the same reasons. Typical: a machine's panel, deconstruct, anchor, part replacement, a window-open op, a
  multitool setting, a tool swap.
- The effects are the library's (`panel()`, `anchor()`, `machine_basics()`, `wires()`, `part_replacement()`),
  which have their own tests, or are a one-line `then()` into the proc the legacy form already called.
- Nothing about the type is timed, random, or reached through a sequence (a construction ladder, a cycle).

## When hand-written pins are still needed

- **Effects.** A pin shows that "Eject" is offered, not that it ejects the right thing to the right place.
  Anything with its own state change (charge, gas, contents, access) needs a test that reads it.
- **Windows.** A pin sees the op that opens a window, not its buttons, data or the checks on each action:
  pin `ui_act` ops with `test_ui()` and the data with the window's adapter.
- **Time.** Waits (`wait()`), cooldowns, autoclose, periodic work: drive `test_time()`.
- **Sequences and states.** Construction ladders, panel-open-then-cut-a-wire, broken or unpowered states,
  emag, EMP: a pin records one fresh, powered instance only.
- **Other inputs.** Bumps, drags, alt/ctrl/shift clicks other than the plain click, radio, signals, remote
  (AI) control beyond what the menu shows.
- **Anything a pin row already disagreed on.** If the conversion changes a row on purpose, a test that says
  what the new behaviour is beats a blessed row nobody reads.

Rule of thumb: a generated pin is the floor for every converted type; add hand-written pins for each effect
the type owns (not the library's) and for each row of the table above that applies.

## The i7 interaction snapshots

`dq_interaction_domain_snapshot/i7_bulk`, `i7_items_bulk` and `i7_structures_bulk` use the same file layout
(`code/modules/unit_tests/snapshots/<name>/`), with id-keyed rows from the legacy resolver. Re-record after an
intended change with `bash tools/dq_focused_test.sh --bless 'dq_interaction_domain_snapshot/*'`; add a type by
adding an empty file for it. On a mismatch the current rows are written to `data/test-snapshots/<name>/`.

## Look pins

A pin of how a type looks once it exists, for appearance conversions (`code/modules/unit_tests/dq_look_pins.dm`). `bash tools/dq_pin.sh --look /T`
records one type (`snapshots/looks/`, test `dq_look_pin`); `bash tools/dq_pin.sh --look-tree /T` records every creatable subtype of `/T` in one
file (`snapshots/look_trees/`, test `dq_look_tree_pin`, exhaustive tier). Rows: icon, icon_state, dir, colour, alpha, and one row per distinct
overlay and underlay (`icon:state:plane[:colour]`, `xN` when repeated), taken after the presentation lane settled; each type is made with the RNG
reseeded from its path, and a runtime while it is made is a row of its own (without its file and line). The rows do not see a look a later state
change draws: the refresh-drift sweep and hand-written tests cover those.

A look state pin (`bash tools/dq_pin.sh --look-state /T`, `snapshots/look_states/`, test `dq_look_state_pin`, exhaustive tier) moves state and
records the look again: for each numeric var a subtype declares below `/obj` or `/mob` (24 at most), a fresh instance has it written to 0, 1 and 2,
a redraw is requested (`update_icon()` then `changed()`), and the rows are what the look gained (`+`) or lost (`-`) against the made look. A var the look
ignores writes no row. Record it before an appearance conversion and expect the same file after.

## Hit pins

A pin of what a thing does when it is hit or emagged, for the hit-reaction and emag conversions (`DAMAGE_REACTION`, `DAMAGE_REACTION_AFTER`,
`DECLARE_EMAG` to a hit hook, an `emag()` op; `code/modules/unit_tests/dq_hit_pins.dm`). `bash tools/dq_pin.sh --hit /T` records one type
(`snapshots/hit_pins/`, test `dq_hit_pin`). Each trigger gets a fresh instance on the test floor: an EMP (severity 1 and 2), an explosion
(1, 2, 3), a projectile, a blob hit, a thrown crowbar (the public entries `emp_act`, `ex_act`, `bullet_act`, `blob_act`, `hitby`) and an emag card
clicked by a human. The rows are what changed: `<trigger> | <var>: <old> -> <new>` for each var of the target, `deleted`, `turf: +<type> xN` /
`-<type> xN` for what appeared on or left its tile, `runtime: <message>` when the entry threw, `nothing`. Randomness is reseeded per trigger; a var that
holds a clock reading (cooldown, ready, time, next, last, delay, timer) is written as `<set>` or `0`, `atom_integrity` as `up` or `down`, and a blob
hit as `survives` or `destroyed` (a blob rolls its damage). Mobs and turfs are not hit-pinned (the harness cannot make them behave). A pin sees the
state at the end of the call and one drain later, not a timer seconds on, and not a hit hook that runs after the hit instead of before it unless that
changes the end state: hand-written tests cover those. A type whose entry throws on a bare instance (the rig's shock wire without a wearer) is a
finding, not a pin: leave it out and say so.

## Window data pins

A pin of what a window host shows after a scripted set of state changes, for the window conversions (a hand `update_uis()` or `changed()` mark
deleted, the state the window reads tracked; `code/modules/unit_tests/dq_ui_pins.dm`). `bash tools/dq_pin.sh --ui /datum/foo_panel` records one host
(`snapshots/ui_pins/`, test `dq_ui_data_pin`). The host's driver is a `/datum/ui_pin` subtype in a `dq_ui_pins_*.dm` file: `script()` builds the host,
then alternates the changes the window's buttons and the world make with `snap("label")`, which writes one row per top-level key of the host's
`tgui_data()` (`<label> | <key>: <json>`, refs written as `[ref]`, keys sorted). Record the pins in one run on the unmodified code; after the
conversion every changed row is a visible change: bless it only with a documented cause in `intended_changes.md`. The driver also attaches a probe
window (`watch_host()`), so a push test can assert that a step that changed the data pushed the window exactly once.

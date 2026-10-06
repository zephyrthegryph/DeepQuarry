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

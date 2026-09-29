# DeepQuarry conventions: ordinary DM, capabilities, enforced by CI

This page states the rules. `doc/rewrite/migration_guide.md` is the working reference: the API as
built, tagged [built] / [in progress] / [planned], and every old form with its replacement. When the two
disagree, the code wins; fix the page in the same commit.

## The rule of thumb

Write it the way DM already works:
- **Configuration is a type var.** It is free per instance, inherited and map-editable.
- **Behaviour is an override of a well-known proc.** Inheritance is `..()`.
- **A table is a proc that returns a list,** built once per type (`type_list()`).
- **Features are capabilities** that a type lists in `capabilities()`.
- **Macros exist only where DM has no construct:** `TRACKED` / `SETTER` generate or register setters,
  and `nameof()` gives the compiler-checked var name.

## Names

| Kind | Form | Examples |
|---|---|---|
| Capability constructors | `cap_<noun>(...)` | `cap_panel`, `cap_lock`, `cap_slot`, `cap_hand`, `cap_tool` |
| Bundles | plain nouns | `machine_basics`, `wall_machine`, `maintenance_hatch`, `console`, `atmos_device`, `cell_bay`, `power_channels`, `door`, `powered_by` |
| Client UI actions | `act_<action>(mob/user, named args...)` | `act_set_pressure(mob/user, pressure)` |
| Framework UI hooks (never client-reachable) | `ui_<hook>()` | `ui_allowed`, `ui_logged` |
| Look | `draw(datum/look/look)` | DM reserves `appearance` |
| Form fields | `choice_field`, `text_field`, `number_field` | DM reserves `text()` |
| Capability lifecycle | `on_holder_init`, `on_holder_destroy` | `/datum/on_destroy` exists |

`tools/ci` lints that no type proc shadows a constructor or bundle name.

## State

- **Plain vars.** Every dispatched call marks its target changed: entries, UI actions, timers, periodic
  steps, prompt answers, ownership transfers, reagents, damage and power.
- **`TRACKED(type, var, channel)`** generates `set_<var>()`, and **`SETTER(type, var)`** registers a
  hand-written one. Only those setters may write the var (`tracked_lint.py`), and admin VV edits go
  through them.
- **`changed(E, channel)`** is for the rare write outside a dispatched call.
- **Capability booleans** are bits in `cap_state`, allocated only in `code/__defines/cap_bits.dm`
  (`cap_bits_lint.py`). Write them with `cap_set()`; read them with `cap_has()` or the accessors, which
  never return null.
- **Richer state** goes in `cap_data(A, capability)`.
- **H1: map-varied settings stay instance vars** (`req_access`). Constructor arguments are type defaults.

## Capabilities

- **`capabilities()`** returns a list. It is built once per type and interned: identical constructor
  calls share one datum, one set of entries and one set of compiled predicates.
- **Order.** List order is the order of the menu, of examine lines and of the look.
  `layer_order` / `examine_order` override it.
- **Editing the list.** `without(., key)` drops an entry and `replace(., key, new)` swaps one in place.
  A later entry with the same key replaces the earlier one in its position.
- **Gating arguments.** Every constructor takes:
  - `behind`: bits that must be SET;
  - `blocked_by`: bits that must be CLEAR;
  - `locked_by`;
  - `needs` + `else_say`;
  - `works_broken` / `works_unpowered`;
  - `log`;
  - `layer` (the standard state name to draw; `CAP_NO_LAYER` draws nothing).
- **Holder hooks.** `before_entry()` may have side effects (a shock). `caps_suspended()` makes input fall
  through.
- **Handlers:**
  - `cap_hand`: `(mob/user, ...form args)`;
  - `cap_tool` / `cap_use_on` / `cap_insert`: `(mob/user, obj/item/held, ...form args)`.

  Return TRUE on success, or `refuse(user, text)`. Only successes are logged and fingerprinted.
- **Capabilities can own UI actions:** `/datum/capability/<x>/proc/act_<action>(mob/user, atom/holder, ...)`.
  Their UI data arrives under `data["caps"][key]`.
- **Runtime-attached capabilities:** `add_capability()` / `remove_capability()`.
- **System membership:** `joins` / `systems()`.

## Derived procs

- **The procs:** `draw(look)`, `should_run()`, `hidden_verbs()`, `tgui_data()` and
  `on_state_changed(bits)` are plain overrides. The refresh engine re-runs them at the end of the frame
  after a change.
- **Only children the owner draws propagate.** An owned child's change marks its owner only when one of
  the owner's capabilities draws it (`draws_var`).
- **Drift.** The sweep reports `REFRESH DRIFT` and fails test builds.
- **Verbs.** `type_verbs()` is a per-type list; `hidden_verbs()` hides by state. Both are applied
  through the verb store, the only writer of verbs lists.
- **Periodic work:** `periodic_cadence = CADENCE_*` or `periodic_interval = N`, with `should_run()` and
  `periodic_step(delta)`.

## Time

- `COOLDOWN_*` for "not more than once per N".
- `timed_set(src, nameof(var), value, for_time =)` for a value that reverts. The revert happens only if
  the value is unchanged. Never store an end time next to it.
- `after(src, N, PROC_REF(x))` for a delayed action.
- A periodic cadence for repeating work.

## Prompts and UI

- **Prompts.** Use `ask_text` / `ask_number` / `ask_list` / `ask_yes_no` / `ask_color` / `ask_mob`. They
  re-validate the action context and allow one open prompt per user per action. Forms are
  `form = list(...)` on an entry.
- **UI actions.** Client actions are `act_<action>` procs. Names and keys are normalised by
  `ui_action_key()` (hyphen and camelCase become snake_case). Reserved argument names are written last.
- **Validation.** Validate every parameter first with `ui_number` / `ui_text` / `ui_choice` / `ui_ref` /
  `ui_bool`. `ui_actions_lint.py` checks that TSX and DM agree.

## Style

- One proc-reference form: `PROC_REF`, `TYPE_PROC_REF`, `GLOBAL_PROC_REF`.
- `nameof()` for var names.
- Time defines.
- No positional nulls and no backslash continuations.
- No string mini-languages. The `%U%` / `%T%` message tokens are the one exception.

## Lints

`cap_bits_lint.py`, `tracked_lint.py`, `ui_actions_lint.py` and `sys_lint.py` (`dx_old_forms`,
`dx_manual_transfer`, and the dx_* rules from `rewrite/dx-lints`) run in `check_ratchets.sh`. Legacy
sites are baselined shrink-only. New code is held to 0.

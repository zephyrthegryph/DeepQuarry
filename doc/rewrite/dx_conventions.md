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
  `push_to_rust()` are plain overrides (`on_state_changed(bits)` is the old, channel-based form). The
  refresh engine re-runs them at the end of the frame after a change.
- **Declared dependencies.** `derived()` says what each one reads: `runs_while(nameof(v))`,
  `drawn_from(...)` (draw and hidden verbs), `ui_from(...)`, `rust_push(...)`,
  `derive(nameof(v), reads...)` for a cached value computed by `derive_<v>()`. A read is a var name
  (`TRACKED`, derived or a declared relation), `rel(link, nameof(/type::var))`,
  `rel_each(list_link, nameof(/type::var))` or `factor_dep(BF_X)`. A type that declares anything is
  exact: a tracked write re-derives only the outputs that read it, once per frame. Capabilities
  contribute their own reads. Outputs must not write state. `derived_reads_lint.py` checks the bodies
  (`--fix` edits the block), and the drift audit names a missing read. See `migration_guide.md` A2a.
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

## Rust

- **One driver, one outbox.** DM calls `vg_frame()` once a tick (through the native system). Nothing else drains
  Rust: no `vg_world_tick`, no `vg_drain_*`, no heat or gas drains.
- **Reading Rust state.** `native_read(E, NATIVE_KEY(code, field))` goes through the frame's cache; a generated
  getter is the same call without the cache. Never keep a DM copy of a Rust value. A turf's temperature is
  `get_temperature()`; `initial_temperature` is a seed.
- **Writing Rust state.** A generated setter of a config field ends with `rust_pushed()`; override it to re-publish
  derived Rust state. Do not push by hand after a setter.
- **Watching Rust state.** One facility: a watch port (a world kind, the turf solid, gas handles) through
  `vg_world_watch_*`. Wakes leave as `CHANGED` / `CROSSED` records, delivered by `native_crossed()`.
- **Moving gas.** Use `pump_gas()`, `scrub_gas()`, `calculate_transfer_moles()` or the `vg_*_transfer` binds. Never
  write the entropy or power maths in DM.
- **Rates.** `om_rate_*` only.

## Style

- One proc-reference form: `PROC_REF`, `TYPE_PROC_REF`, `GLOBAL_PROC_REF`.
- `nameof()` for var names.
- Time defines.
- No positional nulls and no backslash continuations.
- No string mini-languages. The `%U%` / `%T%` message tokens are the one exception.

## Lints

All run in `check_ratchets.sh`, each with `--selftest` fixtures. Legacy sites are baselined
shrink-only; new code is held to 0. `// ALLOW(<lint>): <reason>` keeps a justified site.

- **`ui_actions_lint.py`** reads `ui_action_key()`'s rules out of `ui_actions.dm`. For a migrated
  interface, every TSX `act()` must reach an `act_` proc (the host's, or a capability's it declares)
  with declared keys. C1 `ui_unsent_param`: every `act_` parameter is sent by some `act()`. C2
  `ui_unvalidated_param`: each parameter's first use is a `ui_*` validator, `!!x`, `switch(x)`,
  `islist(x)` or a compare with a constant.
- **`derived_reads_lint.py`**: each derived output reads only what `derived()` declares.
- **`tracked_lint.py`**: writes to a `TRACKED` / `SETTER` var outside its setter.
- **`cap_bits_lint.py`**: `CAP_*` bits outside `cap_bits.dm`, shared or out of range, and raw
  `cap_state` writes.
- **`sys_lint.py`** rules:
  - `dx_untracked_read` (H4): a derived proc (`draw`, `should_run`, `hidden_verbs`, `tgui_data`, a
    capability's `draw`/`gate`/`ui_data`/`examine`, a `needs =` proc) reads another object's var that
    isn't `TRACKED`/`SETTER` or behind a watched relation.
  - `dx_reactive_write` (H5): a derived proc writes anything but locals, the `data` list, `.` and
    `look.*`. It replaces `SHOULD_BE_PURE`, which these hooks can't carry: DreamChecker's purity is
    transitive over every write, and every capability lookup (`caps_of`/`cap_of`/`cap_data`) memoizes
    through a shared_cache and every `look.*` call writes the builder.
  - `dx_caps_instance_read` (M3): `capabilities()` reads an instance var.
  - `dx_timed_write` (M5): a `timed_set()` var written other than through it or its setter.
  - `dx_string_names`: a string literal as the var name of an `own_*`/`rel_*`/`om_set`/`timed_*`
    accessor.
  - `dx_raw_overlays`: `add_overlay`/`cut_overlay(s)`/`overlays +=`/`-=` outside the look builder.
  - `dx_raw_delay`: a numeric literal (not 0) not scaled by a time define in a delay argument.
  - `dx_manual_fingerprint_log`: `add_fingerprint`/`log_*`/`message_admins` in an `act_` proc or a
    capability entry handler.
  - `dx_constructor_shadow` (H7): a type proc named like a global `cap_*` constructor or bundle.
  - `dx_manual_transfer`: a hand-rolled take-out or move next to `own_set`/`own_add`/`own_put`.
  - `dx_old_forms`: the removed macros.
- **`doc_snippets.py`**: a call in a doc/rewrite `dm` block to a name that doesn't exist. Complete
  (untagged) blocks compile under `-DDOC_SNIPPETS` (`doc_snippets.py --write`, then build with
  `-DDOC_SNIPPETS`); `fragment` blocks are name-checked only, `before` blocks are skipped.

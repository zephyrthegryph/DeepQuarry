# DeepQuarry conventions: ordinary DM, three tables, enforced by CI

This page states the rules. [migration_guide.md](migration_guide.md) is the working reference: the
API, tagged [built] / [in progress] / [planned], and every old form with its replacement (Part F
is the foundation table). The design is in [foundation.md](foundation.md). When a page and the code
disagree, the code wins; fix the page in the same commit.

**Status.** The foundation forms below are **[in progress]** on the `rewrite/f-*` branches. Forms
already on `rewrite/dx-framework` are **[built]** and stay valid until their branch merges and the
old form is converted; the migration guide gives the mapping.

## The rule of thumb

Write it the way DM already works:
- **Configuration is a type var.** It is free per instance, inherited and map-editable.
- **Behaviour is an override of a well-known proc.** Inheritance is `..()`.
- **A table is a proc that returns a list,** built once per type. There are exactly three:
  `capabilities()`, `relations()`, `reactions()`.
- **Features are capabilities** that a type lists in `capabilities()`.
- **Macros exist only where DM has no construct:** `TRACKED` / `SETTER` generate or register setters,
  `PUBLISH` guards notice allocation, and `nameof()` gives the compiler-checked var name.

## Names

| Kind | Form | Examples |
|---|---|---|
| Capability constructors | `cap_<noun>(...)` | `cap_panel`, `cap_lock`, `cap_slot`, `cap_op`, `cap_require`, `cap_construction` |
| Bundles | plain nouns | `machine_basics`, `wall_machine`, `maintenance_hatch`, `console`, `atmos_device`, `cell_bay`, `power_channels`, `door`, `powered_by` |
| Requirements | `req_<x>` and `all_of`/`any_of`/`none_of` | `req_set`, `req_part`, `req_access`, `req_proc` |
| Triggers | plain verbs | `before_op`, `after_op`, `on_notice`, `on_change`, `on_cross`, `every` |
| Reaction sugar | plain nouns | `drawn_from`, `ui_from`, `derive`, `rust_push`, `runs_while` |
| Actions | `ACT_*` and `/datum/action_def/<x>` | `ACT_USE`, `ACT_DROP_ONTO`, `ACT_LOCK` |
| Notices | `/datum/notice/<x>` | published with `PUBLISH(src, type, ...)` |
| Client UI actions | `act_<action>(mob/user, named args...)` | `act_set_pressure(mob/user, pressure)` |
| Framework UI hooks (never client-reachable) | `ui_<hook>()` | `ui_allowed`, `ui_logged` |
| Look | `draw(datum/look/look)` | DM reserves `appearance` |
| Form fields | `choice_field`, `text_field`, `number_field` | DM reserves `text()` |
| Capability lifecycle | `on_holder_init`, `on_holder_destroy` | `/datum/on_destroy` exists |

`tools/ci` lints that no type proc shadows a constructor or bundle name.

## State

- **Plain vars** for configuration and internal state. Every dispatched call marks its target
  changed.
- **`TRACKED(type, var)`** generates `set_<var>()`, and **`SETTER(type, var)`** registers a
  hand-written one. Only those setters may write the var (`tracked_lint.py`); admin VV edits go
  through them. The setter publishes only when something reads the key ([state_and_relations.md](state_and_relations.md)).
  In built code `TRACKED` takes a `channel`; the foundation form drops it.
- **`publish_change(E, key)`** for the rare write outside a setter. [in progress; `changed()` [built]]
- **Capability booleans** are bits in `cap_state`, allocated only in `code/__defines/cap_bits.dm`
  (`cap_bits_lint.py`). Write with `cap_set()`; read with `cap_has()` or the accessors.
- **Richer state** goes in `cap_data(A, capability)`.
- **Map-varied settings stay instance vars** (`req_access`). Constructor arguments are type defaults.
- **Native values** are read with `native_read` and declared with `native(key...)`; never mirrored.

## Capabilities

- **`capabilities()`** returns a list, built once per type and interned: identical constructor
  calls share one datum, one set of entries and one set of compiled predicates.
- **Order.** List order is the menu, examine and draw order. `layer_order` / `examine_order` override it.
- **Editing the list.** `without(., key)`, `replace(., key, new)`, and `refine(key, ...)` to adjust
  one entry. A same-key redeclaration is an init error unless it goes through `refine`/`replace`. [in progress]
- **Gating.** Requirements, not bit arguments: `cap_require(ops = ..., needs = ...)` for a
  capability's contract and `cap_op(needs = ..., at = BAY_X)` for an operation. The old `behind`,
  `blocked_by`, `locked_by`, `needs` + `else_say`, `works_broken` and `works_unpowered` arguments keep
  working and map to requirements.
- **Operations.** `cap_op(name, handler, using=, by=, via=, action=, needs=, delay=, cost=, start_msg=, kind=, key=, at=, log=)`;
  `cap_hand`, `cap_tool`, `cap_use_on`, `cap_insert`, `cap_control` are presets. Handlers return TRUE
  on success or `refuse(user, text)`. Only successes are logged and fingerprinted.
- **Appearance names.** Capabilities do not take `layer =`; states follow the naming convention in
  [look.md](look.md).
- **Capabilities own UI actions** (`act_<action>`), data under `data["caps"][key]`, and may
  contribute `reactions()` and `relations()`.
- **Runtime:** `add_capability()` / `remove_capability()`, or `grant(target, what, source, duration=)`.

## Reactions

- **Static:** `reactions()` returns triggers: `before_op`, `after_op`, `on_notice`, `on_change`
  (with `drawn_from`, `ui_from`, `derive`, `rust_push`, `runs_while`), `on_cross`, `every`.
  `SHOULD_CALL_PARENT`; composed from the type, its capabilities and the generated reads.
- **Dynamic:** `observe(source, trigger, listener, handler)` / `unobserve()`, a `LISTENER` relation.
- **Reads** are `nameof(var)` (must be `TRACKED`/`SETTER`, derived, or a native/relation read),
  `rel(link, nameof(/type::var))`, `rel_each(...)` or `factor_dep(BF_X)`. Generated reads keep the
  table complete; hand-written entries are for what generation cannot see.
- **Outputs must not write state** (`draw`, `tgui_data`, `derive_<v>`, `should_run`).
- **Notices are occurrences only.** State changes are tracked writes, not notices.
- **Repeating work** is `every(...)`. There is no `periodic_cadence` / `periodic_step` /
  `DECLARE_PERIODIC_WHILE` in new code.
- **Verbs.** `type_verbs()` is per-type; `hidden_verbs()` hides by state; both go through the verb store.

## Relations

`relations()` declares links with `rel_one` / `rel_many` and a kind: `REF`, `PAIRED`, `OWNED`.
Internal kinds (GRANT, LISTENER, MEMBER, TIMER, CONTAINED) are used by the framework. `ownership()`
and `OWN(...)` become `OWNED` entries. Write with `rel_link` / `rel_unlink` or the `own_*`
accessors, never string names.

## Time

- `COOLDOWN_*` for "not more than once per N".
- `timed_set(src, nameof(var), value, for_time =)` for a value that reverts; never store an end time.
- `after(src, N, PROC_REF(x), key =, clock =)` for a delayed action. `om_after` and `after_slot` are wrappers.
- `every(...)` for repeating work. A timer that re-arms itself is never correct.
- No `sleep`, `spawn`, `stoplag` or `UNTIL` outside the ask layer and the kernel.

## Prompts and UI

- **Prompts.** `ask_text` / `ask_number` / `ask_list` / `ask_yes_no` / `ask_color` / `ask_mob`
  re-validate the action context and allow one open prompt per user per action. Forms are
  `form = list(...)` on an entry.
- **UI actions.** Client actions are `act_<action>` procs. Names are normalised by `ui_action_key()`
  (hyphen and camelCase become snake_case). Reserved argument names are written last.
- **Validation.** Validate every parameter first with `ui_number` / `ui_text` / `ui_choice` /
  `ui_ref` / `ui_bool`. `ui_actions_lint.py` checks that TSX and DM agree.
- **Player input** goes through actions: a gesture resolves via the bind profile to an action, then
  to the first applicable operation. There is no per-entry alt-click form ([operations_and_actions.md](operations_and_actions.md)).

## Style

- One proc-reference form: `PROC_REF`, `TYPE_PROC_REF`, `GLOBAL_PROC_REF`.
- `nameof()` for var names; time defines; no positional nulls; no backslash continuations.
- No string mini-languages. The `%U%` / `%T%` message tokens are the one exception.
- Per-event flyweights are `/datum/pooled` and are never stored ([pools.md](pools.md)).

## Lints

All run in `check_ratchets.sh`, each with `--selftest` fixtures. Legacy sites are baselined
shrink-only; new code is held to 0. `// ALLOW(<lint>): <reason>` keeps a justified site.

- **`ui_actions_lint.py`**: every TSX `act()` reaches an `act_` proc with declared keys; every
  `act_` parameter is sent (`ui_unsent_param`) and validated (`ui_unvalidated_param`).
- **`derived_reads_lint.py`**: each derived output reads only what is declared. `--fix` edits the
  block; `--fix-generated` writes `code/_generated/reads.dm`, checked for freshness in CI. [generated form in progress]
- **`tracked_lint.py`**: writes to a `TRACKED` / `SETTER` var outside its setter.
- **`cap_bits_lint.py`**: `CAP_*` bits outside `cap_bits.dm`, shared or out of range, raw `cap_state` writes.
- **`sys_lint.py`** rules:
  - `dx_untracked_read` (H4): a derived proc reads another object's var that isn't tracked or behind a watched relation.
  - `dx_reactive_write` (H5): a derived proc writes anything but locals, the `data` list, `.` and `look.*`.
  - `dx_caps_instance_read` (M3): `capabilities()` reads an instance var.
  - `dx_timed_write` (M5): a `timed_set()` var written other than through it or its setter.
  - `dx_string_names`: a string literal as the var name of an `own_*` / `rel_*` / `om_set` / `timed_*` accessor.
  - `dx_raw_overlays`: `add_overlay` / `cut_overlay(s)` / `overlays +=` outside the look builder.
  - `dx_raw_delay`: a numeric delay not scaled by a time define.
  - `dx_manual_fingerprint_log`: fingerprints or logs in an `act_` proc or a capability entry handler.
  - `dx_constructor_shadow` (H7): a type proc named like a global `cap_*` constructor or bundle.
  - `dx_manual_transfer`: a hand-rolled take-out or move next to `own_set` / `own_add` / `own_put`.
  - `dx_old_forms`: the removed macros.
- **Foundation lints [in progress]:** take/release pairing for pooled datums; the
  `turf.temperature` mirror lint; `look_lacks()` missing-part test; round-trip conservation test for
  construction ladders.
- **`doc_snippets.py`**: a call in a `dm` block of `doc/rewrite/*.md` (not `archive/`) to a name that
  doesn't exist. Foundation chapters show unbuilt APIs in `text` blocks so they are not checked.

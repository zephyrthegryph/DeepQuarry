# DeepQuarry conventions: ordinary DM, generic components, enforced by CI

This is the one style for every system. It is the design the user approved (the DX wave, Phase 1),
and it replaces the per-system macro dialects the DX audit catalogued. §10 maps each audit issue
to its fix.

**The rule of thumb:** write it the way DM already works.
- Configuration is a **type var**. It is free per instance, inherited, and editable in maps and VV.
- Behaviour is an **override of a well-known proc**, and inheritance is `..()`.
- A table is a **proc that returns a list**, built once per type.
- Features are **capabilities**: generic components that a type lists in `capabilities()`.
- Macros exist only where DM has no construct: `TRACKED` generates a setter, and `nameof()`
  names a var so the compiler checks it.

---

## 1. State

- **Plain vars by default.** After any dispatched call, the framework marks the object changed
  automatically. The dispatched calls are:
  - capability entries and interactions;
  - `ui_<action>` procs;
  - timers and periodic steps;
  - prompt answers;
  - construction steps and ownership transfers;
  - reagents, damage, power and verbs.
- **`TRACKED(type, var, channel)`**, written next to a normally declared var, generates
  `set_<var>(value)`. The setter compares, writes, calls `changed(src, channel)`, and returns TRUE
  if the value changed. A hand-written `proc/set_<var>()` is also accepted as the setter, for
  setters with side effects.
  - `tools/ci/tracked_lint.py` rejects every write to a TRACKED var outside its setter.
  - Reads are free.
- **`changed(src[, channel])`** is for the rare write outside a dispatched call.
- **The sweep.** A background sweep re-checks objects that have a look, `should_run()`,
  `hidden_verbs()` or an open UI, on a per-tick budget.
  - In production, a missed mark corrects itself within seconds.
  - In test builds, it fails the run: `REFRESH DRIFT: <type> draw() changed with no changed() mark`.
- **Removed:** `OM_FIELD`, `OM_FLAG_FIELD*`, `OM_DERIVE_FIELD`, field references, and every
  `inputs = list(...)`.

```dm fragment
/obj/machinery/atmospherics/binary/pump
	var/target_pressure = ONE_ATMOSPHERE
TRACKED(/obj/machinery/atmospherics/binary/pump, target_pressure, CHANGE_MACHINE_SETTINGS)
```

## 2. Capabilities

```dm fragment
/obj/machinery/power/apc/capabilities()
	. = ..()
	. += cap_cover(open_tool = TOOL_CROWBAR, locked_by = LOCK)
	. += cap_slot(nameof(cell), /obj/item/cell, behind = COVER)
	. += cap_emag(say = "You short out the APC's access lock.", effect = PROC_REF(emag_unlock))
```

- **Built once and shared.** `/atom/proc/capabilities()` returns a list. It is built once per type
  (`caps_of(A)`), and the capability datums in it are shared by every instance of the type.
- **Order.** List order is the order of the menu, of examine lines, and of look layers.
- **Removing an entry.** `. = without(., /datum/capability/anchor)` drops an inherited entry.
- **A capability is a complete feature.** It provides its interactions, its state, examine lines,
  look layers, UI data, the gating of other entries, refusal messages, logging and verbs.
- **State lives on the holder.**
  - A boolean is a bit in `cap_state` (`CAP_COVER_OPEN`, `CAP_PANEL_OPEN`, `CAP_LOCKED`,
    `CAP_BROKEN`, `CAP_EMAGGED`, …), written through `cap_set(A, bits, on)`.
  - Anything richer is a lazily created datum, `cap_data(A, capability)`.
  - The accessors are written once each: `cover_is_open(A)`, `panel_is_open(A)`, `is_locked(A)`,
    `is_emagged(A)`, `is_broken(A)`.
- **The standard library:**
  - `cover`, `panel`, `wires(type)`, `lock(access)`, `breakable` (with welder repair), `powered`,
    `emag(say, effect)`;
  - `slot(nameof(var), type)`, `anchor`, `deconstruct(board)` with the standard frame ladder,
    `construction(stages...)`;
  - `rotate`, `buckle` and `label`/`rename`.
- **Bespoke entries are small capabilities too:**
  - `hand(name, PROC_REF(x))`;
  - `tool(name, TOOL_X, PROC_REF(x), delay =)`;
  - `use_on(name, type, PROC_REF(x))`;
  - `insert(name, type, PROC_REF(x))`.
- **Presets are plain procs** that return capability lists: `machine_basics(board)`,
  `wall_machine(...)`, `floor_machine(...)` and `computer(board)`.
- **Gating** is a set of named arguments on any entry:
  - `behind = COVER|PANEL`;
  - `locked_by = LOCK`;
  - `needs = PROC_REF(x)` with `else_say = "..."`. `x` is a proc on the holder,
    `(mob/user, obj/item/held)`, that returns TRUE, FALSE (and `else_say` is shown) or a reason.
  - Every entry refuses while the holder is broken or unpowered, unless it is marked
    `works_broken` / `works_unpowered`.
- **Logging.** Each entry takes `log = LOG_GAME|LOG_ADMIN`. The dispatcher fingerprints and logs,
  so no handler calls `add_fingerprint()`, `log_game()`, `log_admin()` or `message_admins()`.
- **Handlers** are `(mob/user, obj/item/held, …form answers by name)`. They never re-check what
  their gating guaranteed.
- **Moving off base types.** `emagged`, `panel_open`, `locked`, `wiresexposed`, `welded`,
  `bolted`, the `wires` var, `circuit` (it moves to `deconstruct`) and access state (it moves to
  `lock`) leave the base types. A one-time converter rewrites map varedits.
- **Removed:**
  - every `*_act` tool proc, and attackby/attack_hand logic;
  - `emag_act`/`DECLARE_EMAG`;
  - `INTERACT_*`, `DECLARE_INTERACTIONS`, datum-per-interaction subtypes and
    `dq_interaction_from_spec`;
  - `REQ_*`, replaced by `needs`.

### 2.1 The capability datum interface (`code/datums/capabilities/_capability.dm`)

| Proc | Returns / does |
|---|---|
| `interactions(holder)` | `/datum/interaction/capability` entries, built once per type |
| `examine(holder, user)` | examine lines |
| `draw(holder, look)` | look layers, drawn before the holder's own `draw()` body |
| `ui_data(holder, user, data)` | adds keys to `tgui_data()` |
| `gate(holder, user, entry)` | null, or a refusal for another entry |
| `hidden_verbs(holder)`, `verbs()` | verbs to hide now; the verbs it adds |
| `on_holder_init(holder, mapload)`, `on_holder_destroy(holder)` | per-instance state |

Configuration is vars on the capability datum, set by its constructor with named args. The shared
gating vars are `key`, `behind`, `locked_by`, `needs`, `else_say`, `works_broken`,
`works_unpowered` and `log`.

## 3. The look

```dm fragment
/obj/machinery/power/apc/draw(datum/look/look)
	..()   // capabilities draw first: cover_open, panel_open, wires, broken, dark
	look.state("apc[cover_is_open(src)]")
	look.gauge("apc_charge", level = cell?.percent() / 100, levels = 4)
	look.glow("apc_lock", when = is_locked(src))
```

- **`draw()` is the override.** `draw(datum/look/look)` is a plain override that calls `..()`.
  DM reserves the name `appearance`, so it can't be used.
- **The builder calls** are `look.state(name)`, `look.overlay(name, when =)`,
  `look.gauge(name, level =, levels =)` and `look.glow(name, when =)`.
- **The builder is cheap.** It is reused, not allocated per draw. It produces a change key, so an
  identical result costs a string compare and churns no overlays. A type that draws nothing
  keeps its mapped icon_state.
- **Standard layer names:** `cover_open`, `panel_open`, `wires`, `locked`, `sparks`, `broken`,
  `dark`. A one-time tool renames cryptic DMI states through the dmi.toml pipeline.
- **Removed:** templates and `{x?a:b}` strings, `APPEARANCE_*`/`DECLARE_APPEARANCE*`,
  `update_icon()` calls and `update_icon()` overrides.

## 4. Periodic work and verbs

- `periodic_cadence` (a type var), `should_run()` and `periodic_step(dt)` are the whole periodic
  API. `should_run()` is re-evaluated on change, and there is one body name for every cadence.
- Verbs are native DM verbs. `hidden_verbs()` (call `..()`) is re-evaluated on change, and a
  capability's verbs come from the capability.

## 5. UI

```dm fragment
/obj/machinery/atmospherics/binary/pump/tgui_data(mob/user)
	. = ..()
	.["pressure"] = target_pressure

/obj/machinery/atmospherics/binary/pump/proc/act_set_pressure(mob/user, pressure)
	pressure = ui_number(pressure, 0, MAX_PUMP_PRESSURE)
	if(isnull(pressure))
		return refuse(user, "That isn't a pressure.")
	set_target_pressure(pressure)
```

- **`tgui_data()` is a plain override** that calls `..()`, so capabilities add their data. It is
  pushed automatically on change.
- **An action is a proc named `act_<action>(mob/user, named args...)`.** Only `act_*` procs are
  client actions; `ui_*` procs are framework hooks and are never reachable from a client. The
  action name and every key go through `ui_action_key()` (lowercase; hyphens and camelCase become
  snake_case; anything but `[A-Za-z0-9_-]` is rejected), so `act('bolt-toggle', {targetState})`
  reaches `act_bolt_toggle(mob/user, target_state)`. The client's params become named arguments,
  then the reserved names (`user`, `src`, `usr`, `ui`, `state`) are written last, so a payload can
  never set them. An argument name the proc doesn't declare is a runtime, which the dispatcher
  catches, logs and refuses.
- **Validation.** DM doesn't enforce the argument types, so the body validates them with
  `ui_number(x, min, max)`, `ui_text(x, max_length)`, `ui_choice(x, list)`,
  `ui_ref(x, list, type)` and `ui_bool(x)`, and refuses with `refuse(user, text)`. The first use of
  every parameter must be one of those validators (or `!!x`, `switch(x)`, `islist(x)`, or a
  compare against a constant); handing it straight to a helper proc counts only when the helper
  validates its own parameter first.
- **Every parameter is client-facing.** Each parameter except `user` must be sent by some TSX
  `act()`. An internal flag (`force`, `silent`) goes on a separate internal proc, since a client
  could set any parameter by naming it.
- **Gating and logging.** `ui_allowed(mob/user, action)` is the type-wide gate. `ui_logged()` is
  a per-type list mapping actions to log levels.
- **CI** (`ui_actions_lint.py`, which reads `ui_action_key()`'s rules out of `ui_actions.dm`)
  checks that every TSX `act()` of a migrated interface names an existing `act_` proc with
  matching argument names after normalisation, that every parameter is sent by some `act()` (C1),
  and that each is validated before use (C2).
- **Removed:** `DECLARE_UI`, `UI_ACT*`, `UI_DATA*`, `UI_ARG_*` and the generated tables.

## 6. Prompts

```dm fragment
/obj/item/camera_assembly/proc/set_up_camera(mob/user)
	var/networks = ask_text(user, "Which networks?", default = "SS13")
	if(!networks)
		return   // cancelled, or no longer valid (the player was told why)
	become_camera(networks, ask_text(user, "Camera name?", default = default_camera_name()))
```

- **The linear prompts** are `ask_text`, `ask_number(min, max)`, `ask_list`, `ask_yes_no`,
  `ask_color` and `ask_mob`.
  - Each one captures the calling action's context: the user, the target, the held item, and the
    entry's requirements or the window's state.
  - It re-validates that context when the answer arrives. If the context no longer holds, it
    returns null and tells the player why.
  - Prompting handlers are run async by the dispatcher.
- **Forms:** `form = list(choice_field("pack", PROC_REF(packs)), text_field("reason", max_length =
  256), number_field("qty", 1, 50))` on an entry. The answers arrive as named handler arguments,
  and the body validates them. DM reserves `text()`, hence the `_field` names.
- **Removed:** `act_ask`, `topic_ask`, `rerun_ask` and friends, the `kNNN` keys, and `om_ask`
  prompt flows.

## 7. Time

- **Timed values.** `timed_set(src, nameof(var), value, for_time =, clock = CLOCK_OWN|CLOCK_WORLD)`
  writes through the setter. It writes the previous value back the same way when time runs out,
  so there is no lapse hook. `time_left(src, nameof(var))` and `timed_cancel()` complete it.
- **Cooldowns** are `COOLDOWN_START(src, var, 3 SECONDS)` / `COOLDOWN_FINISHED`.
- **Removed:** `EXPIRY_*` and `EXPIRY_ON_LAPSE`.

## 8. Ownership, logging and style

- **Ownership.** `own_set(src, nameof(var), I)` takes I from its hand, slot or container, moves
  it in, and adopts it. There is no `drop_item(); forceMove(src)` before it.
- **Relations.** Write one side of a `REL_PAIR` only.
- **Style rules:**
  - one proc-reference form (`PROC_REF`, `TYPE_PROC_REF`, `GLOBAL_PROC_REF`);
  - time defines everywhere;
  - no positional nulls;
  - no string mini-languages. `%U%`/`%T%` message tokens are the one exception.
- **Teardown hooks** (`DESTROY_STEP`/`CAPTURE`/`AFTER`) become plain overrides where possible.

## 9. Lints

Every old form is banned once its migration lands, each with a baseline of 0.
- **`tracked_lint.py`:** writes outside a TRACKED setter.
- **`dx_old_forms`:** the removed macros listed above.
- **`dx_manual_refresh`:** `update_icon()`, `SStgui.update_uis(src)` or `om_changed()` in
  gameplay code.
- **`dx_manual_fingerprint_log`:** `add_fingerprint`/`log_game`/`log_admin`/`message_admins` in an
  `act_*` proc or a capability entry handler (the dispatcher records successes); ratcheted.
- **`dx_manual_transfer`:** `drop_item()`/`unEquip()`/`remove_from_mob()` or `forceMove(src)`/
  `loc = src` within a few lines of `own_set`/`own_add`/`own_put`; ratcheted.
- **`dx_raw_delay`:** a numeric literal other than 0, not scaled by a time define, in the delay of
  `after`/`om_after*`/`addtimer`/`do_after`/`COOLDOWN_START`, `timed_set(for_time =)` or a
  constructor's `delay =`; ratcheted.
- **`dx_string_names`:** a string literal where a var name goes (the var-name argument of every
  global `own_*`/`rel_*` accessor, `om_set`, `timed_set`, `time_left`, `timed_cancel`); ratcheted.
- **`dx_constructor_shadow`:** a type proc or verb named like a global `cap_*` constructor or a
  preset, which a bare call inside `capabilities()` would reach first (review 2, H7).
- **`dx_raw_overlays`:** `add_overlay`/`cut_overlay(s)`/`overlays +=`/`overlays -=` outside the
  look builder and the legacy appearance runtime; ratcheted.
- **`dx_untracked_read`:** a reactive proc (`draw`, `should_run`, `hidden_verbs`, `tgui_data`,
  a capability's `draw`/`gate`/`ui_data`/`examine`/`hidden_verbs`, a `needs =` proc) reads another
  object's var that isn't TRACKED (or registered with `SETTER`) or reached through a watched
  relation. Static: matched by var name; `tools/ci/sys_rules/dx_reactive.py` lists the limits.
- **`dx_caps_instance_read`:** `capabilities()` reads an instance var.
- **`dx_timed_write`:** a var handed to `timed_set()` written other than through it or its setter.
- **`ui_actions_lint`:** a TSX `act()` that doesn't match an `act_` proc (after `ui_action_key()`);
  an `act_` parameter no `act()` sends (`ui_unsent_param`); an `act_` parameter used before a
  validator (`ui_unvalidated_param`).
- **`cap_bits_lint`:** a `CAP_*` bit allocated outside `cap_bits.dm`, a shared or out-of-range bit,
  or a raw `cap_state` write outside `cap_set()`.
- **Purity (DreamChecker):** `should_run()` and the capability `draw`/`gate`/`ui_data`/`examine`/
  `hidden_verbs` hooks carry `SHOULD_BE_PURE(TRUE)`. `/atom/draw()` and `/atom/hidden_verbs()` don't
  yet, because `caps_of()` memoizes through a shared_cache, and neither does `tgui_data()`, whose
  legacy overrides write state.
- **`allow_tags`:** an unregistered `ALLOW()` tag.
- **`doc_snippets`:** a complete ```` ```dm ```` block in `doc/rewrite` that doesn't compile
  (`python tools/ci/doc_snippets.py --write`, then build with `-DDOC_SNIPPETS`), and a call in any
  complete or ```` ```dm fragment ```` block to a name that doesn't exist (ratcheted).
  ```` ```dm before ```` blocks are skipped.

## 10. Audit issues and their fixes

| Issue | Fix |
|---|---|
| H1 string var names | TRACKED setters, `nameof()`, the TRACKED lint |
| H2 refresh gaps | derived procs re-run on change, plus the sweep and drift failure |
| H3 re-run prompts | linear `ask_*()` with re-validation |
| H4 proc-ref and handler sprawl | overrides and capabilities; `PROC_REF` only; `(mob/user, …)` |
| H5 docs drift | the snippet CI |
| H6 interaction sprawl | capabilities and the bespoke entries |
| M1 mini-languages | plain DM in procs |
| M2 positional nulls | type vars and named args |
| M3 storage schemes | overrides, type vars and `type_list()` |
| M4 hand init | `/datum/New()` starts non-atom declarations |
| M5 requirement vocabulary | `needs` / `else_say` |
| M6 ALLOW zoo | the tag registry |
| M7 codegen leftovers | lint |
| M8 mirrored state | capability state bits and derived procs; mirrors deleted |
| M9 manual fingerprints and logs | the dispatchers |
| L1 raw deciseconds | lint |
| L2 backslashes | list-returning procs |
| L3 cadence body names | `periodic_step(dt)` only |
| L4 `args` shadowing | named handler arguments |

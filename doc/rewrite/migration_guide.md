# DeepQuarry migration guide

This is the single document an agent needs to convert code to the new framework. It contains:
- **Part A:** the framework as designed, with the exact API.
- **Part B:** the catalogue of every old form, each with its new form, a real before/after, and the traps.
- **Part C:** how to run a conversion and what to report.

Nothing else is required reading. `doc/rewrite/dx_conventions.md` and the design pages are background. `doc/rewrite/framework_fixes.md` (§9) is binding: where it disagrees with this guide, it wins, and this guide is corrected to match.

**Status markers.** Every API below is tagged with its state on `rewrite/dx-framework`:
- **[built]:** merged and tested; use it.
- **[in progress]:** being built now; don't depend on it without checking.
- **[planned]:** designed and approved, but not written. **Don't invent it.** If your conversion needs it, stop and report.

**Names as built:**
- **Single capabilities** use the `cap_` prefix (`cap_cover`, not `cover`), because plain names collided with existing procs (`deconstruct`, `rotate`, `insert`, `label`, `lock`).
- **Bundles and presets** are plain nouns (`machine_basics`, `wall_machine`, `maintenance_hatch`, `cell_bay`, `power_channels`, `console`, `atmos_device`, `door`, `powered_by`). A shadow lint stops any other proc from taking those names.
- **UI actions** are `act_<action>`, not `ui_<action>`, because `ui_*` is the framework's hook namespace. Client action names are normalised centrally: hyphen and camelCase become snake_case.

Where a design page uses an older name, this guide wins.

---

# Part A: the framework

## A1. The rules

1. **A feature is a capability.** Never add a base-type var plus conditionals for a feature some objects have. Examples: emagged, panel open, locked, has a cell.
2. **State is plain vars.** A dispatched call marks its target changed, and everything that depends on the target refreshes automatically: look, verbs, UI, `should_run()`. What a derived proc reads is declared in `derived()` (A2a), so a change re-derives only what reads it.
3. **Behaviour is an override of a well-known proc:** `capabilities()`, `draw()`, `tgui_data()`, `act_<x>()`, `should_run()`, `periodic_step()`, `examine_lines()`, `hidden_verbs()`.
4. **Tables are procs returning lists.** No string mini-languages, no positional nulls, no `{x?a:b}` templates.
5. **Lifetime is ownership.** Owned things move and die with their owner. Delete with an intent verb, not `qdel()`.
6. **World behaviour is a system** with private state, reached only through its `api.dm` and events. *[planned: kernel step 2]*
7. **Nothing sleeps outside the kernel.** Prompts and I/O are linear handlers that the dispatcher runs detached.
8. **Nulls stay out of APIs.** Accessors never return null; use null objects or sentinels.

## A2. State and change

| API | What it does | Status |
|---|---|---|
| plain `var/x` | state. After any dispatched call on an object, the framework marks it changed | [built] |
| `TRACKED(type, var, channel)` | next to a var: generates `set_<var>(value)`, which compares, writes, calls `changed()` and returns TRUE if changed. CI rejects writes to that var outside its setter | [built] |
| `SETTER(type, var)` | registers a hand-written `set_<var>()` with side effects as the setter (also used by VV) | [built] |
| `changed(E, channel = CHANGE_EXPLICIT, var)` | for the rare write outside a dispatched call (an unowned callback, raw FFI data). Without `var` everything is re-derived. `TRACKED` setters, `timed_set` and the ownership accessors pass the var, so a type that declares its reads (A2a) re-derives only what reads it. A hand-written `SETTER` passes `nameof(var)` too | [built] |
| `cap_set(A, bits, on)` / `cap_has(A, bits)` | capability state bits (`cap_state`). Bits are allocated by a registry with a uniqueness lint; never hand-number them | [built] |
| `cap_data(A, capability)` | a capability's lazily created per-holder datum, for state that isn't a bit | [built] |
| Accessors | `cover_is_open(A)`, `panel_is_open(A)`, `is_locked(A)`, `is_emagged(A)`, `is_broken(A)`, `wires_exposed(A)`, `is_bolted(A)`, `is_welded(A)`. Accessors never return null | [built] |

**Dispatched calls** (these mark their target automatically, and re-derive everything): capability entries, `act_*` UI actions, timers, `timed_set` reverts, periodic steps, prompt answers, construction steps, ownership transfers, reagent and integrity changes, and verbs. The background sweep catches missed marks: in test builds it **fails** with the type and var; in production it corrects within seconds.

## A2a. Declared dependencies [built: rewrite/dx-deps]

`should_run()`, `draw()` (with `hidden_verbs()`), `tgui_data()` and `push_to_rust()` are derived from state. A type says what each reads in `derived()`, a per-type block built once and cached like `capabilities()` (`SHOULD_CALL_PARENT`, pure: read no instance state):

```dm
/obj/item/laser_pointer/derived()
	. = ..()
	. += runs_while(nameof(energy))          // should_run(): re-checked when energy changes; wakes or parks the cadence
	. += drawn_from(nameof(pointing))        // draw() and hidden_verbs()
	. += ui_from(nameof(energy))             // tgui_data(): the open windows are pushed
	. += derive(nameof(power_state), nameof(stat), rel(nameof(power_area), nameof(/area::equip_on)))  // cached var, computed by derive_power_state()
	. += rust_push(nameof(target_pressure), nameof(on))   // push_to_rust() runs, once per frame, when any of these change
TRACKED(/obj/item/laser_pointer, energy, CHANGE_ITEM_CHARGE)     // a declared var must be able to notify
```

| Read | Means |
|---|---|
| `nameof(var)` | a var of the type. It must be `TRACKED` / `SETTER`, a `derive()` value, or a declared relation (`OWN` / `REL`); the lint refuses anything else |
| `rel(nameof(link), nameof(/type::var))` | `var` on what the declared relation `link` names (a `REL` / `OWN` view) |
| `rel_each(nameof(list_link), nameof(/type::var))` | the same for every member of a `REL_LIST` / `OWN` list |
| `factor_dep(BF_X)` | a body factor, fired when the body's cached factors change that factor |

**How it runs.** A tracked write calls `changed(E, channel, var)`. A type that declares anything is **exact**: only the outputs that read `var` are queued (`refresh_queued` is a bitmask of `DEP_RUN` / `DEP_DRAW` / `DEP_UI` / `DEP_PUSH` and one bit per `derive()` value), the entities that hop to it are marked, and a var nobody reads does nothing. A type that declares nothing keeps the old rule (any change re-derives everything), and a plain `changed(E)` always re-derives everything. The drain flushes each output at most once per entity per frame, in the order derive values, run, draw, UI, push. An exact type's periodic step no longer marks the entity blindly: the vars it writes are tracked.

**`derive(var, reads...)`** keeps a cached var, recomputed by `derive_<var>()` only when a read changed, in dependency order (a value that reads another runs after it; a cycle is reported). The body must be pure. The framework is the only writer of the var (the tracked lint counts every other write). It is tracked, so other entries can read it, and a value that comes out unchanged re-runs nothing. Read it at or after the first refresh; before that it holds its declared default. Keep it a scalar or an interned value: a list rebuilt each time never compares equal.

**Hops go only through relations.** The link var must be a declared `REL` / `REL_LIST` / `OWN...` var. The relation layer already calls one place when a view is linked or unlinked (`_rel_index()` / `_rel_unindex()`), and that is where a hop joins or leaves the reverse index (`GLOB.derived_watch`, weak keys). Linking, unlinking and replacing the view also re-derive what reads through it. A hop through a plain var is refused when the type's table is compiled, with a clear error. A non-atom datum calls `derived_attach(src)` in `New()`, like an atom does at init.

**Capabilities carry their own reads.** `/datum/capability/proc/derived_reads(holder)` returns the entries for the holder vars its `draw()` / `ui_data()` / `cap_should_run()` read (the slot contributes `drawn_from` and `ui_from` of its var, the charger `runs_while` of its cell slot). They are merged into the holder's table, so it declares only what its own code reads. They add reads but never make a holder exact; `. += runs_while()` (no reads) is the opt-in for a holder that reads nothing of its own.

**Rules.** Outputs must not write state: in test builds a tracked write while `should_run`, `draw`, `hidden_verbs`, `tgui_data` or a `derive_<var>` runs is reported (`OUTPUT WROTE STATE`). An exact type does not override `on_state_changed()`: use `push_to_rust()` with `rust_push(...)`.

**Lint and audit.** `tools/ci/derived_reads_lint.py` parses each derived proc body and fails when it reads a var of the type that the matching declaration doesn't list (`src.x`, or a bare `x` the type declares). `--fix` adds the missing reads to the source `derived()` block (a dev tool; it doesn't generate anything at build). It also flags a declared var that isn't tracked, derived or a relation, and a hop through a non-relation. Legacy code is in `tools/ci/derived_reads_baseline.txt` (shrink-only). `tracked_lint.py` counts every write to a tracked or derived var outside its setter. The sampled `REFRESH DRIFT` audit is the one audit: it re-derives the look, hidden verbs, `should_run()` and every `derive()` value, compares them with what is applied, and names the likely undeclared read (in test builds: the tracked vars whose change was dropped since the last full refresh).

## A3. Capabilities

```dm
/obj/machinery/thing/capabilities()
	. = ..()                        // list order = menu order = examine order = draw order
	. += machine_basics(board = /obj/item/circuitboard/thing, wires = /datum/wires/thing)
	. += cap_hand("Toggle", PROC_REF(toggle))
	. = without(., /datum/capability/anchor)                  // drop an inherited one
	. = replace(., /datum/capability/cover, cap_cover(open_tool = TOOL_WRENCH))
```

**Bespoke entries** [built]:

```dm
cap_hand(name, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE,
	works_unpowered = FALSE, log, list/form, priority, stance, name_proc, applies, blocked_by = NONE)
cap_tool(name, quality, handler, delay, ...same gating...)          // works_broken/unpowered default TRUE
cap_use_on(name, held_type, handler, ...same gating...)             // use an item on this
cap_insert(name, held_type, handler, ...same gating...)             // put an item in
```

| Gating keyword | Meaning |
|---|---|
| `behind = COVER\|PANEL` | only while that cover or panel is open |
| `locked_by = LOCK` | refused while the lock is engaged |
| `needs = PROC_REF(x)` (or a list) + `else_say = "..."` | `x(mob/user, obj/item/held)` returns TRUE or a refusal text |
| `works_broken`, `works_unpowered` | an entry refuses while broken or unpowered **unless** set |
| `blocked_by = <bits>` | refused while those state bits are set |
| gating hooks [built] | `before_entry()`, `caps_suspended()`, `cap_gating`/`cap_apply_gating` for bundles that gate their parts |
| `log = LOG_GAME\|LOG_ADMIN` | the dispatcher logs, and always fingerprints |
| `form = list(text_field(...), number_field(...), choice_field(...))` | answers arrive as named args |

Handler signatures: a `cap_hand()` handler is `(mob/user, ...form answers)`; `cap_tool()` / `cap_use_on()` / `cap_insert()` handlers are `(mob/user, obj/item/held, ...form answers)`. A handler returns TRUE (success) or a refusal: `return refuse(user, "text")`. A refusal, a cancelled prompt or a null result is not logged or fingerprinted; the target is still marked changed.

## A4. The standard library

| Constructor | Status | Gives |
|---|---|---|
Every constructor below also takes the standard gating arguments `behind`, `blocked_by`, `locked_by`, `needs`, `else_say`, `works_broken`, `works_unpowered`, `log`, plus `layer =` (the state name it draws; `CAP_NO_LAYER` draws nothing). Capability-level gating is merged onto every entry the capability builds.

| `cap_cover(open_tool = TOOL_CROWBAR, delay, removable = FALSE, ...gating)` | [built] | open/close entry (`BY_HAND` opens by hand), `cover_open` state and look, examine; `removable` adds the knocked-off cover (`CAP_COVER_REMOVED`) |
| `cap_panel(tool = TOOL_SCREWDRIVER, delay, ...gating)` | [built] | maintenance panel |
| `cap_wires(wires_type, ...gating; behind = PANEL)` | [built] | wire access; the wires datum lives in `wires_of(A)` (replaces the `wires` var) |
| `cap_lock(access, req_one_access, id_types, ...gating)` | [built] | ID swipe lock; reads the holder's mapped `req_access`/`req_one_access` first (replaces `locked` and `req_access` gating) |
| `cap_emag(say, effect, mode = EMAG_ONCE, already_say, delay, ...gating; log = LOG_ADMIN)` | [built] | emag entry; `effect(mob/user, obj/item/card)` runs FIRST and may refuse (FALSE: no bit, no charge); then the bit is set and a charge spent |
| `cap_breakable(repair_tool = TOOL_WELDER, repair_delay, ...gating)` | [built] | broken state (from atom_break/atom_fix), welder repair, examine |
| `cap_anchor(tool = TOOL_WRENCH, delay, needs_floor, ...gating)` | [built] | (un)anchor |
| `cap_rotate(clockwise, counter, needs_unanchored, ...gating)` | [built] | rotate entries |
| `cap_buckle(...gating)` | [built] | buckling (settings are the holder's type vars) |
| `cap_label(max_length, ...gating)`, `cap_rename(max_length, ...gating)` | [built] | hand-labeller label, pen rename |
| `cap_power(...gating)` | [built] | the `dark` state and examine while unpowered; entries refuse unpowered unless `works_unpowered` |
| `cap_slot(var_name, accepts, ...gating, eject_needs, name, ...)` | [built] | one item slot: insert, eject, examine, UI data; the var becomes owned; draws its item when it has a layer |
| `cap_deconstruct(board, behind = PANEL, ...)` | [built] | crowbar dismantle to a frame (in the design, `deconstructible`) |
| `cap_construction(stage(...), ..., ladder_options(...))` | [built] (costs are `cap_tool`/`cap_insert`/`cap_use_on`/`cap_hand` entries with no handler; `uses`, `sfx`, `icon` on `stage()`) | build/undo ladders |
| `cap_frame_ladder()` | [built] (a proc on `/obj/structure/frame`) | the standard machine/computer frame ladder |
| `cap_wall_mount(offset)` | [built] | faces a wall machine away from its wall and offsets it onto it |
| `cap_atmos_unwrench(delay)` | [built] | unfasten an atmos device into its pipe item, refused while running or over-pressured |
| **Bundles** [built]: `machine_basics(board, anchored_by = TOOL_WRENCH, repair_tool)` (panel, breakable, power, anchor, deconstruct behind the panel), `wall_machine(board, offset, repair_tool)` (basics without anchoring + wall mount), `console(board)`, `atmos_device(uses_power, unwrench_delay)`, `maintenance_hatch(wires, access, cover_locked_while, panel_needs_cover_closed, cover_tool, removable_cover, emag_say, emag_effect, emag_mode)` (cover + panel + wires behind it + lock + emag; the lock and emag only work closed up; the coverlock only holds the cover shut) | [built] | a later capability with the same key replaces an earlier one in place, so a bundle can refine another's part (the hatch's panel replaces the basics' panel) |
| **Bundles** [in progress]: `cell_bay(slot_var)`, `power_channels()` (owns `act_channel`/`act_breaker`/`act_nightshift`), `powered_by(system, role)` (rewrite/dx-apc); `door(...)` (rewrite/dx-doors) | [in progress] | |
| Items: `cap_use_self(name, handler, ...gating, form =, log =, cooldown =, in_inventory = FALSE)`, `cap_use_at(name, handler, range = 1, target_types =, ...gating, form =, log =, cooldown =)` (replace `attack_self`/`afterattack`) | [built] | `cap_use_self`: item in hand used on itself, handler `(mob/user, ...form)`, runs from `attack_self`, answers `INPUT_ACTION_SELF_USE`, refused unless held when offered through the resolver/Menu (`needs cap_in_hand`; a direct `attack_self()` call, e.g. an action button, is trusted as before, since its callers decide reach; `in_inventory = TRUE` also accepts worn). It replaces the old `self_use()` helper. `cap_use_at`: the held item is the holder, the clicked atom the target, handler `(mob/user, atom/target, ...form)`; `range` 1 = adjacent, >1 also ranged; `target_types` filters. Click order: target `attackby` first, then the item's `use_at` entries (via `after_click()`), then legacy `afterattack`. The dispatch marks, fingerprints and logs the ITEM; mark the target yourself with `changed(target)` |
| Mobs: `cap_ai(targets)`, `cap_ai_behaviors(...)`, species `species_capabilities()` | [planned] | plan §2.3, §2.4 |
| `cap_system(path)` membership (`systems()`) | [built] (O(1) join/leave) | used by `/datum/system` once it exists |

**Capabilities may own UI actions** [built]: `/datum/capability/<x>/proc/act_<action>(mob/user, atom/holder, ...args)` plus `ui_logged()` on the capability; the dispatcher resolves it on the holder's capabilities when the holder has no `act_<action>` itself. Capability UI data arrives under `data["caps"][<key>]`.

[planned] (framework_fixes.md §9.5; don't invent them):
- **Machines:** `machine_board`/`machine_wires` type vars read by `machine_basics()`; `refine(key, ...)` to adjust one part of a bundle; `service_panel(access)`; `cap_occupant(max, types, enter_delay, eject_on)` with `occupants(src)` and derived `occupant_count`; `cap_access(req_access)`; parts: `cap_parts(list(/obj/item/stock_parts/x = n))` with `derive_part_rating()` (replaces `RefreshParts`); `look.loop(sound)`; `cap_slot(..., eject_tool = TOOL_X)`.
- **Derived values:** `derived()` with `runs_while`/`drawn_from`/`ui_from`/`derive(...)`, and `rust_push(reads...)` replacing hand `update_rust_device()` calls (§9.2).
- **Vore:** `cap_interior(transmit, escape_delay, on_enter, on_exit)`; `settings()` rows (`setting_choice/number/text/bool/color`) with one `act_set_setting(user, key, value)`.

## A5. Look

```dm
/obj/machinery/thing/draw(datum/look/look)
	..()                                   // capabilities draw first: broken, cover_open, panel_open, emagged
	look.state("thing_on")                 // icon_state
	look.overlay("thing_lights", when = on)
	look.gauge("thing_charge", level = charge, levels = 5)
	look.glow("thing_screen", when = on)   // emissive
	look.light(2, 0.25, COLOR_GREEN)       // set_light
```

[built] Things the framework handles for you:
- A property the look stops setting reverts to the type default.
- Image overlays are part of the change key.
- An identical result costs almost nothing.

**Never** call `update_icon()`, `queue_icon_update()` or `update_appearance()`, and never override `update_icon`. **Standard state names:** `broken`, `cover_open`, `panel_open`, `wires`, `locked`, `sparks`, `emagged`, `dark`. The icon-state rename tool [built] maps legacy states to them in `dmi.toml` and updates the code.

## A6. Periodic work and verbs

```dm
/obj/machinery/thing
	periodic_cadence = CADENCE_SLOW        // CADENCE_SLOW (2 s) / CADENCE_SECOND / CADENCE_FAST, or periodic_interval = N for a custom interval
/obj/machinery/thing/derived()
	. = ..()
	. += runs_while(nameof(on))            // A2a: what should_run() reads
/obj/machinery/thing/should_run()      // re-evaluated when a declared read changes; FALSE parks at zero cost
	return on && !is_broken(src)
/obj/machinery/thing/periodic_step(delta)   // delta = the cadence's interval in deciseconds; scale by it
	...
	return PROCESS_KILL                    // optional: park until the next change
```

Side effects of a change (a Rust device sync, a network rebuild): override `on_state_changed(bits)` [built]. The refresh engine calls it at most once per frame after a change, with the channels raised since the last refresh. Never call it by hand; it must not write the state it reacts to (test builds report a self-mark).

Verbs:
- **Always on:** native `/verb/` declarations.
- **Conditional:** `hidden_verbs()` returns the verbs to hide right now; it is re-evaluated when a `drawn_from` read changes and applied through the verb store [built].
- **Per subtype:** `type_verbs()` [built].
- **Species, traits and capabilities:** `granted_verbs()` [built]: per instance, derived; default returns every capability's `verbs()`, and a human adds `/datum/trait/proc/granted_verbs()` of its species' traits (example: `xenomorph_hunter`). `hidden_verbs()` still wins.
- **Admin:** `ADMIN_VERB(...)` (unchanged).
- **Debug:** `DEBUG_VERB(...)`, compiled out of release [planned].
- **Categories:** `set category = VERB_CAT_*` defines only [planned: plan §2.12]. Until the defines land, don't invent new category strings.

## A7. UI

```dm
/obj/machinery/thing/tgui_data(mob/user)
	. = ..()                                      // capabilities add their data (locked, broken, cell…)
	.["on"] = on
	.["target"] = target_pressure

/obj/machinery/thing/proc/act_set_pressure(mob/user, pressure)   // the TSX sends act("set_pressure", {pressure})
	pressure = ui_number(pressure, 0, MAX_PRESSURE, round_to = 1)
	if(isnull(pressure))
		return refuse(user, null)
	target_pressure = pressure
	return TRUE

/obj/machinery/thing/ui_allowed(mob/user, action)                  // type-wide gate
	return !is_locked(src) || issilicon(user)
```

[built]:
- The dispatcher finds `act_<key>` on the host or on one of its capabilities. Only procs named `act_*` are client-reachable.
- Reserved argument names (`user`, `holder`, `src`, `usr`, `ui`, `state`) are written last, so a client can't override them; never name an `act_` argument after one.
- Unknown argument names are logged and refused.
- Validators: `ui_number(v, min, max, round_to)`, `ui_text(v, max_length)`, `ui_choice(v, list)`, `ui_ref(v, within, type)`, `ui_bool(v)`, plus `refuse(user, text)`. Validate before use; a lint checks it.
- The TSX lint checks every `act()` name has an `act_` proc with matching argument names. **Literal names only:** `act(\`be_player_${x}\`)` is banned; pass it as an argument.

[planned]:
- `ui_rights = R_X` on admin panels;
- `config` sent once per open;
- pushes coalesced and driven by `changed()`;
- generated TSX data types that must be imported.

## A8. Prompts

```dm
/obj/machinery/thing/proc/rename(mob/user)
	var/name = ask_text(user, "New name?", max_length = MAX_NAME_LEN)
	if(!name)
		return                     // cancelled, or no longer valid (the player was told why)
	set_name(name)
```

[built]:
- `ask_text`, `ask_number(min, max)`, `ask_list`, `ask_yes_no`, `ask_color`, `ask_mob`.
- Each captures the calling action's context and re-validates it on answer.
- One open prompt per user per action.
- Prompting handlers run detached automatically.
- Forms: `form = list(text_field(...), number_field(...), choice_field(...))`.

[built]: re-validation re-runs the entry's `needs`, or the `needs =` passed to the `ask_*`; `third_party = TRUE` checks only the answerer (a consent prompt). `ask_number` returns null on cancel, so 0 is a valid answer: test with `isnull()`.

[planned] (framework_fixes.md §9.1, option A): handlers that ask or await run as kernel-tracked tasks, cancelled when the holder is deleted, the user disconnects or the target goes; `as = ASK_THIRD_PARTY`/`ASK_CONSENT`, `timeout =`, `default =`, `yes =`/`no =` labels, `validate =`, `ask_form(...)`, `task_why()`, `await_sql`/`await_http`/`await_job` returning `/datum/io_result`, `start_task()`, `await_action()`, `test_answers()`. Until then use the built `ask_*` above.

## A9. Time

The decision table. **Read it before writing anything with a timer.**

| You want | Write | Status |
|---|---|---|
| "Not more than once per N" | `COOLDOWN_DECLARE(x)` + `COOLDOWN_START(src, x, N)` / `COOLDOWN_FINISHED(src, x)` | [built] |
| A var that reverts after N | `timed_set(src, nameof(var), value, for_time = N)`, read the var directly, `time_left(src, nameof(var))` for a countdown, `timed_cancel(...)` | [built] |
| A temporary condition **with behaviour** (EMP'd, failed, jammed, on fire) | a timed grant of a capability: `om_grant_for(src, GRANT_CAPABILITY, /datum/capability/condition/x, source, N)` (becoming `grant_for()`, framework_fixes.md §9.3) | [built] (`condition.dm`) |
| Do something once, later | `after(src, N, PROC_REF(x), args...)`; owned by src (dropped if src is gone). A datum argument deleted meanwhile **arrives as null** and the call still runs (counted, logged), so cleanup always happens: check your args. `after_if_alive(...)` drops the call instead, for a pure effect | [built] |
| One pending "do later" per name (re-arming replaces it) | `after_slot(src, "name", N, PROC_REF(x))` | [built] |
| Something repeating while a condition holds | a cadence: `should_run()` + `periodic_step(dt)`, **never** a timer that re-arms itself | [built] |
| Delete after N | `expire(N)` (movables) | [built] |
| Long work split over ticks | a system `periodic_step()` returning `STEP_YIELD` | [planned] (kernel) |
| Wait for a player or I/O | linear `ask_*`, or `await_sql`/`await(...)` in a handler | ask [built]; await [planned] |

**Never:**
- store an end time next to `timed_set`;
- compare `world.time` against a stored stamp (use `COOLDOWN_*` or `time_left`);
- write `sleep`, `spawn`, `stoplag` or `UNTIL` outside the kernel;
- write a proc that re-arms its own timer.

## A10. Ownership, relations and lifetime

| You want | Write | Status |
|---|---|---|
| A owns B (B moves and dies with A) | `OWN(type, var, policy)` and `own_set(src, nameof(var), B)`, which takes B from its hand, slot or container, moves it in and adopts it. Replacing disposes of the old value by policy | [built] |
| Dispose of what a var owns now | `own_clear(src, nameof(var))` | [built] |
| A points at B (cleaned up on both ends) | `relations()` with `rel_one()`/`rel_many()` (`back =`, `other_deleted =`, `on_unlink =`, `keyed =`, `watch =`), written with `rel_link(src, nameof(var), B)` / `rel_unlink()` (not `link()`, which is a BYOND built-in; never a string name) | `relations()` [built]; typed `/datum/om/relation` conversion [planned] (plan §2.9) |
| Two-sided pair | write **one** side; the framework writes the other | [built] |
| Remove and destroy a consumed item | `consume(item, actor)` | [built] |
| Turn into something else | `replace_with(path, ...)` | [built] |
| Empty a slot or container by policy | `slot_clear(slot)` / `ledger_empty(policy)` | [built] |
| Teardown work | an `on_destroy()` hook only for what no policy can express; never null or qdel owned vars there | [built] |

## A11. Requirements

- **[built]** `needs = PROC_REF(x)` + `else_say` on capability entries.
- **[planned]** (plan §2.10): a shared `chk_*` library (`chk_alive`, `chk_conscious`, `chk_capable`, `chk_unrestrained`, `chk_adjacent`, `chk_near_subject`, `chk_held`, `chk_carried`, `chk_hand_free`, `chk_on_turf`), and `ask_*` re-validation running the same `needs`.
- **Until it lands:** convert `REQ_ON`/`REQ_TARGET_STATE` to `needs = PROC_REF(<the same proc>)`, drop reach/adjacent/inventory clauses (the dispatcher applies them), and leave `ASK_*` alone.

## A12. Systems and the kernel [planned]

- **Definition:** a system is `/datum/system/x` in `code/modules/x/`. It has private state (`VAR_PRIVATE`), `needs = list(...)` (boot order), `periodic_cadence` + `should_run()` + `periodic_step(dt)`, `member_should_run(A)` / `member_step(A, dt)` for atoms that joined through `cap_system()`, `emits` + `events()`, `latency_class`, and an `api.dm` that other folders may call.
- **Replaces:** `SUBSYSTEM_DEF`, `/datum/world_service`, `GLOB.x_service`, `boot_after`/`order_after`, `init_order`, `fire()`.
- **Until the kernel lands:** don't convert subsystems. Do add `api.dm` procs for what other folders call, and route new callers through them.

## A13. Automatic: don't write these

- **Fingerprints and logs:** the dispatcher fingerprints and logs (`log =` on the entry). Delete `add_fingerprint(user)` in converted handlers.
- **Marking changes:** the dispatcher marks the target changed. No `update_icon()`, no `SStgui.update_uis(src)`.
- **Sanitising:** `ask_text` and `ui_text` sanitise; don't double-encode.
- **Access checks** for `cap_lock`-gated entries: covered by `locked_by = LOCK`.

## A14. Base vars and nulls

- **Base types:** never add a var to `/atom`, `/obj`, `/obj/item`, `/obj/machinery`, `/mob`, `/mob/living` or `/mob/living/carbon/human` without asking. A ratchet counts them [planned].
- **No `= list()` on instance vars:** use lazy lists.
- **Null policy (library and framework code):** accessors never return null (a count is 0, a list is empty, a state is FALSE); use a null object or a sentinel where "nothing" must be represented; relations, timers (`after`, `after_slot`, `timed_set`) and dispatch drop dead targets, so a handler never receives a null or deleted target.
- **Accessors never return null.** Use a null object (`/datum/thermal_profile/default`) or a defined sentinel (`NIGHTSHIFT_AUTO`), not null.
- **No defensive guards in converted code:** no `?.` chains or `if(!x) return` on values the framework guarantees (owned vars, relation targets inside their hooks, timer and callback args). `QDELETED()` checks belong only at edges: I/O callbacks and user input.


---

# Part B: the catalogue of old forms

Every form that goes away is listed here with its count on `integrate/b17` and the lint that tracks it. The `dx_old_forms` ratchet (`tools/ci/sys_rules/dx_old_forms.py`) started at 18,363 sites, and each wave drives its rules to 0. **A converted folder may contain none of these.**

| # | Old form | Count | Lint rule | New form | Section |
|---|---|---|---|---|---|
| B1 | `DECLARE_INTERACTIONS`, `EXTEND_INTERACTIONS`, `INTERACT_*`, `/datum/interaction/*` subtypes, `declare_interactions()`, `dq_interaction_from_spec` | 3,269 | `old_interaction_decl` | `capabilities()` | A3 |
| B2 | `*_act` tool procs (`screwdriver_act`, `crowbar_act`…) | 603 | `old_tool_act` | `cap_tool` or a library capability | A3, A4 |
| B3 | `emag_act`, `DECLARE_EMAG*`, the `emagged` var | 78 | `old_emag` | `cap_emag` | A4 |
| B4 | `REQ_*`, `/datum/predicate` (non-slot), `ASK_*`, `PROMPT_*`, `requires` | 902 + 451 + 224 + 497 | `old_requirement` | `needs =` | A11 |
| B5 | `APPEARANCE_*`, `DECLARE_APPEARANCE*`, `appearance_overlays()`, `update_icon` overrides | 844 | `old_appearance` | `draw(look)` | A5 |
| B6 | `update_icon()`, `queue_icon_update()` calls | 2,322 | `old_manual_refresh` | delete | A2 |
| B7 | `DECLARE_UI*`, `UI_ACT*`, `UI_DATA*`, `UI_ARG_*`, `UI_SUBACT*` | 6,055 | `old_ui` | `tgui_data()` + `act_<x>()` | A7 |
| B8 | `om_ask`, `act_ask`, `topic_ask`, `rerun_ask`, `verb_ask`, `client_ask`, `flow_ask`, `prompt_flow`; `tgui_input_*`, `tgui_alert`, `input()`, `alert()` | 2,142 + 48 + 58 | `old_prompt` | `ask_*` | A8 |
| B9 | `EXPIRY_*`, `ELAPSED` | 776 + 95 | `old_expiry` | `COOLDOWN_*` / `timed_set` / grant | A9 |
| B10 | `OM_FIELD`, `OM_FLAG_FIELD*`, `OM_DERIVE_FIELD`, `OM_FIELD_SETTER` | 242 | `old_field` | plain var / `TRACKED` | A2 |
| B11 | `DECLARE_VERB*` | 85 | `old_verb_decl` | native verb / `type_verbs()` / `hidden_verbs()` | A6 |
| B12 | `DECLARE_PERIODIC*`, `DECLARE_REPEAT`, `machine_step`, `om_task_periodic`, `MACHINE_WAKE/SLEEP` | 420 + 74 | `old_periodic` | cadence | A6 |
| B13 | `add_fingerprint()` in handlers | 625 | `manual_fingerprint` | delete | A13 |
| B14 | `om_after*` variants, `om_qdel_after`, `OWN_TIMER` | 1,505 + 109 + 47 + 52 | *(new: `timer_forms`)* | `after` / slot / cadence / `expire` | A9 |
| B15 | temporary-state vars and fields (`failure_until`, `emp_until`, `jammed`…) | n/a | *(review)* | timed grant | A9 |
| B16 | direct `qdel()` | ~3,270 | *(new: `direct_qdel` in converted folders)* | lifecycle verbs | A10 |
| B17 | typed `/datum/om/relation/*`, `om_link`, `REL*` + `rel_*` | ~120 + 35 + 276 + 2,208 | *(new)* | `relations()` [built; REL* migrated; om relations planned: `tools/dx/convert_relations.py --dry-run`] | A10 |
| B18 | 16 ownership macro spellings | ~635 | *(new)* | `ownership()` [built, migrated; lint `sys/dx_ownership_forms`] | A10 |
| B19 | new base-type vars; `= list()` instance vars | n/a | *(new: `base_vars`)* | capability / lazy list | A14 |
| B20 | `set category = "..."` literals; old-style admin/debug verbs | 656 + 28 | *(new: `verb_category`)* | `VERB_CAT_*`, `ADMIN_VERB`, `DEBUG_VERB` | A6 |
| B21 | `check_rights()`, raw `.holder`, `rights & R_` | 82 + 327 + 17 | `check_grep.sh` baseline | `admin_can` / `admin_require` / `TOPIC_RIGHTS` | B21 |
| B22 | `sleep`, `spawn`, `stoplag`, `UNTIL` outside the kernel; sync SQL | ~40 + tests | `scheduler` | `om_io` / `await` / slices | A9 |
| B23 | `SUBSYSTEM_DEF`, `/datum/world_service`, `GLOB.x_service`, `boot_after`, `order_after` | 29 + 44 | *(boundary lint)* | `/datum/system` [planned] | A12 |
| B24 | reads and writes of another system's fields | 1,657 | *(boundary lint B1)* | `api.dm` | A12 |
| B25 | DM copies of Rust state; DM gas maths | ~8 mirrors, 5 solvers | *(new: `rust_mirror`)* | read through / one bind | B25 |
| B26 | 5 Rust→DM delivery patterns | 5 | n/a | one adapter → `changed()` | B26 |
| B27 | `SStgui.update_uis()`, per-push `config` | 323 | *(new)* | `changed()` | B27 |
| B28 | `browse()`, literal skin ids, client state scattered | ~6 + ~15 files | *(new: `skin_ids`)* | tgui/`ask_*`, `SKIN_*`, `client.session` | B28 |

Each entry below gives the rule, a real before/after, and the traps.

## B1. Interactions → `capabilities()`

```dm
// BEFORE: laserpointer.dm:51-61
DECLARE_INTERACTIONS(/obj/item/laser_pointer, INTERACT_INSERT(/obj/item/stock_parts/micro_laser, PROC_REF(interaction_item), "Install"))
/obj/item/laser_pointer/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(!diode)
		user.drop_item()
		W.forceMove(src)
		own_set(src, "diode", W)
		to_chat(user, span_notice("You install a [diode.name] in [src]."))
	else
		to_chat(user, span_notice("[src] already has a diode."))
	return TRUE

// AFTER: a slot does install, eject, examine and refusal messages
/obj/item/laser_pointer/capabilities()
	. = ..()
	. += cap_slot(nameof(diode), /obj/item/stock_parts/micro_laser, eject_tool = TOOL_SCREWDRIVER)
```

```dm
// BEFORE: door_control.dm:36-48 (an interaction datum per action)
/datum/interaction/machine_hand/remote_toggle
	id = "remote_toggle"  name = "Toggle"  category = INTERACTION_CAT_TOGGLE
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/button/remote/proc/can_press))
	effect = /obj/machinery/button/remote/proc/interaction_toggle
// AFTER
/obj/machinery/button/remote/capabilities()
	. = ..()
	. += cap_hand("Toggle", PROC_REF(toggle), needs = PROC_REF(can_press), else_say = "The button is spent.")
```

**Traps:**
- Check the library first. A hand-written `cap_hand` that opens a cover is wrong: use `cap_cover`.
- Entry order is menu order.
- Handlers take `(mob/user, obj/item/held)` and return TRUE or `refuse(...)`.
- Don't move the item yourself: `cap_slot` and `own_set` do it.

## B2. Tool acts → `cap_tool` or the library

```dm
// BEFORE: laserpointer.dm:63-69
/obj/item/laser_pointer/screwdriver_act(mob/user, obj/item/tool)
	if(!diode)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You remove the [diode.name] from the [src]."))
	diode.forceMove(get_turf(loc))
	own_take(src, "diode")
	return ITEM_INTERACT_SUCCESS
// AFTER: covered by cap_slot(..., eject_tool = TOOL_SCREWDRIVER) in B1. Delete the proc.
```

```dm
// BEFORE: apc.dm:436-463 (15 lines of state checks around "open the cover")
/obj/machinery/power/apc/crowbar_act(mob/user, obj/item/tool)
	...
	if(coverlocked && !(stat & MAINT) && remaining_power > 15)
		to_chat(user, span_warning("The cover is locked and cannot be opened."))
		return ITEM_INTERACT_BLOCKING
	opened = 1
	update_icon()
// AFTER
	. += cap_cover(open_tool = TOOL_CROWBAR, needs = PROC_REF(cover_unlocked))    // or the maintenance_hatch bundle (in progress)
/obj/machinery/power/apc/proc/cover_unlocked(mob/user)
	if(!coverlocked || (stat & MAINT) || cell?.percent() <= 15)
		return TRUE
	return "The cover is locked and cannot be opened."
```

**Traps:**
- `cap_tool` entries work while broken or unpowered by default (tools act on the hardware); hand entries don't.
- A `delay` is a timed action; never `do_after`.

## B3. Emag → `cap_emag`

```dm
// BEFORE: apc.dm:700-715
/obj/machinery/power/apc/emag_act(remaining_charges, mob/user)
	if(!(emagged || hacker))
		if(opened)
			to_chat(user, "You must close the cover to do that.")
		else if(wiresexposed)
			to_chat(user, "You must close the wire panel first.")
		...
			if(do_after(user, 6, target = src))
				emagged = 1
				locked = 0
// AFTER
	. += cap_emag(say = "You short out the APC's interface.", effect = PROC_REF(on_emag), blocked_by = COVER|PANEL)
/obj/machinery/power/apc/proc/on_emag(mob/user)
	cap_set(src, CAP_LOCKED, FALSE)
	return TRUE            // FALSE refuses, and the emagged bit stays clear
```

**Traps:**
- Delete the `emagged` var and every `if(emagged)`; use `is_emagged(src)`.
- The effect runs **before** the bit is set, and can refuse.
- Repeatable emags use `mode = EMAG_REPEATABLE`.

## B4. Requirements → `needs`

```dm
// BEFORE: megaphone.dm:48-58
DECLARE_INTERACTIONS(/obj/item/megaphone, INTERACT_USE(null, PROC_REF(interaction_self)))
/obj/item/megaphone/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/text, PROC_REF(shout_entered), title = "Megaphone",
		message = "Shout a message?", ask_flags = ASK_CARRIED | ASK_CAPABLE)
// AFTER (cap_use_self, needs and ask_text are all [built])
/obj/item/megaphone/capabilities()
	. = ..()
	. += cap_use_self("Shout", PROC_REF(shout), needs = PROC_REF(can_broadcast))
/obj/item/megaphone/proc/shout(mob/user)
	var/t = ask_text(user, "Shout a message?")
	if(t)
		do_broadcast(user, capitalize(t))
```

| Old | New |
|---|---|
| `REQ_ON(proc)`, `REQ_TARGET_STATE(proc)` | `needs = PROC_REF(proc)` (the same proc body; TRUE or text) |
| `REQ_IN_INVENTORY`, `REQ_INTERACTION_REACH`, `REQ_REACH_ADJACENT` | delete: the dispatcher applies reach by entry kind |
| `REQ_CONSCIOUS`, `ASK_CONSCIOUS`, `PROMPT_CONSCIOUS` | `GLOBAL_PROC_REF(chk_conscious)` [built] (`chk_alive`/`chk_capable`/`chk_held`/`chk_carried`/`chk_adjacent`... for the other ASK_*/PROMPT_* flags) |
| tag, compare and body-type clauses | a small `needs` proc, or a slot `accepts =` |
| `ASK_*` flags on a prompt | [built] `ask_*` re-runs the entry's `needs` and takes `needs =`; delete `ask_flags` on converted prompts (the old om prompts keep theirs until removed) |

## B5. Appearance → `draw(look)`

```dm
// BEFORE: canister.dm:173-190
DECLARE_APPEARANCE_PROC(/obj/machinery/portable_atmospherics/canister, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/portable_atmospherics/canister/appearance_overlays()
	. = list()
	if(destroyed)
		icon_state = "[canister_color]-1"
		return .
	icon_state = "[canister_color]"
	var/flag = desired_update_flag()
	if(flag & 1)
		. += "can-open"
	if(flag & 2)
		. += "can-connector"
	if(flag & 4)
		. += "can-o0"
	if(flag & 8)
		. += "can-o1"
	else if(flag & 16)
		. += "can-o2"
	else if(flag & 32)
		. += "can-o3"

// AFTER: no flag word, no manual state bookkeeping
/obj/machinery/portable_atmospherics/canister/draw(datum/look/look)
	..()
	if(destroyed)
		return look.state("[canister_color]-1")
	look.state(canister_color)
	look.overlay("can-open", when = valve_open)
	look.overlay("can-connector", when = connected_port)
	look.gauge("can-o", level = pressure_band(), levels = 4)     // can-o0..can-o3
```

```dm
// BEFORE: door_control.dm:98 (a string template language)
APPEARANCE_TEMPLATE(/obj/machinery/button/remote, "doorctrl{appearance_powered?0:-p}")
// AFTER
/obj/machinery/button/remote/draw(datum/look/look)
	..()
	look.state(power_state == POWER_UNPOWERED ? "doorctrl-p" : "doorctrl0")   // power_state [planned], framework_fixes.md §9.3
```

**Traps:**
- Call `..()` first; the capabilities draw their layers.
- Never set `icon_state` directly in gameplay code.
- For the capability layers, use standard state names; run the rename tool for legacy ones.

**Power reads:** there is no `is_powered()`. The one read is the derived `power_state` (`POWER_BROKEN`/`POWER_UNPOWERED`/`POWER_OFF`/`POWER_IDLE`/`POWER_ACTIVE`) [planned, framework_fixes.md §9.3]; until it lands, `cap_powered(src)` [built].

## B6. Manual refresh → delete

Every `update_icon()` and `queue_icon_update()` call in a converted folder is deleted. If the write happened outside a dispatched call (a raw callback or FFI data), write `changed(src)` instead. The sweep fails in tests when a mark is missed, so a deletion that misses a case is caught.

## B7. UI → `tgui_data()` + `act_<x>()`

```dm
// BEFORE: round_status_panel.dm:28, :98-107
DECLARE_UI_STATE(/datum/round_status_panel, ADMIN_STATE(R_ADMIN))
UI_ACT(/datum/round_status_panel, "call_shuttle", ui_act_call_shuttle)
UI_ACT_PROC(/datum/round_status_panel, ui_act_call_shuttle)
	if(!check_rights(R_ADMIN|R_EVENT))
		return
	if(SSticker?.mode?.name == "blob")
		tgui_alert_async(ui.user, "You can't call the shuttle during blob!")
		return
	...
	SStgui.update_uis(src)
	return TRUE

// AFTER
/datum/round_status_panel/proc/act_call_shuttle(mob/user)
	var/why_not = shuttle_api_why_cant_call()
	if(why_not)
		return refuse(user, "You can't call the shuttle: [why_not].")
	shuttle_api_call_evac(caller = user)
	return TRUE
```

| Old | New |
|---|---|
| `UI_ARG_NUM(x, min, max)` | the `x` argument plus `x = ui_number(x, min, max)` in the body |
| `UI_ARG_TEXT`, `UI_ARG_CHOICE`, `UI_ARG_REF` | `ui_text`, `ui_choice`, `ui_ref` |
| `UI_DATA` / `UI_DATA_REPLACE` | `tgui_data(user)`, calling `..()` first |
| `tgui_static_data` | unchanged |
| `SStgui.update_uis(src)` | delete: the change pushes |
| `DECLARE_UI_STATE(..., ADMIN_STATE(R))` | the state stays until `ui_rights` [planned]; narrow per action with `admin_require(user, R)` |

**Traps:**
- The TSX `act("x", {...})` names and keys must match the `act_x` proc's argument names; the lint checks it.
- No template-literal action names.
- A capability may already own the action (`cap_power_channels`); don't duplicate it.

## B8. Prompts → `ask_*`

| Old | New |
|---|---|
| `om_ask(user, /datum/om/prompt/text, PROC_REF(done), ...)` + an answer proc | `var/t = ask_text(user, "...")` inline in the handler |
| `act_ask(..., "k231", ...)` keys, `rerun_ask` | the same `ask_*` inline (no keys) |
| `prompt_flow()` / `flow_execute()` re-runs | a linear handler (plus `await_sql` [planned] for SQL) |
| `tgui_input_text/number/list`, `tgui_alert`, native `input()`/`alert()` | `ask_text`, `ask_number`, `ask_list`, `ask_yes_no` |
| forms of several prompts in a row | `form = list(text_field(...), number_field(...), choice_field(...))` on the entry; `ask_form(...)` inside a handler [planned, §9.1] |

The re-run machinery (`om_ask`, `act_ask`/`rerun_ask`, `prompt_flow`/`flow_execute`, `/datum/om/flow`, `om_prompt_answer`/`test_prompts`) still exists in old code; framework_fixes.md §9.1 deletes all of it. Convert to the inline form, never add to it.

**Traps:**
- Code before `ask_*` runs once; there's no re-run.
- Check for null after every `ask_*`: null means cancelled **or** invalid, and the player was already told why.

## B9. Expiry → `COOLDOWN_*`, `timed_set` or a grant

```dm
// BEFORE: laserpointer.dm:16, 81, 206
	EXPIRY_DECLARE(last_used_time)
	...
	if(!(ELAPSED(src, last_used_time, CLOCK_WORLD) >= cooldown))
		return
	...
	EXPIRY_STAMP(src, last_used_time, CLOCK_WORLD)
// AFTER
	COOLDOWN_DECLARE(point_cooldown)
	...
	if(!COOLDOWN_FINISHED(src, point_cooldown))
		return
	...
	COOLDOWN_START(src, point_cooldown, cooldown)
```

| Old | Means | New |
|---|---|---|
| `EXPIRY_STAMP` + `ELAPSED(...) >= N` | rate limit | `COOLDOWN_START` / `COOLDOWN_FINISHED` |
| `EXPIRY_AT` + a check against it | "until time T" | `timed_set(src, nameof(flag), TRUE, for_time = N)` and read `flag` |
| `EXPIRY_ON_LAPSE(type, var, clock, proc)` | "do X when it ends" | `timed_set(..., revert_to = ...)` for a value, or a timed grant whose capability's removal does X |
| `LEFT_UNTIL` | countdown | `time_left(src, nameof(flag))` |

**Temporary state: one form per intent** (framework_fixes.md §9.3):

| The state is | Write | Not |
|---|---|---|
| behaviour for a while (EMP'd, jammed, failed) | a timed grant: `grant_for(GRANT_CAPABILITY, /datum/capability/condition/x, source, N)` (today `om_grant_for`) | a flag plus checks in every handler |
| a pure value for a while | `timed_set(src, nameof(var), value, for_time = N)` | a stored end time |
| a rate limit | `COOLDOWN_*` | `EXPIRY_*`, `world.time` stamps |
| a body number (slowdown, pain) | a body effect with a duration | a modifier timer, a stored end time |

## B10. Fields → a plain var or `TRACKED`

```dm
// BEFORE: laserpointer.dm:230
OM_FIELD(/obj/item/laser_pointer, recharging, 0, CHANGE_EXPLICIT)
// AFTER: nothing. `recharging` disappears entirely (B12 derives it from `energy < max_energy`).

// BEFORE: atmo_control.dm:714
OM_FIELD(/obj/machinery/computer/general_air_control/fuel_injection, automation, 0, CHANGE_MACHINE_SETTINGS)
// AFTER: a plain var; written only in act_ handlers (dispatched, so auto-marked)
/obj/machinery/computer/general_air_control/fuel_injection
	var/automation = FALSE
// Only if something outside a dispatched call writes it:
TRACKED(/obj/machinery/computer/general_air_control/fuel_injection, automation, CHANGE_MACHINE_SETTINGS)
```

**Trap:** `OM_DERIVE_FIELD`'s `inputs = list(...)` goes away. A derived value is a proc, and the refresh re-reads it.

## B11. Verb declarations → native, `type_verbs()` or `hidden_verbs()`

```dm
// BEFORE: health.dm:154-157
DECLARE_VERB(/obj/item/healthanalyzer/improved, /obj/item/healthanalyzer/proc/toggle_adv)
DECLARE_VERB(/obj/item/healthanalyzer/advanced, /obj/item/healthanalyzer/proc/toggle_adv)
DECLARE_VERB(/obj/item/healthanalyzer/phasic, /obj/item/healthanalyzer/proc/toggle_adv)
DECLARE_VERB(/obj/item/healthanalyzer/scroll, /obj/item/healthanalyzer/proc/toggle_adv)
// AFTER (the pattern on the framework branch)
/obj/item/healthanalyzer
	var/has_advanced_mode = FALSE
/obj/item/healthanalyzer/type_verbs()
	. = ..()
	if(has_advanced_mode)
		. += /obj/item/healthanalyzer/proc/toggle_adv
/obj/item/healthanalyzer/improved
	has_advanced_mode = TRUE
```

| Old | New |
|---|---|
| `DECLARE_VERB(type, verb)` | a native `/verb/`, or `type_verbs()` for a per-subtype set |
| `DECLARE_VERB_IF(type, verb, "varname")` | `hidden_verbs()` returning the verb while the var is false |
| `DECLARE_VERB_HIDE` | `hidden_verbs()` |
| a trait or species granting verbs in `apply()` | `/datum/trait/proc/granted_verbs()` [built] (see `xenomorph_hunter`); species-level grants still use `om_grant` in `apply()` |

## B12. Periodic → a cadence

```dm
// BEFORE: atmo_control.dm:714-745
OM_FIELD(/obj/machinery/computer/general_air_control/fuel_injection, automation, 0, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE(/obj/machinery/computer/general_air_control/fuel_injection, MACHINE_PIPELINE, "automation")
/obj/machinery/computer/general_air_control/fuel_injection/machine_step()
	if(!radio_connection())
		return PROCESS_KILL
	if(automation)
		...
// AFTER
/obj/machinery/computer/general_air_control/fuel_injection
	var/automation = FALSE
	periodic_cadence = CADENCE_SLOW
/obj/machinery/computer/general_air_control/fuel_injection/should_run()
	return automation && radio_connection()
/obj/machinery/computer/general_air_control/fuel_injection/periodic_step(dt)
	...                                    // the old body, minus the guard
```

| Old | New |
|---|---|
| `DECLARE_PERIODIC_WHILE(T, PIPELINE, "var")` | `periodic_cadence` + `should_run()` returning the condition |
| `DECLARE_REPEAT(T, delay, proc, field)` | `periodic_interval = delay` + `should_run()` + `periodic_step(dt)` |
| `machine_step()` | `periodic_step(dt)` |
| `MACHINE_WAKE(src)` / `MACHINE_SLEEP(src)` / `step_active` | delete: a changed var re-evaluates `should_run()` |
| `om_task_periodic(E, PERIODIC_X)` | `periodic_cadence = CADENCE_X` |
| a timer that re-arms itself | a cadence (the `kernel_timer_loop` lint) |

**Traps:**
- Scale by `dt`.
- A step that has finished returns `PROCESS_KILL`, or lets `should_run()` go FALSE.
- Mob Life stages are a different form: see B30.

## B13. Fingerprints → delete

`add_fingerprint(user)` inside a capability handler, an `act_` action or a prompt handler is deleted, because the dispatcher does it. Keep it only in code that isn't dispatched (rare; a comment says why).


## B14. Timers: one form per intent

| Old | Count | New |
|---|---|---|
| `om_after(E, d, PROC_REF(x), ...)` | 1,505 | `after(E, d, PROC_REF(x), ...)`: owned by E; a deleted datum argument arrives as null and the call runs (SStimer's semantics, so null-check your args); `after_if_alive()` to drop it instead |
| `om_after_unique` / `om_after_replace` | 19 / 20 | `after_slot(E, "name", d, PROC_REF(x))`: a slot is unique, and re-arming replaces |
| a proc that re-arms its own timer, `om_after_stagger`, `om_after_drift` | 4 + 7 + loops | a cadence (B12) |
| `OWN_TIMER(type, name)` | 52 | `after_slot` (a slot is already owned and cancelled on destroy) |
| `om_qdel_after(E, d)` | 47 | `expire(d)` on E |
| `om_deadline` | 31 | internal to the scheduler; never call it in gameplay code |
| `world_next_tick` | 2 | keep (world-level only) |
| `om_task_periodic` | 74 | a cadence (B12) |
| `om_task_slices` | 11 | a system `periodic_step` returning `STEP_YIELD` [planned]; keep until the kernel lands |

```dm
// BEFORE: laserpointer.dm:209, 214-215 (set a state, then a timer to put it back)
	icon_state = "[initial(icon_state)]_[pointer_icon_state]"
	...
	om_after(src, cooldown, PROC_REF(reset_laser_icon))
/obj/item/laser_pointer/proc/reset_laser_icon()
	icon_state = initial(icon_state)
// AFTER: a timed var the look reads; no reset proc
	timed_set(src, nameof(pointing), TRUE, for_time = cooldown)
/obj/item/laser_pointer/draw(datum/look/look)
	..()
	if(pointing)
		look.state("pointer_[pointer_icon_state]")
```

```dm
// BEFORE: geiger.dm:131 (a replace-timer used as "reset if nothing for N")
	om_after_replace(src, TIME_WITHOUT_RADIATION_BEFORE_RESET, PROC_REF(reset_perceived_danger))
// AFTER: a timed value that reverts by itself
	timed_set(src, nameof(perceived_danger), new_danger, for_time = TIME_WITHOUT_RADIATION_BEFORE_RESET, revert_to = RAD_LEVEL_NONE)
```

See the temporary-state table in B9 before choosing between a timer, `timed_set` and a grant.

## B15. Temporary state → a timed grant [built]

Any var or field that exists only to hold a temporary condition with behaviour becomes a capability held for a time by a source. Examples: `failure_until`, `emp_until`, `jammed_until`, `shocked_until`, `overloaded`, `on_fire_until`.

```dm
// BEFORE (the APC today): a field, a check in every handler, a draw branch, a UI key
	var/failure_until
	...
	if(failure_until > world.time) ...          // repeated wherever it matters
// AFTER
/obj/machinery/power/apc/proc/energy_fail(duration, datum/source)
	om_grant_for(src, GRANT_CAPABILITY, /datum/capability/condition/power_failure, source, duration)
/datum/capability/condition/power_failure
	blocks = ALL_ENTRIES
	else_say = "it isn't responding"
/datum/capability/condition/power_failure/draw(atom/holder, datum/look/look)
	look.state("emagged")
```

- **Keep:** `timed_set` for pure value reverts that have no behaviour.
- **Mobs:** keep afflictions and modifiers for body effects (they already follow this model).
- **Built:** `GRANT_CAPABILITY` (`code/datums/capabilities/condition.dm`) is a per-key effect: `om_grant_for(A, GRANT_CAPABILITY, path, source, duration)`, `om_grant(...)` and `om_revoke(...)`. The capability is one shared instance per path (`cap_condition_instance(path)`), attached with `add_capability()` while any source holds it and removed with the last hold (timed expiry or a deleted source). `/datum/capability/condition` has `blocks` (`ALL_ENTRIES`, or a list of capability types whose entries it refuses), `exempt` (capability types that still work), `else_say` (plain text, "it isn't responding"; override `refusal(holder)` to use the holder's name), `hides_verbs` and `draw()` (overlay `layer_name`).

The full decision table (grant, `timed_set`, `COOLDOWN_*`, body effect) is in B9.

## B16. `qdel()` → lifecycle verbs

| Situation | New | Count so far |
|---|---|---|
| an item used up by an action (`drop_from_inventory(x); qdel(x)`) | `consume(x, user)` | 489 converted |
| `new /x(loc); qdel(src)` (turn into / deconstruct into) | `replace_with(/x, ...)` | 148 |
| effects, projectiles, temporary helpers deleted after a time | `expire(N)` or `lifetime = N` | 96 |
| looping over an owned list with `qdel` | `slot_clear()` / `ledger_empty(policy)` | 29 |
| `qdel(owned_var)` in `on_destroy` | **delete the line**: the destroy sequence disposes of it by policy (`decl_lint: destroy_qdel_owned`) | n/a |
| replacing an owned value (`qdel(x); x = new`) | `own_set(src, nameof(x), new ...)`, which disposes of the old one by policy | n/a |
| a genuine "destroy this now" (admin delete, gibbed remains) | keep `qdel()` | n/a |

About 3,270 direct calls remain: 725 `qdel(src)` and about 2,500 `qdel(local)`. Classify each call before converting it, and never convert a `qdel(src)` inside the object's own teardown.

## B17. Relations → `relations()` [built; typed relations planned]

```dm
// BEFORE: throw_of in three storages (thrownthing.dm:10-19, :73; atoms_movable.dm:572)
/datum/om/relation/throw_of
	source_single = TRUE
	target_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER
/datum/om/relation/throw_of/on_unlink(datum/thrownthing/source, atom/movable/target, datum/om/edge/edge)
	om_unhook(target, /datum/om/event/before/living_turf_collision, source)
	if(target.throwing == source)
		rel_clear(target, "throwing")
... om_link(src, thrownthing, /datum/om/relation/throw_of)
... rel_set(src, "throwing", TT)
// AFTER
/atom/movable/relations()
	. = ..()
	. += rel_one(nameof(throwing), back = nameof(/datum/thrownthing::subject), other_deleted = DELETE_ME, on_unlink = PROC_REF(throw_ended))
... rel_link(src, nameof(throwing), TT)
```

`relations()` and the REL* migration are built (doc/rewrite/ownership.md §4.1); the typed
`/datum/om/relation` types are not converted yet (`python tools/dx/convert_relations.py --dry-run`
lists each with its proposed entry and what blocks it). Meanwhile:
- Declare links in `relations()` and write them with `rel_link(src, nameof(x), y)` (always `nameof()`, never a string), **one side only**.
- Don't add new `/datum/om/relation` types.
- Never store the same link twice (a relation plus a plain var copy, like the borer's `host =`).

## B18. Ownership declarations → one form [built]

The 16 declaration macros (`OWN` 211, `REL_LIST` 91, `REL_PAIR` 77, `REL` 48, `REL_PAIR_LIST` 34, `PROTO` 27, …) are gone. Declare in `ownership()` (`owns(nameof(var), policy = ...)`, `shares(nameof(var))`, `proto(nameof(var))`) and `relations()` (`rel_one`, `rel_many`, `rel_key`); see doc/rewrite/ownership.md §1.2. `sys/dx_ownership_forms` bans the old macros, the interim `declare_ownership(decl)`, and string var names in accessors. (`OWN_TIMER` and `DECLARE_SHARED_CACHE` are separate and stay.)

## B19. Base-type vars and per-instance lists

- **Don't add feature vars to base types:** make them a capability's state bit or `cap_data`.
- **`var/list/x = list()` on an instance:** use `var/list/x` and the `LAZY*` macros. `/mob` alone allocates 11 lists per instance this way, and `/human` 4 more.
- **Converting a feature:** delete its base var (`emagged`, `panel_open`, `locked`, `wiresexposed`, `welded`, `circuit`, the `wires` var…) and run the map converter [built] for its map varedits.

## B20. Verb categories and admin/debug verbs [planned: defines]

| Old | New |
|---|---|
| `set category = "Abilities.Vore"` (656 literals, 115 values) | `set category = VERB_CAT_ABILITIES_VORE` (about 45 defines, function-based) |
| `/client/verb/x()` + `if(!check_rights(R_DEBUG)) return` | `DEBUG_VERB(x, R_DEBUG, "Name", "Desc", VERB_CAT_DEBUG_x)`, compiled out of release |
| `/client/proc/x()` + `set category = "Admin"` + an in-body rights check | `ADMIN_VERB(x, R_X, "Name", "Desc", ADMIN_CATEGORY_X)`; use the `client/user` arg, never `usr` |
| a legacy admin proc that nothing grants | delete it |

The four leaked production debug verbs and the duplicate `reload_configuration` are being fixed on `fix/tickets-debugverbs`.

## B21. Admin rights [built on `rewrite/admin-rights`]

| Old | New |
|---|---|
| `check_rights(R_X)` (reads `usr`) | `admin_require(user, R_X, entry)`, which refuses **and** writes the denial audit line; or `admin_can(client, R_X)` for a boolean |
| a re-check inside a proc only reachable from an `ADMIN_VERB` with the same rights | delete |
| a Topic action with an in-body check | `TOPIC_RIGHTS(R_X)` on the action |
| raw `.holder`, `rights & R_X` outside `modules/admin/holder*` | `admin_can()` (baselined, shrink-only) |

## B22. Sleeping and blocking → callbacks, `await` or slices

| Old | New |
|---|---|
| `SSdbcore.run_query_sync()`, `UNTIL(query.process())` | `om_io(src, /datum/om/io/sql, sql, args, PROC_REF(on_rows), context...)` [built], or `await_sql()` in a handler [planned] |
| `UNTIL(rustg_iconforge_check(job) != ...)` | an `om_io` job kind for rust-g jobs [planned] |
| `spawn()` around slow work (for example `simple_mob.dm:760` around `animal_nom`) | a timed action or `after()` |
| `spawn(N)` in admin verbs | `after(src, N, PROC_REF(x))` |
| `stoplag()`/`CHECK_TICK` loops over big work (map chunks, atom batches) | leave them until the kernel's `STEP_YIELD` slices exist [planned] |
| `UNTIL(!busy)` in gameplay (`reflectors.dm:64,308`) | delete; the `periodic_step` path already handles it |
| `sleep()` in unit tests | the harness helper `wait_ticks(n)` / `run_until(PROC_REF(cond), timeout)` [planned] |

## B23. Subsystems and world services → systems [planned]

**Don't convert these before the kernel's step 2 lands.** In the meantime:
1. **New cross-folder callers** go through that folder's `api.dm` procs. Create the proc if it's missing; never add a new `SSx.field` or `GLOB.x_service.field` read from outside.
2. **No new `boot_after`/`order_after`, `init_order` numbers or `.initialized` checks.** Name the dependency in a comment for the DAG conversion.
3. **No new `SUBSYSTEM_DEF` or `/datum/world_service`.**

After the kernel: `SUBSYSTEM_DEF(x)` becomes `/datum/system/x`, `Initialize()` becomes `initialize()`, `fire()` becomes `periodic_step(dt)`, the flags become `latency_class` and `lane`, `GLOB.x_service` becomes `system(/datum/system/x)` or the `api.dm` procs, and `boot_after` becomes `needs`. See the systems design page §3 for eight worked conversions.

## B24. Cross-system field access → `api.dm`

```dm
// BEFORE: expedition_controller.dm:249 (expedition writes flight's private index)
	GLOB.flight_service.destination_by_target[REF(site.overmap_sector())] = destination.id
// AFTER: expedition announces; flight owns its index (systems design §3.6)
	release_or_move_site(site, new_name = descriptor_name)     // emits site_moved
/datum/system/flight/proc/retarget_expedition(datum/expedition_site/site, old_destination_id)
	...
	destination_by_target[REF(site.overmap_sector())] = D.id
```

- **Reads:** a query proc in the owner's `api.dm`.
- **Writes:** a command proc in the owner's `api.dm`, or an event the owner handles.
- **Baseline:** 1,657 accesses (242 writes), shrink-only.

## B25. Rust: no DM copies, no DM re-implementations [built on `rewrite/f-rust`]

**Mirrors deleted or reduced:**

| DM copy | New |
|---|---|
| `pipe_network.volume`, `pipeline.volume`, `pipe_network.gases`, `sync_gases()` | deleted; `volume()` reads `air.return_volume()` [built, rust-integration] |
| `turf.temperature` | `initial_temperature`, a **seed** read once when the heat cell and the air are built. The live temperature is `get_temperature()`; `set_temperature()`/`add_heat()` write it. `check_grep.sh` rejects a turf `.temperature` [built] |
| grid `PGRID_VIEWAVAIL` / `PGRID_VIEWLOAD` (the eased view values) | deleted; `power_view_avail()` / `power_view_load()` return the raw ledger value and the monitor UI eases what it shows on the client [built; the TSX easing is not written, see below] |
| DM inputs to Rust components (`SSvg` drift sweep) | the sweep is gone from production: `SSvg` is `SS_NO_FIRE`, `reconcile_all()` and `vg_reconcile_all()` exist only in test builds (the sandbox teardown and the binding fuzz test) [built] |
| hand pushes after a generated setter | a generated setter (`set_<field>()` of a Rust config field) ends with `rust_pushed()`. A type overrides it to re-publish state Rust does not own; nobody pushes by hand after a setter. Built for the pump (`pump.dm`) [built] |
| SMES `charge`, `input_available`, `output_used` | unchanged [planned] |
| APC `sync_cell_charge()`, the radiation shielding flush, `power_sync()`, the other four devices' `update_rust_device()` | these push **DM-owned vars** (not Rust config fields), so the generated-setter hook cannot reach them. They become `TRACKED` + `rust_push` once W1's reactions land [planned] |

**Gas moves are Rust.** `pump_gas()`, `pump_gas_passive()`, `queue_pump_gas()` and `scrub_gas()` are thin wrappers: they apply the machine's material hooks (`material_pump_efficiency()`, `material_pump_power()`, `record_material_pumping()`) and feed the flow meter, and `vg_pump()` / `vg_scrub()` do the maths **and** the move in one call (`verdigris/domains/gas/src/power_budget.rs`). `calculate_transfer_moles()` is one Rust solve (`vg_moles_to_pressure`). Deleted: `filter_gas()`, `filter_gas_multi()`, `mix_gas()`, `calculate_specific_power()` (now `vg_specific_power()`), `calculate_specific_power_gas()`, `calculate_equalize_moles()`. The trinary filter, omni filter and both mixers already call `vg_filter_transfer*` and `vg_mix_transfer`.

`mingle_with_turf()` is `pipeline.leak_into()`, one `vg_batch_mingle_hook` call. `temperature_interact()` is `pipeline.exchange_heat_with_turf()`, whose every branch (open turf, wall, special-temperature surface, unsimulated turf) is `vg_thermal_exchange()`, the one Rust formula. A pipe as a heat body coupled to the turf (the heat domain's `GasCoupling`) is the eventual form; it needs a body whose capacity follows its gas.

**Rate models.** There is one DM API: `om_rate_*`. The `dq_rx_rate_*` wrappers are deleted (rules call `om_rate_*`). There is one Rust implementation, `vg_core::rate::RateModel`.

## B26. Rust → DM changes: one door, the frame outbox [built on `rewrite/f-rust`]

One call per tick, `vg_frame(elapsed, budget)`, steps the Rust world (laws, heat, gas, power), ticks the hosts, steps the pipe devices on their own period and the scheduler (timers, rate crossings, keys, every watch port), and returns **one outbox page**:

| record | meaning | goes to |
|---|---|---|
| `NATIVE_REC_CHANGED (entity, key)` | a value changed (gas observation, a change watch) | `native_publish_change()`, the machine service's gas queue, or a world watch's lane |
| `NATIVE_REC_NOTICE (entity, kind, args)` | a typed event, or a pipe device's step | the generated `on_<component>_<event>()`, `native_publish_notice()`, `device.rust_device_stepped()` |
| `NATIVE_REC_CROSSED (watch, band, detail)` | a watch crossed a band (heat threshold, band, set entry; world watches; timers, rates, keys) | `native_crossed()` |

`/datum/system/native` (`code/datums/native/system.dm`) delivers them; the OM scheduler calls its `frame()` once per tick (`world_step()`). `native_read(E, key)` reads a Rust-owned value through a per-frame cache that a CHANGED record for the entity clears. The three `native_*` procs are the seam to the reaction framework: today they raise OM channels/events and call the watch's own callback; at integration they call `publish_change`, `PUBLISH` and `on_cross`.

The old drivers and drains are gone from DM: `vg_world_tick`, `vg_world_events`, `vg_world_step`, `vg_entity_tick_all`, `vg_heat_tick`, `vg_heat_take_wakes`, `vg_pipe_step_devices`, `vg_drain_dirty_gas_observations`, `vg_drain_events` (now `vg_dispatch_notice`, called by the native system per NOTICE). Heat watches are ordinary watch ports: a body uses its world kind (`VG_KIND_HEATBODY`), the turf solid `VG_HEAT_CELLS`, both through the generic `vg_world_watch_*` binds (and `vg_world_watch_set*` for the heat ledger's threshold sets); the bespoke `vg_heat_watch*` binds are deleted.

Tests that step Rust by hand call `vg_world_run_steps(n)` and then `native_system().drain()` (delivers what Rust holds without pacing); `SSair.rust_step_pipe_devices()` is the test hook that forces a device period.

## B27. TGUI pushes and payloads

| Old | New |
|---|---|
| `SStgui.update_uis(src)` (323 sites) | delete; `changed()` pushes, coalesced to 0.2 s [planned] |
| a full `config` block on every push | `config` only on open, ready and full update [planned] |
| unused generated `.d.ts` files | generated types imported via `useBackend<T>` [planned] |
| per-push rebuilds of static-ish data (lathe designs, `_production.dm:217-259`) | `tgui_static_data` cached per type and state; rebuild on change |

## B28. Windows, skin and the client

| Old | New |
|---|---|
| `browse()` / `/datum/browser` (about 6 left) | a tgui window |
| literal skin ids in `winset(C, "mainwindow.x", ...)` | `SKIN_*` defines [planned], checked against `skin.dmf`; winset/winget through `dx_exec` |
| state on `/client`, `/datum/preferences` or `/mob` that belongs to the connection | `client.session` [planned] |
| rebuilding the HUD and plane masters on every mob Login; `client.screen = list()` | screen groups built once per client [planned] |

## B29. Domain notes

| Domain | Special rule | Plan section |
|---|---|---|
| Materials | properties through `properties.dm`; item effects through `material_effects()` [planned] | §2.1 (steps 1–3 done on `rewrite/materials`) |
| Reagents | nothing under `holder/` names belly, virus or vore; tags next to their reagent | §2.2 (steps 1–3 done on `rewrite/reagents`) |
| Species | no new vars on `/datum/species`; rendering, speech and movement become `species_capabilities()` [planned] | §2.3 |
| Mob AI | behaviours stay flyweight `/datum/ai_behavior`; declaration moves to `cap_ai_behaviors()` [planned]; no new `ports/` files | §2.4 |
| Vore | outside callers use `vore/api.dm` [planned]; no new outside `/obj/belly` references | §2.5 |

## B30. Mob Life stages [planned: framework_fixes.md §9.5 Life]

The target model: one `/datum/system/life` with an ordered stage plan. Each stage declares what it reads in `derived()`, runs while `should_run(mob)` holds, and steps with `step(mob, dt)` returning `STEP_*`.

| Old | New |
|---|---|
| `idle(self)` | `should_run(mob)` (positive: the old `idle()` inverted) |
| `perform()` | `step(mob, dt)`, returning `STEP_DONE`/`STEP_YIELD`/`STEP_PARK`/`STEP_AGAIN_IN(t)` |
| `wake_on` mask, `rewake_delay()`, `life_wake()` bits | reads declared in `derived()`: `runs_while(nameof(/mob/living::losebreath), ...)`; the stage wakes when a read changes |
| a var a stage reads, written directly | `TRACKED`, written only through its setter (`losebreath`, `internal`, ...) |

Gating booleans become capabilities and numbers become factors, read through `factor_dep(BF_X)`. Until this lands, don't convert Life stages; don't override `Life()` and don't add `handle_*` procs.

---

# Part C: running a conversion

## C1. Scope

- **Convert one whole folder at a time.** A folder is either converted (no old forms at all) or untouched. Add it to `tools/ci/converted_folders.txt` [planned] when it's done.
- **Stop and report if you need a [planned] API.** Don't invent it, and don't leave a half-converted file.
- **Work on your own branch and worktree off the current framework branch.** Set `DQ_PREBUILT_VERDIGRIS=1` and copy the matching `verdigris.dll`.

## C2. Order inside a file

1. **Delete** what the framework now does: `update_icon()` calls, `add_fingerprint`, `SStgui.update_uis`, `MACHINE_WAKE`.
2. **Capabilities:** interactions, tool acts, emag, slots, locks, covers → `capabilities()` from the library first, bespoke entries last.
3. **Look:** appearance declarations → `draw(look)`.
4. **UI:** `UI_ACT` → `act_<x>` with validators; `UI_DATA` → `tgui_data`.
5. **Prompts:** → `ask_*`.
6. **Time:** expiry, timers, periodic → B9, B12, B14 and B15. **Check the A9 table for every timer.**
7. **Lifetime:** `qdel` → B16.
8. **Vars:** delete the base vars the capabilities replaced, and run the map converter for their varedits.

## C3. Verify

- Compile with 0 errors.
- `tools/build/build.sh lint`: DreamChecker 0, and the `dx_old_forms` counts for your folder at 0.
- Focused tests for every type you touched: `bash tools/dq_focused_test.sh ...`. Add a test for each capability entry you wrote: that it works, that it refuses when it should, and that the look and UI change.
- The refresh sweep in test builds fails on a missed change mark. **Don't silence it; find the write.**

## C4. Report

List the files converted, the old-form counts before and after, the [planned] APIs you needed (a blocker list), and anything in this guide that didn't match the real code. **Fix the guide in the same commit if it was wrong.**

---

# Appendix: a complete worked conversion (the laser pointer)

**Before:** `code/game/objects/items/devices/laserpointer.dm`, 260 lines. The pieces that change:

```dm
/obj/item/laser_pointer
	...
	var/cooldown = 10
	EXPIRY_DECLARE(last_used_time)
	var/recharge_locked = 0
	var/obj/item/stock_parts/micro_laser/diode

DECLARE_INTERACTIONS(/obj/item/laser_pointer, INTERACT_INSERT(/obj/item/stock_parts/micro_laser, PROC_REF(interaction_item), "Install"))
/obj/item/laser_pointer/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	... 10 lines: move the diode in by hand, own_set, messages ...
/obj/item/laser_pointer/screwdriver_act(mob/user, obj/item/tool)
	... 6 lines: move the diode out by hand, own_take, message ...
/obj/item/laser_pointer/proc/laser_act(atom/target, mob/living/user)
	...
	if(!(ELAPSED(src, last_used_time, CLOCK_WORLD) >= cooldown))
		return
	...
	add_fingerprint(user)
	...
	icon_state = "[initial(icon_state)]_[pointer_icon_state]"
	...
	EXPIRY_STAMP(src, last_used_time, CLOCK_WORLD)
	energy -= 1
	if(energy <= max_energy)
		set_recharging(TRUE)
		if(energy <= 0)
			to_chat(user, span_warning("You've overused the battery of [src], now it needs time to recharge!"))
			recharge_locked = TRUE
	flick_overlay(I, showto, cooldown)
	om_after(src, cooldown, PROC_REF(reset_laser_icon))
/obj/item/laser_pointer/proc/reset_laser_icon()
	icon_state = initial(icon_state)
/obj/item/laser_pointer/periodic_step()
	if(prob(20 - recharge_locked*5))
		energy++
		if(energy >= max_energy)
			energy = max_energy
			set_recharging(FALSE)
			recharge_locked = FALSE
/obj/item/laser_pointer/ownership()
	. = ..()
	. += owns(nameof(diode), policy = OWN_CONTAINED)
OM_FIELD(/obj/item/laser_pointer, recharging, 0, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/laser_pointer, PERIODIC_SLOW, "recharging")
```

**After:**

```dm
/obj/item/laser_pointer
	...
	var/cooldown = 1 SECOND
	var/recharge_locked = FALSE
	var/pointing = FALSE                                   // timed; read by draw()
	var/obj/item/stock_parts/micro_laser/diode
	periodic_cadence = CADENCE_SLOW
	COOLDOWN_DECLARE(point_cooldown)

/obj/item/laser_pointer/ownership()
	. = ..()
	. += owns(nameof(diode), policy = OWN_CONTAINED)
TRACKED(/obj/item/laser_pointer, energy, CHANGE_ITEM_CHARGE)   // laser_act() and the step write it through set_energy()
TRACKED(/obj/item/laser_pointer, pointing, CHANGE_EFFECTS)

/obj/item/laser_pointer/capabilities()
	. = ..()
	. += cap_slot(nameof(diode), /obj/item/stock_parts/micro_laser, eject_tool = TOOL_SCREWDRIVER)
	. += cap_use_at("Point", PROC_REF(laser_act), range = world.view)   // [built]; delete afterattack

/obj/item/laser_pointer/proc/laser_act(mob/user, atom/target)   // cap_use_at handler: (user, target)
	if(!COOLDOWN_FINISHED(src, point_cooldown))
		return
	...                                                     // the effect code is unchanged
	COOLDOWN_START(src, point_cooldown, cooldown)
	set_energy(energy - 1)
	if(energy <= 0)
		to_chat(user, span_warning("You've overused the battery of [src], now it needs time to recharge!"))
		recharge_locked = TRUE
	flick_overlay(I, showto, cooldown)
	timed_set(src, nameof(pointing), TRUE, for_time = cooldown)

/obj/item/laser_pointer/draw(datum/look/look)
	..()
	if(pointing)
		look.state("pointer_[pointer_icon_state]")

/obj/item/laser_pointer/derived()
	. = ..()
	. += runs_while(nameof(energy), nameof(max_energy))    // energy dropping in laser_act() wakes the recharge
	. += drawn_from(nameof(pointing))

/obj/item/laser_pointer/should_run()                       // recharges only while not full
	return energy < max_energy

/obj/item/laser_pointer/periodic_step(dt)
	if(prob(20 - recharge_locked * 5))
		set_energy(min(energy + 1, max_energy))
		if(energy == max_energy)
			recharge_locked = FALSE
```

**What went away:**
- the interaction datum and the install handler (the slot does it);
- `screwdriver_act` (the slot's eject tool);
- the expiry pair (a cooldown);
- `add_fingerprint` (the dispatcher);
- direct `icon_state` writes and the reset timer (a timed var plus `draw`);
- `set_recharging`, `OM_FIELD(recharging)` and `DECLARE_PERIODIC_WHILE` (`should_run()` derives it from `energy`).

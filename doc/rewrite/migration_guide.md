# DeepQuarry migration guide

This is the single document an agent needs to convert code to the new framework. It contains:
- **Part F:** the foundation design's old-to-new table (read first).
- **Part A:** the framework as designed, with the exact API.
- **Part B:** the catalogue of every old form, each with its new form, a real before/after, and the traps.
- **Part C:** how to run a conversion and what to report.

Nothing else is required reading. `doc/rewrite/dx_conventions.md` and the design pages are background. `doc/rewrite/archive/framework_fixes.md` (§9) was binding for the DX framework; its decisions are folded into this guide. Where the foundation design ([foundation.md](foundation.md)) differs from Part A or B, **Part F wins**; Parts A and B describe the API as built and stay correct until the `rewrite/f-*` branches merge and a folder is converted.

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

# Part F: foundation forms (read first)

The foundation design ([foundation.md](foundation.md)) replaces several Part A and Part B forms.
Everything on the right is **[in progress]** on the branch shown; the left column is **[built]**
and remains valid (and is how existing code is written) until that branch merges. Do not convert
call sites to a right-hand form before its branch has merged; the F batch adds the new forms beside
the old ones and does not migrate callers.

## F1. Old form to new form

| Old form [built] | New form | Branch | Chapter |
|---|---|---|---|
| `om_after(E, delay, proc, args...)`, `after_slot(E, "name", ...)`, `rx_after(...)`, `OWN_TIMER` | `after(owner, delay, handler, key =, clock =, with = list(args...))` (no varargs); `after_pending` / `cancel_after` / `after_left`; `OWN_TIMER` is deleted (timers are TIMER relations). The old procs are wrappers **[built on master, A1]** | a1 | [reactions.md](reactions.md) �4 |
| `om_hook(source, event, listener, proc)` / `om_hooked()` | `observe(source, on_notice(/datum/notice/x), listener, handler)` / `unobserve()` (dynamic), or `on_notice` in `reactions()` (static); a `before/*` veto becomes `before_op(GUARD_X, h)` + `guard(E, GUARD_X, ...)`. Per-event targets: F5 **[built on master, A1]** | a1 | [reactions.md](reactions.md) �3, �3a |
| `DAMAGE_REACTION(type, kind, proc)` / `DAMAGE_REACTION_AFTER`, `REFLECTS`, `EMP_DISABLE` | `before_op(damage(kind), h)` (may block) / `after_op(damage(kind), h)` in `reactions()`; `CAPABILITY(T, reflects(kinds, chance))`, `CAPABILITY(T, emp_disable(duration))`. The macros are thin wrappers **[built on master, A1]** | a1 | [reactions.md](reactions.md) �1b |
| `derived()` with `runs_while`, `drawn_from`, `ui_from`, `derive`, `rust_push` | `reactions()`: the same sugar over `on_change`, plus generated reads. Old `derived()` entries are folded in | f-reactions | [reactions.md](reactions.md) |
| `ownership()` / `OWN(type, var, policy)` | `relations()` with `rel_one`/`rel_many` and `kind = OWNED` | f-reactions | [state_and_relations.md](state_and_relations.md) |
| `relations()` with `rel_one`/`rel_many` untyped | the same table with `kind = REF \| PAIRED \| OWNED` | f-reactions | [state_and_relations.md](state_and_relations.md) |
| `TRACKED(type, var, channel)`, `changed(E, channel, var)`, `OM_FIELD` | `TRACKED(type, var)` (publishes only when read); `TRACKED_BRIDGED(type, var, CHANNEL)` only while an OM stage `wake_on` or `om_watch()` reads the channel (removed with S4); `PUBLISH_CHANGE(E, key)` for a fact that is not one var. `OM_FIELD` setters publish their var key too **[built on master, A1]** | a1 | [state_and_relations.md](state_and_relations.md) �1 |
| Event/`om_emit` occurrences, `signal`-style notifications | `PUBLISH(src, /datum/notice/x, ...)` and `on_notice`; the notice types are generated (`code/_generated/om_notices.dm`) with the mapping table `tools/dx/codemods/om_event_map.json` | a1 | [reactions.md](reactions.md) �3 |
| `on_channel(bits, h)` (S2 bridge) | `on_change(list(keys...), h, at_most =, when =)`; producers publish `MOB_KEY_*` (deleted with the channel bridge) | a1 | [reactions.md](reactions.md) |
| `om_grant(T, GRANT_VERB / GRANT_VERB_HIDE / GRANT_CAPABILITY, id, src)`, `om_revoke` | `grant(T, verb_path \| hidden_verb(path) \| capability_type, source, duration)` / `revoke()`; `om_attach(E, behaviour)` -> capabilities, `reactions()` or relations (F5) | a1 | [state_and_relations.md](state_and_relations.md) |
| `shares(nameof(v))`, `proto(nameof(v))` | no declaration: type the var (registry or flyweight type); `rel_one(nameof(v), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)` | a1 | [state_and_relations.md](state_and_relations.md) �2 |
| a data-only `capabilities()` override | `CAPABILITY(T, entry)` one line; `refine(CAP_REAGENTS, add =)` merges, `starts =` replaces | a1 | [lifecycle.md](lifecycle.md) |
| `periodic_cadence` + `should_run()` + `periodic_step(dt)`; `DECLARE_PERIODIC_WHILE`; `DECLARE_REPEAT`; pipelines and stages | `every(interval, handler, when=, members=, phase=, after=, budget=)`; stages are work items with `after` edges | f-reactions / f-kernel | [reactions.md](reactions.md), [scheduling_and_kernel.md](scheduling_and_kernel.md) |
| `idle` / `wake_on` / `rewake_delay` on a stage | `should_run` with declared reads (adapters keep old stages running) | f-kernel | [scheduling_and_kernel.md](scheduling_and_kernel.md) |
| `update_rust_device()`, `push_to_rust()` hand pushes, `power_sync` | generated `rust_push(reads...)` | f-rust | [rust.md](rust.md) |
| Mirrors: `turf.temperature`, APC `sync_cell_charge`, gas observation drains | `native_read(E, key)`, `native(key...)`, one `vg_frame` outbox | f-rust | [rust.md](rust.md) |
| Reactor watch/token, per-domain watches | one World watch facility + `on_cross` | f-rust | [rust.md](rust.md) |
| `cap_entry_point(cap_hand(...), INTERACTION_ENTRY_ALT, ...)`, per-entry alt-click, `INTERACT_*` | `cap_op(..., action = ACT_X, priority =, stance =)`; gestures bind to actions in a bind profile (stance is a gesture modifier); `INTERACT_VERB` is `action = ACT_NONE`; the kind-by-kind table is B1 | f-ops [built: a2-ops] | [operations_and_actions.md](operations_and_actions.md) §5, §5a |
| `_DEFAULT` ordering, `INTERACT_ROBOT` / `INTERACT_TK` priority 1 | `priority = OP_PRIORITY_DEFAULT`; declaration order (the cyborg op before the silicon one); `via = ROUTE_TK` | a2-ops [built] | [operations_and_actions.md](operations_and_actions.md) §5 |
| `behind = COVER \| PANEL` bits | compartments: `compartment(BAY_X, door =, route_gate =)` and `at = BAY_X` on operations, slots, ladders | f-ops | [operations_and_actions.md](operations_and_actions.md) |
| `needs = PROC_REF(x)` + `else_say`, `works_broken`, `works_unpowered`, `locked_by`, `blocked_by` | requirements: `req_*`, `all_of`/`any_of`/`none_of`, `cap_require(ops =, needs =)` (old arguments still map to them) | f-ops | [operations_and_actions.md](operations_and_actions.md) |
| `cap_hand` / `cap_tool` / `cap_use_on` / `cap_insert` / `cap_control` | presets over `cap_op(name, handler, using=, by=, via=, action=, needs=, delay=, cost=, kind=, key=, at=, log=)` | f-ops | [operations_and_actions.md](operations_and_actions.md) |
| Same-key redeclaration silently replacing | init error unless via `refine(key, ...)` or `replace` | f-ops | [operations_and_actions.md](operations_and_actions.md) |
| Global "can hold" / `has_hands` booleans | affordances (`AFF_*`) from slot providers; routes (`ROUTE_*`) | f-ops | [operations_and_actions.md](operations_and_actions.md) |
| `layer =` on capability constructors, `CAP_NO_LAYER` | icon naming convention: `look.variant`, `look.part`, `look.glow`; standard names in `look_names.dm`. **[built on master, G12]**: library constructors take no `layer =`; a capability draws its fixed standard name, a holder that shows it another way calls `look.hide(name)` in `draw()`; a slot names its part with `part =` | f-look | [look.md](look.md) |
| `behind =` / `blocked_by =` / `locked_by =` on **library** constructors (`cap_panel`, `cap_cover`, `cap_slot`, `lock_op`, `emag_op`, ...) | **[built on master, G12]** requirements in `needs`: `req_set(COVER)` (must be open), `req_clear(COVER \| PANEL)` (must be shut), `req_clear(LOCK)` (not locked); a compartment is `at = BAY_X`. Same refusal messages. The `cap_op` presets (`cap_hand`, `cap_tool`, ...) keep their old arguments until the ops batch | a3 | [look.md](look.md), F4 |
| Hand-written construction stage entries, `apc_steps` | `cap_construction` with `insert`, `wire`, `fasten`, `weld` and joints `fit`, `plate`, `parts`; presets `machine_frame`, `computer_frame`, `wall_frame`, `girder`, `mech_chassis` | f-look | [construction.md](construction.md) |
| `POOL_DECLARE` / `POOL_RESET`, storing packets via `ownership()` | `/datum/pooled`: automatic reset, `take`/`release`, `snapshot()` | f-look | [pools.md](pools.md) |
| `system.members`, `cap_system` roles, `world_services()` | `MEMBER` relations, `join(system, E, source)` | f-kernel | [scheduling_and_kernel.md](scheduling_and_kernel.md) |
| MC `Loop` for gameplay, `SSbehaviours` | `kernel_tick()` phases K, N, U, D, P, R, G; `request_urgent(member, work, deadline)` | f-kernel | [scheduling_and_kernel.md](scheduling_and_kernel.md) |

## F4. Lifecycle declarations (G4) [built on master]

Each `DECLARE_*` lifecycle macro has a foundation form. The macros stay until the codemod has moved their sites;
`DECLARE_DEFAULT_CHILD` and `DECLARE_LOGIN_VERB` are already thin wrappers over the new forms. Chapter:
[lifecycle.md](lifecycle.md) section 9.

| Old | New | Where |
|---|---|---|
| `DECLARE_DEFAULT_CHILD(T, "cell", "cell_type")` | `rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(cell_type))`; a list var: `rel_many(..., starts = list(/obj/x = 2))`; a null DEFAULT (the var holds its own path): `starts = nameof(var)` | `relations()` |
| `DECLARE_REAGENTS(T, V, C)` on the root of a chain | `reagents(V, starts = C)` (`V` a number or `nameof(volume)`) | `capabilities()` |
| `DECLARE_REAGENTS(T, null, C)` on a subtype (659 of 666 stacked sites) | `refine(CAP_REAGENTS, starts = C)`: ADDS to the inherited contents, as the macro did | `capabilities()` |
| `DECLARE_REAGENTS(T, V, C)` on a subtype | `refine(CAP_REAGENTS, starts = C, volume = V)` | `capabilities()` |
| `DECLARE_REAGENTS_TINTED` / `_TYPED` | `reagents(V, starts = C, tint = TRUE)` / `reagents(V, starts = C, holder = /datum/reagents/x)` | `capabilities()` |
| `DECLARE_REAGENT_FROM_VAR(T, V, "id_var", "amount_var")` | `reagents(V, starts_from = list(nameof(id_var) = nameof(amount_var)))` | `capabilities()` |
| `DECLARE_NO_REAGENTS(T)` | `. = without(., CAP_REAGENTS)` | `capabilities()` |
| `DECLARE_LOGIN_VERB(T, verb)` | `. += type_verb(verb, login = TRUE)` | `type_verbs()` |
| `DECLARE_GAS(T, "v", V, K, gases)` | `gas_store(nameof(v), V, K, gases)` | `capabilities()` |
| `DECLARE_REGISTRY(T, REGISTRY_X)` | `membership(joins = REGISTRY_X)` (a list may mix registry ids and `/datum/system` types) | `capabilities()` |
| `DECLARE_START_TIMER(T, delay, PROC_REF(x))` | `after_init(delay, PROC_REF(x))` (armed at init, not materialize; `delay` may be `nameof(var)`) | `reactions()` |
| `DECLARE_BEHAVIOUR(T, B)` | per behaviour: a trait + examine line is `cap_trait(TRAIT_X, examine =)`; an after-fact behaviour is `on_notice`; a before-veto behaviour is `before_op` on a guard key (G3). Audit in lifecycle.md 9 | varies |
| `DECLARE_BIND(T, binder)` | no real site (the test fixture only): data to Rust is `push_to_rust()` with the generated `rust_push()` reads, the binding's lifetime a relation / `lifecycle_unbind()` | varies |

**Trap:** do not mix the two forms in one chain. A type converted to `reagents()` that still inherits a
`DECLARE_REAGENTS` gets two holders (the capability replaces the declared one); convert a whole chain from its root
(`/obj/item/reagent_containers` is one root with 633 subtypes; `/obj/structure/reagent_dispensers`, converted, is
the worked example).

## F5. A1 mapping tables [built on master]

**om events** (`tools/dx/codemods/om_event_map.json`, regenerated by `python tools/dx/gen_om_notices.py`, CI checks it):
each event with a listener maps to a target. 111 after-facts -> a generated `/datum/notice/<name>` (fields = the
event's payload in New() order); `qdeleting` hooks mostly only clear a reference: declare the relation and delete
the hook. Vetoes -> guard keys:

| before/* event | Guard key |
|---|---|
| `movable_pre_move` | `GUARD_MOVE` |
| `movable_z_changed` | `GUARD_Z_CHANGE` |
| `in_range_of_irradiation`, `living_irradiate_effect` | `GUARD_IRRADIATE` |
| `living_injure` | `GUARD_INJURE` |
| `living_body_status` | `GUARD_BODY_STATUS` |
| `attackby`, `attack_self`, `attack_hand`, `atom_tool_act`, `click_alt` | `GUARD_ATTACKBY`, `GUARD_ATTACK_SELF`, `GUARD_ATTACK_HAND`, `GUARD_TOOL_ACT`, `GUARD_CLICK_ALT` (an op's `before_op` once the entry is an op) |
| `hit_by_thrown`, `cross`, `falling_down`, `stumbled_into` | `GUARD_THROWN_HIT`, `GUARD_CROSS`, `GUARD_FALL`, `GUARD_STUMBLED_INTO` (converted: spontaneous vore) |
| `item_pre_attack`, `robot_item_attack`, `catch_throw` | `op` (the operation's before_op) |
| the rest (`human_get_*`, `mob_handle_hud*`, `disposal_*` ...) | `review` (an accumulator: a provider or a capability, judged per site) |

An emit site that reads the result (`reads_result` in the map) cannot become a notice: it is a guard or a review.
Events with no listener are deleted with their emit sites (A1 deleted 7; `handle_mutations`, `turf_prepare_step_sound`
and the two `dqai_target_*` are expression emits left for A4).

Worked examples: dry galoshes (`/datum/om/behaviour/dry` + `before/shoes_step_action` -> `on_notice(/datum/notice/shoes_step)`
in the galoshes' `reactions()`), squeaky shoes (`om_hook` -> `observe(owner, on_notice(...), src, PROC_REF(on_step))`),
spontaneous vore (an om behaviour attached with `DECLARE_BEHAVIOUR` and `om_attach` -> four `before_op(GUARD_*)` on
`/mob/living`; call sites `guard(src, GUARD_X, ...)`).

**grants, verbs, attachments, watches:**

| Old | New |
|---|---|
| `om_grant(T, GRANT_VERB, /x/proc/y, src)` / `om_revoke` | `grant(T, /x/proc/y, src)` / `revoke()` (example: `rotatable.dm`, `climbable.dm`) |
| `om_grant(T, GRANT_VERB_HIDE, path, src)` | `grant(T, hidden_verb(path), src)` |
| `om_grant_for(T, GRANT_CAPABILITY, /datum/capability/x, src, d)` | `grant(T, /datum/capability/x, src, d)` |
| `om_grant(T, GRANT_ABILITY / GRANT_TRAIT / GRANT_LANGUAGE, ...)` | unchanged until their stores move (A4 review) |
| `om_attach(E, /datum/om/behaviour/x)` (static, per type) | the behaviour's handlers as `reactions()` / a capability on the type (example: spontaneous vore) |
| `om_attach` holding per-instance state | a relation to an owned datum (`rel_one(..., kind = RELK_OWNED)`) whose type has the reactions |
| `om_watch(owner, target, CHANNEL, behaviour)` | `observe(target, on_change(list(keys)), owner, PROC_REF(h))`; needs the target's key published (TRACKED / PUBLISH_CHANGE). The 7 channel watches wake OM sleepers, so they move with S3 (stage engine); gas watches (`om_watch_arm_*`) stay on the gas watch facility |

## F2. Choosing the form

| You want | Write |
|---|---|
| Something happened; others may care | `PUBLISH` a notice; consumers `on_notice` |
| A value changed; recompute a view | `TRACKED` setter; `reactions()` `on_change` sugar |
| Veto or adjust an operation | `before_op` |
| A native value crossed a line | `on_cross` (`urgent =` if the latency matters) |
| Do later / repeatedly | `after` / `every` |
| A player gesture | an action (`ACT_*`) that resolves to a `cap_op` |
| A feature with parts, gating, entries | a capability |
| A link between datums | `relations()` with the right kind |

## F3. Traps

- The foundation forms are not usable in converted code until their branch merges; use the left
  column and the status markers in Parts A and B.
- Do not migrate call sites as part of the F batch. Add the new API beside the old one.
- `on_notice` is for occurrences; do not model a state as a notice, and do not coalesce notices.
- A handler receiving a pooled datum (notice, `op_ctx`, damage packet) must not keep it.

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

> Foundation: becomes `reactions()` with generated reads (F1); the sugar names stay.

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

## A2b. Reactions, notices and the ledger [built: rewrite/f-reactions]

Reference: `dx_conventions.md`, "Reactions". Deliberate differences from the plan text: relation kind constants are
`RELK_REF/RELK_PAIRED/RELK_OWNED` (`REF` is a macro); `every(when = ...)` (`while` is a DM keyword); the keyed or
timer is `after(owner, delay, handler, key =, clock =, with =)` (A1 removed the varargs; `rx_after()` is internal).

| Old | New |
|---|---|
| `om_after(E, d, proc, args...)` | `after(E, d, proc, with = list(args...))` (om_after stays as a wrapper) |
| `after_slot(E, slot, d, proc, args...)` | `after(E, d, proc, key = slot, with = list(args...))`; after_slot is a wrapper over the keyed timer |
| a hand `changed()` plus polling a var | `on_change(list(nameof(v)), PROC_REF(h))` in `reactions()` |
| `om_emit(E, new /datum/om/event/x)` for an occurrence | `PUBLISH(E, /datum/notice/x, args...)` + `on_notice()` |
| `om_hook(source, event, ...)` | `observe(source, on_notice(type, h), listener, PROC_REF(h))` |
| hand-kept grant counters and source lists | `grant(target, what, source, duration)` / `revoke()` |
| `system.members` / `cap_system` rosters | `join(system, E, source)` / `members_of(system)` [rosters not yet deleted] |
| `rel_one(nameof(v), back = ...)` | still valid; `rel_one(nameof(v), type, kind = RELK_PAIRED, back = ...)` |
| `derived()` reads | still valid; folded into `reactions()` for `READERS` |

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
Every constructor below also takes the standard gating arguments `needs`, `else_say`, `works_broken`, `works_unpowered`, `log` (and `at =` where a compartment applies). Since G12 there is no `behind` / `blocked_by` / `locked_by` and no `layer =`: a state gate is a requirement in `needs` (`req_set(COVER)`, `req_clear(COVER | PANEL)`, `req_clear(LOCK)`), folded onto the entries with the old messages, and a capability draws its fixed standard look name (`look.hide(name)` in the holder's `draw()` drops it). Capability-level gating is merged onto every entry the capability builds.

Every entry a library capability builds is a real op [built: a2-ops, G16]: it has a key (`open_cover`, `remove_cover`, `open_maintenance_panel`, `pulse_wires`, `cut_wires`, `repair`, `anchor`, `insert_<var>` / `eject_<var>` / `eject_<var>_alt` / `eject_<var>_self` / `eject_<var>_menu` for a slot, `step:<from>><to>:<tool or item>` for a ladder step, `dismantle`, `put_in` / `take_out` / `empty_out`, `pour_in` / `splash` / `fill_from`, ...), an action, a priority and requirements, so your type's own ops compete with the library's by priority (`OP_PRIORITY_*`) and declaration order. `before_op(key, ...)`, `cap_require(key, ...)` and `refine()` (for top-level ops) name them. Settings and other menu-only entries (climb, flip, the signaler's three, a label's removal, Give a drink, Feed, Put out, Empty out, Set transfer amount) are `ACT_NONE`. The library's ops take no provider slot (`by = NONE`).

| `cap_cover(open_tool = TOOL_CROWBAR, delay, removable = FALSE, ...gating)` | [built] | open/close entry (`BY_HAND` opens by hand), `cover_open` state and look, examine; `removable` adds the knocked-off cover (`CAP_COVER_REMOVED`) |
| `cap_panel(tool = TOOL_SCREWDRIVER, delay, ...gating)` | [built] | maintenance panel |
| `cap_wires(wires_type, ...gating)` | [built] | wire access behind the maintenance panel (its type); the wires datum lives in `wires_of(A)` (replaces the `wires` var) |
| `cap_lock(access, req_one_access, id_types, ...gating)` | [built] | ID swipe lock; reads the holder's mapped `req_access`/`req_one_access` first (replaces `locked` and `req_access` gating) |
| `cap_emag(say, effect, mode = EMAG_ONCE, already_say, delay, ...gating; log = LOG_ADMIN)` | [built] | emag entry; `effect(mob/user, obj/item/card)` runs FIRST and may refuse (FALSE: no bit, no charge); then the bit is set and a charge spent |
| `cap_breakable(repair_tool = TOOL_WELDER, repair_delay, ...gating)` | [built] | broken state (from atom_break/atom_fix), welder repair, examine |
| `cap_anchor(tool = TOOL_WRENCH, delay, needs_floor, ...gating)` | [built] | (un)anchor |
| `cap_rotate(clockwise, counter, needs_unanchored, ...gating)` | [built] | rotate entries |
| `cap_buckle(...gating)` | [built] | buckling (settings are the holder's type vars) |
| `cap_label(max_length, ...gating)`, `cap_rename(max_length, ...gating)` | [built] | hand-labeller label, pen rename |
| `cap_power(...gating)` | [built] | the `dark` state and examine while unpowered; entries refuse unpowered unless `works_unpowered` |
| `cap_slot(var_name, accepts, ...gating, eject_needs, name, ..., part)` | [built] | one item slot: insert, eject, examine, UI data; the var becomes owned; draws the look part `part` (null: nothing) while filled |
| `cap_deconstruct(board, ...gating)` | [built] | crowbar dismantle to a frame (in the design, `deconstructible`); `machine_basics()` passes `needs = req_set(PANEL)` |
| `reagents(volume, starts, holder, tint, starts_from)`, `gas_store(var, volume, temp, gases)`, `membership(joins)`, `cap_trait(trait, examine)` | [built, G4] | starting state: [lifecycle.md](lifecycle.md) section 9, F4 |
| `cap_construction(stage(...), ..., ladder_options(...))` | [built] (costs are `cap_tool`/`cap_insert`/`cap_use_on`/`cap_hand` entries with no handler; `uses`, `sfx`, `icon` on `stage()`) | build/undo ladders |
| `cap_frame_ladder()` | [built] (a proc on `/obj/structure/frame`) | the standard machine/computer frame ladder |
| `cap_wall_mount(offset)` | [built] | faces a wall machine away from its wall and offsets it onto it |
| `cap_atmos_unwrench(delay)` | [built] | unfasten an atmos device into its pipe item, refused while running or over-pressured |
| **Bundles** [built]: `machine_basics(board, anchored_by = TOOL_WRENCH, repair = TOOL_WELDER, dismantle = TRUE, powered = TRUE)` (panel, breakable, power, anchor, deconstruct behind the panel; `dismantle = NONE` and `powered = FALSE` leave those out), `wall_machine(board, offset, repair, dismantle, powered)` (basics without anchoring + wall mount), `console(board)`, `atmos_device(uses_power, unwrench_delay)`, `maintenance_hatch(cover_holds, panel_needs_cover_closed, cover_tool, removable_cover, emag_say, emag_mode, wires)` (cover + panel + wires behind it + lock + emag; declares the compartment `BAY_HATCH` whose door is the open cover; the wiring is `wires`, the lock's access the holder's `req_access`; `cover_holds` is a holder proc that says why the cover can't move, opening or closing; the lock and the emag are ops keyed `CAP_LOCK`, `CAP_LOCK_SWIPE`, `CAP_EMAG` that a holder adds `cap_require()` contracts to and `refine()`s) | [built] | a later capability with the same key replaces an earlier one in place, so a bundle can refine another's part (the hatch's panel replaces the basics' panel) |
| **Bundles** [built]: `cell_bay(slot_var, accepts, at, needs, size)` (draws `LOOK_CELL`) (`at = BAY_HATCH` puts the bay behind a hatch's compartment), `power_channels()` (owns `act_channel`/`act_breaker`/`act_nightshift`; channel indicators are the parts `channel-<c>-<m>`), `powered_by(system, role)` and `powered_by(POWERED_BY_AREA, role)` (MEMBER of the holder's area: lights and consoles; read with `area_members(area, role)`); `door(...)` (rewrite/dx-doors) | [built] | the APC is the worked example: [foundation.md](foundation.md) |
| Items: `cap_use_self(name, handler, ...gating, form =, log =, cooldown =, in_inventory = FALSE)`, `cap_use_at(name, handler, range = 1, target_types =, ...gating, form =, log =, cooldown =)` (replace `attack_self`/`afterattack`) | [built] | `cap_use_self`: item in hand used on itself, handler `(mob/user, ...form)`, runs from `attack_self`, answers `INPUT_ACTION_SELF_USE`, refused unless held when offered through the resolver/Menu (`needs cap_in_hand`; a direct `attack_self()` call, e.g. an action button, is trusted as before, since its callers decide reach; `in_inventory = TRUE` also accepts worn). It replaces the old `self_use()` helper. `cap_use_at`: the held item is the holder, the clicked atom the target, handler `(mob/user, atom/target, ...form)`; `range` 1 = adjacent, >1 also ranged; `target_types` filters. Click order: target `attackby` first, then the item's `use_at` entries (via `after_click()`), then legacy `afterattack`. The dispatch marks, fingerprints and logs the ITEM; mark the target yourself with `changed(target)` |
| Machines [built, B2]: `cap_parts(list(part_stat(nameof(var), part_type, base, per, offset, mode, scale, derive)))` | [built] | component parts as the source of derived stats: each `part_stat()` var is written from the machine's owned `component_parts` relation (latent parts read without materializing), re-derived when the relation changes (an `on_change` reaction) and from every legacy `RefreshParts()` caller; `part_rating(holder, type, PART_RATING_SUM/AVG/MIN/MAX/COUNT)`; the RPED is its op `replace_parts`. Worked example: `cell_charger.dm` (its `RefreshParts()` override is deleted). The other 58 `RefreshParts` overrides convert to `part_stat()` rows |
| `cap_occupant(slot_id, max, types, enter_delay, on_enter, on_exit)` | [built, B2] | a machine holding a mob in its sealed ledger occupant slot (the relation; the destroy spill is the slot's drop policy). Ops `enter_<slot>` (drag a mob onto it, ACT_DROP_ONTO), `enter_<slot>_self` and `eject_<slot>` (ACT_NONE); reads `occupants(holder)` (never null) and `occupant_of(holder)`; from code `occupant_enter(holder, M, user)` / `occupant_eject(holder, M, destination)`; every slot change by any path publishes `OCCUPANTS_KEY` and refreshes the holder. Worked example: `transportpod.dm` |
| `cap_access(access, req_one_access, ops = OP_CONTROL, id_types)` | [built, B2] | access-gated ops without lock state: a `cap_require()` contract whose requirement is a credential provider (`access_credential()`: held card, then worn ID / PDA / silicon access); the holder's own `req_access` wins (`access_needs()`); `access_allowed(holder, user, held)` for code outside an op. The lock asks the same providers. Worked example: `drone_console.dm` |
| `service_panel(wires, panel_tool, access, emag_say, emag_effect, emag_mode)` | [built, B2] | panel + wires behind it (+ access on opening the panel, waived when emagged, + an emag) as one bundle, no cover; each part keeps its capability type, so `replace()` still swaps one. Worked example: `vending.dm` |
| Mobs: `cap_ai(targets)`, `cap_ai_behaviors(...)`, species `species_capabilities()` | [planned] | plan §2.3, §2.4 |
| `cap_system(path)` membership (`systems()`) | [built] (O(1) join/leave) | used by `/datum/system` once it exists |

**Capabilities may own UI actions** [built]: `/datum/capability/<x>/proc/act_<action>(mob/user, atom/holder, ...args)` plus `ui_logged()` on the capability; the dispatcher resolves it on the holder's capabilities when the holder has no `act_<action>` itself. Capability UI data arrives under `data["caps"][<key>]`.

[planned] (archive/framework_fixes.md §9.5; don't invent them):
- **Machines:** `refine(key, ...)` to adjust one part of a bundle; `look.loop(sound)`; `cap_slot(..., eject_tool = TOOL_X)`. (`service_panel`, `cap_occupant`, `cap_access` and `cap_parts` are built: the table above.)
- **Derived values:** `derived()` with `runs_while`/`drawn_from`/`ui_from`/`derive(...)`, and `rust_push(reads...)` replacing hand `update_rust_device()` calls (§9.2).
- **Vore:** `cap_interior(transmit, escape_delay, on_enter, on_exit)`; `settings()` rows (`setting_choice/number/text/bool/color`) with one `act_set_setting(user, key, value)`.

## A5. Look

> Foundation: `layer =` is replaced by the naming convention (`look.variant`/`part`/`glow`), F1 and [look.md](look.md).

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

**Never** call `update_icon()`, `queue_icon_update()` or `update_appearance()`, and never override `update_icon`.

[built: `rewrite/f-look`] **One naming convention for states** (`code/__defines/look_names.dm`):

| State | Meaning | Built by |
|---|---|---|
| `<base>` | the base sprite | `look.state()` / the mapped `icon_state` |
| `<base>-<variant>` | the base, in a variant (`airlock-lit`) | `look.variant("lit", when = on)` |
| `<base>-<part>[-<v>]` | a part drawn for this sprite only | `look.part("panel", "open")` |
| `<part>[-<v>]` | a part every sprite of the icon shares (`panel-open`, `broken`, `charge-3`) | `look.part(...)` |

`look.variant(name)` replaces the base with `<base>-name` when the icon has it; `look.part(name, value)` draws the first of `<base>-name[-value]` then `name[-value]` (nothing if neither exists; `value` TRUE is a plain part, FALSE/null draws nothing); `look.glow(name, value)` upgrades a part you already added to emissive, so glow states are never separate names. Names are exact and dashed: a legacy `panel_open` state is not found until it is renamed (`rename_states.py --standard`, below). `look.hide("panel-open")` hides a part by its full name, or `look.hide("panel")` every value of it. Icon states are read once per icon file (`look_states_of()`); nothing calls `icon_states()` per draw.

Library capabilities draw their layer as a part, so a type's icon just needs the standard states: `broken`, `cover-open`, `panel-open`, `wires`, `locked`, `dark`, `lid`, `cell`, `bolts`, `welded`, `emergency`. `look_missing_standard_parts(A)` lists what a type's icon lacks; a type says what it knowingly lacks with `look_lacks()` and opts in to the unit test's enforcement with `look_checked()` (a checked type with a gap fails the test). The rename tool maps legacy states to the convention:

```
python tools/dq_icons/rename_states.py icons/obj/power.dmi.toml --map apc_frame=frame --refs code/modules/power   # dry run
python tools/dq_icons/rename_states.py icons/obj/power.dmi.toml --map-file renames.txt --apply
python tools/dq_icons/rename_states.py icons/obj/power.dmi.toml --check                                          # states off the convention
python tools/dq_icons/rename_states.py icons/obj/power.dmi.toml --standard --refs code/modules/power             # legacy names -> standard (panel_open, apco*, <base>-panel), states plus quoted references
```

## A6. Periodic work and verbs

> Foundation: periodic work becomes `every(...)` (F1); verbs are unchanged.

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

[built, G14]:
- **Pushes are coalesced and driven by change.** A tracked write that `tgui_data()` reads (generated `ui_from()`
  reads, or a declared `ui_from()`) marks the host; the refresh engine queues each open window and the kernel's
  phase R pushes it **at most once per tick** (`code/modules/tgui/ui_push.dm`). An `act_<x>()` returning TRUE
  updates the acting window. So `SStgui.update_uis(src)` in a converted file is deleted (the round status panel is
  the worked example). `SStgui.update_uis()` itself stays for legacy callers.
- **`ui_rights = R_X`** (a type var) on an admin panel: its window uses `ADMIN_STATE(R_X)` and every `act_<x>()` /
  `UI_ACT` from a user without one of the rights is refused and audited (`admin_require()`). Narrow per action inside
  the handler with `admin_require(user.client, R_Y, entry)`.

[planned]:
- `config` sent once per open;
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

[planned] (archive/framework_fixes.md §9.1, option A): handlers that ask or await run as kernel-tracked tasks, cancelled when the holder is deleted, the user disconnects or the target goes; `as = ASK_THIRD_PARTY`/`ASK_CONSENT`, `timeout =`, `default =`, `yes =`/`no =` labels, `validate =`, `ask_form(...)`, `task_why()`, `await_sql`/`await_http`/`await_job` returning `/datum/io_result`, `start_task()`, `await_action()`, `test_answers()`. Until then use the built `ask_*` above.

## A9. Time

> Foundation: `after()` is the one timer and `every()` the one repeating form; `om_after` and `after_slot` become wrappers (F1).

The decision table. **Read it before writing anything with a timer.**

| You want | Write | Status |
|---|---|---|
| "Not more than once per N" | `COOLDOWN_DECLARE(x)` + `COOLDOWN_START(src, x, N)` / `COOLDOWN_FINISHED(src, x)` | [built] |
| A var that reverts after N | `timed_set(src, nameof(var), value, for_time = N)`, read the var directly, `time_left(src, nameof(var))` for a countdown, `timed_cancel(...)` | [built] |
| A temporary condition **with behaviour** (EMP'd, failed, jammed, on fire) | a timed grant of a capability: `om_grant_for(src, GRANT_CAPABILITY, /datum/capability/condition/x, source, N)` (becoming `grant_for()`, archive/framework_fixes.md §9.3) | [built] (`condition.dm`) |
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

> Foundation: `ownership()` and `OWN` become `relations()` entries of kind `OWNED`; relation kinds are `REF`/`PAIRED`/`OWNED` (F1).

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

> Foundation: requirements are `/datum/req` flyweights with typed refusal reasons and `cap_require` (F1, [operations_and_actions.md](operations_and_actions.md)).

- **[built]** `needs = PROC_REF(x)` + `else_say` on capability entries.
- **[planned]** (plan §2.10): a shared `chk_*` library (`chk_alive`, `chk_conscious`, `chk_capable`, `chk_unrestrained`, `chk_adjacent`, `chk_near_subject`, `chk_held`, `chk_carried`, `chk_hand_free`, `chk_on_turf`), and `ask_*` re-validation running the same `needs`.
- **Until it lands:** convert `REQ_ON`/`REQ_TARGET_STATE` to `needs = PROC_REF(<the same proc>)`, drop reach/adjacent/inventory clauses (the dispatcher applies them), and leave `ASK_*` alone.

## A11a. Operations [built]

Nothing needs migrating: `cap_hand`/`cap_tool`/`cap_use_on`/`cap_insert` keep their arguments and behaviour (they are
presets of `cap_op`). For new or reworked code:

- A gated action becomes `cap_op(name, handler, needs = req_..., action = ACT_X)`; put a contract on a whole kind of
  op with `cap_require(OP_STRUCTURAL, needs = ...)` instead of repeating `needs` on each entry.
- `needs = PROC_REF(x)` still works; `req_proc(PROC_REF(x), reads = list(...))` is the same check that also says what
  it reads (so a timed op cancels early).
- Replace a copied op with `refine(key, delay = ...)`; a duplicate op key is an init error.
- A control that a remote console or UI may also work: `cap_control(...)`, or `via = ROUTE_PHYSICAL | ROUTE_UI`.
- Open parts of a machine through `compartment(BAY_X, ...)` and `at = BAY_X`, not ad-hoc `behind` bits.
- Gestures: answer an action (`action = ACT_LOCK`); do not read click modifiers or the stance. A real `cap_op()` (not
  a `cap_hand`/`cap_tool` preset) whose action the actor's bind profile lists for the gesture is run by the click
  router before the interaction resolver. Among the ops of one action `priority =` (`OP_PRIORITY_*`) decides, then
  declaration order; the first that would run answers, else the first meant one refuses. A menu-only op is
  `action = ACT_NONE`; a hostile one `action = ACT_ATTACK` (a harm or disarm click reaches it first); one for some
  stances only `stance = I_X` or a list. Every library capability already builds real ops (G16), so a type's own op
  competes with them by priority, not by being the only op there.
- Keep `entry = INTERACTION_ENTRY_HAND` (or `_ITEM`, `_SELF`, `_ALT`) on a converted op while other code still calls
  that entry proc directly (a silicon's `silicon_use` hand use, a computer's any-item fallback).
- Veto or follow an op with `before_op(key | capability type, handler)` / `after_op(...)` in `reactions()`; the
  handler gets the `op_ctx` and must not keep it. `after_op` fires only for a committed op.
- `act_action` is a capability UI action, not an atom proc: do not call `atom.act_action`.

## A12. Systems and the kernel [planned]

> Foundation: [in progress] on `rewrite/f-kernel`; see [scheduling_and_kernel.md](scheduling_and_kernel.md).

- **Definition:** a system is `/datum/system/x` in `code/modules/x/`. It has private state (`VAR_PRIVATE`), `needs = list(...)` (boot order), `periodic_cadence` + `should_run()` + `periodic_step(dt)`, `member_should_run(A)` / `member_step(A, dt)` for atoms that joined through `cap_system()`, `emits` + `events()`, `latency_class`, and an `api.dm` that other folders may call.
- **Replaces:** `SUBSYSTEM_DEF`, `/datum/world_service`, `GLOB.x_service`, `boot_after`/`order_after`, `init_order`, `fire()`.
- **Built [rewrite/f-kernel]:** the kernel tick (`code/controllers/kernel/kernel.dm`) runs once per MC iteration in phases K N U D P R G; `SSbehaviours` no longer fires; input, verb_manager and garbage are hosted by the kernel (`SS_KERNEL_HOSTED`), the rest of the MC queue is unchanged.
- **Work items:** `/datum/work_item` (interval, handler, `run_when`, members, phase, after, budget, lane, urgent, clock) registered with `kernel_register_work(owner_type, W)`. `every()` and friends produce these. `while` is a reserved word in DM, so the constructor argument is `when` and the field is `run_when`. Reaction items (`every` / urgent `on_cross` / `on_notice`, `code/datums/reactions/work.dm`) call the holder as `handler(dt)` (or `handler(band, previous_band)` for a crossing); an item whose owner is a `/datum/system` calls `handler(dt)`, or `handler(member, dt)` with `members =`. Handlers return `STEP_DONE` / `STEP_YIELD` / `STEP_PARK`.
- **Ordering:** `after = list(owner_types or item keys)` inside a phase; one validator (`graph_validate()`, `kernel/graph.dm`) serves the boot DAG and the work graph. An edge to an earlier phase is already satisfied; to a later phase or at nothing is an error in `kernel().work_errors`.
- **Urgent:** `request_urgent(member, work, deadline)` for an item declared `urgent = TRUE`: one pending request per (member, work), runs in phase U from a reserved slice, shares the item's per-member execution token with the cadence so elapsed time is applied once, and `metrics()["urgent"]` counts breaches.
- **Membership:** `member_join(key, E, source, role)` / `member_leave` / `members_of(key, role)` (`kernel/membership.dm`). `system.members` and `member_index`, `cap_system/roles.by_role` and the hand `world_services()` list are gone: use `S.member_list()`, `cap_system_members()` and the derived `world_services()`.
- **Stages:** `stage_work_item(stage_type, members, interval)` adapts an existing stage (`should_step(E)` is `!idle(E)`, reads from `reads`). Nothing is migrated.
- **Still true:** don't convert subsystems to systems by hand: every `SSx` call site would change. The deferred list is in `kernel.md`, Implementation notes (rewrite/f-kernel).

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
- **Tracked base vars [built, B4/G8]:** `anchored`, `density` and `opacity` are tracked: write them only through
  `set_anchored()` / `set_density()` / `set_opacity()` (type-level defaults stay plain). The setter publishes the var key to
  its readers and, as a bridge until S4, raises the channel the type's declared field names (a machine's
  `CHANGE_MACHINE_ANCHORED`, a mob's `CHANGE_MOB_CAN_MOVE`: `tracked_bridged_changed()`), so it has no `istype()`. Admin
  edits go through the setter (`SETTER`). `tools/ci/tracked_lint.py` rejects a raw write in any proc.
- **Machine power and integrity state [built, B4/G8]:** `NOPOWER` is the power capability's state, written only by
  `set_powered(powered)` (`power_change()` and the few custom power rules call it) and published as `MACHINE_KEY_POWERED`;
  `use_power` is its tracked draw mode (`set_use_power()` publishes `nameof(use_power)`); `BROKEN` is the integrity state,
  written only by `atom_break()` / `atom_fix()`, which publish `INTEGRITY_KEY_BROKEN`. `has_stat()`, `operable()` and
  `set_use_power()` stay the accessors. `sys/fields stat_owned` rejects `stat_add/stat_remove/set_stat` of either bit
  anywhere else.

  ```text
  /obj/machinery/light_switch/power_change()
      if(!otherarea)
          set_powered(powered(LIGHT))
  if(!turbine())
      atom_break()        // was stat_add(BROKEN): "no partner" is the broken state, published
  ```


---

# Part B: the catalogue of old forms

Every form that goes away is listed here with its count on `integrate/b17` and the lint that tracks it. The `dx_old_forms` ratchet (`tools/ci/sys_rules/dx_old_forms.py`, started at 18,363 sites) was removed: every rule banned a form whose replacement has not landed on master (and `old_ui` contradicted the `ui` rule). The catalogue below stays as the inventory; a rule returns with the commit that lands its replacement and converts the callers. **A converted folder may contain none of these.**

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
		rel_set(src, "diode", W)
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

**Kind by kind** [built: a2-ops; the A4 codemod writes these] (the full table with notes and three worked conversions,
the megaphone, the medical records console and the desk bell, is [operations_and_actions.md §5a](operations_and_actions.md)):

| Legacy spec | New form |
|---|---|
| `INTERACT_USE` / `INTERACT_SELF` | `cap_use_self(name, handler)` (ACT_USE offering `req_self_held()`; attack_self keeps running it) |
| `INTERACT_HAND` | `cap_op(name, handler, using = EMPTY_HAND, entry = INTERACTION_ENTRY_HAND)`; a machine silicons work too: `cap_control(...)` |
| `INTERACT_HAND_UNGATED` | as HAND, `works_broken = TRUE, works_unpowered = TRUE` |
| `INTERACT_ITEM` | `cap_op(name, handler, using = <held type>, entry = INTERACTION_ENTRY_ITEM)` |
| `INTERACT_INSERT` | a library slot, else `cap_op(name, handler, using = held_type, entry = INTERACTION_ENTRY_ITEM)` |
| `INTERACT_ALT` | `cap_op(name, handler, action = ACT_TOGGLE, entry = INTERACTION_ENTRY_ALT)` (or ACT_EJECT / OPEN / CLOSE / LOCK / UNLOCK) |
| `INTERACT_DRAG` | `cap_op(name, handler, using = <type>, action = ACT_DROP_ONTO, entry = INTERACTION_ENTRY_DRAG)` |
| `INTERACT_VERB` | `cap_op(name, handler, action = ACT_NONE)`; `REQ_IN_INVENTORY` is `needs = TYPE_PROC_REF(/atom, cap_in_inventory)` |
| `INTERACT_SILICON` / `INTERACT_ROBOT` | `cap_op(name, handler, via = ROUTE_INTERFACE, by = AFF_INTERFACE)`; the robot one also `offered = req(/mob/living/silicon/robot, of = OP_ACTOR)`, declared first |
| `INTERACT_OBSERVER` | `cap_op(name, handler, action = ACT_EXAMINE, via = ROUTE_UI, by = NONE)` |
| `INTERACT_TK` | `cap_op(name, handler, via = ROUTE_TK)` |
| `_AS(I_HURT)`, `_HOSTILE` / `_AS(I_DISARM)` | `action = ACT_ATTACK, stance = I_HURT` / `stance = I_DISARM` |
| `_AS(I_GRAB)` / `_AS(I_HELP)`, `_PEACEFUL` | `stance = I_GRAB` / `stance = I_HELP` (ACT_USE) |
| `_DEFAULT`, `_DEFAULT_AS` | `priority = OP_PRIORITY_DEFAULT` |
| `REQ_*` clauses | `needs =` (refuses) or `offered =` (not meant: the input falls through) |

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
	open_request(src, /datum/prompt/text, PROC_REF(shout_entered), answerer = user, title = "Megaphone",
		question = "Shout a message?", ask_flags = ASK_CARRIED | ASK_CAPABLE)
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
	var/flag = (holding ? 1 : 0) | (connected_port() ? 2 : 0) | (4 << (gauge_band - 1)) // the old desired_update_flag()
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
	look.state(power_state == POWER_UNPOWERED ? "doorctrl-p" : "doorctrl0")   // power_state [planned], archive/framework_fixes.md §9.3
```

**Traps:**
- Call `..()` first; the capabilities draw their layers.
- Never set `icon_state` directly in gameplay code.
- For the capability layers, use standard state names; run the rename tool for legacy ones.

**Power reads:** there is no `is_powered()`. The one read is the derived `power_state` (`POWER_BROKEN`/`POWER_UNPOWERED`/`POWER_OFF`/`POWER_IDLE`/`POWER_ACTIVE`) [planned, archive/framework_fixes.md §9.3]; until it lands, `cap_powered(src)` [built].

## B6. Manual refresh → delete

**HUD, sight and canmove [built, B4].** There is no `refresh_hud()` / `refresh_vision()`: the passes are `on_change()`
reactions on `/mob/living` (living_systems.dm) whose reads are declared by hand (published `MOB_KEY_*` facts) and
generated from what `life_hud()` / `life_vision()` / `update_canmove()` and their `life_hud_*` / `life_vision_*` helpers
read (`reaction_reads()` in `code/_generated/reads.dm`). Every such var is tracked (TRACKED / SETTER / an OM field), a
relation or object var (the ownership accessors publish), or `PUBLISHED_BY(T, var, KEY)` (its producer publishes KEY:
`hud_updateflag` via `flag_hud_update(index)`, `organs` and `body` via body invalidation). So a refresh call is replaced by
the setter of what changed, or by publishing the key that covers it: `PUBLISH_CHANGE(M, MOB_KEY_VIEW)` for what the
client looks through (remote view, zoom, vision gear: `recalculate_vis()` does it), `flag_hud_update(WANTED_HUD)` for a
HUD-list entry. `derived_reads/reaction_read_untracked` rejects an untracked input; `sys/presentation presentation_call`
rejects calling a pass from content.

```text
// was: user.refresh_hud()
PUBLISH_CHANGE(user, MOB_KEY_VIEW)
// was: nutrition -= 5; refresh_hud()
adjust_nutrition(-5)
```

Every `update_icon()` and `queue_icon_update()` call in a converted folder is deleted. If the write happened outside a dispatched call (a raw callback or FFI data), write `changed(src)` instead. The sweep fails in tests when a mark is missed, so a deletion that misses a case is caught.

## B7. UI → `tgui_data()` + `act_<x>()`

```text
// BEFORE: round_status_panel.dm:28, :98-107 (the deleted DECLARE_UI forms)
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
```

```dm
// AFTER (round_status_panel.dm is converted: tgui_id, ui_rights, act_<x>() procs, no update_uis)
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
| `SStgui.update_uis(src)` | delete: the change pushes (coalesced, once per tick in phase R) and a TRUE `act_` return updates the acting window |
| `DECLARE_UI_STATE(..., ADMIN_STATE(R))` | `ui_rights = R` on the type [built]; narrow per action with `admin_require(user.client, R, entry)` |
| `DECLARE_UI(T, "Iface", UI_TITLE("T"))` | `tgui_id = "Iface"` and, when the host has no `name`, `ui_title()` |

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

The re-run machinery (`om_ask`, `act_ask`/`rerun_ask`, `prompt_flow`/`flow_execute`, `/datum/om/flow`, `om_prompt_answer`/`test_prompts`) still exists in old code; archive/framework_fixes.md §9.1 deletes all of it. Convert to the inline form, never add to it.

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

**Temporary state: one form per intent** (archive/framework_fixes.md §9.3):

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
| `DECLARE_LOGIN_VERB(type, verb)` | `type_verbs()`: `. += type_verb(verb, login = TRUE)` [built, G4]; the macro is a wrapper over it |
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
	unobserve(target, /datum/notice/living_turf_collision, source)
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

`relations()` and the REL* migration are built (doc/rewrite/archive/ownership.md §4.1); the typed
`/datum/om/relation` types are not converted yet (`python tools/dx/convert_relations.py --dry-run`
lists each with its proposed entry and what blocks it). Meanwhile:
- Declare links in `relations()` and write them with `rel_link(src, nameof(x), y)` (always `nameof()`, never a string), **one side only**.
- Don't add new `/datum/om/relation` types.
- Never store the same link twice (a relation plus a plain var copy, like the borer's `host =`).

## B18. Ownership declarations → one form [built]

The 16 declaration macros (`OWN` 211, `REL_LIST` 91, `REL_PAIR` 77, `REL` 48, `REL_PAIR_LIST` 34, `PROTO` 27, …) are gone. Declare in `ownership()` (`owns(nameof(var), policy = ...)`, `shares(nameof(var))`, `proto(nameof(var))`) and `relations()` (`rel_one`, `rel_many`, `rel_key`); see doc/rewrite/archive/ownership.md §1.2. `sys/dx_ownership_forms` bans the old macros, the interim `declare_ownership(decl)`, and string var names in accessors. (`OWN_TIMER` and `DECLARE_SHARED_CACHE` are separate and stay.)

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
| hand pushes after a generated setter | no generated setter: the DM var is `TRACKED` with a `rust_push` read and `push_to_rust()` writes it with `native_write()` (key `NATIVE_<STRUCT>_<FIELD>`, generated); a Rust-only field has one hand setter over `native_write()`. Built for the APC and pump [built] |
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

`/datum/system/native` (`code/datums/native/system.dm`) delivers them. The kernel's phase N (`native_frame()`, `code/controllers/kernel/native.dm`) runs `native_system().kernel_frame()` exactly once per wheel tick: elapsed deciseconds become wheel ticks (1..`NATIVE_MAX_CATCHUP`, which is also `KERNEL_NATIVE_MAX_CATCHUP`) and the per-tick wake budget scales with them, then `run_frame()` calls `vg_frame` once. Nothing else steps the frame: the OM scheduler's `world_step()` and `native_hosted` are deleted (`world_frame_begin()` keeps the lane queues and the once-per-tick guard; a scheduler on injected `manual_time` never runs a frame), and SSvg is `SS_NO_FIRE`. `native_read(E, key)` reads a Rust-owned value through a per-frame cache that a CHANGED record for the entity clears.

The three `native_*` procs are wired to the reaction framework: `native_publish_change()` calls `publish_change()` under the key's `native("...")` name when `rx_readers()` says something reads it (name a Rust key once with `native_key_name_add(key, "name")`; an unnamed key publishes to no reaction), and still calls `om_changed()` as the bridge for OM-era readers that key on channel bits (om_listen listeners, declared appearances, caches and periodic work). `native_publish_notice()` is `PUBLISH(E, /datum/notice/native, kind, args)`: nothing is allocated unless a reaction or observer wants that type (the old `/datum/om/event/native_notice` had no listeners and is deleted). `native_crossed()` delivers through `rx_crossed()` (bands, hysteresis, urgent path) for a watch declared for a reaction with `native_watch_for_reaction(watch, reaction)`; every other watch (world, gas, heat wake callbacks) keeps its own callback.

Pipe devices (pump, volume pump, passive gate, vent pump, vent scrubber) push their Rust law through the generated `rust_push`: the law's vars are `TRACKED`, `derived()` lists them plus `rust_device_rev`, and `push_to_rust()` runs once per frame. `update_rust_device()` no longer exists. Events with no DM var of their own (a port bound, a neighbour gone, power changed, a weld) and the pump's hand setters over `native_write()` call `rust_device_dirty()`, which bumps `rust_device_rev`. Tests that need the law pushed now call `push_to_rust()`.

The old drivers and drains are gone from DM: `vg_world_tick`, `vg_world_events`, `vg_world_step`, `vg_entity_tick_all`, `vg_heat_tick`, `vg_heat_take_wakes`, `vg_pipe_step_devices`, `vg_drain_dirty_gas_observations`, `vg_drain_events` (now `vg_dispatch_notice`, called by the native system per NOTICE). Heat watches are ordinary watch ports: a body uses its world kind (`VG_KIND_HEATBODY`), the turf solid `VG_HEAT_CELLS`, both through the generic `vg_world_watch_*` binds (and `vg_world_watch_set*` for the heat ledger's threshold sets); the bespoke `vg_heat_watch*` binds are deleted.

Tests that step Rust by hand call `vg_world_run_steps(n)` and then `native_system().drain()` (delivers what Rust holds without pacing); `SSair.rust_step_pipe_devices()` is the test hook that forces a device period.

## B27. TGUI pushes and payloads

| Old | New |
|---|---|
| `SStgui.update_uis(src)` (323 sites) | delete in converted files: a change pushes, coalesced to once per open window per tick (phase R) [built, G14] |
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

## B30. Mob Life stages [planned: archive/framework_fixes.md §9.5 Life]

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
- `tools/build/build.sh lint`: DreamChecker 0, and no Part B form left in your folder (`git grep` the form).
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

## A15. Construction primitives [built: `rewrite/f-look`]

A ladder is what the player does, not stages with hand-written undo, refund, message, icon and delay:

```dm
. += cap_construction(
	ladder_options(sprite = "frame", undo_delay = 1 SECONDS, dismantle = list(TOOL_WRENCH, /obj/item/stack/material/steel, 2)),
	stage("frame", desc = "A bare frame."),
	build_fit(/obj/item/circuitboard/apc),          // a part, pried out again with a crowbar
	build_wire(5),                                  // 5 cable; wirecutters cut it out and give it back
	build_fasten(TOOL_SCREWDRIVER, name = "closed"),
	build_plate(/obj/item/stack/material/steel, 2), // 2 sheets welded on; the welder cuts them off and refunds them
)
```

Primitives: `build_insert(part)` (in and out by hand), `build_wire(n)`, `build_fasten(tool)`, `build_weld()`. Joints: `build_fit(part)`, `build_plate(sheets, n, name =)`, `build_parts(list)`. Presets (lists of stages: pass them to `cap_construction()`): `mech_chassis(result, sprite =, parts =, steps =)`, `machine_frame()`, `computer_frame()`, `wall_frame(board)`, `girder()`. Derived: the undo (the fastener table), the refund (what the build consumed), the messages (the verb table), the stage icons (`sprite` + the stage's position), the delays (per-tool defaults; `undo_delay` overrides every undo), stage names (numbered when two are alike). The ladder owns the stage: ask `built_past(A, "wired")`, keep no stage var. `ladder_options(at = BAY_X)` names the compartment the steps are done in. Not migrated yet: mech and girder content, the old `/datum/construction_graph` users. The `build_` prefix keeps a holder's own `weld()` / `insert()` / `wire()` procs from shadowing them.

## A16. Pools [built: `rewrite/f-look`]

```dm
/datum/damage_packet
	parent_type = /datum/pooled
	var/zone                 // any var: reset to its initial value on release
	var/list/amounts         // a list New() allocates is kept and emptied

var/datum/damage_packet/P = take(/datum/damage_packet)
... P.release()
```

A pooled type declares nothing per field and has no `ownership()`. `reset()` is the hook for what a field cannot say; `pool_max_free` caps the free list (extras are destroyed); `snapshot()` lists the reset fields; poison is on in every test build, so a holder that keeps a released object crashes on its next use. `tools/ci/pool_lint.py` rejects `new` of a pooled type and a `take()` in a file that never releases. `POOL_DECLARE` and `DECLARE_REF(..., TRANSIENT)` still work for the old form.

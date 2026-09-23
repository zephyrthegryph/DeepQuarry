# Object model: kinds, ownership, relations, behaviours, scheduling

Status: **authoritative design**. It supersedes `lifecycle.md` §4 (declared
references). It keeps `lifecycle.md`'s destroy transaction and extends it (§14).
It sits beside `rust_architecture.md`, which covers the Rust side. Nothing here
migrates existing callers yet. This document defines the frameworks, and
migration runs later behind ratchets (§21).

## 1. Goals

The aim is DM code with the error surface of a well-typed, ownership-based
system:

- **No hand-written lifecycle.** Remove per-type `Initialize`, `Destroy` and
  `process()` wherever a framework can own the work.
- **No dangling references and no hard deletes.** Every object has an owner.
  Every other reference is a framework-managed relation.
- **Null only where a type says so.** Composition and typed nullability keep
  null out of behaviour code.
- **Almost no polling.** Things happen because an event, timer, watch or rate
  crossing caused them.
- **Composition over inheritance.** Generic behaviours are configured with
  data, reused through bundles, and validated at boot.
- **Generated glue.** The DM↔Rust and DM↔TypeScript glue comes from one source
  of truth.
- **Plain DM.** Declarations are ordinary procs and types. There are no macro
  DSLs.
- **A static half.** `tools/dm-health` checks what the runtime framework can't.

### 1.1 Principles

1. **Declare, don't code.** Slots, relations, behaviours, schedules, UIs and
   destruction effects are declarations.
2. **One way to do each thing.** There is one relation API, one scheduler, one
   requirement vocabulary and one event system.
3. **Handlers receive their participants.** A handler is called only when what
   it needs is present, so it never fetches an optional reference itself.
4. **Plain types and procs in, generated glue out.**
5. **Fail at boot or in CI, not at runtime.** Declarations are validated when a
   type's archetype is built (§6). dm-health checks what can be checked
   statically.
6. **Everything is inspectable.** Owners, edges, requirement bits, pending
   timers and watches, and the reason a behaviour is asleep are all visible in
   the variable viewer.

## 2. What exists already

This design unifies pieces that are already built or in flight. It doesn't
start from nothing.

| Piece | Where | Becomes |
|---|---|---|
| Containment ledger, slots, latent state | `code/datums/containment/` (C1–C11) | the ownership layer (§4) |
| Destroy transaction, links, verbs | `rewrite/ledger-joint`: `code/datums/lifecycle/transaction.dm`, `links.dm`, `verbs.dm` (LC1–LC3) | the destroy pipeline (§14); `REF_*` links become relation kinds |
| Grants | `rewrite/grants`: `code/datums/grants/` | one relation kind with apply/unapply hooks (§5.6) |
| Abilities (P5) | `code/datums/abilities/ability.dm` | behaviours granted through grants |
| Compact interactions (I7) | `code/datums/interactions/` | archetype interaction tables (§6) |
| Interaction requirements (P2 `REQ_*`) | interactions framework | the requirement library (§8) |
| Mob life systems and hibernation | `code/modules/mob/living/life/scheduler.dm` (DQ Medical) | behaviours under the unified scheduler (§10); converged with DQ Medical |
| Reactor: timer wheel, wake lanes, `RateModel` | `verdigris/core/src/reactor.rs`, `rate.rs`, `code/__defines/reactor.dm` | the scheduler backend (§10) |
| Rules engine (thresholds, hold, band) | `doc/rewrite/rules.md` | the DM-side watch evaluator (§11) |
| Registries (L3) | `code/datums/registries.dm` | derived indexes over membership relations (§5) |
| R10 bindings, entity table, component stores | `rewrite/bindings`, `doc/rewrite/rust_bindings.md` | Rust components usable in declarations (§17) |
| dm-health | `tools/dm-health/` | the static half (§18) |

## 3. Four kinds of object

Every type declares one kind through `object_kind` (default `KIND_ENTITY`).
dm-health reads each type's initial value.

| Kind | What it is | Lifetime | References to it |
|---|---|---|---|
| `KIND_DEF` | immutable definitions: species, materials, reagents, gas types, recipes, behaviours, requirements, events, relation kinds, bundles, UIs, task types | created at boot, frozen, never destroyed | plain variables, never tracked |
| `KIND_SERVICE` | singletons with state: subsystems, managers, registries | the round | plain variables, never tracked |
| `KIND_LOCATION` | turfs and areas | the life of their z-level (expedition z-levels are recycled) | plain variables; releasing a z-level drops relations to them in bulk |
| `KIND_ENTITY` | everything else: items, mobs, machines, minds, bodies, afflictions, reagent holders, UI sessions, running tasks | exactly one owner | an owning slot or a relation, nothing else (§4, §5) |

- **DEFs are frozen after boot.** dm-health enforces this statically with
  `readonly` fields (§18). Test builds also enforce it at runtime: a write to a
  frozen DEF fails the test. That catches the class of bug found tonight, where
  the event headset mutated the shared species definition.
- **Only `KIND_ENTITY` targets need relation tracking.** A variable holding a
  DEF, SERVICE or LOCATION is an ordinary variable.

## 4. Ownership

Every entity has exactly one owner. For atoms the owner is a holder slot, or
the turf it stands on (the turf's world slot). For non-atom entities it is a
slot on the owning entity or service. Ownership forms a tree whose roots are
services and locations.

- **The containment ledger generalises to every entity.** Slots may hold
  datums, not only atoms. `ledger_owner(D)` is framework-managed.
- **Destruction means an owner drops its subtree** (§14). A tree has no
  cycles, so reference counting frees everything once relations are cleared.
- **Nothing is unowned** except locals inside a running proc.
- **No nullspace parking.** Things outside the world are either latent data or
  held in a slot.
- **Owned children** that aren't contents (actions, loops, helper contexts,
  afflictions) live in **datum slots**, with the same destroy policies as atom
  slots: `SPILL` where it makes sense, `DELETE`, `TRANSFER(resolver)`,
  `TO_LATENT` and `KEEP_WITH`.

## 5. Relations

Every non-owning reference to an entity is a **relation**: a typed edge
between two ends, owned by the framework. Direct assignment to a relation
variable is forbidden (dm-health: framework-write-only, §18).

### 5.1 Relation kinds are DEF types

```dm
/relation/sleeper_console
	from_type = /obj/machinery/sleeper
	to_type = /obj/machinery/sleeper_console
	shape = RELATION_ONE_TO_ONE        // or ONE_TO_MANY, MANY_TO_MANY, SYMMETRIC
	exclusive = TRUE                   // linking a new console replaces the old one
	on_end_lost = RELATION_UNLINK      // or RELATION_DESTROY_SOURCE, RELATION_TRANSFER
	holds_while = list(/requirement/same_z)

/relation/sleeper_console/on_unlink(obj/machinery/sleeper/S, obj/machinery/sleeper_console/C, reason)
	S.set_operating(FALSE)
```

- **Shape** declares direction, cardinality and exclusivity. Exclusive kinds
  replace the old edge when a new one links, so code like
  `if(pulling) stop_pulling()` disappears.
- **Conditions** (`holds_while`) are requirements (§8), re-evaluated only when
  their dependencies fire. The edge breaks with a reason when one fails. This
  replaces the distance and visibility checks now scattered through pulling,
  buckling, grabs, tgui status, do_after, multitool links and AI targeting.
- **Hooks** are `on_link`, `on_unlink(reason)` and `on_end_changed`. Rich edges
  also carry state and behaviour. A pull edge, for example, moves its follower.
- **Lifetime.** An edge dies before either end finishes dying. `on_end_lost`
  decides what happens to the surviving end.

### 5.2 Light and rich edges

- **Light edges** are adjacency entries: a lazy `_edges` alist on both ends,
  keyed by relation kind, holding the partner or a list of partners. They cost
  roughly 32–48 bytes each.
- **Rich edges** are `/edge/<kind>` entity datums, held in both ends' `_edges`,
  for relations with state or behaviour. Examples: grab, pull, buckle, a tgui
  session, a running task, a grant. They cost roughly 150–250 bytes each.
- **There is no separate reverse index.** Both ends hold the edge, the way
  Bevy's `ChildOf` and `Children` do. When B dies, the framework walks B's own
  edges, so the cost is proportional to B's degree, not a scan of the world.

### 5.3 Reading relations

- **1:1 kinds** keep a framework-maintained view variable on the source, such
  as `sleeper.console`, so reads cost the same as a plain variable. It is
  non-null for *required* 1:1 kinds.
- **Other shapes** are read with `linked(src, /relation/x)`. It returns a list,
  using a shared empty list when there are none, so `for` needs no null check.
- **Queries** include `linked`, `linked_to` (the reverse direction), `has_link`,
  and transitive walks up the owner and holder chains.

### 5.4 Derived relations

`in_view`, `near(n)` and `same_area` are maintained by the spatial index from
movement events. They can be queried and they emit events, so they drive
proximity watches (§11) without polling.

### 5.5 Writing relations

`link(A, /relation/x, B)` and `unlink(A, /relation/x, B)`. Linking to an
entity that is being destroyed is refused (§14). This structurally prevents
new references during teardown.

### 5.6 Relation kinds that replace existing mechanisms

| Today | Relation kind |
|---|---|
| `RegisterSignal` listener registration | light edge "listens to" (§9) |
| registry membership, `GLOB.x += src` | light edge "member of" a registry service; the registry is a derived index |
| radio, camera, NTNet and holopad channel membership | "member of" a channel |
| grants | rich edge from source to mob, with apply and unapply hooks |
| tgui sessions | rich edge from user to object (§16) |
| pull, buckle, grab, orbit, ride, `vis_contents` attachment | rich edges with movement semantics |
| multitool and console links | 1:1 or 1:N kinds with `holds_while` |
| timers, watches and scheduler entries | edges from entity to scheduler (§10) |
| rate contributions | edges from source to rate field (§12) |

## 6. Declarations and archetypes

### 6.1 `declare()`

Each type declares its composition in one proc, built on a builder API with
named arguments:

```dm
/datum/proc/declare(archetype/A)
	SHOULD_CALL_PARENT(TRUE)          // DreamChecker; dm-health also requires ..() first, on every path

/obj/machinery/space_heater/declare(archetype/A)
	..()
	A.include(/bundle/cell_powered)
	A.include(/bundle/switchable)
	A.add(/component/heat_regulator, max_power = 5 KILOWATTS, target = T20C, mode = REGULATOR_HEAT_AND_COOL)
	A.ui(/ui/space_heater)

/obj/machinery/space_heater/industrial/declare(archetype/A)
	..()
	A.configure(/component/heat_regulator, max_power = 20 KILOWATTS)
```

Builder calls:

| Call | Does |
|---|---|
| `A.slot(name, accepts, capacity, on_destroy)` | an ownership slot |
| `A.add(behaviour or component, config...)` | attaches a behaviour or a Rust component with per-type config |
| `A.configure(behaviour or component, config...)` | changes config inherited from a parent |
| `A.remove(behaviour or component)` | removes something inherited |
| `A.include(bundle, params...)` | applies a bundle (§6.3) |
| `A.relation(kind, required = FALSE)` | declares the type's relation kinds; required ones are non-null |
| `A.watch(watch, params...)` | a static watch (§11) |
| `A.rate(name, min, max, thresholds...)` | a rate-valued field (§12) |
| `A.interaction(...)` | I7 interaction entries |
| `A.registry(registry)` | registry membership |
| `A.ui(ui)`, `A.ui_fragment(fragment, params...)` | UI (§16) |
| `A.destroy_effects(message, sound, debris, neighbour_update)` | declared destruction effects |

### 6.2 Archetypes

- **When they're built.** The first time a type is instantiated, the framework
  runs its `declare()` chain once and builds one `/archetype`. Mapped types are
  built during map load.
- **Validation errors** stop the boot in tests:
  - an unknown config key, wrong unit or out-of-range value (checked against
    the behaviour's or the generated component's schema);
  - an unmet interface (§7.4);
  - duplicate slots;
  - misspelled hooks: every `on_<event>` proc on a behaviour must name a real
    `/event/<event>` type. Checked through `typesof(/behaviour/x/proc)`.
- **What the archetype holds:**
  - the behaviour list, with each behaviour's per-type config;
  - requirement masks;
  - a static event-dispatch table (event → the behaviours implementing its
    hook);
  - slot and relation definitions;
  - the UI;
  - the init plan.
- **Instances carry only their own data.** Behaviours on a type need **no
  per-instance registration**. Today every instance registers signals for its
  components and elements.
- **Merging is explicit.** Parent declarations come first (`..()`), and a
  subtype adds, configures or removes. There's nothing to re-declare, and
  dm-health guarantees `..()`.

### 6.3 Bundles: reuse without inheritance

```dm
/bundle/cell_powered/apply(archetype/A, slot = "cell")
	A.slot(slot, accepts = /obj/item/cell, on_destroy = SPILL)
	A.add(/behaviour/powered_by_slot, slot = slot)
	A.ui_fragment(/ui_fragment/slot_cell, slot = slot)
```

Bundles are parameterised, can include other bundles, and are checked for
conflicts, such as two bundles declaring the same slot.

### 6.4 Inheritance policy

- **Keep inheritance for:**
  - the engine's categories (`atom`, `movable`, `obj`, `mob`, `turf`, `area`);
  - **prefab variants that differ only in data** (`configure`);
  - the mapping catalog, since maps need a type for each placeable thing.
- **Don't use inheritance for code reuse.** That's what behaviours and bundles
  are for.
- **Prefab types become thin and code-free.** The variants registry absorbs
  data-only families.

## 7. Behaviours

A behaviour is a DEF singleton type holding generic logic, configured per
prefab with data.

```dm
/behaviour/powered_by_slot
	requires = list(/requirement/switched_on)
	provides = list(/interface/power_source)
	config = list("slot")                      // validated names for A.add(..., slot = "cell")

/behaviour/powered_by_slot/on_slotted(obj/machinery/M, atom/movable/item, slot)
	...

/behaviour/thermostat_display
	requires = list(/requirement/powered)
	period = 2 SECONDS                         // runs only while requirements hold; staggered

/behaviour/thermostat_display/on_tick(obj/machinery/space_heater/heater)
	heater.update_display()
```

### 7.1 Semantics

- **Requirements** (`requires`) gate the behaviour. It is active only while
  they all hold, and its handlers then get the resolved participants.
- **Triggers:** events (`on_<event>` hooks, §9), wakes, timers, watches,
  rates, and `period` for work that really is periodic.
- **State machines.** A behaviour may declare states, transitions and
  enter/exit hooks. This covers doors, machine power states and weapon modes,
  and removes flags drifting out of sync (`stat & BROKEN`, `on`, `operating`).
- **Ordering and composition:** `after` and `before`, `requires_behaviour` and
  `excludes`.
- **Adding behaviours at runtime.** A source such as a spell or an item grants
  a behaviour through grants, and it's revoked automatically when the source
  goes (§5.6).

### 7.2 Where behaviour data lives

- **Per-type config** lives in the archetype, so it costs nothing per instance.
- **Per-instance state for statically composed behaviours** is variables on
  the prefab. The behaviour lists the variables it needs, and both the
  archetype and dm-health check they exist.
- **Per-instance state for behaviours granted at runtime** goes in a lazy
  per-behaviour table on the entity.
- **Heavy simulation state** (heat, gas, power) lives in Rust components
  (§17), with generated DM accessors.

### 7.3 Execution cost

- **Event handlers are direct calls** from the dispatch table. Nothing iterates.
- **Periodic behaviours visit only their active set:** members whose
  requirement mask is satisfied and that are due. Members are spread across
  timer-wheel buckets so the load is staggered.
- **Membership lists** are maintained by the framework, with O(1) add and
  remove.
- **Hot kinds can implement `on_tick_batch(list/members)`,** which avoids a
  proc call per entity.
- **Every behaviour reports metrics** (calls, time, active count) to the MC
  stat panel and the bench.

### 7.4 Interfaces

Behaviours talk to each other through interfaces, not references. A DEF
`/interface/power_source` defines procs such as `draw(entity, watts)`.
Behaviours `provide` or `need` interfaces, and archetype validation checks that
every need on an entity is met.

- **A missing partner is a boot error, not a runtime null.** A heater declared
  without a power source fails validation.
- **Coupling between heavy simulations happens in Rust,** through coupling laws
  (`rust_architecture.md` §4.3).

## 8. Requirements: one vocabulary

The same library gates tasks, interactions (replacing P2's `REQ_*`), UI
actions, abilities (P5's `why_not`), behaviours and relation conditions.

**Requirement types** are DEFs, used in declarations:

```dm
/requirement/powered
	depends_on = list(/event/power_changed)
/requirement/powered/check(atom/A)
	return A.is_powered()
```

**Checks** are fluent calls on a `/datum/check` that records the first
failure and its message. They're used in procs:

```dm
/task/tool_use/check(datum/check/C, mob/user, atom/target, obj/item/tool)
	C.can_reach(user, target)
	C.holding(user, tool)
	C.tool_quality(tool, tool_quality)
```

- **Built-in checks** include:
  - `can_reach`, `adjacent`, `in_range(n)`, `same_z`, `can_see`;
  - `holding`, `hand_empty`, `conscious`, `has_access`;
  - `tool_quality`, `tool_active`, `powered`, `anchored`, `panel_open`;
  - `slot_filled`, `slot_empty`;
  - `range(value, low, high)`;
  - `unchanged(entity)` (§13);
  - `require(expression, message)`.
- **Dependency capture.** Each check records what it read the first time it
  runs. `can_reach` records movement of both parties, `holding` records equip
  and unequip, `tool_active` records the tool's state. The caller then
  subscribes to exactly those events.
- **Coarse fallback.** A raw `require(expression)` falls back to the
  participants' coarse change events. dm-health can narrow that down by
  inferring which fields the expression reads.
- **Cost ordering.** The library orders checks by cost and stops at the first
  failure.
- **Consistent messages.** The library words failures the same way everywhere,
  and the same text drives disabled-button tooltips (§16).
- **Requirement bits.** For gating, each entity keeps one bit per requirement.
  A bit is re-evaluated only when that requirement's dependency fires for that
  entity, so "is it active?" is a mask compare.

## 9. Events

**Event kinds are DEF types.** Delivery uses double dispatch, so hooks are
ordinary typed procs and emitting an event allocates nothing:

```dm
/event/moved
	phase = EVENT_AFTER                 // EVENT_BEFORE kinds can veto
	delivery = EVENT_IMMEDIATE          // or EVENT_DEFERRED_COALESCED
	bubbles = FALSE

/event/moved/deliver(behaviour/B, atom/movable/source, atom/old_loc, dir)
	B.on_moved(source, old_loc, dir)

// emitting:
emit(/event/moved, src, old_loc, dir)
```

- **Typed.** dm-health checks `emit` arguments against the `deliver` signature
  and the hook signatures.
- **Static subscriptions** come from archetype dispatch tables. **Dynamic
  subscriptions** are light edges (`subscribe(listener, source, /event/x)`),
  cleaned up with either end.
- **Phases.** A `BEFORE` event's handlers may return a veto with a reason,
  replacing `COMPONENT_CANCEL_*` bitflags. An `AFTER` event only notifies.
- **Delivery modes.** `IMMEDIATE`, or `DEFERRED_COALESCED`: ten "changed"
  events in one tick become one delivery.
- **Ordering** is declaration order by default. `after` and `before` are
  declared where order matters.
- **Re-entrancy.** There's a guard per (source, event kind), plus a cascade
  depth limit.
- **Bubbling** up the ownership tree, where an event declares it: from an item
  to its wearer, replacing hand-written relay signals.
- **Handlers never sleep.** Checked statically.
- **`/event/changed(field)`** is the coarse change event that observable fields
  emit (§18.3). UI sessions and coarse task checks listen to it.
- **Existing signals** become the dynamic-edge path, and their `COMSIG_*`
  kinds migrate to event types later.

## 10. Scheduler

Everything that happens later, repeatedly or conditionally goes through one
scheduler. The MC is its budgeted executor, and the Rust reactor (timer wheel,
wake lanes, `RateModel` crossings) is its backend.

| Primitive | API | Replaces |
|---|---|---|
| **Wake** | `wake(entity, /behaviour/x, reason)`, coalesced per tick | ad-hoc recompute calls; generalises `life_wake` |
| **Timer** | `timer(entity, delay, /behaviour/x, key)` → `on_timer(entity, key)`; owned by the entity and cancelled when it dies | `addtimer`/`deltimer` (835 sites) |
| **Random timer** | `timer_random(entity, mean, /behaviour/x, key)`: Poisson scheduling of the next occurrence | per-tick `if(prob(x))` in `process()` |
| **Watch** | §11 | "check every tick whether X crossed Y" |
| **Rate** | §12 | ticking for drain, decay, charge, cooldowns and burn-down |
| **Periodic behaviour** | `period` on a behaviour; only the active set, staggered | 445 `process()` procs, 224 `START_PROCESSING` calls, list-walking subsystems |
| **Task** | §13 | `do_after` (660), `spawn` (677), `sleep` (546), `tgui_input`/`tgui_alert` (2,440) |

- **Hibernation is universal.** An entity with no active behaviours costs
  nothing.
- **Missed-wake audit.** This generalises today's
  `MOB_HIBERNATION_AUDIT`. In test builds, sleeping behaviours' requirements
  are periodically re-evaluated, and a mismatch fails the test. Missing
  dependencies surface immediately.
- **DQ Medical's life systems** become behaviours under this scheduler. They
  are co-designed with DQ Medical, who own mob Life.
- **No-polling policy.** Only genuinely continuous work ticks, and only its
  active set:
  - atmos, heat and fire in Rust;
  - AI while engaged (perception itself is proximity watches);
  - open UIs that opt into live data;
  - engine input and movement.

## 11. Watches

A watch fires when a condition's truth value changes. It is a requirement you
subscribe to transitions of.

```dm
/obj/machinery/alarm/declare(archetype/A)
	..()
	A.watch(/watch/air_pressure_band, low = 80 KPA, high = 120 KPA)

/behaviour/air_alarm/on_air_pressure_band(obj/machinery/alarm/alarm, band)   // BAND_LOW, BAND_OK, BAND_HIGH
	alarm.set_alert_level(band == BAND_OK ? ALERT_NONE : ALERT_WARNING)
```

- **Sources:**
  - **Rust simulation values** (gas, heat, power) are watched *in Rust*, where
    the data lives, through core `watch` and the generic watch registry
    (`rust_architecture.md` §4.7). Crossings arrive as typed events.
  - **DM observable fields** (§18.3) re-evaluate on their change events.
  - **Relations and slots** re-evaluate on link and slot events.
  - **Spatial conditions** re-evaluate on enter/leave from the spatial index.
  - **Time** uses the scheduler.
- **Rich conditions** compose from requirement types with `ALL`, `ANY` and
  `NOT` (as DEF composites), plus temporal wrappers:
  - `/watch/held_for`: a condition true for a duration;
  - `/watch/count_within`: N events within a window;
  - bands with hysteresis.

  Each watch declares its dependencies once. It's evaluated only when a
  dependency changes, never polled.
- **Dynamic watches** are owned edges, cancelled with their owner. For example,
  an AI calls `watch(src, /watch/in_range, target = T, range = 7)` and gets
  `on_in_range`.
- **The rules engine's** hold, band and threshold logic becomes this evaluator
  for DM data.

## 12. Rates

A rate-valued field is exact at any moment and never ticks:

```dm
/obj/item/weldingtool/declare(archetype/A)
	..()
	A.rate("fuel", min = 0, max = 20, on_empty = /event/fuel_empty)
	A.add(/behaviour/burns_fuel, rate = "fuel", per_second = -0.05)

/behaviour/burns_fuel
	requires = list(/requirement/lit)

/behaviour/burns_fuel/on_activated(obj/item/weldingtool/W)
	rate_contribute(W, "fuel", src, config_of(W, "per_second"))

/behaviour/burns_fuel/on_fuel_empty(obj/item/weldingtool/W)
	W.set_lit(FALSE)
```

- **Representation.** The value is closed-form between events: an anchor value,
  an anchor time and the net rate. `rate_value(W, "fuel")` computes the current
  value in O(1).
- **Contributions are edges** from their source. They're removed when the
  source goes or the gating requirement fails, and the net rate is re-anchored
  on every change.
- **Thresholds** (`on_empty`, `on_full`, declared crossings) schedule an exact
  crossing timer. Changing the rate reschedules it.
- **Other shapes:** exponential approach to a target (`RateModel::Relax`);
  sums of linear terms stay linear.
- **Random occurrences at a rate** are Poisson timers (§10).
- **Coupled or non-linear systems** belong in the Rust simulations. When there's
  no closed form, use a root-find at re-anchor, or coarse stepping as a last
  resort.
- **Rust-owned stores** (cells, SMES, reactor rates) are the same model, from
  `core::rate` (`RateStore::model`).

## 13. Tasks

A task is a rich edge between its participants. It completes after a duration,
unless its requirements break first.

```dm
/task/tool_use
	var/tool_quality
/task/tool_use/check(datum/check/C, mob/user, atom/target, obj/item/tool)
	C.can_reach(user, target)
	C.holding(user, tool)
	C.tool_quality(tool, tool_quality)

/task/tool_use/weld_door
	tool_quality = TOOL_WELDING
	duration = 5 SECONDS
/task/tool_use/weld_door/check(datum/check/C, mob/user, obj/machinery/door/door, obj/item/weldingtool/tool)
	..()
	C.tool_active(tool)
	C.require(!door.welded, "[door] is already welded.")
/task/tool_use/weld_door/complete(mob/user, obj/machinery/door/door, obj/item/weldingtool/tool)
	door.set_welded(TRUE)

// caller:
start_task(/task/tool_use/weld_door, user, door, tool)   // returns the task, or the failure reason
```

- **When checks run:**
  - at start and at commit, always;
  - in between, only when a captured dependency fires (§8), coalesced to once
    per tick.

  Correctness only needs the start and commit checks. The checks in between
  exist only to cancel early for UX.
- **Commit is atomic.** The requirements are re-checked immediately before
  `complete()`, which may not sleep (checked statically).
- **Exclusivity falls out of the requirements.** The first task to complete
  changes the world, so a conflicting task fails at commit. Compatible tasks
  both complete. The one rule: **a task's requirements must guard its own
  effect** (`!door.welded`). dm-health warns when `complete()` writes a field
  the check never reads.
- **Claims** are optional UX (don't start a 10-second job that can't finish;
  show "in use"). A claim is a relation plus a requirement over it, not a
  separate mechanism.
- **Participants** are non-null in every hook, and a participant's deletion
  cancels the task with a reason.
- **Progress bars** are a view of the task, not a loop.
- **Prompts** are tasks with an answer. A stamp stops a stale confirmation:

```dm
/prompt/vend/check(datum/check/C, mob/user, obj/machinery/vending/V, datum/stock_entry/entry)
	C.can_reach(user, V)
	C.unchanged(V)                     // V's revision when the prompt opened
	C.require(entry.amount > 0, "[entry.name] is sold out.")
/prompt/vend/answered(mob/user, obj/machinery/vending/V, datum/stock_entry/entry, choice)
	...
```

- **Stamps** are optimistic concurrency. `C.unchanged(X)` compares X's revision
  counter at commit with the value captured at start.
- **Legacy escape hatch.** `AWAIT_TASK(...)` keeps a sleeping proc for flows
  not yet converted. On resume it returns false if any participant or
  requirement broke. dm-health rejects any object local or field read after the
  await without re-validation.
- **Test clock.** Tests fast-forward tasks and timers with it.

### 13.1 Why sleeping procs are the problem

A sleeping DM proc (`sleep`, `spawn`, `stoplag`, `do_after`, `tgui_input`)
keeps strong references in its locals, arguments and `src` for the whole wait.
That causes two failures:
1. **A pinned object can't be freed,** which leads to a hard delete.
2. **The proc resumes on a world that changed:** a deleted or moved target, a
   used tool, a spent item. That's where runtimes and duplication exploits
   come from.

Tasks, owned timers and prompts-as-tasks remove nearly all of this.

## 14. Destruction

`lifecycle.md`'s transaction (LC1, built on `rewrite/ledger-joint`) stays.
This model changes it in five ways:

1. **Survivors leave first,** outermost first, while everything is intact:
   `TRANSFER` and `SPILL` resolve before anything is marked. The mind phase
   (`lifecycle.md` phase 0.5) becomes one case of this general rule: any
   transfer whose destination is outside the dying tree runs early.
2. **Then the rest is marked dying.** From this point `link()` to anything in
   the dying set is refused.
3. **Edges are torn down,** grouped by kind. The surviving end's `on_unlink`
   receives `reason = RELATION_DESTROYING`, and hooks can ask
   `holder_destroying()` to skip pointless re-derivation.
4. **External teardown:** Rust unbind (batched), scheduler edges, client views.
5. **Leaf-first finalisation,** in deterministic slot order. A destroy requested
   by a hook joins the same **worklist**. It never recurses, so explosions,
   z-level release and round end all batch.

Further rules:
- **Fast path.** An entity with no edges, no teardown behaviours and no
  bindings leaves its owner slot, sets its flag and is freed by reference
  counting. That's a few microseconds, against today's Destroy chains.
- **Latent contents** are deleted as data and never materialised.
- **Pooling** becomes safe for high-churn objects (projectiles, effects, damage
  packets), because relations guarantee nothing holds a stale reference.
- **SSgarbage becomes a verifier.**
  - In test builds, every destroyed object is checked. Any survivor fails the
    test, with its holder named by a find-references search.
  - In production it's a cheap sampler plus the hard-delete fallback.
  - Most `QDEL_HINT_*` handling goes.
- **`qdel` is private to the framework.** Callers state intent through
  `consume`, `replace_with`, lifetime/`expire`, slot operations,
  `delete_on_death` and `destroy(target, cause)`. A lint bans bare `qdel` in
  normal code.
- **Legitimate leftover `Destroy()`** is rare: a real consequence outside the
  object's declared relations. It's justified with `// LIFECYCLE:`, preferably
  written as a hook on the other party's relation, and the count is ratcheted.

## 15. Initialization and startup

- **Archetype-driven init.** `Initialize` runs the archetype's init plan. Types
  don't override it, and it's sealed (`SHOULD_NOT_OVERRIDE`) once migration
  completes.
- **Batched by kind after map load:**
  - bulk registry appends;
  - one relation-resolution pass (mapper-declared links, instead of each
    console calling `locate() in range`);
  - one flush to Rust (R10 boot batching);
  - batched lighting.
- **No per-instance signal registration** for behaviours declared on a type
  (§6.2).
- **Latent by default** for closet, crate and vending contents (C9) and machine
  parts (C6), so far fewer atoms exist.
- **Assets** (spritesheets) are generated at build time by the icon pipeline
  and cached, not at boot.
- **The wiki** is built lazily on first request.
- **Later:** Rust-side DMM parsing with prebuilt variable lists.

**Measured baseline** (test map, `virgo_minitest`, benchstore run): 16.5 s in
total.

| Subsystem | Time |
|---|---|
| Assets | 6.9 s |
| Atoms | 3.9 s |
| Wiki | 1.4 s |
| Atmospherics | 0.9 s |
| Lighting | 0.6 s |
| Early Assets | 0.6 s |
| Shuttles | 0.5 s |
| HoloMiniMaps | 0.4 s |
| Mapping | 0.3 s |

**Estimates, to be confirmed with the bench store:**
- the test map drops from 16.5 s to roughly 4–6 s;
- live-map init, which atoms dominate, gets roughly 2–4× faster.

Build-time assets and the lazy wiki are independent quick wins.

## 16. UI (tgui)

### 16.1 Before

The space heater today, from `spaceheater.dm` and `SpaceHeater.tsx`:
- **Type drift:** `power` is declared `BooleanLike` in TS, but DM sends a
  number.
- **Unvalidated parameters:** `text2num(params["newtemp"])` on raw input.
- **Stale viewers:** other viewers aren't updated.
- **Manual processing:** `START_MACHINE_PROCESSING` is called by hand.
- **Ledger bypass:** `C.loc = src` skips the containment ledger.
- **Hidden rule:** `panel_open` is enforced only when an action arrives, so the
  UI can't show a disabled button.

Across the codebase there are 419 `tgui_data` providers, 417 TS interfaces and
299 manual `SStgui.update_uis()` calls. Updates are already event-driven, with
only 2 polling UIs, but manual.

### 16.2 After

```dm
/ui/space_heater
	interface = "SpaceHeater"
	fragments = list(/ui_fragment/toggle, /ui_fragment/regulator_target, /ui_fragment/slot_cell)

/ui/space_heater/can_act(mob/user, obj/machinery/space_heater/heater)
	return heater.panel_open
```

- **Fragments.** Generic behaviours and components ship UI fragments: a data
  block plus a TS component.
  - A component's fragment (`/ui_fragment/regulator_target`) comes from its
    schema, including a range-validated `set_target` action.
  - The cell fragment is bound to the slot and exists only while a cell is in
    it, so the empty case is handled once, in the shared `SlotCell` component.
- **Custom data** uses a plain `data()` proc. Optional values are handled
  explicitly: dm-health types `slot_item()` as nullable and forces the check.
  An absent key becomes an optional TS field.

```dm
/ui/space_heater/data(obj/machinery/space_heater/heater, datum/ui_data/D)
	D.set("target", heater.get_target())
	var/obj/item/cell/C = heater.slot_item("cell")
	if(C)
		D.set("charge", C.percent())

/ui/space_heater/act_set_mode(mob/user, obj/machinery/space_heater/heater, mode as num)
	heater.set_mode(mode)
```

- **Change-driven.** A UI session is a rich edge from user to object. Its status
  is the edge's requirements (`can_see`, `in_range`, `conscious`), so nothing is
  polled. `data()` re-runs only on the object's change events, and only changed
  fragments are resent. That's cheap in DM, with no nested-list diffing.
- **Actions** are `act_<name>` procs with typed parameters (`as num`/`as text`).
  They're validated centrally against a schema, and `can_act()` plus the
  requirement library decide whether an action is enabled.
- **Generated types.** dm-health reads `data()`, the fragments and the `act_*`
  signatures from the AST and generates both the TS types and the server-side
  parameter schema. Drift like `power: BooleanLike` becomes impossible.
- **The client** gets `useUi<SpaceHeater>()` with a typed `act()` and
  `can.<action>` carrying reasons. Buttons disable themselves with the same
  reason the server enforces.

## 17. Rust interop

- **Generated component types.** A `#[vg::component]` in Rust is generated into
  a DM `/component/<name>` type with its schema: names, units, ranges, defaults
  and roles.
- **Config in the declaration.** `A.add(/component/heat_regulator, max_power =
  ...)` puts the config next to the component it belongs to, replacing loose
  `init_*` variables on prefabs. dm-health validates names, units and ranges
  against the generated schema. The values become the bind-time seeds.
- **Events.** Rust events are generated `/event/<component>_<event>` types,
  handled by any behaviour on the entity as `on_<component>_<event>`.
- **Fragments.** Component UI fragments are generated from the schema (§16).
- **One schema feeds everything:** DM accessors, declaration validation, event
  hooks, UI fragments, save schema, variable-viewer metadata, and TS types.
- **Handles only.** Rust never holds a persistent BYOND reference. The CI check
  enforces it.

## 18. dm-health: the static half

`tools/dm-health` (OpenDream AST, flow analysis, access contracts) enforces
what the runtime can't.

### 18.1 Null safety

1. **Flip the default.** Fields, returns and parameters are non-null unless
   marked `nullable`. A baseline covers existing code, strict mode applies to
   new modules, and a ratchet drives the rest.
2. **Narrowing rules.** Only locals and `readonly` fields stay narrowed across
   calls. Any call or suspension (`sleep`, `input`, await) resets narrowed
   fields. That turns "needs review" into an error.
3. **Builtin stubs.** Nullable returns for `locate`, `get_turf`, `get_step`,
   list indexing, `text2num` and `input`. `istype` narrows.
4. **Strict modules** ban untyped `var`, the `:` operator, `vars[]`, `call()`
   and `text2path`, except with an explicit `// dm-health: unchecked`.
5. **Definite assignment.** A non-null field may be set in `Initialize`,
   Kotlin's `lateinit`. The checker proves it's set before use.
6. **Contracts from declarations.** Slot and relation variables are
   framework-write-only. Required relations are non-null. Behaviour data roles
   set their contracts. `slot_item()` returns nullable. Most contracts need no
   comments.

### 18.2 Structural tools against null

In order of preference:
1. **Gate by composition** (§7, §13).
2. **Nullable as part of the type,** with forced narrowing.
3. **Group values that are null together** into one relation or sub-object:
   one presence check, and no half-set state.
4. **Required relations,** which are non-null by construction.
5. **Null objects for DEFs only:** `/datum/material/none`, `NO_SPECIES`.
6. **Zero-or-one iteration** over slot contents.
7. **Definite assignment** in init.

### 18.3 Access and mutation contracts

- **The existing contracts:** `public`, `private`, `protected`, `nonnull`,
  `nullable`, and `readonly` on globals.
- **New `internal`** (module-private, using the README module boundaries).
  This replaces most of `check_grep.sh`'s access rules, about 15 of its 65
  checks, for example:
  - "life scheduler: wake and hibernate in one place";
  - "gas mixture mirror writes";
  - "robot cell writes outside the power ledger";
  - "medical condition severity writes";
  - "organ damage outside the body";
  - "call_ext outside generated bindings";
  - "DM copies of Rust state".
- **New `readonly` on fields:** write-once at init. That's the static half of
  DEF freezing.
- **New `observable`:** writes only through the field's setter (hand-written,
  or the generic `set_observed(src, "field", value)` whose name argument is
  checked). Setters emit `/event/changed`, which keeps watches, UIs and tasks
  current.
- **About 20 syntax and style checks** move from regular expressions to precise
  AST rules, for example:
  - "improperly pathed static lists";
  - "var in proc args";
  - "timer flag sanity";
  - "proc ref syntax";
  - "ambiguous bitwise or";
  - "string-built reactive keys".
- **Maps, HTML and changelogs** stay as `ci-suite` steps.

### 18.4 Framework rules

- **`..()` rules.** `SHOULD_CALL_PARENT` procs must call `..()` on **every
  path**, and first where order matters (`declare()`). DreamChecker only checks
  that it appears somewhere.
- **Dependency completeness.** Fields and procs read by a requirement's
  `check()`, a watch or a UI `data()` must be covered by their declared or
  captured dependencies. This catches stale filters.
- **Task guards.** Warn when `complete()` writes a field its `check()` never
  reads.
- **Suspension points.** An error on any object local or field read after an
  await or sleep without re-validation.
- **Event typing.** `emit` arguments are checked against `deliver` and the hook
  signatures.
- **Generation.** TS types and UI parameter schemas come from `data()` and the
  `act_*` procs (§16).
- **Declaration validation.** Config keys, units and ranges are checked against
  behaviour and generated component schemas.
- **No sleeping handlers** in events, `complete()` or hooks.

## 19. Error classes removed

| Error class | Removed by |
|---|---|
| Hard deletes, dangling references | ownership and relations (§4, §5); SSgarbage as verifier |
| Null-partner runtimes | participants resolved; required relations; typed nullability |
| Processing dead objects, forgotten `STOP_PROCESSING` | scheduler edges (§10) |
| Timers firing on deleted objects | owned timers |
| Leaked signal registrations | subscription edges |
| do_after on a deleted or moved target, double-spend across sleeps | tasks (§13) |
| Stale confirmations and prices | prompt stamps |
| Forgotten `..()` | enforced statically on every path; sealed entry points; merged declarations |
| Stale UIs, missed `update_uis` | change-driven UI (§16) |
| DM↔TS and DM↔Rust drift | generated glue (§16, §17) |
| Unvalidated tgui and Topic parameters | action schemas |
| Missed wakes | observable setters; the dependency audit (§10) |
| Flags out of sync | declared state machines |
| Mutated shared definitions | frozen DEFs |
| String type paths | a lint (the headset bug) |
| Unit mix-ups (deciseconds, kPa) | unit-typed config and fields |
| Re-entrant event loops | re-entrancy guards and depth limits |
| Hand-rolled cooldown bugs | timers and rates |

## 20. Performance, memory and risks

| Risk | Mitigation |
|---|---|
| Indirection overhead in DM (proc calls around 1 µs, table lookups) | precomputed archetype tables; requirement bitmasks; no per-call allocation; batch procs for hot kinds; per-behaviour metrics; bench gates in CI |
| DM numbers are floats exact only to 2^24, so a bitmask variable holds about 24 flags | the framework spreads masks over several variables or packed lists and hides it |
| Edge memory | light edges are about 32–48 B, lazy, and only on targets something points at. They replace hand-rolled back-lists and `datum/weakref` objects (100+ B each) |
| Debuggability ("why didn't it run?") | variable-viewer panels showing the archetype, requirement bits with reasons, timers, watches and edges; an "explain" trace per entity; dm-health's viewer showing each prefab's static composition |
| Learning curve | a small vocabulary (§23); a cookbook of real conversions; boot and CI errors that name the fix |
| Two systems during migration | ratchets and codemods; finish one domain completely before the next |
| Ordering and cascades | deterministic default order; declared before/after; deferred delivery for cascades |
| dm-health depends on OpenDream's parser keeping up with BYOND 516, plus a .NET bridge in CI | pinned versions (hash-checked); loud failures on parse gaps; tracked as a real risk |
| Boot cost of building archetypes | lazy, on first instantiation; cached |
| Compile time grows with the type count | offset by flattening prefab trees; tracked in the bench |
| Balance drift (Poisson and rates replacing per-tick `prob`) | same-mean continuous equivalents; differential tests against the old tick behaviour |
| Two scheduler models (DQ Medical's life systems) | converge into one model with DQ Medical |

## 21. Plan

Frameworks first. Callers migrate later, behind ratchets. Tests are written
now and run when the testing freeze lifts. Ports are verified with
differential tests (old against new on the same inputs), not by inspection.

| Track | Scope | Depends on |
|---|---|---|
| **A: Kinds, ownership, relations** | `object_kind`; the ledger generalised to datum slots; relation kinds (light and rich edges, shapes, `holds_while`, hooks, lifetime policies); `link`/`unlink`/`linked`; derived spatial relations; `REF_*` from LC2 re-expressed as relation kinds; grants re-expressed as a relation kind; destroy-pipeline changes (§14) | LC1–LC3 (built) |
| **B: Scheduler** | wakes; owned timers; Poisson timers; the watch evaluator (DM side; Rust side from `rust_architecture.md`); rate fields and contributions; periodic behaviours with staggering; tasks and prompts with stamps; the test clock; the missed-wake audit; MC integration on the Rust reactor | A (edges) |
| **C: Archetypes and behaviours** | `declare()` builder; archetype build and validation; bundles; behaviour singletons, config, interfaces, state machines; requirement types and the `/datum/check` library with dependency capture and messages; typed events with static dispatch, phases, delivery modes and bubbling | A; B for triggers |
| **D: Startup quick wins** | build-time assets; lazy wiki; batched post-load init passes; bench before and after | none; can start now |
| **E: UI** | `/ui` types, fragments, change-driven sessions, action schemas, generated TS types | C; F for generation |
| **F: dm-health** | default-non-null flip with baseline; builtin stubs; narrowing rules; strict modules; `internal`, `observable`, field `readonly`; contracts from declarations; every-path `..()`; dependency-completeness, task-guard and suspension-point rules; event typing; TS and schema generation; porting the `check_grep` access and syntax rules | parallel to A–E |
| **G: Migration** (later) | domain by domain: prefabs onto declarations, overrides and `qdel` onto verbs, `process()` onto behaviours and rates, `do_after` onto tasks, signals onto events, UIs onto `/ui`. Ratchets on every counted pattern | A–F |

**DQ Medical** reviews this design before code lands. They own mob Life, bodies,
organs, species and afflictions. Their life systems converge into behaviours
and the scheduler (B/C), and their grant kinds (TRAIT, GENE) plug into A.

**Definition of done for the frameworks:**
- every section here is implemented;
- the tests pass once the freeze lifts;
- the bench shows no regression;
- the cookbook covers each primitive with a real conversion.

## 22. Before and after, in brief

| Concern | Before | After |
|---|---|---|
| Machine composition | subtype tree with overrides | prefab `declare()` with bundles, behaviours and components |
| Periodic work | `START_PROCESSING` plus `process()` polling | requirement-gated behaviours; timers, watches and rates; hibernation |
| Cross-object links | var plus hand-written unlinking in both Destroys | relation kind with hooks and conditions |
| Timed actions | `do_after` sleeping loop plus manual re-checks | task with captured dependencies and atomic commit |
| Confirmation prompts | sleeping `tgui_alert` plus stale state | prompt task with a stamp |
| Destruction | `Destroy()` override chains and `qdel` everywhere | declared policies; the transaction; verbs; fast path |
| UI | `tgui_data`, `tgui_act`, `update_uis`, hand-written TS types | `/ui` with fragments, generated types, change-driven sessions |
| Null handling | scattered `if(x)` and `QDELETED` checks | participants; typed nullability; required relations |

## 23. Glossary

- **Archetype:** the compiled composition of a type: behaviours, config,
  requirement masks, dispatch tables, slots, relations, UI and init plan.
- **Behaviour:** a DEF singleton holding generic logic, configured per prefab.
- **Bundle:** a reusable, parameterised group of declarations.
- **Component:** a Rust-backed behaviour generated from `#[vg::component]`.
- **DEF / SERVICE / LOCATION / ENTITY:** the four object kinds (§3).
- **Edge:** one instance of a relation. Light edges are adjacency entries; rich
  edges are datums.
- **Fragment:** a reusable UI piece, with a data block and a TS component.
- **Interface:** a DEF contract between behaviours (`provides`/`needs`).
- **Observable field:** a DM field written only through its setter, which emits
  change events.
- **Prefab:** a thin type that is mostly a `declare()`, used for mapping and
  `new`.
- **Prompt:** a task that waits for a player's answer.
- **Requirement:** a DEF predicate with declared dependencies. `/datum/check`
  is its fluent form.
- **Stamp:** a revision captured at start and compared at commit.
- **Task:** a rich edge between participants that completes after a duration,
  unless its requirements break.
- **Watch:** a subscription to a requirement's transitions.

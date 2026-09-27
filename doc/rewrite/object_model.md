# Object model: kinds, ownership, relations, behaviours, scheduling

Status: **authoritative design, not an implementation status report**. It
supersedes `lifecycle.md` §4 (declared references) and revises its existing
destroy transaction (§14). It sits beside `rust_architecture.md`,
which covers the Rust side. Existing callers have not migrated to this model.
Section 2 distinguishes working foundations from planned prerequisites;
section 21 defines measured, domain-sized migration steps.

## 1. Goals

The aim is DM code with the error surface of a well-typed, ownership-based
system:

- **No hand-written lifecycle.** Remove per-type `Initialize`, `Destroy` and
  `process()` wherever a framework can own the work.
- **Fewer dangling references and hard deletes.** Every entity has one lifetime
  authority. References that must unlink or constrain lifetime are managed
  relations; ordinary short-lived borrows need not become edges.
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
5. **Fail in CI or at boot, not on first use.** CI validates all declared
   archetypes, including uncommon and unmapped types (§6). dm-health checks
   what can be proved statically; runtime audits check missed wakes and leaks.
6. **Everything is inspectable.** Owners, edges, requirement bits, pending
   timers and watches, and the reason a behaviour is asleep are all visible in
   the variable viewer.

## 2. What exists already

This design unifies pieces that exist in the current tree and proposals that
have not landed. Check each prerequisite against the compile manifest rather
than assuming a design document proves it exists.

| Piece | Current checkout | Model's intended next step |
|---|---|---|
| Containment ledger, atom slots, latent state | `code/datums/containment/` | extend ownership to datum slots (§4) |
| Destroy transaction and declared links (LC1–LC3) | `code/datums/lifecycle/{transaction,links,verbs}.dm` and `code/datums/containment/lifecycle.dm` | extend the existing destroy pipeline and express links as relation kinds (§14) |
| Source-tracked ability grants | `code/datums/abilities/ability.dm`; callers revoke manually | tracked grant lifetime (§5.6) |
| Compact interactions and `REQ_*` predicates | `code/datums/interactions/`, `code/__defines/predicates.dm` | reuse their vocabulary and reason messages in reactive checks (§8) |
| Mob life systems and hibernation | `code/modules/mob/living/life/scheduler.dm` | share scheduling primitives before changing the mob-facing model (§10) |
| Reactor: timers, wake lanes, rate models | `verdigris/core/src/reactor.rs`, `code/__defines/reactor.dm` | scheduler backend (§10) |
| Rules engine | `code/datums/rules/` | reuse threshold and hold semantics in watches (§11) |
| Registries | `code/datums/registries.dm` | optionally derive membership from relations where useful (§5) |
| Generated Rust bindings | `code/__defines/verdigris/_bindings.dm` | add component schemas only after the binding design is proven (§17) |
| dm-health | `tools/dm-health/`; current checks described in its README | implement strict contracts incrementally (§18) |

## 3. Four kinds of object

The proposed `object_kind` classifies lifetime and mutation policy. It is not
implemented yet. Converted types declare one kind; unconverted datums keep
their existing lifecycle until a domain migration makes the classification
enforceable.

| Kind | What it is | Lifetime | References to it |
|---|---|---|---|
| `KIND_DEF` | authored definition data: species, materials, reagents, gas types, recipes, behaviours, requirements, events, relation kinds, bundles, UIs, task types | created at boot, configuration frozen | plain variables, never tracked |
| `KIND_SERVICE` | singletons with state: subsystems, managers, registries | the round | plain variables, never tracked |
| `KIND_LOCATION` | turfs and areas | the life of their z-level (expedition z-levels are recycled) | plain variables; z-level release must audit or invalidate external references |
| `KIND_ENTITY` | everything else: items, mobs, machines, minds, bodies, afflictions, reagent holders, UI sessions, running tasks | exactly one lifetime authority | owning slot, tracked relation, or scoped borrow (§4, §5) |

- **Freeze authored DEF configuration, not derived caches.** Existing
  definitions such as interactions fill compiled predicates on first use.
  Move those caches into explicitly mutable storage or compile them before
  freezing. dm-health should reject direct configuration writes where it can
  prove them; runtime writes through framework setters can be checked too.
  Plain DM field assignment cannot be assumed to pass through a runtime guard.
- **Entity relations are the primary tracked case.** A variable holding a DEF
  or SERVICE is ordinarily plain. LOCATION references may also need a tracked
  handle when an expedition z-level can be recycled while the holder survives.

## 4. Ownership

Every converted entity has exactly one **lifetime authority**: the thing whose
release or destruction ends or transfers its lifetime. For atoms this is a
holder slot or the turf's world slot. For non-atom entities it is a slot on an
entity or service. The authorities form a tree rooted in services and
locations. This rule does not mean that every ordinary DM variable is an
owning pointer or must be represented by an edge.

- **One slot contract covers atom contents and datum children.** Atom slots
  use the containment ledger as their indexed implementation, while datum
  slots use the ownership tree; both expose the same claim, release, destroy
  policy and query semantics. BYOND `loc` remains the physical authority for
  atoms. Do not allocate a second mutable relation edge for each contained
  atom or maintain a competing contents index.
- **Latent contents are virtual slot entries.** Each carries a type, count,
  aggregate snapshot and optional payload under the same slot policy as a
  live child. Materialization exchanges the virtual entry for live children
  atomically. A connection to a latent entry needs a stable entry handle and
  an explicit materialization or consumption policy; it cannot point to an
  object that has not been created.
- **Destruction means an authority drops its subtree** (§14). Clearing tracked
  edges removes known references, but engine-held references, legacy lists and
  suspended procs may still pin an object; reference counting is not by itself
  proof of reclamation.
- **Nothing converted is unowned** after construction. The constructor and
  transfer APIs must make the handoff explicit. Temporary locals are scoped
  borrows; long-lived caches declare whether they are relations or handles.
- **No nullspace parking.** Things outside the world are either latent data or
  held in a slot.
- **Owned children** that aren't contents (actions, loops, helper contexts,
  afflictions) live in **datum slots**, with the same destroy policies as atom
  slots: `SPILL` where it makes sense, `DELETE`, `TRANSFER(resolver)`,
  `TO_LATENT` and `KEEP_WITH`.

For a hot direct field that mirrors a single owned child, use
`OM_CLAIM_FIELD(owner, field, slot, child)`. The macro checks that the field
exists at compile time; the caller should take a typed child argument because
DM cannot type-check the helper's dynamic field assignment. The helper
validates the existing mirror, sets it before publishing the ownership change,
and rolls it back on failure. Releasing or deleting the child clears the mirror
before publishing the release. The child must be unowned or already in that
same field and slot;
cross-owner transfer remains an explicit release followed by a claim.

## 5. Relations

A **relation** is a typed, framework-managed edge for a non-owning reference
that needs automatic unlinking, a lifetime policy, membership, or a condition.
Ordinary proc locals and short-lived lookups are borrows. Persistent caches
without those semantics may use validated handles. A converted field declared
as a relation is framework-write-only (dm-health, §18); migration must find
legacy writes and callbacks before claiming that guarantee.

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
- **Mutation order.** Linking, replacement, unlink hooks and destruction have
  defined transaction order. Hooks see the old edge as unavailable and cannot
  resurrect a dying endpoint; a hook-requested link or destroy joins a bounded
  worklist. Failed transfers report a reason rather than leaving half a link.

### 5.2 Light and rich edges

- **Light edges** are adjacency entries on both ends, keyed by relation kind,
  holding the partner or a list of partners. The exact representation is chosen
  after an instance census; no per-datum `_edges` field is added without a
  memory benchmark.
- **Rich edges** are `/edge/<kind>` entity datums for relations with state or
  behaviour. Examples: grab, pull, buckle, a tgui session, a running task, a
  grant. Their declaration names one lifetime authority (usually the source's
  slot or a service). Both endpoints index the edge but do not both own it.
- **Costs are measured, not inferred from a datum estimate.** Count both
  endpoint entries, lists, subscriptions, and retained objects at idle and at
  peak. Compare with the mechanism each conversion removes.
- **There is no separate reverse index.** Both ends hold the edge, the way
  Bevy's `ChildOf` and `Children` do. When B dies, the framework walks B's own
  edges, so the cost is proportional to B's degree, not a scan of the world.

### 5.3 Reading relations

- **1:1 kinds** keep a framework-maintained view variable on the source, such
  as `sleeper.console`, so reads cost the same as a plain variable. It is
  non-null for *required* 1:1 kinds only while the declaring behaviour is
  active; loss of the partner suspends or destroys that behaviour before a
  handler can read the view.
- **Other shapes** are read with `linked(src, /relation/x)` as a read-only
  iterable/view. It supports an empty loop without an allocation or null
  check, but never exposes a shared mutable empty DM list. Callers needing a
  mutable snapshot request a copy explicitly.
- **Queries** include `linked`, `linked_to` (the reverse direction), `has_link`,
  and transitive walks up the owner and holder chains.

### 5.4 Derived relations

`in_view`, `near(n)` and `same_area` are queries over a spatial index.
Observers can subscribe to enter/leave changes using chunk or region
subscriptions. Do not materialise an edge for every nearby pair: movement
fanout and retained pair counts would scale with crowd density. Limit and
benchmark active proximity watchers before broad AI or UI migration.

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

Registry declarations currently enroll an entity when its sparse behaviour
runtime is started with `om_behaviour_start(entity)`. Membership is a non-owning
entry in the same `/datum/registry` storage used by materialization registries.
The object-model registry is created lazily, while legacy registries retain
their existing eager build and keyed indexes. `om_registry_members(path, member_type)` returns
a detached snapshot; `om_registry_has(path, entity)` tests one member. Releasing
the runtime or destroying the entity removes membership. Declaration alone does
not enroll newly constructed atoms, and constructor/materialization integration
is a separate migration step for each legacy registry lifecycle.
The two declaration APIs still differ in activation: `A.registry()` follows
behaviour runtime activation, while `REGISTRY_MEMBERSHIP()` follows atom
materialization. Do not declare the same membership through both paths.

### 6.2 Archetypes

- **When they're built.** Runtime instances use a cached archetype, built on
  first use if that is cheaper. CI enumerates and validates every converted
  type's declaration; test boot may prebuild the same set. An unmapped type
  cannot defer a declaration error to its first live-round spawn.
- **Validation errors** fail CI and test boot:
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
- **Instances carry only their own data.** Static behaviour dispatch needs no
  per-instance signal registration. Sparse or dynamically granted behaviour
  state may still need per-instance storage and teardown.
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
- **Per-instance state for statically composed behaviours** can be variables
  on the prefab when almost every instance uses them. Rare or bulky state
  belongs in a lazy, typed sidecar. The behaviour declares its state contract
  and validation checks it; authors should not have to copy a cluster of
  boilerplate fields into every prefab.
- **Per-instance state for behaviours granted at runtime** goes in a lazy
  per-behaviour table on the entity.
- **Heavy simulation state** (heat, gas, power) lives in Rust components
  (§17), with generated DM accessors.

### 7.3 Execution cost

- **Event dispatch uses precomputed handler tables.** It still pays for the
  handlers and any table traversal; benchmark it against the signal path it
  replaces. High-frequency Rust simulation updates stay batched in Rust.
- **Periodic behaviours visit only their active set:** members whose
  requirement mask is satisfied and that are due. Members are spread across
  timer-wheel buckets so the load is staggered.
- **Membership lists** are maintained by the framework, with O(1) add and
  remove.
- **Hot kinds can implement `on_tick_batch(list/members)`,** which avoids a
  proc call per entity.
- **Behaviours report metrics** (calls, time, active count) through sampled or
  aggregated counters so instrumentation does not dominate cheap handlers.

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

The same requirement semantics gate tasks, interactions, UI actions, abilities,
behaviours and relation conditions. Reuse the existing P2 `REQ_*` predicates,
reasons and selection rules as the starting vocabulary; a new `/datum/check`
API must adapt them, not create a second set with different meanings.

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
- **Explicit dependencies first.** Built-in checks declare their dependencies:
  `can_reach` follows movement of both parties, `holding` follows equip and
  unequip, and `tool_active` follows the tool's state. Running an arbitrary DM
  expression cannot reveal which fields it read. A captured dependency is
  valid only for a checker whose read path is instrumented and tested.
- **Coarse fallback.** A raw `require(expression)` subscribes to documented
  coarse participant changes and is rechecked at the action's commit. If
  those changes do not cover every mutation, the author must declare more
  dependencies or use a synchronous check. dm-health can suggest and verify
  statically visible reads, but dynamic dispatch and reflection remain
  explicit proof gaps.
- **Cost ordering.** The library orders checks by cost and stops at the first
  failure.
- **Consistent messages.** The library words failures the same way everywhere,
  and the same text drives disabled-button tooltips (§16).
- **Requirement state.** An active requirement can have a cached bit, updated
  when a complete dependency fires. Store sparse state for entities with no
  active gates; measure the bit and subscription overhead per instance.

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
  cleaned up with either end. Event delivery and writes through observable
  setters must remain one coherent path during a converted domain's rollout.
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

Broad typed-event observers live in a singleton `/datum/object_model/global_observer`
subtype, started by `om_global_observer(path)`. Its shared plan may use
`from_any()` and allocates one subscription per rule. Per-entity behaviour
plans reject `from_any()` so a global listener cannot accidentally allocate
one token per entity.

The current bridge for existing signals is `owner.Observe(target, COMSIG_*,
PROC_REF(handler))` or `owner.ObserveSet(targets, COMSIG_*, PROC_REF(handler))`.
The owner retains one observation for each signal and handler; it owns cleanup
on either endpoint's deletion. Repeating `ObserveSet` reconciles membership,
and an unchanged set returns early. `Unobserve(signal, handler)` removes one
watch. `on_lost` may name a callback for target
deletion. Use a semantic relation only when the edge itself models game state;
an interest in a target's movement needs an observation alone. Secbot
surrender, door blockers, material services and container connections use
this bridge.
For a legacy component or service with many fixed `COMSIG_*` handlers on one
parent, use a proc-local static `signal => PROC_REF(handler)` table with
`RegisterSignalMap(parent, handlers)` and `UnregisterSignalMap(parent,
handlers)`. Material responses and service diagnostics use this path: the
existing signal table owns the hooks, preserves return bitfields and delivery
order, and cleans them on listener deletion without allocating an `Observe`
datum for every handler. A transferable listener must unregister from its old
parent before registering on the new one. Use `Observe` for sources that change
over time or need endpoint-loss callbacks.
At 250 material assemblies with three movable ancestors, the movement-watch
benchmark measured initial bind at 68.3 µs/service and moved rebind at 54.0
µs/service, down from 194.7 and 226.9 µs/service with the prior per-target
relation wiring. An unchanged rebind rose from 14.9 to 18.0 µs/service.
Process memory sampling was unavailable in that run; the Rust heap sample was
unchanged, but does not measure DM datum or list memory.

## 10. Scheduler

Converted work that happens later, repeatedly or conditionally uses one
scheduling API. The MC is its budgeted executor, and the Rust reactor (timer
wheel, wake lanes, `RateModel` crossings) is its backend. Existing mob Life
and other subsystem schedulers coexist during migration; share reactor
primitives first and remove a domain's old path only after parity is proved.

| Primitive | API | Replaces |
|---|---|---|
| **Wake** | `wake(entity, /behaviour/x, reason)`, coalesced per tick | ad-hoc recompute calls; generalises `life_wake` |
| **Timer** | `timer(entity, delay, /behaviour/x, key)` → `on_timer(entity, key)`; owned by the entity and cancelled when it dies | `addtimer`/`deltimer` (835 sites) |
| **Random timer** | `timer_random(entity, mean, /behaviour/x, key)`: Poisson scheduling of the next occurrence | per-tick `if(prob(x))` in `process()` |
| **Watch** | §11 | "check every tick whether X crossed Y" |
| **Rate** | §12 | ticking for drain, decay, charge, cooldowns and burn-down |
| **Periodic behaviour** | `period` on a behaviour; only the active set, staggered | 445 `process()` procs, 224 `START_PROCESSING` calls, list-walking subsystems |
| **Task** | §13 | `do_after` (660), `spawn` (677), `sleep` (546), `tgui_input`/`tgui_alert` (2,440) |

For one-shot calls to a proc on the owner, `After(delay, PROC_REF(handler))`
returns a cancellable owned entry. `EnsureAfter(delay, PROC_REF(handler))`
instead keeps at most one pending call for that proc and preserves its first
deadline. `ReplaceAfter` moves the deadline; `CancelAfter` cancels it;
`PendingAfter` inspects it. The keyed entry is removed before invoking the
handler, so the handler can schedule itself again. These proc-keyed calls need
no timer field or completion adapter. Use ordinary `After` entries when
several independent calls to the same proc must coexist.

- **Hibernation applies where dependencies are complete.** An entity with no
  active behaviours leaves that scheduler's active set; its ownership and any
  subscribed watches still have a measurable cost.
- **Missed-wake audit.** This generalises today's
  `MOB_HIBERNATION_AUDIT`. In test builds, sleeping behaviours' requirements
  are periodically re-evaluated, and a mismatch fails the test. Missing
  dependencies surface immediately.
- **Mob Life** runs its existing ordered system composition inside one scheduled
  behaviour per living mob. This preserves phase order, shared context and the
  internal wake-bit scheduler while using the common behaviour runtime for cadence.
  It is not one independently timed behaviour per Life system.
- **Scheduled behaviours (implemented, opt-in).** A behaviour can declare
  `run_change_mask`, `run_owned_inputs`, `run_relation_inputs`, `run_events`,
  and `run_period`. Its `on_run(entity, seconds, config)` runs once per queued
  owner and returns zero to sleep, a positive delay for its next run, or null
  for `run_period`. A periodic behaviour can opt into `run_shared_cadence`:
  `SSreactor` distributes all active owners of that behaviour type across shared
  tick slices, while an explicit per-owner due time still uses its native timer.
  Other scheduled behaviours retain their own pending state and deadline; one
  native `REACT_AT` token per entity arms the earliest outstanding due time.
  Local, owned and related tracked writes, relation membership and typed
  events wake only declared dependents. The Rust reactor wakes the owner at
  its deadline, then `SSreactor` budget-dispatches its queued DM `on_run` work.
  Native-domain watches and rate crossings use the same reactor. An opt-in
  `sleep_violation()` participates in the reactor's missed-wake audit.
- **Dispatch diagnostics and priority (implemented).** Scheduled behaviours
  declare `run_priority`, `run_max_lateness` and `run_cost_hint_ms`. The reactor
  records exclusive callback cost, queue age, missed deadlines, work units,
  deferral reasons and bounded overrun incidents. Shared cadence and pending
  runtimes use measured inclusive cost to stay within the tick budget, with
  age promotion to avoid starvation. `Scheduler Diagnostics` shows the live
  state to admins; benchmark reports retain the same counters. See
  `doc/rewrite/scheduler_diagnostics.md` for the API and attribution limits.
- **Life migration status.** AFK and ambience have independent behaviours, and
  living Life has one scheduled frame behaviour on the shared sliced cadence.
  Awake frames have no recurring native timer; deferred Life wakes retain exact
  per-mob deadlines in the reactor wheel. `SSmobs` registers living mobs
  into a pending startup queue (including one initial scan for pre-existing
  mobs), starts their behaviours in bounded batches, and keeps nonliving mobs
  on its legacy list. It still owns the Life hibernation audit and profiling.
  Producers can call typed `wake_life(event_or_family, reason)`; that bridge
  maps event or system-family paths to the existing internal wake bits.
- **Local clocks.** Behaviour deadlines can use per-entity virtual biology,
  decay or action clocks through `run_clock`. Source-owned multiplier and
  inhibition contributions compose; a zero rate parks a virtual deadline
  until resume. `run_set` allows source-stacked suspension of a schedule set,
  including the living biology frame during transformation. Detached organ
  decay uses a scheduled behaviour on the decay clock. These clocks do not
  change the real-time cadence of a living Life frame. Stasis and acceleration
  choose how many biological steps are due; the normal frame runs once, and
  only systems explicitly audited with `biology_catchup` receive extra
  `tick_biology` passes with a fresh context per step. A per-frame cap bounds
  catch-up work. Hibernation does not replay its elapsed biology on a later wake.
  Presentation, actions, status counters and advanced disease symptom timers
  retain their real-time semantics unless separately migrated.
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

  Each watch declares its dependencies once. Converted watches evaluate on
  those changes; a test audit rechecks sleeping watches to detect missing
  producers. Any fallback audit or coarse subscription has a measured cost.
- **Dynamic watches** are owned edges, cancelled with their owner. For example,
  an AI calls `watch(src, /watch/in_range, target = T, range = 7)` and gets
  `on_in_range`.
- **The rules engine's** hold, band and threshold logic becomes this evaluator
  for DM data.

### 11.1 Derived caches

**Implemented core API (September 2026).** A behaviour may declare
`derived_input_mask`, `derived_owned_inputs`, and `derived_relation_inputs`.
`om_derived_read(owner, /datum/object_model/behaviour/example)` refreshes a
dirty value synchronously; `om_observe_derived(observer, owner, behaviour)`
keeps it current while observed and coalesces repeated writes. The behaviour's
`compute_derived()` returns the value, `derived_equal()` compares effective
values, and `on_derived_changed()` receives actual transitions. Only the first
read or observer creates cache state. A computed null is retained, recursive
computes are rejected, and a compute retries if its inputs change mid-read.
Value lists need an explicit `derived_equal()` override.

`om_mark_changed(subject, GROUP_MASK)` is the authoritative setter notification.
It invalidates local readers and readers of owned children or related targets.
`om_track_change(subject, ONE_GROUP_BIT)` allocates a revision counter only for
consumers that request one. Ordinary change marks do not allocate revision
arrays. Archetypes declare the permitted bits with `track_changes(mask)`.
Owned relation kinds can transfer lifetime authority alongside link changes;
ordinary links leave lifetime ownership alone. Membership changes invalidate
the relevant derived view even if no tracked field changed.
Physical containment is exposed through the virtual
`/datum/object_model/relation/physical_contents`: queries read BYOND `loc` and
`contents`, and movement publishes membership changes. It keeps no parallel
edge list. A contained atom's tracked write can invalidate a holder's derived
view; ledger totals remain incremental and authoritative for aggregate reads.
The existing slot ledger also exposes a virtual `slot_member` relation. Slot
insertion, removal, reslotting and contribution changes publish typed object
model events, while the ledger remains the sole index and aggregate authority.
Tracked child writes and explicit ledger contribution refreshes invalidate
derived views of the holder. Latent groups have a separate virtual
`latent_slot_member` relation over ledger entries, with count-change events;
they do not masquerade as physical atoms.
An archetype can opt a tracked change group into ledger contribution refreshes
when that member field affects a container aggregate. Unrelated tracked writes
leave the ledger snapshot alone.

The generated stat domain API lives in `tools/object_model/STATS.md`. It emits
named DM getters, base setters and modifier builders from one catalog, without
one datum per stat. Reusable event subscriptions and composed conditions live
in `tools/object_model/SUBSCRIPTIONS.md`. Behaviour activation installs their
plans and deactivation removes them. The `dm-health` `tracked(setter=...)`
annotation checks typed direct and reflective writes in opted-in files; dynamic
receivers still need review. No existing content domain has been migrated to
these APIs yet.

The generic grant runtime now keeps one owned token per entity, behaviour and
source. Removing the source revokes its token and the behaviour deactivates
when its last grant goes away. `om_bridge_signal(source, COMSIG_*, event_path)`
can forward selected legacy signals into typed object-model events. The bridge
is opt-in so existing signal producers and return semantics keep working.

The older `om_cached()` declaration API below remains available. It describes
an alternate scalar-key cache path and should be removed only after its users
have moved to derived behaviours.

A derived value is an ordinary DM compute proc declared once in the type's
archetype, with the fields, slots and relation kinds it reads. Content calls
`om_cached(PROC_REF(compute_value))`; it does not define a datum per cached
field, write a string-key switch, or allocate a dependency list on each read.
The declaration is shared by the type; per-instance cache state is lazy.
The cache retains a computed null, rejects recursive computation of the same
key, and notices writes made while computing.

```dm
/datum/body/om_declare(datum/object_model/archetype/A)
	..()
	A.cache(PROC_REF(compute_factors), fields = list(NAMEOF(src, factor_source_revision)))

/datum/body/proc/factor_values()
	return om_cached(PROC_REF(compute_factors))

/datum/body/proc/factor_sources_changed()
	factor_source_revision++
	om_field_changed(src, NAMEOF(src, factor_source_revision))
```

The example shows the current scalar producer API. Declared slot and relation
operations publish automatically. The linter must require a checked setter
for a declared scalar dependency so ordinary direct writes cannot skip the
notification; the declaration alone cannot intercept DM assignments.

Change tracking is the common producer layer under caches, watches, tasks and
UI sessions. Use the least detailed form that answers the consumer's question:

| Form | Meaning | Typical consumers |
|---|---|---|
| Revision | An input changed since the last read; no history retained | derived cache, stale task check, UI snapshot version |
| Dirty bit | Several changes can be recomputed together at a safe boundary | body factors, appearance, batched UI refresh |
| Transition event | An occurrence or threshold crossing that must not be lost or coalesced as state | alarms, grants revoked, Rust watch crossings |
| Delta journal | Exact members or fields added, removed or changed since a cursor | open UI list, incremental index, Rust-to-DM batch |
| Spatial or temporal watch | Enter/leave or deadline from an indexed source | proximity, timed requirements, hibernation wake |

The framework owns revisions for committed slot, ownership and relation
operations. Declared scalar fields use setters that write and publish together;
`NAMEOF()` or a checked proc reference gives authors a DM-native name, while
the archetype can intern compact IDs internally. A converted domain's static
check rejects direct writes to those fields, with an audited escape for
reflective writes. Cross-object changes publish on the dependent owner as
well. Tests compare selected cached values with uncached recomputation to
catch missing producers. Do not track every DM var or scan whole objects for
diffs each tick.

Body factors are the main example: afflictions, reagents, modifiers, species,
forms and worn items supply factor tables; the body's factor list is a derived
fold over those sources. The existing combine rules and null-at-baseline fast
path remain. Source addition, removal or value changes invalidate the body's
factor channel, and a test audit compares the cached result with a fresh fold.
The current bridge exposes `body.factor_view()` and
`body.observe_factor_view(observer)` for a fresh derived snapshot and effective
change event. The hot `L.factor(BF_*)` path keeps its existing dirty-bit cache;
converting every producer to typed marks is a separate migration. An observed
refresh copies and compares the roughly 60-value factor list, so use it for
displays or aggregate listeners rather than every combat read.
The public factor and worn-conductivity views return copies, as do their
change-signal arguments. Callers may edit a snapshot without corrupting the
cached value. Each read therefore allocates one list; use scalar getters in
hot loops.
The same pattern serves UI summaries, requirement results and derived slot
properties. Keep the containment ledger's incremental aggregate accumulators
for hot totals; caching the whole scan would make frequent inventory moves
more expensive. Its committed slot mutations publish a contents revision, and
child property changes must refresh the child's contribution and notify the
holder.

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

**Current implementation boundary.** The generic task and scheduler core is
present (`task.dm`, `schedule.dm`): owned timers, periodic callbacks, coalesced
wakes, prompts, revision stamps, deletion cancellation, and start/commit checks.
For a callback owned by the same datum, use `After(delay, PROC_REF(callback))`
or `Every(period, PROC_REF(callback))`. Both return an owned schedule entry that
can be `qdel`ed to cancel. Use the lower-level `om_timer` when a distinct
handler or named timer dispatch is needed.
Tasks now have opt-in live guards for movement, held equipment and incapacity,
and `om_start_timed_action()` provides asynchronous progress and timed checks
for callback and selected-zone conditions. The shared `do_after` entry point
now delegates its timing, guards and progress to `om_do_after_compat()`, preserving
the boolean-return shape and yielding caller. Future callers can use task
completion hooks directly to avoid a sleeping continuation. `AWAIT_TASK` below
is still a design target. `tools/object_model/TASKS.md` has the migration API.
The shared `expire()` helper also uses an owned schedule entry, so rearming
cancels the prior expiry and deleting the atom cancels the pending callback.
The stock market's recurring process timer uses the same owned scheduler and
no longer needs a timer-specific `Destroy()` override.
The germ-sensitive component's exposure countdown is owned as well; repeated
movement preserves the existing countdown, while pickup and teardown cancel it.
Shared wiring now claims an owned `om:wires` slot when constructed for a holder;
`set_wires()` transfers or replaces it, and state restoration uses the setter.
Wired atom types no longer need individual wire deletion in `Destroy()`.
Disposal trunks now use an exclusive relation from their connection component;
either endpoint's deletion unlinks it. Single-endpoint reads use
`om_first_linked()` or `om_first_linked_to()` to avoid copying an endpoint list.
NTNet DoS programs similarly select relays through a single relation instead
of a mirrored target field and relay-side source list. Body worn conductivity
has an optional observed derived view; ordinary reads still use the existing
lazy cache, and observers receive only effective changes.
Mind hosts use a single relation to their backing brain tissue; deleting or
replacing the organ unlinks it while the existing `tissue` read remains usable.
Single-outgoing relation setters now call `om_replace_related(source, kind,
target)`. It validates the candidate before removing the old edge and attempts
to restore the old edge if a reentrant hook defeats the new link. Relation
hooks are synchronous, so callbacks can still observe unlink then link; code
needing a truly atomic state transition must use a domain transaction.
Robot installed cells similarly have a non-owning relation because physical
containment owns the cell. Radio listener membership is exposed as a virtual
relation over SSradio's existing channel lists.

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
  - in between, when a declared or verified dependency fires (§8), coalesced
    to once per tick.

  Correctness only needs the start and commit checks. The checks in between
  exist only to cancel early for UX.
- **Commit is atomic only across a non-suspending effect path.** Requirements
  are rechecked immediately before `complete()`; it and its transitive calls
  may not sleep or await. Mutations and synchronous hooks must leave state
  valid before control returns. The test suite runs competing tasks against
  the same target and stock.
- **Exclusivity needs a complete guard.** The first task to complete changes
  guarded state, so a conflicting task fails at its own commit. Resource
  quantities, indirect writes and multi-object effects need explicit revision
  checks, claims or a domain transaction. A dm-health read/write warning is
  useful evidence, not proof when procs, lists or reflection hide effects.
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

`lifecycle.md`'s LC1–LC3 transaction exists in this checkout. Extend and test
that pipeline with converted domains rather than installing a parallel
destruction mechanism. This model revises its order in five ways:

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
- **Transfer failure and visibility.** Specify which tree and links hooks can
  observe in each phase. A failed `TRANSFER` must either preserve the child
  and abort the transaction or take a declared fallback; it must never leave
  an unowned child. Reentrant hooks add work to the same bounded worklist.
- **Fast path is conditional.** An entity with no tracked edges, teardown
  behaviours or bindings can skip those phases, but a legacy list, callback,
  engine reference or sleeping proc can still retain it. Verify eligible
  types before enabling the fast path; measure its actual cost.
- **Latent contents** are deleted as data and never materialised.
- **Pooling** is allowed only after the object's handles, external references
  and reset path are audited. Relations alone do not make reuse safe.
- **SSgarbage becomes a verifier.**
  - In tests, audit converted ownership and edges, and run reference searches
    on survivors or sampled types. Measure the audit cost before making an
    all-object search mandatory.
  - In production it's a cheap sampler plus the hard-delete fallback.
  - Most `QDEL_HINT_*` handling goes.
- **`qdel` remains the engine-facing deletion operation.** Converted callers
  state intent through
  `consume`, `replace_with`, lifetime/`expire`, slot operations,
  `delete_on_death` and `destroy(target, cause)`. A domain ratchet bans bare
  `qdel` only after that domain has moved to the new lifecycle. The practical
  migration target is **framework-only `qdel` in converted gameplay code**:
  content asks for a lifecycle operation, and the framework makes the final
  engine call. A legacy or engine caller that still invokes `qdel` on a
  converted object must enter the same transaction and produce the same
  cleanup. Enforce this per converted domain, not across the unmigrated tree.
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

**Hypotheses, not targets guaranteed by this model:** an earlier estimate put
the test map at 4–6 s and live-map init at 2–4× faster. Re-run the baseline
before quoting either figure; validate each startup change separately so
unrelated asset and wiki work is not credited to archetypes.

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

- **Change-driven where complete.** A UI session is a rich edge with one
  lifetime authority and links to user and object. Its status can subscribe to
  `can_see`, `in_range` and `conscious` changes. Converted `data()` providers
  rerun on documented changes; live simulation data may still need a bounded
  refresh. Benchmark event volume and payload size before claiming a win.
- **Actions** are `act_<name>` procs with typed parameters (`as num`/`as text`).
  They're validated centrally against a schema, and `can_act()` plus the
  requirement library decide whether an action is enabled. The server checks
  status, parameters and current state again when each action arrives; a
  disabled client button is only presentation.
- **Generated types.** dm-health reads `data()`, the fragments and the `act_*`
  signatures from the AST and generates both the TS types and the server-side
  parameter schema. Drift like `power: BooleanLike` becomes impossible.
- **First framework pass:** `tools/object_model/ui_schemas.json` is the explicit
  source for converted UI field and action contracts. Run
  `python tools/object_model/ui_bindings.py` to generate
  `code/datums/object_model/generated_ui_schema.dm` and
  `tgui/packages/tgui/interfaces/ObjectModel/generatedSchemas.ts`; run it with
  `--check` to reject stale output (CI does this). Each entry names a
  `/datum/object_model/ui` subtype and its TGUI interface. The generated DM
  subtype provides the action parameter rules and data schema consumed by the
  server adapter; the generated TS supplies data/action types. Converted UIs
  should put their data only through `ui_data.put()`, which checks generated
  field types and required keys. The current OpenDream AST bridge is used by
  dm-health, but extracting complete data/action contracts from arbitrary DM
  bodies is still a later step; this explicit schema keeps both sides in sync
  without guessing from control flow.
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

`tools/dm-health` already has an OpenDream AST bridge, flow analysis and some
access contracts. The rules below are the intended strict mode, not a list of
current guarantees. Its README and `docs/type-system.md` distinguish the
implemented checks from the proposal.

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
  captured dependencies. Static analysis reports unresolved dynamic reads;
  the missed-wake audit supplies separate runtime evidence. Neither is
  silently treated as complete when code uses reflection or external state.
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
- **No sleeping handlers** in events, `complete()` or hooks, including their
  statically resolved call paths. Unknown callees require an explicit reviewed
  boundary or the task cannot claim an atomic commit.

## 19. Error classes reduced after conversion

These are intended outcomes for a converted domain with complete producers,
relations and guards. Legacy paths retain their current risks; a declaration
alone does not remove an error class.

| Error class | Reduced by |
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
| Indirection overhead in DM and FFI | compare dispatch and handler cost with the path replaced; precompute sparse archetype tables, avoid per-event allocation, batch hot simulation work, and gate on idle and peak tick cost |
| DM numbers are floats exact only to 2^24, so a bitmask variable holds about 24 flags | the framework spreads masks over several variables or packed lists and hides it |
| Edge, subscription and base-datum memory | benchmark whole retained graph against the removed lists, weakrefs and callbacks; use lazy state, avoid adding several fields to every `/datum`, and count both ends of an edge |
| Spatial fanout | use indexed queries and bounded observer subscriptions, not stored relations for every nearby pair; benchmark dense crowds and movement bursts |
| Missed wakes and stale UIs | explicit dependencies, producer audits, test-time rechecks and per-domain coverage; never assume a raw expression or reflective write emits a complete change event |
| Destruction cascades and transfers | specify phase visibility and failure behavior; use a bounded worklist and tests that destroy or relink endpoints from hooks |
| Task races and indirect effects | non-suspending transitive commit paths, revision/claim checks for scarce resources, and concurrent-user tests |
| Debuggability ("why didn't it run?") | variable-viewer panels showing the archetype, requirement bits with reasons, timers, watches and edges; an "explain" trace per entity; dm-health's viewer showing each prefab's static composition |
| Content-author boilerplate | compare a converted machine's declarations, fields and hooks with the original; add bundles only for repeated patterns, and use sparse behaviour state for rare data |
| Learning curve | a small vocabulary (§23), a cookbook of real conversions, and CI errors that name the missing dependency or owner |
| Two systems during migration | one lifetime/scheduling authority per converted domain; domain ratchets and codemods remove old paths once parity is proved |
| Ordering and cascades | deterministic default order; declared before/after; deferred delivery for cascades |
| dm-health depends on OpenDream's parser keeping up with BYOND 516, plus a .NET bridge in CI | pinned versions (hash-checked); loud failures on parse gaps; tracked as a real risk |
| Boot cost and late validation of archetypes | validate all converted types in CI; benchmark eager test validation and lazy cached runtime construction separately |
| Compile time grows with the type count | offset by flattening prefab trees; tracked in the bench |
| Balance drift (Poisson and rates replacing per-tick `prob`) | same-mean continuous equivalents; differential tests against the old tick behaviour |
| Mob Life semantics during scheduler convergence | share reactor primitives first; preserve Life's composition and wake rules until medical parity, hibernation audit and benchmarks pass |

## 21. Plan

Implement the smallest primitives needed by real conversions, measure them,
then widen the domain. Do not require tracks A–F to finish before any caller
migrates. Convert all callers of an old mechanism **within one bounded domain**
before removing that domain's old path; the whole codebase need not change in
one patch. Ratchets count the remaining legacy patterns. Verify ports with
differential tests on the same inputs, not inspection alone.

| Stage | Work | Exit gate |
|---|---|---|
| **0. Baseline and contracts** | Reconcile this document with the current tree; classify lifetime authorities and tracked references; census instances, lists, edges, timers, hard deletes and manual cleanup. Record `bench --runs=3` test-map and live-map boot, retained memory, idle, peak tick and relevant scenarios. | Baseline and invariant list are reviewable; estimates are labelled as estimates. |
| **1. Minimal lifetime pilot** | Prove the unified destroy worklist and direct-`qdel` bridge, then convert one bounded datum ownership family so all of its gameplay deletion calls use lifecycle verbs. Convert a paired atom relation such as sleeper and console next, including either-end deletion and replacement. | No bare gameplay `qdel` or mechanical `Destroy` cleanup remains in the converted family; both deletion entry paths, relation order, transfers and reentrant hooks have falsifiable tests; no regression in the pilot's memory and tick cost. |
| **2. Complete machine pilot** | Convert the space heater's cell slot, processing trigger, interaction and UI action path using only the declarations needed for it. Keep the old and new implementations in a differential fixture, then remove the old path for the converted type. | Content code is materially simpler; UI types and server validation agree; boot, idle, active processing, memory and UI event volume meet measured gates. |
| **3. Shared scheduler and requirements** | Put converted machine timers, watches and wake paths on the reactor. Reuse P2 predicate reasons and the rules engine's threshold semantics. Convert one machine family at a time; keep mob Life's author-facing API until separately proven. | Missed-wake audit, parity tests and bench pass; old processing tables are removed for each converted family. |
| **4. Tasks and prompts** | Convert one resource-consuming timed interaction and one vending confirmation; add revision checks, claims where needed, a test clock and transitive no-sleep checks. | Competing-user, deletion, movement and stale-price tests pass without double spending. |
| **5. Composition and generation** | Generalise patterns demonstrated by several conversions into archetypes, bundles, behaviour state contracts, UI fragments and generated schemas. Validate all converted types in CI. Grow dm-health strict mode by converted module. | Authors write fewer fields and hooks than before; errors identify missing owners, producers or schemas; no memory or boot regression. |
| **6. Domain rollout** | Convert further machines and items, then complex body, power and atmos domains where the primitives fit. Remove each domain's old signals, timers, `Destroy` cleanup and UI glue only when its ratchet reaches zero. | Differential, focused tests and the repository bench pass for each domain; hard deletes and runtimes fall. |

Startup assets and lazy wiki are independent work and should be measured
separately from the object model. DQ Medical's mob Life, bodies, organs,
species and afflictions require a dedicated review before their author-facing
model changes. Their existing hibernation audit is a gate, not something to
discard when sharing the backend.

**Definition of done for a converted domain:** its ownership and dependency
invariants are explicit; old and new behavior match in focused tests; its
bench has no material regression in boot, retained memory, idle or peak tick;
the old path is removed; and a content-author example demonstrates less
manual lifecycle and scheduling code. The entire framework is done only when
the remaining domains meet those gates and the legacy mechanisms can be
deleted.

### 21.1 Scope of consolidation

The high-yield targets are repeated ownership cleanup, paired links, signal
unregistration, timer cancellation, processing enrollment, interaction
requirements, grants and UI parameter handling. A converted content type
should mostly declare those relationships and write its distinctive effects.
The generic model does not replace domain algorithms, Rust simulation loops,
or every useful subtype. Measure **author effort** as well as code size: count
declarations, state fields, hooks and special-case escape hatches for several
real conversions. If the framework makes ordinary content longer or harder to
debug, simplify its API before widening the migration.

## 22. Before and after, in brief

| Concern | Before | After |
|---|---|---|
| Machine composition | subtype tree with overrides | prefab `declare()` with bundles, behaviours and components |
| Periodic work | `START_PROCESSING` plus `process()` polling | requirement-gated behaviours; timers, watches and rates; hibernation |
| Cross-object links | var plus hand-written unlinking in both Destroys | relation kind with hooks and conditions |
| Timed actions | `do_after` sleeping loop plus manual re-checks | task with explicit dependencies and a guarded non-suspending commit |
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

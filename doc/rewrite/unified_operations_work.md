# Unified operations, observations, and work

**Status:** Design proposal, 2026-09-29. The DM examples describe an API to evaluate; they are not implemented code. This document consolidates the proposed changes to the DX, object-model, Life, and kernel designs. It does not supersede the existing implementation documents until the contracts here are accepted and built.

Related repository documents: [rewrite overview](README.md), [object model](object_model.md), [interactions](interactions.md), [containment](containment.md), [damage](damage.md), [body architecture](../body_architecture.md), and [mob Life architecture](../mob_life_architecture.md).

## 1. Decisions and boundaries

The smallest useful common foundation is:

1. **Typed requirements** answer whether a proposed operation or work item may run, with a refusal reason and declared dependencies.
2. **Observations** connect tracked changes, relations, and external producers to consumers. Consumers choose whether to recompute later or request urgent work.
3. **Operations** perform authoritative, non-sleeping state transitions. They select contextual affordance providers and enforce invariants at commit.
4. **Work specifications** describe scheduled computation owned by a domain system.
5. **Notices** describe occurrences and provide one registration and dispatch mechanism for what are now called events and hooks.

These share requirements and observations. They do not become one mega-datum: an operation has actor, target, selected provider, and commit semantics; work has timing and budget semantics; a notice has delivery semantics. A feature may contribute any combination of them. A domain system owns state and APIs, while its work specifications describe only the portions the kernel schedules.

The design favors direct DM reads and generated setters. CI checks for direct writes to tracked fields and bypasses of authoritative operation paths. CI does not generate code. Development-time generated code, if used, is committed and checked for freshness.

## 2. Requirements, affordances, and operations

### 2.1 Contextual affordances

An affordance is an ability supplied by a concrete provider, not a Boolean on a mob. A manipulation query returns a usable provider and port, or a reason for failure. It considers the actor, target, tool, route, and current state.

Examples:

| Provider | Offers | Limitations |
|---|---|---|
| Human left hand | Hold and operate physical controls | Requires the left arm and hand, usable grasp, free slot, and an accessible route |
| Borg gripper module | Hold compatible items | Exists only while the module is installed and functional |
| Feral mouth | Carry selected small items | Cannot operate controls that require fine manipulation |
| Silicon interface | Operate compatible machines | Does not imply an item-holding slot or physical reach |
| Telekinetic provider | Manipulate at range | Has its own line-of-effect, strength, and containment rules |

Multiple providers can satisfy one request. The resolver chooses one and records its identity, port, and source in the operation context. If the provider disappears during a prompt or timed action, the operation cancels. Silent substitution is allowed only when an operation explicitly permits rebinding.

### 2.2 Operation context and execution

An operation context contains at least the actor, target, held tool, input intent, selected provider and port, access route, relevant location or containment path, authority, and an operation identifier. It captures observed generations for early cancellation of a pending action; generations do not replace final validation.

The dispatcher:

1. Finds operations offered by the target and chooses the intended candidate. A refusal and a fallthrough are distinct outcomes.
2. Resolves an actor provider and a route, then evaluates standard and operation-specific requirements. Requirements return typed reasons rather than sending messages themselves.
3. Performs any prompt or timed phase. Its continuation retains the whole context, including the original actor when the prompt is shown to another player.
4. Immediately before commit, checks liveness and re-evaluates requirements against current state. If a selected provider, target, or route changed, it either explicitly rebinds or fails.
5. Runs bounded before-operation interceptors, rechecks if they changed the proposal, and commits without sleeping. The effect itself enforces its structural invariants.
6. Publishes state changes and after-operation notices. Presentation is queued and coalesced where safe.

No requirement is trusted merely because it passed before an input prompt or do-after. A requirement may be a reusable predicate such as physical reach, installed part, free port, or target removable. A complex custom predicate declares the state and relations that should wake or cancel it; it is still re-evaluated at commit. Broad observation is an acceptable fallback when exact dependencies are impractical.

### 2.3 Pickup and machine use

The following illustrates the intended amount of declaration. Constructors and helper names are provisional.

~~~dm
// One offer on the item base, not one declaration per item subtype.
/obj/item/proc/operations()
    . = ..()
    . += /datum/operation/take_item

/datum/operation/take_item
    required_affordance = /datum/affordance/hold_item
    route = ACCESS_PHYSICAL
    effect = /datum/effect/transfer_to_selected_port

// This console accepts either a physical control provider or a compatible
// silicon interface. Power and installed-interface checks come from its
// machine contract; this operation adds only its special rule.
/obj/machinery/console/proc/operations()
    . = ..()
    . += operation("Use console", /datum/effect/open_console,
        provider = any_of(/datum/affordance/operate_control,
                          /datum/affordance/silicon_interface))
~~~

The transfer effect checks that the item can leave its current holder, the destination port still exists and accepts it, and the ledger move succeeded. It returns an explicit result. It must not call a convenience method that drops the item on the floor when insertion fails. Server-authority moves such as map spawning use a separately named authority route, not a hidden bypass of player pickup.

Machine structure is a target-side contract. A machine can declare that its physical controls need a particular installed interface or part. The machine feature contributes that requirement to its operations; each button does not repeat it. Power, broken-state, access, and cover requirements compose by all/any expressions with operation-specific overrides. A machine may expose a separate emergency operation that works unpowered, rather than giving all operations the same exception.

### 2.4 Hands are ports backed by body slots and parts

The present body-slot definitions already associate left and right hand slots with body parts. Build on that single source of truth:

~~~dm
/datum/slot_def/body/hand/left
    id = SLOT_ID_HAND_L
    required_parts = list(BP_L_ARM, BP_L_HAND)
    provides_port = /datum/manipulator/hand/left

/datum/slot_def/body/hand/right
    id = SLOT_ID_HAND_R
    required_parts = list(BP_R_ARM, BP_R_HAND)
    provides_port = /datum/manipulator/hand/right
~~~

The body or ledger reconciles active ports when a part is attached, detached, replaced, or changes function. A missing limb removes its provider. A broken, blocked, restrained, or occupied hand may leave the provider present but unavailable, so the resolver can report the actual reason. A prosthetic can back the same stable port ID with a new source part. A borg module or feral anatomy can contribute a different slot and provider through the same mechanism.

Loss of an occupied port is an immediate invariant: resolve the held item during the part or factor transition, with an explicit drop or transfer policy. It must not wait for the next Life tick. A two-handed item binds two distinct ports atomically; losing either triggers its declared release or degraded-grip behavior.

### 2.5 Containment and absorption

Reach is a route through a containment and spatial graph, not just adjacency and not a global actor Boolean. An actor inside a belly may physically reach another item in that interior space but not a machine outside it. A fully absorbed body may additionally lose its physical manipulation providers. A remote interface, speech, or mental action can use a different route if it truly crosses that boundary.

The containment edge or absorbed feature supplies the access policy once. Pickup, machine use, tool use, and dragging all consult the same route resolver. Absorption also invalidates selected physical routes in pending operations. The operation's own effect checks the selected route again at commit.

## 3. Tracked state and coalescing

### 3.1 Retain the existing DX foundation

The DX proposal already provides plain vars, TRACKED and SETTER writers, exact declared reads for derived outputs, relation hops, and a drift audit. Retain those mechanisms. General read wrappers would add overhead and syntax without intercepting arbitrary direct reads or Rust state. Use declared observations for reactive consumers; use sanctioned accessors only where they enforce a domain boundary or enable focused diagnostics.

A tracked setter compares old and new values, commits the write, and publishes a keyed change. Relation writes publish both endpoint changes and rebind dependent observations. A change has subject, key, old and new values where available, and a generation. Lazy per-entity or per-context generations are preferable to allocating a revision counter for every field on every instance. Exact field keys are still useful for derived outputs.

External state owners must publish through an adapter: a Rust gas cell change, DB result, client connection, or BYOND engine callback cannot be discovered by a DM field setter. Native gas watches should report relevant changes for occupied sources and threshold crossings, and movement must rebind the occupant's watch.

### 3.2 What coalesces

State changes take effect immediately. The framework coalesces **idempotent follow-up work**, keyed by entity and output: appearance, HUD, open UI, derived cache, or a scheduled reevaluation. A synchronous reader sees the committed state; a dirty cached value recomputes on demand if its answer is needed before the drain.

An explosion still applies a damage packet separately to every target. Several hits on one target remain ordered: armour, shields, affliction thresholds, limb loss, death, source attribution, and reflected damage can differ by hit. The target's HUD may refresh once after them. A hundred targets still produce a hundred necessary damage evaluations and at least one dirty entry per changed target. Bulk mode must defer only safe invalidations, never suppress authoritative consequences or occurrence notices.

~~~text
hit A → apply mitigation and injury now → publish hit occurrence → mark A's views dirty
hit A → sees first injury, applies second hit → publish occurrence → A remains dirty
hit B → apply injury now → publish occurrence → mark B's views dirty
drain → recompute A and B once each for each affected derived output
~~~

Bulk processing may be sliced across ticks. Each completed entity mutation stands alone; an error in a later slice cannot strand earlier invalidations behind an unclosed global batch.

### 3.3 Missed changes and staleness

Direct-write CI, dependency lint, and a drift audit reduce missed changes but cannot make them impossible while helper procs, native state, and engine callbacks exist. Test critical work with mutations of each declared input and relation. A rule with difficult dependencies can subscribe to a broad owner change plus a bounded safety resample.

Pending operations are cancelled early when an observed actor, target, provider, or route changes. Commit still re-evaluates requirements and liveness. This handles a prompt that returns after limb loss, movement, absorption, deletion, a part removal, or another actor taking the item. Rebinding to another provider requires explicit operation policy.

## 4. One notice mechanism for events and hooks

A notice is a typed payload; observing is its registration mechanism. Replace the conceptual split between hook and event APIs with one observe/publish API, while retaining three delivery contracts:

| Contract | Delivery | Example |
|---|---|---|
| Before-operation decision | Synchronous, non-sleeping, bounded; may veto or return a constrained proposal | A ward vetoes opening a sealed door |
| Occurrence | Ordered, delivered once per occurrence; not coalesced by default | An item was taken; a hit landed |
| State invalidation | Coalescible; consumers can inspect the final value | The item's charge changed; refresh its UI |

~~~dm
observe(item, /datum/notice/item_transferred, listener,
        PROC_REF(on_item_transferred))
publish(item, new /datum/notice/item_transferred(actor, old_holder, new_holder))
~~~

Before handlers do not replace structural invariants. They may not sleep or make arbitrary partial mutations. A proposal adjustment causes requirement validation again. After handlers that must run in the same stack are kept small; expensive reactions request work. Registrations have owner tokens or per-source counts, deterministic ordering, automatic teardown, a recursion limit, and tracing. Removing one of several registrations between the same listener and source must preserve the others.

State change and occurrence remain different payload contracts even if they share dispatch. Opening and closing a door in one tick may leave its final state unchanged; both occurrences still happened. Two hits cannot be merged into one notice merely because both targeted the same mob.

## 5. Systems and work specifications

### 5.1 One scheduled-work vocabulary

A /datum/system owns domain state and a public API. It contributes zero or more work specifications. Each work item describes membership, cadence or trigger, observed inputs, phase, deadline or maximum latency, read/write contract, and explicit before/after edges. A pipeline is a named ordered group of work items, not another scheduler. A system may also expose synchronous commands and queries; those are not queued merely to fit the work vocabulary.

~~~dm
/datum/system/respiration/proc/work()
    . = list()
    . += work(
        id = /datum/work/respiration/exchange,
        members = /datum/member_query/has_respiration_profile,
        observes = list(RESPIRATION_PROFILE, BREATH_SOURCE,
                        AIRWAY, ENVIRONMENT_AIR),
        cadence = CADENCE_BREATH,
        urgent_on = list(BREATH_SOURCE_LOST, AIR_BECAME_DANGEROUS),
        phase = PHASE_PHYSIOLOGY,
        step = TYPE_PROC_REF(/datum/system/respiration, exchange_step))
~~~

Boot dependencies and runtime ordering are different graphs. Boot says which owner must initialize first. Runtime before/after edges order work within a declared phase or schedule; missing targets and cycles fail validation. A work item may belong to multiple named sets. Dynamic feature attachment updates membership with source counts, since two features can enroll one entity in the same system.

The kernel owns the budget, deadline wheel, urgent queue, runlevels, and measurements. Work that exhausts its budget yields and resumes without sleeping inside a step. Clocks remain explicit: world, biological/stasis-aware, and machine clocks may advance differently. Urgent work has a stated tick deadline and reserved budget or an overload report; lane priority alone is not a latency guarantee.

### 5.2 Wake, urgent request, and direct execution

These have different meanings:

- **Wake:** clear a parked condition and make the item eligible at its normal cadence.
- **Request urgent:** enqueue a particular member/work pair for the next safe scheduler point, before ordinary cadence work, with a deadline and deduplication.
- **Synchronous operation:** finish now, before the caller proceeds. Damage, pickup, movement decisions, and transfer invariants use this path.

Urgent work receives elapsed time and an execution token so it cannot double-apply a later cadence step. A bounded synchronous observer may update an immediate safety fact, but it should not recursively run a whole Life frame.

### 5.3 What stays outside scheduled work

Gameplay subsystems and world services should become domain systems with work where they repeat or wait. The kernel host retains garbage, input, verb management, database and TGUI transport, budget/failsafe, and the one native driver. Boot/shutdown and direct commands are system behavior but are not scheduled work.

BYOND callbacks such as Move, Entered, Login, Topic, verbs, construction, and deletion occur when the engine calls them. They should be thin adapters to operations, setters, notices, or work requests. Rust gas, heat, and network computation remains native and publishes relevant changes through the kernel adapter. External I/O completes through callbacks. Vendored host integrations may remain outside this gameplay model. The goal is that gameplay rules and deferred gameplay work have one owner, not that every executed proc is a scheduled job.

## 6. Life and non-oxygen respiration

### 6.1 Separate gas exchange from biological supply

The current code has oxygen, nitrogen, phoron, methane, CO2, and skin-breathing cases. A generic profile must distinguish:

- where a breath sample comes from: room, internals, belly, water, suit, or another source;
- what gas is consumed and what is exhaled;
- which gas or combination supplies the body, at what partial pressure;
- hazards such as poison, smoke, temperature, and pressure;
- whether lungs, skin, gills, a pump, or another organ performs exchange;
- whether the body needs any respiratory supply at all.

Most lung breathers can use data-only profiles:

~~~dm
/datum/respiration_profile
    var/intake_gas = GAS_O2
    var/exhale_gas = GAS_CO2
    var/poison_gas = GAS_PHORON
    var/min_intake_pressure = 16
    var/deficit_name = "oxygen"

/datum/respiration_profile/lungs

/datum/respiration_profile/lungs/vox
    intake_gas = GAS_N2
    poison_gas = GAS_O2
    deficit_name = "nitrogen"
~~~

An alraune-style skin profile can specialize the supply rule: CO2 is consumed and O2 exhaled, while either CO2 or O2 pressure may support the tissue. A simple list of accepted gases cannot express the difference between supply and consumption.

~~~dm
/datum/respiration_profile/skin/alraune
    intake_gas = GAS_CO2
    exhale_gas = GAS_O2

/datum/respiration_profile/skin/alraune/proc/supply_quality(datum/gas_sample/S)
    var/support = S.partial_pressure(GAS_CO2) + S.partial_pressure(GAS_O2)
    return clamp(support / min_intake_pressure, 0, 1)
~~~

The profile returns a supply-quality result and any consumed/exhaled gas. Physiology combines that result with demand, circulation, and tissue uptake. Its generic internal names should describe respiratory supply and debt rather than assume oxygen. Human-facing readouts can still say oxygen; Vox readouts can say nitrogen. A breathless body with zero respiratory demand is valid. A body with demand and no exchange or alternate supply must be diagnosed as an incomplete plan, not treated as perfectly supplied. A lungless skin breather has an exchange provider and needs no lung organ.

Do not use truthy fallbacks to interpret a null breath or poison gas as the human default. Resolve a profile first; null must have an explicit meaning.

### 6.2 Dangerous-air latency

The proposed sleeping breathing stage currently wakes for location and equipment and resamples steady air after 30 seconds. Its breath counter advances only when the stage runs and a breath is taken every fourth run. Consequently, an in-place air change without another wake can wait roughly four resamples plus Life-frame alignment before being sampled. Merely marking the stage awake does not meet an urgent-air requirement.

An occupied air source therefore needs a native-to-DM change watch. The source publishes relevant composition, pressure, temperature, or hazard-threshold changes; the occupant's profile decides whether its breath result may change. Movement and source selection rebind the watch. A dangerous change requests urgent respiratory work for affected occupants, including parked mobs. The latency guarantee starts when the native source publishes the change; the native step's own delay is measured separately. A short bounded safety resample remains prudent for critical occupied spaces and missing-publication detection.

The respiration step updates supply quality promptly. Periodic animation, sounds, and gas consumption retain their appropriate cadence. An urgent sample must not charge a full six-second physiology interval twice.

## 7. Hard cases and acceptance tests

| Case | Required behavior |
|---|---|
| Human loses a hand while holding an item | Provider disappears, held item is resolved immediately, pending actions using that hand cancel |
| Hand becomes blocked, then recovers | Provider identity stays stable; availability and refusal reason change; no stale held item |
| Two-handed object loses one port | The composite hold rule releases or degrades it once, without selecting the same port twice |
| Borg loses its gripper but retains a silicon interface | Pickup fails; compatible machine control still works |
| Feral has no hands but can carry a small item in its mouth | Pickup selects the mouth only for accepted items; hand-only controls remain unavailable |
| Human is contained or absorbed | Physical routes obey the containment boundary; permitted interior and remote routes remain possible |
| Prompt returns after target movement or deletion | Context is cancelled or final requirements fail; no stale transfer occurs |
| Explosion hits many targets, or one target repeatedly | Every hit and immediate consequence occurs in order; derived views refresh once per changed entity/output |
| Air changes in place around a hibernating Vox | Nitrogen supply or oxygen toxicity triggers urgent reevaluation without waiting for a Life cadence |
| Reentrant notice deletes its source | Dispatch stops safely, registrations tear down, and unrelated occurrences are not coalesced |
| Two features enroll one entity in one system | Removing either feature leaves membership until the final contributor leaves |
| Bulk processing fails midway | Committed changes still drain; no global batch remains open |

Tests should mutate every declared observation and relation for critical work; verify refusal reasons and final operation checks; exercise native air publication; assert event order and non-coalescing for occurrences; and measure wake latency under load. Benchmarks should compare memory for provider and revision metadata, scheduler overhead, and mass-damage refresh cost before adopting finer tracking everywhere.

## 8. Migration order

1. Define the shared requirement and observation contracts atop the existing tracked-setter and relation machinery. Keep direct reads; add CI checks for direct writes and known operation bypasses.
2. Implement the operation context and selected-provider result. Migrate pickup and one machine interaction as representative end-to-end paths. Preserve an explicit server-authority transfer API.
3. Derive hand providers from body slots and part relations; make part loss and action-block changes resolve occupied ports immediately. Add borg gripper and feral mouth examples.
4. Consolidate event and hook registration under one notice API. Make occurrence delivery non-coalescing by default, fix multi-registration teardown, and retain separate before/state delivery policies.
5. Extend observations to pending actions and Life work; add urgent scheduling with deadline metrics. Connect the native gas change adapter before relying on respiratory hibernation.
6. Introduce one work-specification vocabulary for repeating and deferred gameplay, then migrate gameplay subsystems by domain. Keep the kernel host and synchronous operation boundary explicit.
7. Generalize respiratory supply profiles and naming after the urgent wake path is tested. Preserve species-specific chemistry and presentation.

Each migration step should replace its old call path and test the invariant at the authoritative boundary. A parallel legacy entry point that bypasses the new operation or setter would defeat the architectural guarantee.

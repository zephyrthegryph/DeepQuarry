# Rust bindings (R10: the binding layer)

How DM and Rust share objects. It covers everything with a lifetime (devices,
machines, items, mobs, turfs); stateless calls (jobs, layout, one-off queries)
use the same generator as plain typed commands and queries. The atmos pump
(§14) is the reference example. This replaces `rust_core.md` §8–9's per-bind
approach.

## 0. The invariant

**Every fact that both sides use has exactly one store.** Nothing is copied
across the boundary to be "kept in sync". Values cross only as:

- a **command** that changes the one store;
- a **read** of the one store;
- an **event**: Rust tells DM something happened, and DM keeps no state from it.

A desync needs two copies of a fact. This design removes the second copy:

- **Facts Rust stores** (settings, simulation state) have no DM var at all.
  DM reaches them only through generated procs, so DM code can neither write
  them behind Rust's back nor keep a stale copy. This is enforced by the
  compiler, not by discipline.
- **Facts DM stores that Rust needs** (placement, containment, construction,
  damage state) are *inputs*. Every way they can change is a framework
  transition or an accessor that notifies Rust as part of the change (§7).
  The one class DM cannot hide (a few BYOND built-in vars) is lint-enforced
  and covered by a reconciler that fails CI on any divergence and repairs
  production within one sweep.

## 1. Model

- **Entity.** A bound atom has one Rust entity, and DM stores its handle in one
  var, `vg_entity`. The handle is the R2 packed handle (20-bit index, 4-bit
  generation, exact as a DM number).
- **Component.** Each domain contributes components to entities: a gas device
  (pump, vent, filter), a power consumer, producer or store, a heat body, a
  radiation source, and so on. One atom can hold several; a pump is a gas
  device *and* a power consumer. Components of the same entity are coupled
  inside Rust (the pump's compression work becomes its power demand), so DM
  never relays between domains.
- **Grid kind.** Per-turf data (gas cells, heat cells, air-blocking masks) is
  keyed by coordinates. Turfs need no handle and no var.
- **Field roles** in a component:

| Role | Examples | Store | DM access |
|---|---|---|---|
| **config** | target pressure, power rating, on/off, vent mode, filter mask | Rust | generated `get_*` and `set_*`; no DM var |
| **state** | gas, heat, charge, flow rate, power drawn | Rust | generated `get_*` and queries; never written by DM |
| **input** | anchored, broken, connected ports, position | DM | derived by a pure proc and pushed when a source changes (§7) |

Rule: if Rust needs a value every step, Rust stores it. DM keeps only what is
DM's by nature (placement, containment, construction, damage) and exposes it
as an input.

## 2. Declaring a component (Rust)

A component is a struct in its domain crate. One attribute generates the
schema, the FFI procs, the DM surface, validation, the state codec and the
documentation.

```rust
#[vg::component(domain = gas, dm = "/obj/machinery/atmospherics/binary/pump", ports = [input, output])]
pub struct Pump {
	#[vg(config, unit = "kPa", range = 0.0..=MAX_PUMP_PRESSURE, default = ONE_ATMOSPHERE, on_invalid = clamp)]
	target_pressure: f32,
	#[vg(config, unit = "W", range = 0.0..=MAX_PUMP_POWER, default = 30_000.0)]
	power_rating: f32,
	#[vg(config, default = false)]
	on: bool,
	#[vg(input, from = [construction, integrity])]
	operable: bool,
	#[vg(state, unit = "mol/s")]
	flow_rate: f32,
}

#[vg::query(Pump, ui = [target_pressure, power_rating, on, flow_rate])]

#[vg::events(Pump)]
pub enum PumpEvent { TargetReached, Starved }

impl GasDevice for Pump {
	fn law(&self) -> Law {
		if !(self.on && self.operable) {
			return Law::Off;
		}
		Law::flow()
			.rate(Rate::Power(self.power_rating))
			.until(Port::Output.at_least(self.target_pressure))
	}

	fn couple(&self, step: &StepReport, entity: &mut EntityCtx) {
		entity.power().demand(step.work_w); // cross-domain, inside Rust
	}
}
```

- `dm` names the DM type the component attaches to. Subtypes inherit it and
  can switch to another component of the same domain, or opt out.
- `on_invalid` is `clamp` or `reject`. Validation, units and ranges exist once,
  in Rust.
- The power draw is not a pump field. It is the power consumer component's
  state, and it's read like any other state field.

## 3. The generated DM surface

The generator writes procs and defines into
`code/__defines/verdigris/_bindings.dm`, and type-level declarations into
`_bindings_types.dm`. Nothing in them is written by hand.

```dm
// Which component this type holds (type-level, no per-instance memory).
/obj/machinery/atmospherics/binary/pump/vg_gas = VG_GAS_PUMP

// Initial values for config: set on subtypes or var-edited in maps, read once when bound.
/obj/machinery/atmospherics/binary/pump/var/tmp/init_target_pressure
/obj/machinery/atmospherics/binary/pump/var/tmp/init_power_rating
/obj/machinery/atmospherics/binary/pump/var/tmp/init_on

// The only way to reach the values.
/obj/machinery/atmospherics/binary/pump/proc/get_target_pressure()        // kPa
/obj/machinery/atmospherics/binary/pump/proc/set_target_pressure(value)   // kPa; returns what was stored
/obj/machinery/atmospherics/binary/pump/proc/get_flow_rate()              // mol/s, read-only
/obj/machinery/atmospherics/binary/pump/proc/pump_query_ui()              // assoc list, one call

// Schema constants for UIs; no copied limits.
#define VG_PUMP_TARGET_PRESSURE_MAX 4500

// Event handlers, with no-op defaults. Override the ones you need.
/obj/machinery/atmospherics/binary/pump/proc/on_pump_target_reached()
/obj/machinery/atmospherics/binary/pump/proc/on_pump_starved()
```

- **Initial values** (`init_*`) are constructor arguments, not state. A lint
  forbids any reference to them inside a proc body, so they can't be mistaken
  for the live value. An unset one uses the schema default. They are never
  written at runtime, so they cost no per-instance memory unless a map sets
  them.
- There is **no DM var** named `target_pressure`, so `target_pressure = 50`
  does not compile. The setter is the only way to change it.
- **Admin var-edit** shows a section with each component's live fields and
  writes through the setters. Editing an `init_*` after the atom is bound goes
  to the setter too.
- **Debugging:** `vg_describe(atom)` prints every component's fields, inputs
  and recent commands (from the R9 flight recorder).

## 4. Lifecycle

All of it lives in base procs keyed by the type's component vars, so a subtype
cannot skip it.

| Moment | Where | What happens |
|---|---|---|
| bind | the base `on_materialize()` (L2) | one call creates the entity and its components from the `init_*` values and current inputs, then stores `vg_entity` |
| unbind | J1 `pre_destroy()`, which `qdel` runs before any `Destroy` override | removes the entity; clears `vg_entity` |
| collapse to latent | the C10 collapse, a ledger transaction | saves every component's config and state into the latent blob, then unbinds |
| materialize from latent | the ledger materialize | binds from the blob instead of the `init_*` values |
| a source changes | the source's transition or accessor | recomputes and resubmits the input (§7) |
| world start | `verdigris_init()` | resets every Rust store and checks the ABI hash, so no handle survives from a previous round |

**Boot batching.** During world init, binds go into a spawn buffer: handles
are reserved from Rust in blocks, so `vg_entity` is set immediately, and one
call creates the whole batch. Every generated proc first flushes the buffer if
it's non-empty (a single number check). Every read and command therefore sees
every earlier bind. The buffer is invisible outside the generated code and
empty after init.

## 5. Writes

`set_x(value)` is one FFI call that:

1. resolves the handle and component (a stale, wrong-component or unbound
   handle is a typed error and a DM runtime naming the atom);
2. validates the value against the schema (`clamp` or `reject`);
3. submits a typed command through the domain's `MainPort` (R4), which applies
   it to what DM sees immediately and to the simulation at the next frame;
4. returns the stored value.

Nothing is buffered on the DM side after init, so nothing can be lost or
reordered. Sets are rare (players, admins, construction). A COUNT benchmark
gate requires **zero sets per idle tick**: repeated per-tick DM writes mean a
law belongs in Rust.

## 6. Reads

`get_x()` is one FFI call returning `MainPort::read`: this tick's writes over
the pinned frame. From DM's point of view each entity is linearizable: a read
always reflects every earlier set. State fields come from the pinned frame, at
most one frame old.

- **Query groups** return several fields in one call (`pump_query_ui()`).
- **Batch reads** return one field or group for a list of atoms in one call,
  for consoles and scanners that show many devices.
- DM never stores a read across ticks. A lint flags member-var assignment from
  `get_*` or `*_query_*`, and a unit test checks that no bound type declares a
  var with a component field's name.

## 7. Inputs: the only DM-owned values Rust stores

An input is a pure DM proc over declared sources (for example
`pump_input_operable()`), recomputed and resubmitted only when a source
changes. Sources come in five classes. The first four make a missed update
impossible by construction:

| Class | Examples | Why an update can't be missed |
|---|---|---|
| 1. Ledger relationships | a canister in a connector port, a cell in a machine, contents | they change only through ledger transactions, which fire `on_slotted` and `on_unslotted` (J6) |
| 2. Movement | position, which turf, which z-level | every move goes through the movement hooks (J5); raw `loc` writes are already a lint error (C1), and C11 removes the rest |
| 3. Framework transitions | construction graph state (I5), integrity breakpoints (D4) | the framework is the only writer |
| 4. DM vars behind accessors | machine status flags, panel open | a source var is renamed and reached only through a get and set proc pair (TG did this for `stat`, which became `machine_stat`), so a raw write does not compile |
| 5. BYOND built-ins | `anchored`, `density`, `opacity`, `dir` | these can't be hidden: raw writes are linted, and the reconciler covers them |

Prefer the higher classes. For example, "connected" should come from the
connector's ledger slot (class 1), not from `anchored` (class 5).

**Reconciler** (`SSvg`), the safety net for class 5 and for bugs anywhere:

- A budgeted sweep recomputes every bound atom's inputs and compares them with
  Rust's stored inputs through batched reads. It also compares the set of
  bound atoms with Rust's live entities, looking for orphans on either side.
- **Test and dev builds** reconcile every bound atom after every unit test (in
  the test sandbox's teardown) and after every step of the binding fuzz test.
  A divergence fails the test that caused it, naming the atom, field,
  expected value and actual value.
- **Production** sweeps cover every atom within 60 seconds and repair and log
  any divergence. The COUNT benchmark metric `vg_reconcile_repairs` must stay 0.

## 8. Events

Rust records events in each domain's outbox. SSreactor drains each domain
once per tick (one FFI call per domain), and the generated dispatcher calls the
named handler on the atom after checking `atom.vg_entity == handle`. There are
no per-object callbacks each tick and no pushed display values: a display
value is a `state` field read when it's shown.

## 9. Errors and safety

- Panics are caught per FFI call and per command in the apply loop. A failing
  command leaves its value unchanged and reports an error. It can't take down
  the batch or DreamDaemon.
- Errors are typed (component, field, handle, reason) and become DM runtimes
  with the atom attached.
- Handles are generation-checked, so reusing a slot can't alias another atom.
- Values an atom's type or map provides are validated by a unit test that
  checks every bound type's `init_*` values against the schema, so a bad
  default fails CI instead of failing at bind time.

## 10. Why desync cannot happen

| Scenario | Why it can't |
|---|---|
| DM code changes a setting without telling Rust | the DM var does not exist; only `set_*` changes it |
| Rust clamps or updates a value DM still holds | DM holds no copy |
| A read right after a write sees the old value | reads return this tick's writes over the frame |
| An atom is created, destroyed or collapsed without Rust knowing | binding is in base lifecycle procs subtypes can't skip (materialize, J1 pre-destroy, ledger collapse); the reconciler checks both directions |
| A stale handle reaches a recycled slot | generation-checked handles |
| A map or admin edit | `init_*` values are read once at bind; var-edit writes through setters |
| Save and load | the state codec reads and writes the Rust store |
| An invalid value | validated once, in Rust; the setter returns what was stored |
| A panic in the middle of a batch | caught per command; the value is unchanged; an error is reported |
| A new round with leftover Rust state | `verdigris_init()` resets every store; ABI handshake |
| An input changes through a class 1–4 source | the transition or accessor updates Rust as part of the same change |
| A class 5 built-in changes through a path nobody hooked | the lint rejects raw writes; the reconciler fails CI and repairs production within one sweep |
| DM caches a Rust value in a var | lint and unit test (§6) |
| Two domains disagree about one atom | components are coupled inside Rust in the same frame, never through DM |
| Boot batching reorders anything | every generated proc flushes the spawn buffer first |

## 11. How this meets the goals

| Goal | How |
|---|---|
| No desync | one store per fact (§0); the invariant table (§10) |
| Clean interface | typed, named procs generated from one Rust declaration; no positional slots, magic numbers or hand-written glue |
| Developer friendliness | declare a struct and a law in Rust; in DM, set `init_*` values and call `get_*`/`set_*`; UIs use one query proc; events are named handlers you override |
| Minimal memory | one `vg_entity` var per bound atom; component choice and `init_*` values are type-level; turfs need nothing; schemas are static |
| Performance | one FFI call per set, get or query; batch reads; boot binds batched; one event drain per domain per tick; zero binding traffic per idle tick (COUNT gate) |
| Generic, no duplication | handles, validation, units, errors, persistence, events, reconciliation, var-edit and docs are generic; a domain supplies only its data and its law |
| Works for everything | components for machines, items and mobs; grid kinds for turfs; typed commands for stateless work |
| Safety | panics isolated per call and per command; typed errors; generation-checked handles; reset each round |

**Rejected alternatives:**
- **DM vars plus dirty flags:** two copies, so a missed flag is a silent desync.
- **DM vars plus a per-tick diff:** two copies, and polling every tick.
- **Rust pushing state into DM vars:** stale between pushes, and FFI traffic every tick.
- **One kind per atom:** a pump couldn't be a gas device and a power consumer at once.

## 12. Enforcement

- **Compile time:** bound fields have no DM var; input source vars (class 4)
  are reachable only through accessors.
- **Generator checks:**
  - the DM type exists;
  - no DM var on a bound type has a field's name;
  - accessor names don't collide between components on one type;
  - every event has a handler (a generated default);
  - every field declares its units and range.
- **Lints:**
  - `call_ext` only in generated files (exists);
  - `init_*` never in proc bodies;
  - no member-var caching of reads;
  - no raw writes to class 5 sources or to `loc`.
- **Tests:**
  - read-your-writes;
  - stale, wrong-component and unbound handles;
  - binding at materialize, and unbinding at pre-destroy even when `Destroy` is overridden;
  - the latent round trip and the state save/load round trip;
  - `init_*` validation for every bound type;
  - a panic becomes a DM runtime;
  - boot batching (a read before and after the flush);
  - the `verdigris_init()` reset;
  - an injected desync (a test that bypasses a setter through `vars[]` or a raw FFI call) must be caught;
  - a fuzz test of random sets, moves, breaks, destroys, collapses and connections, with full reconciliation after every step.
- **Benchmarks (COUNT metrics, independent of load):**
  - sets per idle tick = 0;
  - reconcile repairs = 0;
  - FFI calls per idle tick don't grow.

## 13. Cost

- **FFI calls:** one per set, get or query; none per idle tick; binds batched at boot.
- **DM memory:** one var per bound atom, plus one slot in the entity table.
- **Rust memory:** components in arenas, and a small per-entity component index.
- **Reconciler:** one input evaluation per atom per sweep, in batched reads. For
  example, 5,000 atoms over 60 seconds is about 85 evaluations per second.

## 14. The pump, before and after

Before (`pump.dm` today):
- a `target_pressure` var;
- six scattered `update_rust_device()` calls;
- `rust_set_device(1, 2, RUST_DEVICE_LAW_PUMP, target_pressure, power_rating)`, with four positional slots;
- a string-keyed device map in SSair, and a commit on every call;
- `rust_device_stepped()` pushing display values every tick;
- `STOP_MACHINE_PROCESSING` in `Initialize()`.

After (the whole binding-related part of the file):

```dm
/obj/machinery/atmospherics/binary/pump/high_power
	init_target_pressure = 9000
	init_power_rating = 45000

/obj/machinery/atmospherics/binary/pump/ui_data(mob/user)
	return pump_query_ui()

/obj/machinery/atmospherics/binary/pump/ui_act(action, list/params)
	. = ..()
	switch(action)
		if("pressure")
			set_target_pressure(text2num(params["pressure"]))
			return TRUE
		if("power")
			set_on(!get_on())
			return TRUE

/obj/machinery/atmospherics/binary/pump/on_pump_target_reached()
	update_icon()
```

No `process()`, no sync calls, no ids, no port numbers, no per-tick callbacks.
`operable` comes from construction and integrity (classes 3 and 4) through
generated wiring, so the pump file doesn't mention it.

## 15. Migration

1. **Runtime and generator** (R10, one branch):
   - entities, components and grid kinds on `MainPort`;
   - the `#[vg::component]`, `#[vg::query]` and `#[vg::events]` attributes;
   - validation and typed errors;
   - the generated DM surface;
   - boot batching;
   - `SSvg` (reconciler and event dispatch);
   - lints and tests.

   The pump is the reference component.
2. **Gas devices** (M2) move onto it. These are deleted:
   - `rust_pipenets.dm`'s device procs;
   - `SSair.rust_pipe_devices` and `next_rust_device_id`;
   - `rust_device_stepped()`;
   - every `update_rust_device()`.
3. **Power** (M3 consumers, producers and storage), **heat** (bodies and the H4
   regulator) and **radiation** sources become components. Turf gas and heat
   become grid kinds.
4. **Stateless binds** (jobs, layout, metrics) become typed commands and queries.
5. The old untyped paths are deleted with no shims, and the lints go
   repo-wide.

## 16. Implementation notes (step 1, landed on `rewrite/bindings`)

What the runtime, generator and pump component actually turned out to need,
beyond what earlier sections specify exactly:

- **The entity handle crosses as raw-plus-one.** A packed handle's bits can
  themselves be `0` (index 0, generation 0 is an ordinary handle), so `0`
  cannot mean both "the first entity ever bound" and "unbound" — that would
  be exactly the hand-rolled sentinel collision §0 rules out. Every
  `vg_entity` value is the raw handle plus one; DM never sees the offset,
  and every FFI entry point that takes a `vg_entity` rejects anything below
  1 as "not bound" before decoding.
- **Per-domain bind and reconcile dispatch is override-based, not a
  switch.** `vg_bind_<domain>(entity)` and `vg_reconcile_<domain>()` are
  base no-op procs on `/atom/movable`, and the generator overrides them on
  each bound type to call that type's own `vg_<kind>_bind`/`<kind>_reconcile`.
  This is what the generic, domain-list-driven `vg_bind()`/`vg_reconcile()`
  call, so adding a kind never means regenerating a switch statement across
  every other kind in the domain.
- **The reconciler's dispatch is generated per component**
  (`<kind>_reconcile()`), comparing every declared input field's pure proc
  against a generated read-only `get_*()` of Rust's stored value and pushing
  a repair on mismatch. `SSvg` (`code/controllers/subsystems/vg.dm`) drives
  a budgeted production sweep and exposes `vg_reconcile_all()`, a full pass
  in one call, for the test sandbox teardown and the fuzz test.
- **Event drain and dispatch are declared but not yet wired end to end.**
  `#[vg::events]` gives each event a stable id and `snake_case` name, and the
  generator emits the numeric defines and a no-op `on_<kind>_<event>()`
  handler stub per event — satisfying §12's "every event has a handler, a
  generated default." The outbox drain that would actually call one (§8) is
  intentionally deferred: nothing emits a component event yet (that is
  physics, M2's law), so building and testing a full drain-and-dispatch path
  now would be exercising dead code. Its shape is fixed (id, name, handler)
  so M2 does not need a generator change to start emitting `PumpEvent`s;
  only the drain call and SSvg wiring remain.
- **The pump keeps `update_rust_device()` as a bridge, not a second store.**
  `target_pressure`/`power_rating`/`on` have exactly one store — the Pump
  component behind `MainPort<PumpKind>` — reached only through the
  generated `get_*`/`set_*`. `update_rust_device()` reads through those
  getters and republishes to the legacy per-device-edge law
  (`rust_pipenets.dm`, `RUST_DEVICE_LAW_PUMP`) that still does the actual
  gas moving, so the pump keeps working exactly as before while the
  binding layer becomes the source of truth. This bridge, `rust_set_device`
  and `rust_unregister_device` are deleted in migration step 2 once M2's
  generic Flow law reads `Pump` directly from the same `MainPort`.
- **`power_rating` is still a live DM var — on other, not-yet-migrated
  devices.** It is declared on the shared `/obj/machinery/atmospherics`
  ancestor (`atmospherics.dm`), which `volume_pump.dm`, `outlet_injector.dm`
  and others still read as a plain var. Binding `Pump` to it does not (and
  cannot yet) remove the ancestor declaration; on `pump` specifically it is
  inherited but never read or written by anything after this migration — a
  latent, inert shadow rather than a live desync risk, resolved once every
  atmos device migrates and the ancestor var is deleted.
- **`from = [construction, integrity]` sources.** Only `integrity` gets a
  generated hook today (`atom_break()`/`atom_fix()`, class 3): it is the one
  source with a landed, unconditional framework transition point.
  `construction` has no I5 graph to hook yet, so — like the `anchored`
  BYOND built-in (class 5) — it relies on the reconciler alone until I5
  lands; the generator accepts any source name but only emits a hook for
  ones it recognizes as having a concrete transition point.
- **Boot batching (§4) is not built yet.** `pump_bind()` today does one
  entity-table reservation and one `MainPort::put` per call, exactly like
  any other tick's bind — correct (every read after it sees it, same as
  §4 promises), just not yet batched into one call per world-init block.
  With one component kind live, boot-time bind traffic is negligible; this
  is real follow-up work once several kinds (and therefore a real map-load
  spike) exist, not a correctness gap the reference component needed to
  prove.
- **J1/C10 are not on master yet.** Unbind lives in
  `/atom/movable/on_dematerialize()` (today's earliest guaranteed point,
  the same hook L3's `leave_registries()` already piggybacks on), with a
  single marked comment to move it once J1's `pre_destroy()` lands. There is
  no latent-collapse integration yet, for the same reason (C10 not landed);
  the state codec hook for save/load is not built yet either — deferred to
  when a latent-safe atom actually needs one, since none does today.

# Rust bindings (R10: the binding layer)

How DM and Rust share objects. This replaces the ad-hoc binds described in
`rust_core.md` §8–9 for anything with a lifetime (devices, consumers, bodies,
sources). Stateless calls (jobs, layout, one-off queries) keep plain typed
binds made by the same generator. The atmos pump (§13) is the reference
example.

## 0. The invariant

**Every fact that both sides use has exactly one store.** Nothing is copied
across the boundary to be "kept in sync". Values cross only as:

- a **command** that changes the one store,
- a **read** of the one store,
- an **event** (Rust tells DM something happened; DM keeps no state from it).

Desync needs two copies. For facts Rust stores, this layer makes a second copy
impossible to create: the DM var does not exist, so no DM code can write or
cache it. For the few facts DM stores and Rust needs as inputs, every write
path is closed (setters and lints) and a reconciler proves agreement: a
divergence fails the test that caused it and cannot survive a production
sweep (§7).

## 1. Fact classes

| Class | Examples | Store | DM access | Crosses as |
|---|---|---|---|---|
| **config** | target pressure, power rating, on/off, vent mode, filter mask, setpoints | Rust | generated `get_*`/`set_*` procs; no DM var | `set_*`, a validated command |
| **state** | gas, heat, charge, flow rate, power drawn | Rust | generated `get_*` and query groups; no DM var | never written by DM |
| **input** | anchored, broken, panel open, connected ports, position | DM | ordinary DM vars behind setters | derived by a pure proc, pushed on the sources' change signals, reconciled |
| **identity** | this atom and its Rust object | both (a handle) | `vg_handle`, set only by the base bind | bind and unbind in base lifecycle procs |
| **persistence** | save and load, latent blobs | Rust (config and state) | generated state codec | blob to spawn, and back |
| **event** | target reached, starved, threshold crossed | none (transient) | `vg_event()` handler | outbox drain once per tick |

Rule of thumb: if Rust needs a value every step, Rust stores it. DM stores only
what is DM's by nature (placement, construction, damage state) and exposes it
as an input.

## 2. Declaring a kind (Rust)

A kind is a struct in its domain crate. The macro generates the schema, the
FFI procs, the DM surface, validation, the state codec and the docs.

```rust
#[vg::kind(domain = gas, dm = "/obj/machinery/atmospherics/binary/pump", ports = [input, output])]
pub struct Pump {
	#[vg(config, unit = "kPa", range = 0.0..=MAX_PUMP_PRESSURE, default = ONE_ATMOSPHERE, on_invalid = clamp)]
	target_pressure: f32,
	#[vg(config, unit = "W", range = 0.0..=MAX_PUMP_POWER, default = 30_000.0)]
	power_rating: f32,
	#[vg(config, default = false)]
	on: bool,
	#[vg(input, sources = [anchored, integrity_broken])]
	operable: bool,
	#[vg(state, unit = "mol/s")]
	flow_rate: f32,
	#[vg(state, unit = "W")]
	power_draw: f32,
}

#[vg::query(Pump, name = ui, fields = [target_pressure, power_rating, on, flow_rate, power_draw])]

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
}
```

- `config`: Rust store. DM gets `get_` and `set_`, seeded from DM type and map defaults (§3).
- `state`: Rust store. DM gets `get_` only.
- `input`: derived from DM. `sources` names the DM state it depends on (§7).
- `on_invalid`: `clamp` or `reject`. Validation exists once, in Rust.
- Units are part of the schema. Generated DM docs and defines carry them.

Whether a pump is powered is not an input: power lives in the Rust power
domain (M3), so the law asks the power domain directly.

## 3. Generated DM surface

For each kind the generator writes the procs into
`code/__defines/verdigris/_bindings.dm` and the type-level declarations into a
generated `_bindings_types.dm`:

```dm
#define VG_KIND_GAS_PUMP 7

// Seeds: type and map defaults for config, read once at bind, never again.
/obj/machinery/atmospherics/binary/pump/var/tmp/vgs_target_pressure
/obj/machinery/atmospherics/binary/pump/var/tmp/vgs_power_rating
/obj/machinery/atmospherics/binary/pump/var/tmp/vgs_on

/obj/machinery/atmospherics/binary/pump/proc/get_target_pressure()      // kPa
/obj/machinery/atmospherics/binary/pump/proc/set_target_pressure(value) // kPa; returns the stored value
/obj/machinery/atmospherics/binary/pump/proc/get_flow_rate()            // mol/s, read-only
/obj/machinery/atmospherics/binary/pump/proc/vg_query_ui()              // assoc list, one call
/obj/machinery/atmospherics/binary/pump/proc/vg_input_operable()        // declared here, implemented by the type
```

- **Seeds** (`vgs_*`) are the only place config defaults live on the DM side.
  Subtypes override them in their type block and mappers var-edit them. They
  are `tmp` (the state codec persists the Rust store instead), read once at
  bind, and a lint forbids any reference to them in a proc body. An unset seed
  uses the schema default. Seeds are never written at runtime, so they cost no
  per-instance memory unless a map edits them.
- **Accessors** are the only way to reach config and state. There is no DM var
  named `target_pressure`, so `target_pressure = 50` does not compile.
- **Admin var-edit** lists the config fields from the schema and writes through
  the setters. Editing a seed after bind also routes to the setter.
- **tgui**: `ui_data` calls `vg_query_ui()` (one FFI call).
- **Events**: the type implements `vg_event(event, list/payload)`, and the
  generated dispatcher calls it (§8).

## 4. Lifecycle

All of it lives in base procs keyed by the type's `vg_kind`, so a subtype
cannot skip it.

| Moment | Where | What happens |
|---|---|---|
| bind | base `on_materialize()` (L2) | one call spawns the Rust object with seeds and current inputs, stores `vg_handle` and registers the atom in the DM handle table |
| unbind | J1 `pre_destroy()`, which `qdel` runs before any `Destroy` override | removes the Rust object and clears the handle |
| collapse to latent | C10 collapse (a ledger transaction) | captures config and state into the blob, then unbinds |
| materialize from latent | ledger materialize | binds with the blob instead of seeds |
| an input source changes | the source's setter signal | resubmits the derived input (§7) |
| world start | `verdigris_init()` | resets every Rust domain store and checks the ABI hash. DM handles only ever exist in the current world. |

A handle is the R2 packed handle (20-bit index, 4-bit generation, exact as a DM
number). The DM handle table is a flat list per kind indexed by slot, so an
event resolves to its atom in O(1), and the dispatcher checks
`atom.vg_handle == handle` before calling it.

## 5. Writes

`set_x(value)` is one FFI call that:

1. resolves the handle (a stale, wrong-kind or unbound handle is a typed error
   and a DM runtime naming the object);
2. validates the value against the schema (`clamp` or `reject`);
3. submits a typed command through the domain's `MainPort` (R4), which applies
   it to the main-side overlay immediately and to the simulation at the next
   frame;
4. returns the stored value.

Nothing is buffered on the DM side, so nothing can be lost or reordered there.
Sets are rare (players, admins, mapload, construction). A benchmark COUNT gate
requires **zero binding sets per idle tick**: a per-tick DM write means a law
belongs in Rust.

## 6. Reads

`get_x()` is one FFI call returning `MainPort::read`: the overlay (every write
DM made this tick) over the pinned frame. From DM's point of view each object
is linearizable: a read always reflects every earlier set. State fields come
from the pinned frame, at most one frame old, and DM never stores them. Query
groups return several fields in one call.

DM must not cache a read in a member var across ticks. A generated lint flags
member assignments from `get_*` and `vg_query_*`, and a unit test checks that
no bound type declares a var named like one of its kind's fields.

## 7. Inputs: the only DM-owned values Rust stores

An input is a pure DM proc (for example `vg_input_operable()`) over declared
sources.

- **Closed sources.** Every source is DM state that changes only through a
  framework transition or a setter that sends a signal: `loc` (movement hooks,
  J5), `anchored` (a setter, and I5 construction), integrity breakpoints (D4),
  construction state (I5) and `panel_open` (a setter). Lints forbid raw writes
  to declared source vars; `loc` and `contents` are already linted (C1).
- **Event path.** The binding subscribes to its sources' signals and
  resubmits the derived value only when it changed.
- **Reconciler** (`SSvg`). A budgeted sweep recomputes every bound object's
  inputs and compares them with Rust's stored inputs in batched reads. It also
  compares the DM handle table with Rust's live set, looking for orphans on
  either side.
  - Test and dev builds reconcile **every** bound object after every unit test
    (in the test sandbox's teardown) and after every step of the binding fuzz
    test. A missed update fails the test that introduced it, naming the object,
    field, expected value and actual value.
  - Production sweeps cover every object within 60 seconds, repair any
    divergence and log it. The benchmark COUNT metric `vg_reconcile_repairs`
    must stay 0.

## 8. Events

Rust records events in its outbox. SSreactor drains each domain once per tick
(one FFI call per domain), and the generated dispatcher calls `vg_event()` on
the atom. There are no per-object callbacks each tick and no pushed stats: a
display value such as flow rate is a `state` field read when shown.

## 9. Errors and safety

- Panics are caught per FFI call (the bind macro already does this) and per
  command in the apply loop. A failing command leaves the stored value
  unchanged and reports an error. It never takes down the batch or
  DreamDaemon.
- Every error is typed (kind, field, handle, reason) and becomes a DM runtime
  with the atom attached.
- Validation, clamping and unit conversion exist once, in Rust.
- Handles are generation-checked and per kind, so reusing a slot cannot alias.

## 10. Why desync cannot happen

| Scenario | Why it can't |
|---|---|
| DM code changes a setting without telling Rust | the DM var does not exist; only `set_*` changes it |
| Rust clamps or updates a value DM still holds | DM holds no copy |
| A read right after a write sees the old value | reads are the overlay over the frame (read-your-writes) |
| An object is created, destroyed or collapsed without Rust knowing | bind and unbind are in base lifecycle procs that subtypes cannot skip (materialize, J1 pre-destroy, ledger collapse), and the reconciler checks identity both ways |
| A stale handle hits a recycled slot | the generation check, plus per-kind tables |
| A map or admin edit changes a value | seeds are read once at bind; var-edit writes through setters |
| Save and load | the state codec reads and writes the Rust store |
| An invalid value | it is validated once, in Rust, and the setter returns what was stored |
| A panic in the middle of a batch | a per-command catch; the value is unchanged and an error is reported |
| A new round with leftover Rust state | `verdigris_init()` resets every store; the ABI handshake |
| A DM-owned input changes through a path nobody hooked | lints on source writes; the reconciler fails CI and repairs production within one sweep |
| DM caches a Rust value in a var | the lint on member assignment from reads, and the unit test on bound types' vars |

## 11. Enforcement

- **Compile time:** bound fields have no DM var, so the accessors are the only API.
- **Generator checks:** the DM base type exists; seeds match config fields; no
  DM var on a bound type collides with a field name; every event has a
  handler; units and ranges are declared.
- **Lints:**
  - `call_ext` only in generated files (this exists);
  - `vgs_*` only in type blocks and maps;
  - no raw writes to input sources;
  - no caching of reads;
  - no positional multi-slot commands (the generator only emits typed ones).
- **Tests:**
  - read-your-writes;
  - stale and wrong-kind handles;
  - bind at materialize, and unbind at pre-destroy even when `Destroy` is overridden;
  - the latent collapse and materialize round trip;
  - the state save and load round trip;
  - a panic becomes a DM runtime;
  - the `verdigris_init()` reset;
  - the reconciler catches a deliberately injected desync (a test that bypasses a setter through `vars[]` must fail);
  - a fuzz test of random sets, moves, breaks, destroys and collapses, with full reconciliation after every step.
- **Benchmarks (COUNT metrics, independent of load):**
  - binding sets per idle tick = 0;
  - reconcile repairs = 0;
  - FFI calls per idle tick do not grow.

## 12. Cost

- One FFI call per set, get or query, and none per idle tick from bindings.
- Per bound object: one `vg_handle` var and one handle-table slot. Seeds are
  type-level, with no per-instance memory unless mapped. Schemas are static.
- The reconciler costs one derived-input evaluation per object per sweep
  period, in batched reads. For example, 5,000 objects over 60 seconds is
  about 85 evaluations per second.

## 13. The pump, before and after

Before (`pump.dm` today):
- a `target_pressure` var;
- six scattered `update_rust_device()` calls;
- `rust_set_device(1, 2, RUST_DEVICE_LAW_PUMP, target_pressure, power_rating)`, with four positional slots;
- a string-keyed device map in SSair, with a commit per call;
- `rust_device_stepped()` pushing display values every tick.

After:

```dm
/obj/machinery/atmospherics/binary/pump
	vg_kind = VG_KIND_GAS_PUMP
	vgs_target_pressure = ONE_ATMOSPHERE

/obj/machinery/atmospherics/binary/pump/vg_input_operable()
	return anchored && !(stat & BROKEN)

/obj/machinery/atmospherics/binary/pump/ui_data(mob/user)
	return vg_query_ui()

/obj/machinery/atmospherics/binary/pump/ui_act(action, list/params)
	. = ..()
	switch(action)
		if("pressure")
			set_target_pressure(text2num(params["pressure"]))
			return TRUE
		if("power")
			set_on(!get_on())
			return TRUE

/obj/machinery/atmospherics/binary/pump/vg_event(event, list/payload)
	if(event == VG_EVENT_PUMP_TARGET_REACHED)
		update_icon()
```

No `process()`, no sync calls, no ids, no port numbers, no per-tick callbacks.

## 14. Migration

1. **Runtime and generator** (R10, one branch):
   - the `#[vg::kind]`, `#[vg::query]` and `#[vg::events]` macros;
   - per-kind handle tables on `MainPort`, validation and typed errors;
   - the generated DM surface;
   - `SSvg` (the reconciler and event dispatch);
   - lints and tests.

   The pump is the reference kind.
2. **Gas devices** (M2): every device kind moves onto it. These are deleted:
   - `rust_pipenets.dm`'s device procs;
   - `SSair.rust_pipe_devices` and `next_rust_device_id`;
   - `rust_device_stepped()`;
   - every `update_rust_device()`.
3. **Power** (M3 consumers, producers and storage), **heat** (bodies and the H4
   regulator) and **radiation** sources: each becomes kinds, and its old binds
   are deleted.
4. **Stateless binds** (jobs, layout, metrics, bulk topology registration)
   become typed commands and queries through the same generator.
5. The old untyped paths are deleted with no shims, and the lints turn on
   repo-wide.

Classification of the existing binds, and the order, go in this file's
appendix as each lands.

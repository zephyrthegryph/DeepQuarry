# Material engineering implementation

Accepted scope: shared operating loads and condition, correct conservation and
elapsed-time accounting, branch-aware power delivery and cells, pressure/chemical/
thermal assemblies and pumps, configurable emitters, physical diagnostics and
repair, fabrication feedback, measured contract qualification, dependency-driven
updates, and focused plus live verification.

## Delivery checklist

- [x] Shared construction, condition, operation and property definitions.
- [x] Fixed-reference pressure ratings; duration-based chemical exposure;
      conservative heat/leaks; persistent wear and stored energy.
- [x] Dependency subscriptions for ambient and internal exposure, including off
      and sleeping equipment; lifecycle cleanup and topology changes.
- [x] Cells: delivered-energy accounting, discharge limits, no refill on rebuild,
      local temperature, finite thermal buffers and superconducting operation.
- [x] Cable graph: branches/loops, per-path losses, local temperature and exposure,
      topology caching, source/consumer accounting.
- [x] Atmos containment and pump performance; preserve heat-exchanger semantics.
- [x] Emitters: requested/actual output, cadence, real input/beam/heat accounting,
      installed components, cooling and faults.
- [x] Existing tools and compact interfaces expose measured loads and limits;
      component replacement repairs only the replaced component.
- [x] Fabrication defaults, estimates and comparable role effects.
- [x] Physical qualification projects and existing contracts/evidence/documents;
      configuration identity, useful delivered output, sustained stages.
- [x] Tests exercise actual outcomes, conservation, different update intervals,
      sleep/wake/movement/deletion, and normal station defaults.
- [x] Bounded live Southern Cross smoke test, visual inspection, commit/restart.

No item above is complete merely because a component has a material ID or a
generic statistic changes. Each completed item requires observable operation.

## Implementation map

- `material_service.dm` owns assembly temperature, finite phase storage, chemical
  exposure time, operating energy totals, and dependency-driven environmental
  observation. It is independent of a machine's on/off processing flag. It watches
  both internal and surrounding gas, movement through nested containers, turf
  replacement, and Rust pipenet handle replacement. Destruction releases the
  original subscription identity, queued work, and signals. Exposure uses a
  dedicated resumable subsystem, not one callback timer per assembly. Queue
  ownership swaps between generations; repeated notifications coalesce.
- `material_composites.dm` applies cold-reference pressure strength, persistent
  fatigue, separate liner/exterior corrosion, and conservative gas leakage.
  The service owns solid/gas heat exchange so normal machine processing cannot
  apply the same environmental exposure twice.
- `material_power_graph.dm` reduces straight cable runs to resistor edges, solves
  junction currents, distinguishes branch load, and divides current around loops.
  `powernet.dm` charges source-side losses and deposits that paid energy into the
  cable distribution from the completed interval before replacing its solution.
  The loop-core numeric iteration is implemented once in Rust
  (`verdigris/verdigris/src/material_power.rs`) with f64 arithmetic, bounded input
  sizes/work, finite-value validation, and the existing panic-isolated FFI.
  DM retains the physical topology, material coefficients, heat and damage.
- `cell.dm` accounts for actual stored-energy debit, delivered charge, resistive
  heat, and a shared discharge allowance. Reapplying construction preserves charge
  and damage. Critical temperature/current come from the conductor; finite cooling
  comes from the thermal role, not an energy multiplier.
- `material_equipment.dm` supplies pump drive/impeller behavior and emitter input,
  beam reservoir, output, and waste-heat accounting. The gas helpers apply useful
  compression work to the receiver, including committed batched transfers.
- `material_diagnostics.dm` uses existing multitools, screwdrivers, material
  stacks, photocopiers, paper evidence, and fax delivery. There is no special trial
  device or UI certification action. Printed values use readable names and units.
- `EngineeringAssembly.tsx` displays condition, operating limits, installed parts,
  emitter settings, and the current observation. `SelectableRecipe.tsx` keeps the
  default recipe compact and exposes comparable, component-specific properties
  when choosing replacement materials.
- `engineering_qualification.dm` provides recorded power, pressurized-transfer,
  and beam projects through the existing contract/role/stage/evidence framework.
  Acceptance time, non-overlapping intervals, configuration revision, immutable
  report identity, measured output, and conversion efficiency constrain progress.

## Contract and workshop cleanup

The design review removed catalog breadth that did not correspond to a real
player decision. Generic objective-priority negotiation is gone; contracts add
special terms only for delivery time, payment, disclosure, ownership, liability,
or an operating protocol. Social roles remain available for credit and payout
agreements, but ordinary contract completion no longer depends on registering
nominal participants. Population-dependent Research sales scale their customers,
product breadth, and revenue together. The former replication offer is out of
rotation until the game can identify a repeatable experiment and an independent
operator.

Alloy qualification now comes from applying an ordinary analyzer to the actual
finished stack. The event records its remaining physical quantity and keeps the
analyzer operator distinct from any later document handler. Furnace firing a
finished batch performs a real high-temperature solution treatment; the hot
stock can then be forged or quenched in the existing bath. Unreachable process
names and phases were removed rather than retained as unused simulation knobs.
Bulk-derived special behavior also requires a meaningful fraction of its active
feedstock, preventing trace-everything mixtures from collecting every ability.

Engineering assembly qualification uses one sustained 45-second operating
record. A copied report cannot qualify another contract, and configuration
changes reset the observation. This retains physical setup and measurement
without asking players to repeat the same run and fax three times.

## Verification findings fixed during implementation

- Default emitter output must use concrete optical melting temperature, not the
  legacy heat-resistance score (ordinary glass leaves that score unset).
- `WEAKREF(src)` deliberately returns null after deletion begins. Cleanup must
  retain/use the original weak-reference identity when unregistering gas watches.
- A recreated pipenet can have unchanged pressure but a different gas handle.
  Topology publication now explicitly invalidates material watches.
- Replacing an emissive/radioactive material with inert stock must also update the
  existing behavior component and stop its processing, not merely change its ID.
- BYOND's represented cell-charge change is used for heat accounting so numeric
  rounding does not create a discrepancy between reported and stored energy.
- Tiny-map tests cannot assume the full station's unit-test landmarks exist.
  World-interaction tests use real map turfs and an in-bounds physical beam target.
- Heating unchanged reagents must immediately invalidate their cached corrosion
  rate. If settling corrosion destroys the vessel, callers stop using its service
  owner; nullspace vessels delete safely without attempting a spill onto null.
- The first full-station smoke test exposed scaling problems absent from the
  tiny map: roughly 22,000 material timers and power-network stages above a
  second. That build was stopped, not accepted. Exposure moved to a budgeted
  queue; electrical resistance weights are cached and the preconditioned solver
  warm-starts from its last solution. Unused degree-two cable knots are collapsed.
  Thermal changes below 0.05 K remain stored until meaningful enough to process;
  their energy is not discarded.
- The next live run confirmed the timer reduction (around 200 rather than
  22,000) but still exposed excessive electrical work. Pendant branches now use
  an exact tree reduction, only loop cores iterate, and a temperature change
  invalidates only its affected cable runs. Per-graph solving, resistance, and
  heat-deposition timings are included in the compact profiler.
- Those timings identified a 962-junction main-grid core spending about 1.2s
  in DM's 256-iteration loop. The numeric loop was replaced with the Rust solver;
  a 1,600-junction mesh, malformed-input checks, and warm-start/loop tests pass
  in the host Rust test build. There is no retained DM solver fallback.

## Scope and limits

The model deliberately uses representative geometry and nominal distribution
voltage. It is not an arbitrary circuit simulator, an inventory heat simulation,
or a promise that every possible custom material/network combination is balanced.
The focused test run covers this change; generated-station tests and the slow full
DM suite are not part of this pass. Multiplayer balance remains a playtest task.

UI validation: the diagnostics and fabrication functional checks pass (3 tests,
11 assertions). TypeScript and Biome checks pass, and the production bundle was
generated. The new diagnostics was rendered with the actual stylesheet and
visually inspected at 680 × 1000. The broader UI suite encountered existing
35-ms timing gates in its large-button and power-monitor benchmarks; the host
measured 100% CPU utilization during this verification. Those gates were not
weakened or disabled. This is not a claim that the full test suite is green.

Final focused DM regression: **19 passed, 0 failed, 0 skipped**, using
`virgo_minitest` on 2026-09-04. This includes actual emitter target damage, real
cable connectivity and heat deposition, affordable fractional cell draws,
infinite-cell compatibility, and zero runtimes. The scratch focus list is cleared
before committing. The test compile reported one pre-existing unused-variable
warning in `pinpointer.dm`.

The final six-test follow-up also passed with zero failures and zero runtimes,
including temperature-dependent reagent corrosion and safe vessel rupture both
on-map and in nullspace. Compilation took 1m20s; the focused assertions completed
in approximately 0.12s after the tiny map initialized.

After the full-map scaling correction, an eight-test follow-up passed with zero
failures and zero runtimes. It includes queue coalescing/deletion and warm-started
branch/loop solutions in addition to the physical conservation tests.

The final Rust-backed integration run also passed all eight DM tests with zero
runtimes (`data/logs/material-ffi-retry-20260904`). It caught and corrected both
the binding suffix and plain-list-versus-associative-list marshaling before live
use. The three focused host Rust tests passed; the 32-bit release DLL also built.

## Final live smoke test

The production build passed DreamChecker with zero diagnostics and DM compilation
with zero errors (the existing unused `itemlist` warning remains). The restarted
Supermatter-only server listens on port 1337. The final measurements are under
`data/logs/material-engineering-perf-heap-20260904`.

The initial native run reported 247.406 seconds of initialization; the final,
more heavily contended run reported 293.524 seconds.
The first two gameplay profile snapshots contained no DM runtimes. The main
3,407-cable graph solved in 18.75 ms, then 12.5 ms, compared with approximately
1,206 ms for the earlier DM numeric solver. Its heat-deposition pass still took
81–88 ms; the entire powernet stage was 138–193 ms. These are logical stage costs,
not a claim that every server tick takes that long. Timers remained around 230,
with recent timer subsystem averages below 0.25 ms, rather than the earlier
22,000-timer explosion.

The follow-up performance pass removed two remaining sources of needless work.
Material subscriptions now have a mixture-level registry: ordinary room-air
remixing is classified once and does not fan out across every housing, while
temperature, corrosive plasma/miasma/zauker/hot oxygen, and dangerous pressure
changes retain immediate semantic wakeups. Cable heat is conserved in five-second
batches; grids containing superconductors still settle every accounting cycle.
Finally, future exposure deadlines use a min-heap rather than rescanning every
future-due assembly once per second. Four focused regressions cover semantic wake
filtering, heap ordering/reprioritization/deletion, movement/subscription cleanup,
and physical cable-loss conservation; all pass with zero failures.

On the final full-map run, the exposure logical run fell from approximately
3.87 seconds/199 slices before the heap to 0.35 seconds/34 slices as the startup
thermal transient settled. The roughly 12,000 `pending` entries are future heap
deadlines, not objects visited every fire. Recent powernet averages were 52–68 ms,
versus 164–208 ms before batching, and the last complete powernet stage measured
43 ms. The main graph's native numeric solve remained about 15–18 ms. The most
recent complete machinery stage was 141 ms, of which the gas dependency scan was
115 ms; only 83 material/device wakes were accepted from 1,575 dirty mixtures.
The host was 72–83% busy during sampling and had large unrelated contention, so
these are comparative smoke-test measurements, not isolated hardware benchmarks.
Multiplayer balance and destructive playtests remain open, but the material
system no longer creates the timer, numeric-solver, future-queue, or ordinary-air
fanout pathologies found during this pass.

At the sampled point DreamDaemon used approximately 1.65 GiB working set and
1.68 GiB private memory. The server is left running for playtesting. The diagnostic
preview is a rendering of the actual React component and stylesheet with fixture
data, not a screenshot of a live BYOND measurement.

## The material card, traits and batches (lane L2)

The ~56 stats the model once carried collapsed into a short card, traits that show only when
present, and a batch of three things. Nothing below is stored twice: every other number is a
formula over these (`code/content/materials/properties.dm`).

**The card** (`/datum/material`): `strength`, `toughness`, `heat_resistance`, `conductivity`,
`corrosion_resistance`, `weight`, on one scale (steel: 60, 75, 38.75, 11, 50, 20; exotic stock
runs past 100). Derived readers: `melting_point()` (250 K + 40 per point of heat resistance),
`conductive()` (conductivity 8 or more), `electrical_resistivity()`, `dielectric_strength()`,
`specific_heat()`, `yield_strength()` (5 x strength), `fracture_toughness()` (0.3 x toughness),
`brittleness()` (strength over toughness), `protectiveness()`, `explosion_resistance()`.
Hit points are `toughness * MATERIAL_HP_PER_TOUGHNESS`. Calibration formulas that were written
against a steel part measure a part against steel (`MATERIAL_REFERENCE_*`).

| Collapsed | Into |
|---|---|
| hardness, yield_strength, integrity, protectiveness, explosion_resistance, fracture_toughness, elasticity, brittleness | strength and toughness |
| conductivity, electrical_resistivity, conductive, dielectric_strength, thermal_insulation, magnetism | conductivity |
| reactivity | corrosion_resistance (its inverse) |
| heat_resistance, melting_point, specific_heat | heat_resistance |
| density | weight |

**Traits** (`traits`: id -> strength 0-100, only the ones a material has): superconducting,
thermal buffer, cryogenic buffer, thermal switch, shape memory, piezoelectric, thermoelectric
(also the heat pump), radiovoltaic (also the glow after irradiation), field storage (also the
slow trickle), exothermic, reactive, catalytic, sorbent (gas and reagent pores), antimicrobial,
hemostatic (also the tissue mend), luminescent, radioactive, toxic. The six temperature
thresholds are fixed per trait or follow its strength (`critical_temperature()`,
`thermal_switch_temperature()`, `MATERIAL_*_TEMPERATURE`); there is one strength each.
`field_charge_efficiency`, magnetism and the dead surface and field entries are gone.

**A batch** (`/datum/material_batch`) is composition, temper and flaws.
- *Composition*: substance id -> amount in sheets. Bulk materials and trace substances are one
  list; a wanted additive (carbon in steel) is just composition. There is no impurity list and no
  scalar purity.
- *Temper*: 0 soft to 100 hard. Quenching raises it (strength up, toughness down); a
  solution-treated piece left to cool without a quench, or the anneal step, brings it back down.
- *Flaws*: 0 flawless to 100 ruined, one number for porosity, locked-in stress, defects and
  poor mixing. Casting adds flaws; forging, homogenising, purifying, vacuum and beams remove them.

**Trace effects** (`material_traces.dm`): a small table, each substance with one clear effect per
percent of the batch mass, saturating at its limit: sulfur lowers toughness, dissolved hydrogen
lowers toughness (embrittlement), lead lowers strength and adds the toxic trait (surgical tools
poison), carbon raises strength and lowers conductivity and superconduction, silicon and
interstitial phoron raise heat resistance, oxide inclusions lower corrosion resistance, lithium
raises conductivity. An acid wash strips leachable traces; a hard vacuum degasses.

**Breakdown**: every card stat and trait carries the steps behind it (`stat_notes`), shown as
"Toughness 62: base 70, sulfur -12, tempered +4" in examine, the engineering window, the
fabricator picker and the wiki. The traces themselves stay hidden until assayed.

**Assay**: an analyzer used on any material stack is a spectrometry reading
(`/obj/item/stack/material/proc/assay`). It reveals the stack traces and marks it assayed. The
analyzer on processed stock also records the contract certification as before.

**Stacks merge like a beaker of solid.** Plain stock of the same material merges whatever lot it
came from; its trace amounts add (so concentrations average by amount), a split takes its share,
and the merged stack is unassayed if either half was. Processed stock merges when its bulk
composition, temper bucket and treatments match (`/datum/material_batch/proc/identity()`); its
traces average and the merged stock is registered as the material its new traces make. Stock of
a different temper or treatment does not merge. Ordinary building ignores traces: a stack
material is the plain singleton; only melting a stack into a batch, or engineering with an
alloy, uses them.

**Open for L4**: the trace roll on fresh stock (`GLOB.material_stock_trace_pool`) is a stand-in
for per-round and per-lot pools of each source signature contaminants; reagent ids that match
a trace-table id (carbon, silicon, lithium, sulfur, hydrogen, lead) already enter melts as that
substance, any other reagent enters as an inert residue until the contaminant vocabulary links
up. Surface layers and field treatments are unchanged inputs to the traits.

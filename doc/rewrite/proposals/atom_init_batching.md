# Atom init: per-type templates, inert-atom skip, relation batching

Status: design, written from measurements (2026-10-30). Nothing below is implemented yet except the measuring tool.

## 1. Measurements

Tool: `-params boot_phase_timers=1` (`code/engine/kernel/boot_phase.dm`; a server build takes it as `DQ_WORLD_PARAMS=boot_phase_timers=1`).
It prints, per phase, the wall time summed over the map load, the calls, and the types that spent the most. Rows are inclusive and
overlap. Each timed phase costs about 3 us itself (an empty step reads 3 to 4 us), so rows of a few us each are timer overhead.

Production boot of Southern Cross, 485,253 atoms (393,468 turfs, 91,887 objects, 50 mobs), `Atoms` 224 to 238 s with the timers on
(a loaded machine gave 416 s: compare ratios, not seconds):

| Phase (inclusive) | Objects | Turfs |
|---|---|---|
| `Initialize` (decls + caps_init + nested inits) | 65 s, 712 us each | 60 s, 152 us each |
| `setup_run` | 45 s, 487 us each | 24 s, 61 us each |
| `caps_init` | 33 s | 45 s (about 35 s of it is the timers' own overhead, see 2.1) |
| `lifecycle_decls_init` | 18 s | 5 s |
| `materialize` | 19 s | none (fast path) |
| early starts, params, `setup_early` | 13 s | 6 s |
| `engine_init`: capability `on_holder_init` / `lifeform_init` / `stat_holder_init` / `hooks_change_baseline` | 11 / 8 / 4 / 3 s | 1 / 6 / 1 / 6 s |

Types that dominate (production): objects `/obj/structure/lattice`, `/obj/machinery/door/firedoor/*`, vents and pipes
(`atmospherics/*`), windows (`setup_run` 7 s, `materialize` 6 s), `/obj/structure/extinguisher_cabinet` and `/obj/item/extinguisher`
(starting contents, `lifecycle_decls_init` 2.8 s each), lights, grilles. Turfs: `/turf/space` is 310 k of the 393 k.

BYOND profile of the same boot (inflated about 2x): `rel_set` 88 s inclusive over 412 k calls, `rel_view_set` 57 s over 183 k,
`_rel_attach` 55 s over 213 k, `own_key` 12.5 s self over 572 k, `state_changed` 849 k calls, `own_field_changed` 384 k calls.

### 2. What the numbers say about the three ideas

2.1 Per-type template (and the inert-atom skip) for turfs. A probe of the compiled plans (`init_plan`, `lifeform_plan`) gives:

| Type | init plan steps | what they are |
|---|---|---|
| `/turf/space` | 1 | the lifeform step (two `setup` rows); no capability hooks, relations, baselines, verbs or every() |
| `/obj/structure/lattice` | 1 | the same |
| `/turf/simulated/floor/tiled/steel` | 4 | on_change baseline, verb entry, adjacency, setup rows |
| `/turf/simulated/wall/r_wall` | 5 | the same plus every() |

So the engine already replays a compiled per-type plan, and for 64 % of the atoms (space) that plan is one step. A template or a skip
for space turfs can save only the per-call overhead of `engine_holder_init`, `table_of`, `init_plan_of` and the eleven `if` tests:
about 10 to 15 us real per atom, 3 to 5 s of 224 (2 %). Most of the large `/turf/space` rows above are the timers' own overhead (11
timed steps at 3 to 4 us each). The structural gain the lanes assume is not there for turfs.

2.2 The cost is per-instance work of simulated turfs and of objects with declared state: three `setup` hooks and a sunlight handler and
turf-edge adjacency and an `after_init` timer on every simulated turf; starting contents (a cabinet makes an extinguisher, which runs a full
nested init); `on_holder_init` hooks of machinery; `materialize` of windows, lights, grilles and doors; relation links.

2.3 Relations are the one engine cost that is both large and general (the profile above): each link writes the view, calls
`own_field_changed`, makes the target's reverse index entry (`_rel_index`, which needs `own_key(source)`: nine string builtins the first
time a datum is keyed) and the partner side.

## 3. Design

### 3.1 Per-type template (lane 1)

Extend `init_plan` from "which steps run" to "what the steps produce when nothing is mapped on the instance":

- `lifeform_init` for a type whose plan has only setup rows: the plan stores the rows; `setup_note` is the only per-instance act. Done
  inside the plan walk, not as a separate step.
- `hooks_change_baseline`: a type's baseline for a hook whose inputs are vars equal to the type's initial values is a constant of the type.
  The template stores the value once per (type, hook) and an instance with no edited input var copies it into `change_last`. An instance
  whose inputs were edited by the map (`vars` differ from `initial()`) takes the walk. The condition is checked with the same
  `own_field_static_work` memo the write path uses, so the two cannot disagree.
- `stat_holder_init`: the same rule for stats whose inputs are unedited (the stat layer already captures map edits of stat vars).
- Capability `on_holder_init` stays per instance (it makes instance state); it already runs from the plan.

Observable state is identical by construction; proof is a test that boots each representative type twice (template and walk, switched by
a debug toggle in the style of `GLOB.init_plan_off`) and compares `change_last`, stat values, `rx` records and relation indexes.

### 3.2 Inert-atom skip (lane 2)

An atom is inert for init when its type's plan has no steps beyond setup rows, it has no owned starts, no relations and no mapped
edits. For such an atom `engine_holder_init` is not called: `caps_init` tests one bit on the type's plan. This is the cheap part and is
all that the data supports for turfs (2 %). The risky half of the idea (deferring setup to first touch) is not supported by the data: the
space turf's two setup rows are the only per-instance work, and they are `space_appearance` (must run before the chain) and a plain row.
Deferring work to first touch would add a first-touch path to every reader of those vars for no measured gain, so it is not planned.

### 3.3 Relation batching (lane 3)

A map load makes about 213 k links. Batch them in the init frame (`materialize_batch`, which already defers power binds and resolvers):

- During the outermost `InitializeAtoms()` a link's reverse-index insert (`_rel_index`) and its `own_field_changed` for a source that is
  not yet initialized are queued as (target, source, var) rows instead of run per link; the frame flushes them once, grouped by target, so
  an index (`om_refs_in`, the turf index) is created and grown once per target and `own_key(source)` is read once per source.
- A queued row that a later write removes (an `_rel_detach` of the same link before the flush) is dropped from the queue, so the flush
  never indexes a link that no longer exists.
- `own_field_changed` for an uninitialized source is already skipped by `state_changed` (pre-init); the batch keeps that and publishes
  nothing the per-link path would not.

Tests: a link made before and after the flush has the same index; a detach inside the frame leaves no index entry; the full-map
reverse-index census (`rel_index` totals per type) is equal with the batch on and off.

## 4. Order

By measured payoff: (3.3) relations, then the per-instance setup/materialize costs of the top object types (windows, firedoors,
vents/pipes, cabinets), then (3.1) baselines and stats for simulated turfs, then (3.2) the one-bit skip. The measuring tool lands first
so every step is read off an unprofiled production boot.

## 4. Measurements 2026-10-30 (after the space-turf step skip)

Same tool, production Southern Cross, timers on (load-sensitive: compare rows).

| Row | Before | After |
|---|---|---|
| `caps_init (turf)` | 44.9 s | 23.7 s (`engine_holder_init (turf)` 39.8 s to 18.7 s) |

`/turf/space` no longer enters or times the engine steps its plan has no work for (`engine_holder_init_planned`).

### 4.1 Rule bindings (13 to 16 s, 21.6k bindings, 180 us each)

New rows split `materialize: rule bindings`: `owner links and table` 5.2 to 6.0 s (two `rel_set`, 240 to 275 us per binding),
`subscribe` 7.9 s (`node_of` 2.0 s over 15k, `dq_rx_when_threshold` 4.1 to 4.3 s over 15k, 270 to 285 us each), `baseline check` 1.4 s.
Windows are 5 s of it (6.7k, `/obj/structure/window/reinforced`), then firedoors 1.7 s and lights 1.2 s.
No cheaper per-instance form exists without changing what a binding is: each threshold trigger creates a native node and a native watch
per object. A design change would be one shared watch per (type, property, level) that fans out to its owners, or deferring thresholds
the way heat rules already defer (`dq_rules_heat_deferred`) until the object's first touch. Neither is done here.

### 4.2 `own_field_changed` full path on init

`ofc stat_relation_changed: power_area` is 8.3 s over 22k writes (375 us), almost all of it `stat_ct_update` (three channel entries per
machine, 67k updates, `gate` 2.0 s, `release` 0.5 s) on pipes, firedoors and lights. `flooring` writes cost 100 us in `own_field_changed`
(`draw_hop_published` 0.9 s, `publish_change` 0.7 s) of 217 us for the whole `rel_set`.

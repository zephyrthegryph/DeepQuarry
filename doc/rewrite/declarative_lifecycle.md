# Declarative lifecycle: conversion guide

Status: **authoritative** for the declaration primitives. Macros:
`code/__defines/lifecycle_decl.dm`. Runtime: `code/datums/lifecycle/declarations.dm`.
Tests: `code/modules/unit_tests/dq_decl_lifecycle_tests.dm`. Backlog lint:
`tools/ci/decl_lint.py`. Read [lifecycle.md](lifecycle.md) first for the destroy transaction
and `DECLARE_REF`.

## 1. The idea

Most `Initialize()` overrides and `on_destroy()` hooks do generic work: fill reagents, make a
cell, set an icon, join a registry, start a timer, drop contents. Each of those is now **one line
next to the type**, and the lifecycle does the work. Every declaration is added to one table per
type, built the first time an instance asks and shared by every instance. Nothing is allocated
per instance except what the declaration creates.

Rules:

- Declarations take **constants**: numbers, paths, strings, and lists of those. They are
  evaluated once per type. Where a value can differ per instance (a mapped `volume`), pass the
  **var name as a string** and it is read from the instance when applied.
- A declaration naming a var the type does not have is reported once (a stack trace at table
  build) and dropped.
- Declarations inherit. A subtype adds to the table its parent built. Each primitive says
  whether a subtype's line replaces or adds (§3).

## 2. When each declaration runs

| Point | Where | What runs, in this order |
|---|---|---|
| **init** | end of `/atom/Initialize()` (the root, so before any subtype code after `. = ..()`), and `table_initialize()` | 1 children, 2 gas, 3 reagents, 4 appearance |
| **materialize** | `/atom/on_materialize()`, after the core registries, rules and OM start | 5 conditional registries, 6 service members, 7 binds, 8 behaviours, periodic work, timers |
| **dematerialize** | `/atom/on_dematerialize()`, before the core leaves registries | periodic stop, service leave, bind release (skipped while destroying: phase 1 did it) |
| **destroy** | the destroy transaction | phase 1: bind release. Phase 3/4: children, by their `DECLARE_REF` kind. Phase 6: `DESTROY_EFFECTS`, including `drop_contents` (per atom, before a batch merge) and `debris` |

Instance state is set up at **init** rather than materialize. A sandboxed object
(`new_unmaterialized()`, a latent entry being built) then has its reagents, children and
appearance, which it must have. Only its world registrations wait for materialize.
`dq_decl_order` tests this.

Turfs don't call the root `Initialize()`. Declarations on turfs only run through
`table_initialize()`, so don't declare init-time state on a turf type that overrides
`Initialize()`.

## 3. The primitives, with before and after

### 3.1 Starting reagents: `DECLARE_REAGENTS`

```dm
DECLARE_REAGENTS(PATH, VOLUME, CONTENTS)          // VOLUME: number, var name, or null = parent's
DECLARE_REAGENTS_TINTED(PATH, VOLUME, CONTENTS)   // then color = reagents.get_color()
DECLARE_REAGENTS_TYPED(PATH, VOLUME, CONTENTS, /datum/reagents/x)
DECLARE_NO_REAGENTS(PATH)                         // drop the inherited declaration
```

**CONTENTS add to the parent's**, the way the old `. = ..(); reagents.add_reagent()` chain did.
VOLUME replaces the parent's.

```dm
// Before
/obj/item/reagent_containers/pill/tox/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_TOXIN, 50)
	color = reagents.get_color()

// After
DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/tox, null, list(REAGENT_ID_TOXIN = 50))
```

```dm
// Before (illustrative: a type that owns its holder)
/obj/structure/sink/Initialize(mapload)
	. = ..()
	create_reagents(100)
	reagents.add_reagent(REAGENT_ID_WATER, 100)

// After
DECLARE_REAGENTS(/obj/structure/sink, 100, list(REAGENT_ID_WATER = 100))
```

Hazards:

- **Order.** Declared reagents are added at the root, before a parent's own post-`..()`
  additions (snacks' nutriment). If the total overflows the volume, the parent's additions are
  what get truncated now. Treat an overflow as a bug in the numbers. The table warns on it.
- **Holder resets.** If the type or an ancestor calls `create_reagents()` in its own
  `Initialize()`, that runs after the root and throws the declared contents away. Convert the
  ancestor's holder first: declare its volume with `DECLARE_REAGENTS(ancestor, N, null)` and
  delete the `create_reagents()` line.
- **Keep in Initialize:** amounts from `rand()` or per-instance picks, `add_reagent()` with a
  data argument, and reagents chosen by state set in `Initialize()` (see the MRE `seasoning`
  var in `code/game/objects/items/weapons/storage/mre.dm`).
- **Per-type list vars** that only feed `add_reagent` in a loop (`prefill`,
  `filled_reagents`) become a declaration, and the var goes. DM allocates a type-level
  `list(...)` initial value per instance, so these are a memory win too.

**Script:** `python tools/ci/decl_convert_reagents.py [--dry-run] [path-prefix...]` converts
the leading run of constant `reagents.add_reagent(ID, N)` lines after `. = ..()` for every
type under `ROOTS` in the script (the types whose holder is declared). It skips any type whose
own or ancestor's `Initialize()` resets the holder. Add a root to `ROOTS` once you declare its
holder.

### 3.2 Owned children with a default: `DECLARE_DEFAULT_CHILD`

```dm
DECLARE_REF(PATH, "var", OWNED|OWNED_LIST|HELD|SPILL|SPILL_LIST, null)   // how it dies (unchanged)
DECLARE_DEFAULT_CHILD(PATH, "var", DEFAULT)                            // how it's born
```

DEFAULT is a type path, a list of paths or `list(path = count)` for a list var, or the **name
of a var holding the type** (`"cell_type"`). The var's own value wins:

- a path in the var (`var/obj/item/cell/cell = /obj/item/cell/high`) creates that path;
- an instance creates nothing;
- a list of paths creates each.

Children are made with `new type(src)`. The `DECLARE_REF` line is required; the table refuses a
default for a var that has none.

```dm
// Before
/obj/machinery/space_heater/Initialize(mapload)
	. = ..()
	if(cell_type)
		cell = new cell_type(src)
	default_apply_parts()

// After
DECLARE_DEFAULT_CHILD(/obj/machinery/space_heater, "cell", "cell_type")

/obj/machinery/space_heater/Initialize(mapload)
	. = ..()
	default_apply_parts()
```

```dm
// Before
/obj/machinery/floodlight/Initialize(mapload)
	. = ..()
	cell = new(src)

// After
DECLARE_DEFAULT_CHILD(/obj/machinery/floodlight, "cell", /obj/item/cell)
```

Keep in `Initialize()`: children built with extra arguments (`new X(src, a, b)`), children
wired to each other after creation, and random picks. You can still declare a child and then
configure it in `Initialize()` after `. = ..()`, because the child already exists by then.

The destroy side is just the `DECLARE_REF` kind. Delete any `qdel(var)` / `QDEL_NULL(var)` in
`on_destroy()` for an OWNED var (`decl_lint`: `destroy_qdel_owned`).

### 3.3 Gas contents: `DECLARE_GAS`

```dm
DECLARE_GAS(PATH, "air_contents", VOLUME, TEMP, list(GAS_O2 = kPa, ...))
```

Moles are `P * V / (R * T)` per gas. VOLUME may be a var name. The var must also be declared
`OWNED`, and the gas mixture handle is released with it in phase 4.

```dm
// Before (illustrative)
/obj/item/tank/oxygen/Initialize(mapload)
	. = ..()
	air_contents.adjust_gas(GAS_O2, (6*ONE_ATMOSPHERE)*volume/(R_IDEAL_GAS_EQUATION*T20C))

// After (when the base creates air_contents only to fill it)
DECLARE_GAS(/obj/item/tank/oxygen, "air_contents", "volume", T20C, list(GAS_O2 = 6*ONE_ATMOSPHERE))
```

A tank whose base `Initialize()` already makes `air_contents` keeps that until the base is
converted. The declaration skips a var that already holds a mixture, so convert the base first.
`MolesForPressure()`-style amounts computed from other state stay in code.

### 3.4 Appearance: `DECLARE_APPEARANCE`

```dm
DECLARE_APPEARANCE(PATH, "state_var" | null, list(
	"value" = list(APPEARANCE_ICON_STATE = "x", APPEARANCE_OVERLAYS = list("ov", ...),
		APPEARANCE_COLOR = "#rrggbb", APPEARANCE_ICON = 'x.dmi'),
	"*" = list(...)))            // fallback row
```

- Each line is a **layer** keyed by one var, and the row is picked by `"[value]"`. Booleans are
  `"0"`/`"1"`. A layer with no matching row and no `"*"` row adds nothing.
- Later layers win for icon_state, colour and icon; overlays add up.
- The combined result is built once per (type, combination of row keys) and shared: the
  `wall_overlay_images()` pattern, made generic.
- It is applied at init and by the base `/atom/update_icon()`. A declared type needs no
  `update_icon()` override, or one that calls `..()` and keeps only the non-visual work.
- The declaration swaps **only the overlays it added**. It never calls `cut_overlays()`.

```dm
// Before
/obj/machinery/space_heater/update_icon()
	cut_overlays()
	icon_state = "sheater[state]"
	if(panel_open)
		add_overlay("sheater-open")
	switch(state) ... set_light(...)

// After
DECLARE_APPEARANCE(/obj/machinery/space_heater, "state", list("0" = list(APPEARANCE_ICON_STATE = "sheater0"), "1" = list(APPEARANCE_ICON_STATE = "sheater1"), "2" = list(APPEARANCE_ICON_STATE = "sheater2"), "3" = list(APPEARANCE_ICON_STATE = "sheater3")))
DECLARE_APPEARANCE(/obj/machinery/space_heater, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("sheater-open"))))

/obj/machinery/space_heater/update_icon()
	..() // declared appearance
	switch(state) ... set_light(...)
```

Not declarable: icon states computed from several conditions at once (the floodlight's
`"flood[open ? "o" : ""][open && cell ? "b" : ""]0[on]"`), overlays that depend on contents,
numeric fill levels, and emissives. Those stay in `update_icon()`. The `decl_lint` rule
`init_visuals` counts `add_overlay`/`cut_overlays`/`icon_state =` in `Initialize()`. Many of
them are the second kind; mark a real keeper with `// ALLOW(decl): <reason>`.

### 3.5 Registries: `DECLARE_REGISTRY`

```dm
DECLARE_REGISTRY(PATH, REGISTRY_ID)
```

For an ordinary registry this is `REGISTRY_MEMBERSHIP()`. For a **conditional** registry it
also joins at materialize, which replaces an unconditional `registry_join(ID, src)` in
`Initialize()`/`on_materialize()`. Leaving is automatic in both cases (dematerialize or
destroy). `registry_lint.py` already bans `GLOB.x += src`. `decl_lint` counts
`registry_join(..., src)` and `GLOB.x[k] = src` in `Initialize()` (`init_registry`).

```dm
// Before (illustrative)
/obj/structure/ghost_pod/Initialize(mapload)
	. = ..()
	registry_join(REGISTRY_GHOST_PODS, src)

// After
DECLARE_REGISTRY(/obj/structure/ghost_pod, REGISTRY_GHOST_PODS)
```

A join that depends on state (only when `active`) stays `registry_join()` from the setter.

### 3.6 World-service membership: `DECLARE_SERVICE_MEMBER`

```dm
DECLARE_SERVICE_MEMBER(PATH, "planet_service", TYPE_PROC_REF(/datum/world_service/planets, addTurf), TYPE_PROC_REF(/datum/world_service/planets, removeTurf))
```

The service is read from `GLOB.<name>` at materialize, and `join(src)` is called on it. At
dematerialize `leave(src)` is called, or nothing if LEAVE is null. Only use it when the service
call takes just `src`.

### 3.7 Binds: `DECLARE_BIND`

```dm
/datum/decl_binder/my_thing/bind_list(list/atoms)   // one bulk FFI call when one exists
/datum/decl_binder/my_thing/bind(atom/A)            // or per atom (the default bind_list loops)
/datum/decl_binder/my_thing/unbind(atom/A)          // idempotent
DECLARE_BIND(PATH, /datum/decl_binder/my_thing)
```

- **Batched.** During an `SSatoms` batch (map load, template load, a generated site), every
  materializing atom is queued per binder. `bind_list()` gets the whole batch once, when
  `InitializeAtoms()` ends, right after the cable flush. Outside a batch it binds at once with
  a one-atom list.
- An atom deleted or dematerialized before the flush drops out of the queue.
- **Release** runs in destroy phase 1 (before dematerialize, as `lifecycle.md` requires) and on
  a non-destroy dematerialize (collapse to latent).

This is the layer for the bulk-bind work (`rewrite/boot-bind`). A binder whose `bind_list()`
calls a list FFI entry point (like `vg_power_bind_cable_list`) turns a per-atom bind into one
call per batch. **Not converted here, on purpose:** the base power machine
(`/obj/machinery/power/on_materialize()` → `power_autoconnect()`, `lifecycle_unbind()` →
`disconnect_from_network()`) and heat bodies. `rewrite/boot-bind` owns those files. When it lands a list
API, the conversion is:

```dm
/datum/decl_binder/power_node/bind_list(list/atoms) -> power_bind_machines(atoms)  // the bulk call
/datum/decl_binder/power_node/unbind(obj/machinery/power/M) -> M.disconnect_from_network()
DECLARE_BIND(/obj/machinery/power, /datum/decl_binder/power_node)
```

After that, delete the two overrides.

The 17 `connect_to_network()` calls in subtype `Initialize()` bodies (`decl_lint`:
`init_bind`) are dead today. They run before `vg_bind()` has minted the entity and return
FALSE, and the base autoconnects at materialize anyway. Delete them.

### 3.8 Scheduling: `DECLARE_BEHAVIOUR`, `DECLARE_PERIODIC`, `DECLARE_START_TIMER`

```dm
DECLARE_BEHAVIOUR(PATH, /datum/om/behaviour/x)      // om_attach at materialize
DECLARE_PERIODIC(PATH, PERIODIC_SLOW)               // om_task_periodic at materialize, stop at dematerialize
DECLARE_START_TIMER(PATH, 2 MINUTES, PROC_REF(die)) // om_after at materialize; DELAY may be a var name
```

The OM teardown already stops all of these at destroy.

```dm
// Before (illustrative)
/obj/machinery/thing/Initialize(mapload)
	. = ..()
	om_task_periodic(src, PERIODIC_SLOW)

// After
DECLARE_PERIODIC(/obj/machinery/thing, PERIODIC_SLOW)
```

Keep in code: periodic work that starts only in some states (it starts from the setter that
enables it), and timers with `rand()` delays or extra arguments. For an OM decl type
(`/datum/om/decl`), a behaviour already declared there needs nothing more.

### 3.9 Destroy effects: `DESTROY_EFFECTS` with `drop_contents` and `debris`

```dm
DESTROY_EFFECTS(PATH, new /datum/destroy_effects_data(message = "%SRC% breaks apart!", \
	sound = 'sound/effects/x.ogg', drop_contents = TRUE, debris = list(/obj/item/stack/rods = 2)))
```

- `drop_contents` moves whatever is still in contents to the drop location in phase 6, per atom
  (even when a batch merges the rest of the effects per turf). Slot policies (phase 3) have
  already handled slotted things; this catches the rest.
- `debris` spawns `count` of each type at the turf.
- `message`, `sound`, `debris_type` and neighbour re-smoothing are unchanged.

```dm
// Before (illustrative)
/obj/structure/crate_shelf/on_destroy(force)
	for(var/atom/movable/A in contents)
		A.forceMove(loc)
	new /obj/item/stack/material/steel(loc, 2)
	visible_message(span_warning("[src] collapses!"))
	..()

// After
DESTROY_EFFECTS(/obj/structure/crate_shelf, new /datum/destroy_effects_data(message = "%SRC% collapses!", \
	drop_contents = TRUE, debris = list(/obj/item/stack/material/steel = 1)))
```

Caveat: `debris` uses `new type(T)`, so a stack's amount argument is lost. Use a stack subtype
with the right default amount, or keep that one line in `on_destroy()`.

## 4. Script-friendly description (for conversion workers)

Workflow per site:

1. `python tools/ci/decl_lint.py --report | grep <your dir>` lists the sites as
   `file:line: rule`.
2. Convert each by its rule (the table below).
3. Delete an `Initialize()` override whose body is left as only `. = ..()` (the `init_lint`
   ratchet drops with it). Keep `// INIT:` reasons accurate on what remains.
4. `python tools/ci/decl_lint.py --update` and `python tools/ci/init_lint.py --update` shrink
   the baselines. Neither may grow.
5. Compile, then run `tools/ci/check_ratchets.sh` and `check_grep.sh`.

| Rule | Mechanical rewrite | Leave alone when |
|---|---|---|
| `init_reagents` | constant `reagents.add_reagent(ID, N)` right after `. = ..()` → `DECLARE_REAGENTS(type, null, list(ID = N))`; `create_reagents(N)` → `DECLARE_REAGENTS(type, N, null)` (and no descendant may re-create it) | data arg, computed amount, state-dependent, after other code |
| `init_new_child` | `x = new /p(src)` / `x = new x_type(src)` / `if(ispath(x)) x = new x(src)` → `DECLARE_DEFAULT_CHILD(type, "x", /p or "x_type")` | extra ctor args; wired after creation (then declare and configure after `..()`) |
| `init_gas` | `air_contents = new(V)` + constant `adjust_gas` → `DECLARE_GAS` | amounts from `MolesForPressure()` or other state |
| `init_registry` | unconditional `registry_join(ID, src)` → `DECLARE_REGISTRY(type, ID)` | conditional on state |
| `init_service` | `GLOB.x_service.add(src)` with a matching remove → `DECLARE_SERVICE_MEMBER` | extra arguments |
| `init_bind` | delete `connect_to_network()` in `Initialize()` (dead, see §3.7) | |
| `init_scheduling` | unconditional `om_task_periodic(src, P)` / `om_attach(src, B)` / constant-delay `om_after(src, D, PROC_REF(p))` → `DECLARE_PERIODIC` / `DECLARE_BEHAVIOUR` / `DECLARE_START_TIMER` | conditional, `rand()` delay, extra args |
| `init_visuals` | a fixed `icon_state =`/`add_overlay("x")` that follows one var → `DECLARE_APPEARANCE` | computed from several conditions or contents (`// ALLOW(decl): <why>`) |
| `destroy_qdel_owned` | delete the `qdel(x)`/`QDEL_NULL(x)`: phase 3/4 does it by the var's kind | an ordering the framework can't give (see lifecycle.md §4.2) |
| `destroy_drop` | contents `forceMove` loop → `drop_contents = TRUE` | per-item logic in the loop |
| `destroy_effects` | message/sound/debris lines → `DESTROY_EFFECTS` data | message text built from state |
| `destroy_registry` / `destroy_scheduling` / `destroy_unbind` | delete: the lifecycle does it | |

`--counts` prints totals per rule and per directory.

## 5. Checks

- `tools/ci/decl_lint.py` is in `tools/ci/check_ratchets.sh`, fingerprinted in
  `tools/ci/decl_baseline.txt`, shrink-only. `// ALLOW(decl): <reason>` keeps a site.
- `init_lint.py` counts overrides. Deleting an emptied override lowers it, so run
  `--update` after a sweep.
- Tests (`dq_decl_*`): reagents (inheritance, tint, shared table), children (defaults, var wins,
  lists, deletion), gas, appearance (layers, swap, shared rows), registry (join, leave, rejoin),
  binds (batch, flush, drop from queue, release once), scheduling (behaviour, periodic, timer),
  destroy effects, the init/materialize order, and the pilots.

## 6. Pilot results

- **Reagent containers.** The holder of every `/obj/item/reagent_containers` is
  `DECLARE_REAGENTS(/obj/item/reagent_containers, "volume", null)`. The base `Initialize()` and
  the unused `starts_with` var are gone. `decl_convert_reagents.py` converted **589** subtype
  fills (546 overrides deleted outright, 43 kept for their other work). The MRE component's
  per-instance pick became a `seasoning` var.
- **Space heater.** Cell from `cell_type`, and icon_state/hatch overlay as two appearance
  layers. `update_icon()` keeps only the light.
- **Floodlight.** Its cell is declared. Its icon stays in code (multi-condition).

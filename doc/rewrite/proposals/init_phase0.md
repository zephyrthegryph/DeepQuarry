# Init phase 0: a home for every `Initialize()` row (proposal, 2026-10-25)

Status: proposal for user review. Doc only; no code. Numbers are `origin/master` at the time of writing
(`tools/ci/init_baseline.txt`: 166 `init_lines` rows + 7 `world_reads` rows = **173**; the lane brief said about 146, master
has moved since). Contract: `final_api.html` section 6 ("The init phase contract"), `framework_gaps.md` MI14, `lifecycle.md`.

## 1. Problem

An `Initialize()` override is allowed to hold per-instance state only (`ALLOW(init/CODE)`), and the `init_lines` ratchet counts every
imperative line in one. What is left in the baseline is mostly code written **before** `..()`: it has to run before the parent chain
because a parent reads what it sets. The contract names the phases (params, early children, declared children and gas, the type's own
setup after `..()`, `after_init()`), but the code-before-`..()` has only one home today, `owns_*(early = TRUE)`, and that is only for a
child object. So the rows stay.

The observation that makes most of them go away:

> **Code before `..()` exists only because an override cannot otherwise run before its ancestors.** Every declared form (`param()`,
> `rolls()`, `variants()`, `per_type()`, `owns_*(starts =)`, `keeps_if()`, `knows()`, `registry()`) already runs at the **root** of
> the chain, before any type's code after `..()`. Once no override has code before `..()`, "before the parent" is vacuous: the forms
> run at the root, in a declared order (ancestors first, `from =` for a dependency).

The order is: `/atom/New()` params, early children (phase 0), then the chain's pre-`..()` code of each override, then the root's forms
(`lifeform_preinit`: params, `per_type`, `rolls`, `variants`; then `lifecycle_decls_init`, `caps_init`), then each override's code
after `..()`, then `setup()` hooks, then `after_init()` (`InitAtom()` in `code/controllers/subsystems/atoms_init.dm`,
`engine_holder_preinit()` in `code/engine/declare/scopes.dm`). A row is a **real** phase-0 need only when its output is read by a
phase-0 form itself (a `param(apply)`, a `starts =` proc) or by a pre-`..()` line of another override that has not yet converted.
The census below finds none of the second kind that cannot convert in the same wave, and exactly one family of the first kind
(the human's species).

## 2. Census: every row, by what it sets and who reads it

Row counts are `init_lines` rows unless marked `w` (`world_reads`). `A` = file:line on `origin/master`.

| Owner (rows) | Where | What it sets | Who reads it | Home (section 3) |
|---|---|---|---|---|
| `/atom` (17) | `code/game/atom/atoms_initializing_EXPENSIVE.dm:68` | 2 proc pragmas (`SHOULD_NOT_SLEEP`, `SHOULD_CALL_PARENT`); the double-init guard, `flags`/`flags_1` bits, the `lifecycle_decls_init`/`caps_init` calls; `add_atom_colour` and `atom_integrity = max_integrity`; a **commented-out** light block (3 rows: `if`, `update_light`, `expr`) | everything | pragmas to S1; dead block deleted (3); colour and integrity to F5 (4); the other 8 are the chain itself: roots (R1) |
| `/atom/movable`, `/obj`, `/turf` (1 each) | `atoms_movable.dm:34`, `micro_structures.dm:399`, `turf.dm:107` | `*_instance_setup()`, one call shared with the `table_initialize()` path | the instance | roots (R1) |
| `/datum/controller/global_vars` (13) | `code/controllers/globals.dm:45` | the global-init walk (`call(src, I)()`), the benchmark `#if` notes, WARNINGs | boot | root (R1): it is the boot step that makes `GLOB`, it runs before any type table exists |
| `/datum/decl` (2) | `code/datums/repositories/decls.dm:66` | `SHOULD_CALL_PARENT`, `SHOULD_NOT_SLEEP` | none | pragmas (S1) |
| `/datum/decl/emote` (2 + 1w) | `code/modules/emotes/emote_define.dm:47` | `GLOB.emotes_by_key[key] = src` | emote lookup | `registry()` (E8) |
| `/area` (1) | `code/game/area/areas.dm:66` | `apply_ceiling()` | turfs of the area at their init | `setup()` (E4) |
| `/turf/space` (1) | `code/game/turfs/space/space.dm:24` | `space_appearance()` (icon_state from position, starlight) | the look | look part (E10) |
| `/turf/open` (2) | `LINDA_turf_tile.dm:51` | `setup_open_air()` (gas mixture) before, `register_open_air()` after | atmos at `..()` | `gas_store(when =)` (E12) and `setup()` (E4); both procs are also called by `table_initialize()` |
| `/mob` (3) | `code/modules/mob/mob.dm:49` | `PUBLISH_LEGACY(world_mob_created)`, `lastarea`, `set_focus` | the mob, later | `setup()`: they join `finish_mob_setup()` (E4) |
| `/obj/machinery/atmospherics/pipe` (4) | `atmospherics.dm:100`, `pipes/pipe_base.dm:52` | `ensure_pump_materials()`; `level = 1` when on a wall | pipe init, hides_under_flooring | `setup()` for the first (2, verify the parent does not read it first); `preset()` for `level` (2) |
| `/mob/observer/dead` (36 + 3w) | `code/modules/mob/dead/observer/observer.dm:71` | copies the body it leaves: `appearance`, then resets `invisibility`/`layer`/`plane`/`alpha` (5); `see_in_dark = world.view` (1); gender, name, mind-name, real_name fallback picks with `GLOB.first_names_*` (15 + 3w); `rel_set(mind)`, `default_pixel_x/y` (3); places itself with `forceMove`/`moveToNullspace`/`to_chat` (7); `if(!name)` fallback (2); `set_real_name`, two `animate()` (3) | the ghost's look, name, visibility net | `param(from_body, apply =)` (E1: 5 + 15 + 3 = 23), `rolls(name)` (E2: 2 + 3w), `setup(place_ghost)` and friends (E4: 11). framework_gaps R10 names this row: "init form for copy the leaving body" is `param(apply)` plus a `schema_ref(/mob)` param (the caller passes the body; the ghost no longer reads `loc`) |
| `/mob/living/silicon/robot` (11) | `code/modules/mob/living/silicon/robot/robot.dm:142` | `ident`, `updatename`; `setup_radio/camera/brain/laws/module/components/cell` (virtual steps subtypes override); `grant(robot_naming())` | the rest of init, the HUD | `rolls(ident)` + `rolls(name, from = ident)` (E2: 2); `owns_one/owns_many(early =, starts = PROC_REF(...))`, the virtual step stays as the `starts` proc exactly as `start_laws()` does for the AI (E3: 7); `grant` entry `when = may_pick_name` (E14: 2) |
| `/mob/living/silicon/ai` (8) | `ai.dm:205` | `rel_set(common_radio)` alias; the `spawn_safety`/`brain_at_make` branches that leave an empty core and answer `INITIALIZE_HINT_QDEL` (4 rows); `release_mind` on the brain's host, the greeting (`on_mob_init`) | init | `keeps_if(PROC_REF(has_brain), instead = PROC_REF(leave_empty_core))` (N3: 4); `setup()` for the alias, mind release, greeting (E4: 4). `aiRadio`/`laws` are already early |
| `/mob/living/carbon/human` (5) | `human.dm:46` | `set_species()` (species or `species_at_make`): builds the body | everything of the human | N2: `param(species_at_make, apply = PROC_REF(set_species), early = TRUE)`: the one real phase-0 consumer of an early child (the DNA is early, MI14) |
| `/mob/observer/blob` (7 + 1w) | `code/modules/blob2/overmind/overmind.dm:48` | numbered name (3); blob languages from the type table and the default language (4 + 1w) | the overmind | `rolls(name)` + setup `real_name` (E2: 3); `knows(PROC_REF(blob_languages))` (E6: 5) |
| `/obj/structure/blob` (4) | `blobs/base_blob.dm:34` | `faction` from the overmind (2); `consume_tile()`, `sync_overmind_look()` | the blob | `preset(faction)` (N1: 2); `setup()` (E4: 2) |
| `/obj/machinery/camera/intcircuit` (5 + 1w) | `integrated_electronics/subtypes/camera.dm:126` | `network` from `network_id` (2); random `c_tag` and `name` (2); `cameranet.addCamera` (1 + 1w) | the camera net | `preset(network)` (N1: 2); `rolls(c_tag)`, `setup(name)` (E2: 2); registry membership with the camera's `lifecycle_dematerialize` (E8: 2) |
| `/obj/effect/overmap/visitable/sector/temporary` (5) | `overmap/spacetravel.dm:8` | the not-on-the-overmap `CRASH`; `start_x/y` from `loc`; `map_z += get_empty_zlevel()` | the sector initializer | `keeps_if(...warn =)` (E5: 2); `preset(start_x)`, `preset(start_y)`, and `map_z` (N1: 3, the z claim is an effect, decision D3) |
| `/obj/effect/shuttle_landmark/automatic` (2) | `shuttle/landmarks.dm:137` | `original_name`; `landmark_tag += "-x-y-z-[random_id]"` | the landmark registry | `preset(original_name)` (N1: 1); `rolls(landmark_tag)` (E2: 1) |
| `/obj/belly` (1) | `vore/eating/belly_obj.dm:301` | `belly_share_lists()`: shared static lists | every belly var read | `per_type()` (E9; verify the lists are read-only) |
| `/obj/machinery/protean_reconstitutor` (2) | `game/machinery/protean_reconstitutor.dm:48` | `rel_take_all(component_parts)`, `RefreshParts()` | the machine | `built_from()` and `default_parts()` (E7) |
| `defib_kit`, `bluespaceradio`, `proton_pack`, `medigun_backpack` (1 each) | `make_tethered()` in `datums/behaviours/tethered_item.dm:106` | builds the tethered handheld before `..()` | the pack's init | `owns_one(early = TRUE, starts = paddle_path)` (E3: 4) |
| `/obj/item/clothing/suit` (1) | `clothing.dm:911` | `MakeHood()` | the suit | `owns_one(early = TRUE, starts = PROC_REF(make_hood))` (E3: 1) |
| `/obj/machinery/door/airlock/angled_bay` (1) | `airlock_angled_bay.dm:89` | `obtain_icon()`: fill icon by `fill_type` | the look | look part (E10) |
| `/obj/item/seeds/random` (2) | `hydroponics/seed_packets.dm:65` | `proto_set(seed_static, create_random_seed())`, `seed_type` | the pack | `starts =` on the prototype relation and `rolls(seed_type, from =)` (E2) |
| `/obj/machinery/light/flamp` (1) | `power/lighting.dm:1214` | `layer = initial(layer)` | the draw | `preset(layer)`, or delete if the parent no longer moves `layer` (N1) |
| `/obj/machinery/embedded_controller/radio` (1) | `embedded_controller_base.dm:95` | `set_frequency(frequency)` before the program exists | radio | `radio_listen(freq = nameof(frequency))` (E8) |
| `/obj/machinery/rnd/production`, `mecha_part_fabricator_tg` (3) | `research/tg/machinery/_production.dm:53`, `mech_fabricator.dm:95` | `available_designs = list()`, `illegal_local_designs = list()` | the machine | lazylist declaration (`code/__defines/_lists.dm`): the line goes (E11) |
| `/datum/persistent` (6), `/datum/persistent/paintings` (1) | `persistence/datum/persistence_datum.dm:25`, `paintings.dm:9` | reads the save file and applies the tokens at boot | `SSpersistence` | boot step of the owning system (E13) |
| `/datum/asset_transport` (4 + 1w) | `asset_cache/transports/asset_transport.dm:17` | `preload`, staggered `send_assets_slow` per client | assets | boot step of the assets system (E13) |
| `/datum/techweb_node` (6) | `research/tg/techwebs/_techweb_node.dm:54` | turns three id lists into assoc sets | node lookups | data normalised where the research system loads the node (E13) |
| `/datum/instrument` (2) | `instruments/instrument_data/_instrument_data.dm:60` | `calculate_samples()` unless legacy | `ready()` | the instrument system's boot step, or lazy in `ready()` (E13) |

Roll-up (sums to 173): **S1/dead 7** (4 pragmas, 3 commented lines), **roots R1 24** (atom 8, movable/obj/turf 3, global_vars 13),
**engine moves F5 4**, **E1 `param(apply)` 23**, **E2 `rolls` 15**, **E3 early owns 12**, **E4 `setup()` 24**, **E5 `keeps_if` 2**,
**N3 `keeps_if(instead)` 4**, **E6 `knows` 5**, **E7 parts 2**, **E8 registry/radio 6**, **E9 `per_type` 1**, **E10 look 2**,
**E11 lazylist 3**, **E12 `gas_store` 1**, **E13 system boot 20**, **E14 `grant` 2**, **N1 `preset` 11**, **N2 early apply 5**.
Row-level splits inside the observer, AI and robot are by line and are approximate by one or two rows; the converting wave
re-derives them.

## 3. Forms

### Exists today (write these now)

- **E1 `param(var, schema_ref(T), pos =, apply = PROC_REF(x))`** (`code/engine/lifeforms/params.dm`): the observer's body. `new /mob/observer/dead(body)` becomes
  `make(/mob/observer/dead, at = T, from_body = M)`; `apply` copies look, gender, name and mind from the param (`keep = FALSE`, so the ghost does not hold the body).
- **E2 `rolls()`**: runs at the root, before any type's code after `..()`, seeded; a `PROC_REF` generator may read `GLOB` and the registry (the AI's `roll_ai_name`
  reads `REGISTRY_MOBS`), which is the honest home of the `world_reads` name picks. `from =` orders `name` after `ident`.
- **E3 `owns_one/owns_many(early = TRUE, starts = PROC_REF(x))`** (phase 0, `own_init_starts(early_pass = TRUE)`): children a pre-`..()` line used to build. A subtype that
  differed in a virtual step overrides the `starts` proc (the AI's `start_laws(current, mapload)`).
- **E4 `setup(PROC_REF(x))`**: after the chain returns. Wherever the old line ran before `..()` only by habit.
- **E5 `keeps_if(cond, warn =)`**, **E6 `knows()`**, **E7 `default_parts()` / `built_from()`**, **E8 `registry()` / `membership()` / `radio_listen()`**,
  **E9 `per_type()`**, **E10 a look part (`draw()`)**, **E11 lazylists**, **E12 `gas_store()`**, **E14 `grant()` with `when =`**.
- **E13 a system's `initialize()`** (doc section 2): a boot-time datum with an explicit `Initialize()` (decl, persistent, techweb node, instrument, asset transport) is not
  an atom and no chain calls it; the loader is. Its work moves to the loader's system (boot-phase IO is allowed there, doc "Boot-phase blocking IO"), so the datum has no
  `Initialize()` and the name stops colliding with the atom contract.

### New (open; each needs an implementation lane)

- **N1 `preset(nameof(var), PROC_REF(compute), from = list(...), when = cond)`**: the deterministic sibling of `rolls()`. A value computed from the instance's own place or
  params (a pipe's `level` from the turf under it, a sector's `start_x` from `loc`, a camera's `network` from `network_id`), at the root of the chain, before any code after `..()`.
  Same suppression rule as `rolls()` (a map edit or param that differs from the default wins), same `from =` ordering, so a cycle is a declaration error. The generator is a
  condition-like proc: it reads, never writes (this is what makes it checkable by the existing purity guard). It may share the rolls table in the engine; it is a separate
  entry name because a roll is random and a preset is not (no rename dodge: the counts stay honest per form). Clears 11 rows.
- **N2 `param(..., apply = PROC_REF(x), early = TRUE)`**: `apply` runs in phase 0 (after the early children, before the chain) instead of at the root. Only for a setter whose
  output a phase-0 form or a parent's pre-`..()` code reads: the human's `set_species()`. Clears 5 rows. Until then the human stays as MI14 left it.
- **N3 `keeps_if(cond, warn =, instead = PROC_REF(x))`**: `instead` runs once when the instance is discarded (the AI core that leaves an empty terminal). It runs from `InitAtom()`
  where the discard is decided, as the effect the old override's branch had. Clears 4 rows.
- **R1 `init_roots`** in `tools/ci/lint_scopes.toml` (`[lint.init]`): a **closed** list of the types that *are* the chain: `/atom`, `/atom/movable`, `/obj`, `/turf`,
  `/datum/controller/global_vars`. Their `Initialize()` rows are not debt: no form can run before the chain it defines. Each entry carries its justification; adding to it is a
  design change. Clears 24 rows (it would be dishonest to leave them in a shrink-only baseline that can never reach zero).
- **S1 lint housekeeping**: `init_lines` does not count proc directives (`SHOULD_CALL_PARENT`, `SHOULD_NOT_SLEEP`, `PRIVATE_PROC`); and the commented-out block in
  `/atom/Initialize()` is deleted (3 rows). 7 rows.
- **F5 engine moves**: `add_atom_colour(color, FIXED_COLOUR_PRIORITY)` becomes part of the first look (the colour layer reads `color`); `atom_integrity = max_integrity` becomes
  `param(nameof(atom_integrity), default = PROC_REF(start_integrity))` (a default fills what nothing gave, at the root). 4 rows.
- **Not proposed: a generic `preinit(PROC_REF(x))` hook.** It would be the escape hatch every residual row reaches for, and the census finds no row that needs it. The
  capability-side `on_holder_preinit(A)` already exists for a capability that must make a part before the parent reads it; a type does that with E3. If a residue appears in a
  wave, it is reported and decided then (D2).

## 4. Migration plan

1. **Lint and roots** (S1, R1, F5): lowers 35 rows with no behaviour change except colour and integrity ordering (pins: `atom_integrity` after init, mapper colour). One small lane.
2. **E13 boot loaders** (20 rows): five datums, five systems; independent of the rest. Test: boot gate, persistence load round trip, asset preload, techweb node lookups.
3. **Existing forms, mobs** (E1-E4, E6 for observer, robot, blob, AI, mob, human-untouched): 77 rows in the heaviest files. One lane per file family; tests exist for
   ghosting, borg creation, AI core, blob overmind. The ghost conversion changes callers of `new /mob/observer/dead(M)` (codemod `tools/dx/codemods/ctor_args.py`).
4. **Existing forms, objects** (E3, E5, E7-E12, E14): about 30 rows, mostly one-liners.
5. **New forms** N1, N2, N3 (20 rows): engine lane, each with its own `dq_lifeform_*_tests.dm` file, then the callers.
6. **Ratchet**: each landing runs `analyze baseline --update --lint init`. The target is an `init_lines` baseline of **0** and `world_reads` of 0; R1 is the only path that keeps a
   row, by the list, never by annotation.

Risks: pipes and `turf/open` are also on the `table_initialize()` path, so a hook must run in both; the robot's `setup_*()` are virtual steps subtypes override, so the `starts`
procs must keep their virtual shape or every chassis breaks; `rolls()` is seeded, so a ghost's or a camera's name stops drawing from the world RNG (`intended_changes.md`).

## 5. Lints

- `init`: skip proc directives; read `init_roots` from `lint_scopes.toml` (a root's rows are not sites, and a type not on the list is judged as before).
- `lifeforms`: reject `preset()` whose generator writes; `preset_cycle`, `preset_unknown_target` like `rolls`; `param(early = TRUE)` only with an `apply`; `keeps_if(instead =)`
  proc must exist.
- `allow_annotations`: an `ALLOW(init/FRAMEWORK)` on a root becomes unused (delete it).

## 6. Decisions (DECIDED 2026-10-25, the coordinator on the user's delegation)

- **D1, decided yes.** `init_roots` is a closed list in `lint_scopes.toml` (`/atom`, `/atom/movable`, `/obj`, `/turf`, `/datum/controller/global_vars`), 24 rows. Adding a type is a design change.
- **D2, decided no.** There is no generic `preinit()`. A residual row found in a wave is reported, not given a hatch.
- **D3, decided no.** `preset()` never claims a resource. The sector's `map_z` claim of an empty z-level stays an effect: `keeps_if` plus a `setup(mapload = TRUE)` hook (the parent's reader of `map_z`
  is checked in that wave), and `preset` covers only `start_x` and `start_y`.
- **D4, decided yes.** The boot-time datums (persistent, asset transport, techweb node, instrument) get a boot step in their loader's system; they lose their `Initialize()`.
- **D5, decided yes, with no shim.** The ghost takes the named `from_body` param (`make(/mob/observer/dead, at = T, from_body = M)`). Every `new /mob/observer/dead(body)` caller converts
  in the same commit; the old positional form is deleted with its last caller, so there is no `pos =` compatibility mapping.

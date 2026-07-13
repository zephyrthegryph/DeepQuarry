# AGENTS.md — Working on DeepQuarry

DeepQuarry is a BYOND/DM Space Station 13 codebase. Its lineage is:

```
Baystation12 → Polaris → VOREStation (Virgo) → Yawn-wider → CHOMPStation2 → DeepQuarry
```

DeepQuarry is a **hard fork**: it no longer tracks or merges from any upstream.
The old merge-survival scaffolding **no longer applies** and has been removed:

- The modular folders (`modular_chomp/`, `modular_dq/`) were dissolved into one
  unified tree.
- The origin/edit markers (`// CHOMPEdit`, `// DQEdit`, `// CHOMPAdd`, `// DQRemoved:`,
  `// VOREStation Edit`, …) were stripped — they only existed to help a merge
  engineer locate fork edits, and there are no more merges.

Just put code where it belongs and **edit/delete any file freely**. When you remove
a file, delete it and drop its `#include` from `deepquarry.dme` — don't comment the
include out "in case." Git history is the record of what was removed.

> If you still find a stray `// CHOMPEdit` / `// DQEdit` / `modular_*` reference, it's
> a leftover; treat it as ordinary code/comment and remove it when you touch the file.

---

## 1. Repository layout

| Path | Purpose |
|---|---|
| `code/` | All DM game code (the entire codebase — base + everything the fork added). |
| `maps/` | Maps. The live map is `maps/southern_cross/` — **station-only**: 3 station decks (z1-3) + CentCom (z4) + Transit (z5); the empty/surface/misc z-levels were trimmed (see §9). `maps/virgo_minitest/` is the **unit-test map** selected under `-DCITESTING` (tiny → fast test boots; see `maps/~map_system/_map_selection.dm`). `maps/submaps/`, `maps/common*/`, `maps/overmap/`, `maps/~turfpacks/` hold dynamically-loaded submaps/turfpacks/overmap content. `maps/expedition/` holds the blank substrate the on-demand expedition generator carves. Other top-level map dirs are dormant upstream maps not in the build. |
| `icons/` | Art. Editable sources are `*.png` + `*.dmi.toml`; the build repacks them into `icons/gen/` (see §4). Never hand-edit files under `icons/gen/`. |
| `sound/`, `interface/`, `html/`, `strings/` | Assets, BYOND skin, browser assets, lookup text. |
| `tgui/` | React/TypeScript front-end (TypeScript only, Biome + Bun). |
| `verdigris/` | In-tree Rust extension (cave-gen + vendored auxmos atmos), loaded via FFI. Builds to `verdigris.dll` / `libverdigris.so` (see §4). |
| `config/`, `SQL/` | Server config template and DB schema. |
| `html/changelogs/` | One YAML changelog stub per PR (see §7). |
| `tools/`, `bin/` | Build/lint/map tooling and Windows entry points. |
| `deepquarry.dme` | The compile manifest — every `.dm` in the build is `#include`d here. |
| `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm` | DM linter / DreamChecker config. |

New code goes in the matching `code/` subfolder (mirrors the usual SS13 layout:
`code/modules/…`, `code/game/…`, `code/datums/…`, `code/__defines/…`). New art
goes in `icons/` as `png` + `dmi.toml`. New maps go in `maps/`.

---

## 2. Wiring new files into the build (`deepquarry.dme`)

DM has no auto-discovery — every `.dm` the compiler should see must be `#include`d
in `deepquarry.dme`. One line per file, Windows path separators:

```
#include "code\modules\myfeature\myfile.dm"
```

Order matters when files depend on `#define`s — keep `__defines/` includes near the
top. For proc/var override chains, the last-compiled definition wins; keep that in
mind when choosing where a file is included. Maps register through the glue in
`maps/~map_system/` (`_map_selection.dm`, `maps.dm`) — model new maps on those.

When you remove a feature, **delete the file and its `#include` outright** — there's
no upstream to merge against, so there's no reason to keep a disabled include around.

---

## 3. DM coding standards (enforced by SpacemanDMM / DreamChecker)

- **Absolute type/proc paths only** — `/obj/item/clothing/shoes/jackboots`, never
  relative. (`disallow_relative_type_definitions` / `disallow_relative_proc_definitions`.)
- **Use defined constants**, not string literals — job/faction/access/channel names,
  sounds. Defines live under `code/__defines/`.
- **Avoid `usr`** outside verb procs — plumb `user` through args, or use `src`.
- **Always chain `..()`** in lifecycle overrides (`Initialize`, `Destroy`,
  `MouseDrop_T`, …) unless you specifically need to suppress the parent.
- **Override via vars/subtypes**, not by editing an unrelated base — re-open the
  type and set `icon` / `name` / `desc`, or subtype it.
- **Run DreamChecker before pushing.** Upstream-style red builds get rejected.

### 3a. List allocation (`code/__defines/_lists.dm`)

| Use case | Pattern |
|---|---|
| Constant table shared across all instances of a type | `var/static/list/foo = list(...)` |
| Per-instance mutable, often empty | `var/list/foo` + `LAZYADD`/`LAZYLEN`/`LAZYREMOVE` |
| Per-instance mutable, always non-empty | `var/list/foo = list(...)` (rare) |
| Local working list inside a proc | `var/list/foo = list()` |

Anti-pattern: `var/list/foo = list()` on an *instance* var — allocates one list per
instance even when empty, and subtype overrides inherit the empty alloc. Use a
lazylist instead. For per-subtype constant tables (which DM can't express as a
`static` var), use a getter proc that returns a proc-local `var/static/list`.

### 3b. Type safety

- `istype()` to narrow before reading a subtype member is fine. **Never** use the
  `:` operator to reach a subtype member — `istype()` → cast → access.
- In a typed `for(var/obj/item/foo/F in list)` the `istype` is implicit; use
  `as anything` when the list is known-clean so stray nulls surface as runtimes.
- Never use type paths as strings.

### 3c. Lifecycle / hard-delete prevention

- Prefer `Initialize(mapload, ...)` over `New()` for atoms; `return ..()`.
- `Destroy()` must null held refs, `UnregisterSignal`, cancel timers/callbacks,
  remove from global tracking, then `return ..()`. Return the right `QDEL_HINT_*`.
- Always `qdel()`, never `del()`.

### 3d. Signals & callbacks

- Every signal handler's first line is `SIGNAL_HANDLER`; it must not sleep — hand
  slow work to `INVOKE_ASYNC`.
- Pass procs via `PROC_REF()` / `TYPE_PROC_REF()` / `GLOBAL_PROC_REF()`, never a
  bare string proc name.

### 3e. Performance

- Cache appearances (`/image` / `/mutable_appearance`), not raw `/icon` objects.
- Prefer flat lists indexed by `#define`d ints over assoc lists keyed by strings
  when the keys are a fixed enum (~8 B vs ~24 B/entry).
- Scale `process()` effects by the subsystem `wait` (or a `seconds_per_tick` arg).

### 3f. Magic numbers, input, SQL

- Use the time defines (`1.5 SECONDS`, `5 MINUTES`) — never raw deciseconds.
- `#define` flag/ID/threshold constants.
- Sanitize/`stripped_input()` free text and **re-validate** user/target/state after
  any `input()` / `tgui_input_*` returns. Validate `Topic()` hrefs (`locate(ref) in …`).
- Parameterized SQL only; `format_table_name()` for table names.

---

## 4. Build pipeline

Windows is the supported dev OS. Entry points (`bin/`):

- `bin/build.cmd` — DM + TGUI build → `deepquarry.dmb` + `deepquarry.rsc`.
- `bin/server.cmd` — build then host on port 1337.
- `bin/test.cmd` — unit-test boot (CI verification).
- `bin/tgui-build.cmd` / `bin/tgui-dev.cmd` / `bin/tgui-fix.cmd`.
- `bin/clean.cmd`.

`tools/build/build.ts` (Juke) orchestrates the DM build. Two fork-specific steps:

- **Icon repack** (`tools/dq_icons/`): regenerates `.dmi` from `png` + `dmi.toml`
  into `icons/gen/` before the DM compile (dirty-checked; no-ops when clean).
- **verdigris** (`tools/build/build.ts` `VerdigrisTarget`): builds the Rust FFI
  library (`verdigris.dll` on Windows, `libverdigris.so` on Linux) when its source
  is stale. You can also build it directly with `verdigris/build-windows.sh` /
  `verdigris/build-linux.sh`. The compiled library is a gitignored per-platform
  artifact; the DM game loads it at runtime via `VERDIGRIS_CALL(...)`.

Runtime DMI note: because repacked `.dmi` live only in `icons/gen/`, code that reads
DMI metadata at runtime via rust-g resolves the `icons/gen/` copy automatically
(`icon_metadata()`, `universal_icon.to_list()`).

The DM linter (`SpacemanDMM`) runs as part of the build and in CI — heed every
warning.

---

## 5. TGUI

- `tgui/` is TypeScript-only with Biome (formatter/linter) and Bun (runtime).
- `npm run tgui:lint` to check, `npm run tgui:fix` to auto-fix.
- Interfaces live in `tgui/packages/tgui/interfaces/`. New fork UIs go there.

---

## 6. Changelogs

Every user-visible PR drops one YAML in `html/changelogs/` (`<author>-<branch>.yml`):

```yaml
author: "yourkey"
delete-after: true
changes:
  - rscadd: "Added X"
  - bugfix: "Fixed Y"
  - balance: "Tuned Z"
```

Valid prefixes: `rscadd`, `rscdel`, `bugfix`, `qol`, `balance`, `soundadd`,
`sounddel`, `imageadd`, `imagedel`, `maptweak`, `spellcheck`, `experiment`,
`refactor`, `code_imp`, `config`, `admin`, `server`, `wip`. The merge bot rolls the
YAML into the master changelog and deletes the stub.

---

## 7. PR checklist

- [ ] New `.dm` files `#include`d in `deepquarry.dme`.
- [ ] Absolute type/proc paths only; no `:` operator on subtype access.
- [ ] `Destroy()` nulls refs / unregisters signals / returns the right `QDEL_HINT_*`.
- [ ] Signal handlers start with `SIGNAL_HANDLER`; callbacks use the `*_PROC_REF` macros.
- [ ] Time args use `SECONDS`/`MINUTES`/`HOURS`.
- [ ] DreamChecker (`SpacemanDMM`) passes locally.
- [ ] TGUI (if changed): `npm run tgui:lint` clean, `npm run tgui:fix` leaves no diff.
- [ ] One YAML changelog stub.
- [ ] Squash-able history; commit subject ≤ 72 chars.

---

## 8. Where to look when stuck

- DM linter rules: `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm`.
- Build entry: `bin/build.cmd` → `tools/build/build.ts`.
- Icon pipeline: `tools/dq_icons/`.
- verdigris (Rust FFI): `verdigris/README.md`.
- Changelog format: `html/changelogs/example.yml`.
- PR template: `.github/PULL_REQUEST_TEMPLATE.md`.

---

## 9. Current status / known state

Things that are deliberately mid-flight or disabled, so you don't "fix" them by
accident or assume they work:

- **Atmospherics — LINDA-only.** LINDA (the vendored /tg/ atmos: `/datum/gas_mixture`,
  `gas_types`, `SSair`, environmental/pipes/components under `code/ATMOSPHERICS/`) is
  the **live and only** engine. The old CHOMP/ZAS/XGM engine is **deleted**; there is no
  `USE_LINDA_ATMOS` gate anymore. Gas reactions are the CHOMP roster ported onto LINDA
  (`gasmixtures/reactions.dm`). Multi-z atmos is wired (`SSair.build_multiz_atmos_levels()`
  bridges `GLOB.z_levels` → `SSmapping.multiz_levels`; re-run when z-levels are added).
  The **Rust auxmos** gas-math backend is **fully wired** (the cutover is done): `/datum/gas_mixture`
  is a handle over a Rust arena, turf processing / pressure equalisation (katmos) / multi-z sharing /
  gas overlays and **superconductivity** (heat conduction) all run in Rust, driven from `SSair.fire()`.
  **`/datum/gas_mixture` is an OPAQUE HANDLE (/tg/ model) — there is NO public `temperature`/`volume` var.**
  The Rust arena is the single source of truth. READ via `air.return_temperature()` / `air.return_volume()`
  and WRITE via `air.set_temperature(x)` / `air.set_volume(x)`; a bare `air.temperature = x` is a COMPILE
  error. The accessors cross the FFI boundary, so cache the result in a local in hot loops
  (`var/temp = air.return_temperature()`). Turf heat is the same: the superconductivity arena owns it — use
  `/turf/proc/set_temperature()` / `return_temperature()`, not `turf.temperature = x`. A `check_grep.sh` lint
  ("gas mixture mirror writes") is kept as a belt-and-suspenders guard for untyped access the compiler misses.
  The FFI binds live in `dq_linda_turf_air.dm` (NOT `auxmos_bindings.dm`, which is the earlier
  reference draft and is intentionally **not** `#include`d). The library is `verdigris`
  (`verdigris/atmos/` = vendored auxmos) built on **byondapi 0.6.x** (feature `byond-516-1682`);
  it therefore **requires BYOND 516.1682+** at runtime (older builds crash at atmos init on a missing
  `ByondValue_DecTempRef` symbol — see `doc/auxmos_cutover_status.md`). Gas **reactions** still run in
  DM (the CHOMP roster; `reaction_hooks` is off) — a deliberate split, not a gap. A set of CHOMP/ZAS-era
  atmos callers reach LINDA through a **deliberate, documented compatibility API** — `xgm_compat.dm`
  (`assume_gas`, `c_airblock`, `air_blocked`, `update_nearby_tiles`, `CanZASPass`, gas_mixture helpers)
  and `tg_infra_compat.dm`. These are **not** temporary shims to migrate away: they carry real
  ZAS→LINDA semantic translation (e.g. `assume_gas`'s weighted-temperature mix, `c_airblock`'s BLOCKED
  bitfield), and `CanZASPass` is a hook point dozens of atoms override — there is no "more native" target
  to point callers at, so treat these as the fork's stable atmos API. See `doc/atmos_migration.md`,
  `doc/auxmos_cutover_status.md`, `code/ATMOSPHERICS/README.md`.
  The **`.air`-on-unsimulated-turf** family (Southern Cross has ~1188 `/turf/unsimulated/floor` that
  inherit `init_air` but are NOT `/turf/open`, so have no `air` var) is now guarded at all three sites:
  `setup_allturfs` append, the difference-pass neighbour loop, AND `add_to_active` (`SSair.dm` — the last
  was reached via **vents** `pipeline/mingle_with_turf` and threw a runtime EVERY vent tick, flooding logs).
  The SSair admin debug panel works again: verb "Debug Atmospherics" (Debug→Investigate) →
  `SSair.tgui_interact` → `AtmosControlPanel.tsx` (was dead: nonexistent interface + `ui_*` names when this
  fork's tgui calls `tgui_*`).
- **Quarry system — removed, replaced by the on-demand expedition generator.** The old
  `SSquarry` (depth layers + freight elevator + goals/danger/noise/archetype/persistence)
  and the `maps/deep_quarry/` map are **deleted**. In their place, `code/modules/expedition/`
  provides `SSexpedition.generate_site()`: a lean, demand-driven generator that allocates a
  fresh (or recycled) z-level (`load_new_z()` on `/datum/map_template/expedition_site`), carves
  it with the base `cave_system` automata, bridges it into multi-z atmos, and scatters loot/POIs.
  Now a full loop: `SSexpedition` fires on a 2s tick to poll mission completion and presence-
  release empty sites (their z-levels recycled via a `free_z` pool). The station-side
  `/obj/machinery/computer/expedition` (TGUI `ExpeditionConsole`, auto-placed in a hangar if not
  mapped) rolls a mission board, launches the selected `/datum/expedition_mission` (survey,
  extermination, salvage, retrieval, rescue — see `code/modules/expedition/`), bluespace-deploys
  the pad crew, and recalls them; an extraction beacon on-site returns them too. Missions pay
  survey points + Thalers on completion. A dynamic POI system (`expedition_poi.dm`: vault, camp,
  nest, cache, salvage field, relay) populates sites. Admin Debug verbs ("Generate Expedition
  Site" / "Generate Expedition Mission") jump a site directly. (Reusable non-quarry infra kept:
  `cave_system` automata, `load_new_z`, the `quarry_stalker` combat-AI canary mob, `tab_noop`.)
- **Substance & chemistry system — science core (new, live).** `code/modules/substance/`:
  everything is a `/datum/substance` with a visible surface behavior (effect family + trigger)
  and a hidden five-axis profile (energy/volatility/affinity 0–100, resonance 0–360 cyclic,
  purity) that **rerolls every round** (md5 salt). The engine is `substance_combine(A,B,ctx)`
  (`substance_resolver.dm`): resonance distance picks MATCHING/ADJACENT/OPPOSING → reinforce /
  transform (a `switch`-based family transform map) / conflict; energy=magnitude,
  volatility=control, affinity=yield+dampening, purity=byproducts+wobble; hazards erupt via the
  shared `substance_apply_effect()`. **A substance is ALWAYS a material — there is no vial/gadget.**
  The universal object is the stack `/obj/item/stack/material/substance` (sheets; `…/random_field`
  drops in loot), backed by `/datum/material/substance` (`substance_material.dm`, runtime-registered
  in `GLOB.name_to_material` like `/datum/material/dynamic`, stats derived from the axes;
  `substance_spawn_stack()` / `substance_stack_substance()`). Player-facing pipeline (all operate on
  stacks): the **combiner** (`/obj/machinery/substance_combiner` + TGUI `SubstanceCombiner`) alloys
  two stacks and shows learned-by-doing **Field Notes** (no scanning); the **refiner** pushes one
  axis at others' cost; the **extractor** renders slime extracts / bred produce into bio / botany
  substance stacks. From a stack it is ordinary material: forge via the in-hand material stack-recipe
  menu (`material.get_recipes()`, like exotic/dynamic materials) into weapons, plating, walls, OR via a
  **material-selectable lathe design** (see the material-selection note below) — load a substance alloy
  stack into a protolathe and pick it in the design's material picker. Anything made of it carries
  `/datum/component/substance_infusion` (applied
  via the `dq_apply_material_behaviors` seam) that fires the effect on `COMSIG_SUBSTANCE_FORM_TRIGGER`
  with finite charges. **All trigger conditions are wired** (`substance_triggers.dm` +
  `material_weapons.dm`, via `/obj/item/material/substance_form_trigger()`): melee strike
  (IMPACT+CONTACT), thrown impact (IMPACT+PRESSURE), fire (HEAT), projectile hit (IMPACT+PRESSURE,
  +ENERGY for energy shots), EMP (ENERGY), bare-hand touch (CONTACT); plus **armour struck**
  (`material_impact`, material_armor.dm), any substance **obj destroyed** (`substance_on_destruction`
  in `/atom/atom_destruction`), and substance **walls dismantled** (walls.dm). Substance materials also
  drive the material behaviour vars from their axes (glow/rad/tox) and scale `supply_conversion_value`
  by potency. Xenoarch source: the extractor renders an `/obj/item/anobattery` essence into a field
  substance. Atmospherics (ambient temp/pressure → volatility) and engineering (rig `energy_ceiling`)
  feed the resolver via `/datum/substance_context`. Debug verbs under "Substance: …". Earlier
  vial/charge/node carriers + rigging were removed in favour of the material model. **Substance gun-ammo
  IS built:** base `/obj/item/ammo_casing`/`ammo_magazine` carry a forged material (`set_forged_material`);
  a substance round's bullet gets the infusion only (`apply_substance_infusion`) and discharges via the base
  `/obj/item/projectile/on_impact` form-trigger (IMPACT/PRESSURE, +ENERGY for burn); lathe entry =
  material-selectable `material_rounds_9mm`. Deferred: medical/cargo axis mechanics, the full
  threat-vulnerability intel loop, and discovery-gated techweb fabrication. **Reachability — via existing
  engineering machines, no new machines:** REFINE by loading a substance sheet into a `particle_smasher`
  (the PA's beam target), clicking to pick the trade, and firing the particle accelerator at it until it
  charges past threshold → `apply_refine` (`substance_particle_refine.dm` + a hook in the smasher's
  `process()`). COMBINE by feeding two substance stacks into the `fusion_core` ("R-UST") reactant slots;
  the live field fuses a sheet-pair per interval via `substance_combine`, casts the alloy at the core,
  turns magnitude into reactor energy (`AddEnergy`), and maps a hazard onto `tick_instability`/breach
  (`substance_fusion_combine.dm` + hooks in `_core.dm` attackby/process/Destroy). EXTRACT deferred. The
  standalone `/obj/machinery/substance_combiner`/`_refiner`/`_extractor` remain debug-verb-only fallbacks.
  **Atmos/engineering feed BOTH machine paths** via one shared helper (`substance_env_context()` in
  `substance_resolver.dm`, factored out of the bench combiner): the room's temperature/pressure shift
  volatility and the machine's power rating is the energy ceiling — PA refine ceiling scales with charge,
  fusion combine ceiling with field strength (+plasma heat as extra volatility). `apply_refine()` takes an
  optional context and spills over-ceiling energy into volatility.
  CAVEAT: the PA (CE supply crate) and the R-UST reactor (circuit-board build) are NOT pre-mapped on
  Southern Cross, so refine/combine require building those engineering machines first.
- **Material behaviour system — rewritten; material synergies removed.** A material's three active
  behaviours are plain vars on `/datum/material` (`luminescence`/`radioactivity`/`toxicity`), read via
  `dq_material_*()` and applied to items by a working self-processing `/datum/component/material_behaviors`
  (`material_behaviors.dm`) — replacing the old half-wired magnitude-only component layer
  (`material_components.dm`) and `material_traits.dm`, both deleted. `material_synergies.dm` is deleted, and
  the `dq_apply_material_synergies()`/`dq_synergy_value()` no-op shims plus all 53 `RefreshParts` call sites
  and 2 value-reads are **now fully removed** (zero residual refs). Structures/walls keep self-processing for
  radiation via `products_need_process()` + the read API.
- **Material-selectable lathe designs (BOTH lathes).** A `/datum/design_techweb` can set
  `material_selectable = TRUE` + `selectable_amount` (+ optional `selectable_class`); the lathe UI then
  shows a material picker (loaded materials via `lathe_material_choice_list(container)` in `_production.dm`)
  and the chosen material is consumed and passed to `create_item(target, chosen)` → the product's
  `set_material`. This is how exotic/substance alloys become lathe-buildable WITHOUT one techweb entry per
  material. Design backend: `effective_materials()`/`material_choice_valid()` (`designs.dm`). Both build
  paths thread `chosen_material`: protolathe family `_production.dm` (`build`/`do_make_item`) AND autolathe
  `autolathe.dm` (`make`/`do_make_item`). UI: one shared `Fabrication/SelectableRecipe.tsx` (native row +
  dropdown + x1/x5/x10/max), used by both `Fabricator.tsx` and `Autolathe.tsx` via an `onBuild` callback;
  `materialChoices` in `Types.ts`. Sample designs + node: `designs/material_selectable.dm` (Material
  Knife/Sword, `build_type = AUTOLATHE | PROTOLATHE`, starting node). The lathe material container allows
  any `/datum/material` subtype, so substance/dynamic sheets load. Biome lint/format clean (root
  `npm install` provides Biome); tsc **is** run clean (bun at `~/.bun/bin`; `bun install` in `tgui/` provides
  the workspace) — sample design now also includes `material_rounds_9mm`.
- **Overmap — subsystem on, station map ground-only.** `code/modules/overmap/` compiles and
  runs; the live `maps/southern_cross/` is station-only and does not use overmap sectors.
  Expedition sites are still multi-z at runtime (each is its own `load_new_z()` z-level, so
  vertical multi-z atmos applies). The overmap proper is exercised by `virgo_minitest`.
- **Dynamic overmap POI system — deleted.** The spawn hook in `code/modules/overmap/sectors.dm`
  and the POI templates/loot were removed. Reviving requires restoring that content from git
  history. Leave it removed unless explicitly asked to revive it.
- **ATC (Air Traffic Control) — removed.** The `SSatc` subsystem and its radio-chatter module
  (`busy_space/atc_chatter*`, `chatter_*`) are deleted. The `loremaster`/`organizations` lore
  datums that lived alongside it in `busy_space/` are kept (used codebase-wide).
- **Damage model — unified on TG obj_integrity.** Every damageable `/obj` (structures,
  machinery, doors, vehicles, mechs) now takes damage through the TG integrity system in
  `code/game/atom/atom_defense.dm`: `take_damage(amount, damage_type, damage_flag, …)`,
  `get_integrity()`, `repair_damage()`, and the `atom_break()`/`atom_fix()`/`atom_destruction()`
  hooks. The old parallel `var/health`/`var/maxhealth` + `healthcheck()`/`CheckHealth()` model is
  **gone** — don't reintroduce it; set `max_integrity` (and `integrity_failure` for a "broken
  but not destroyed" state) and route damage through `take_damage()`. Turfs/walls keep their own
  `damage`-var model (as upstream TG does). A few entities run self-contained damage backed by
  obj_integrity but with their own combat logic on top: `/obj/mecha` (component armor/deflect)
  and `/obj/item/uav`. Mob/plant/blob health is a separate system and untouched.
- **verdigris (Rust FFI)** is a build artifact, gitignored per-platform. If `cargo` is absent
  the build warns and skips it, and **both** subsystems that depend on it fail at runtime:
  cave-gen (expedition) and — since the auxmos cutover — **atmospherics** (gas math + turf
  processing + superconductivity all run in the Rust arena now, not pure DM). It builds on
  **byondapi 0.6.x** for BYOND 516.1682+. (The whole library is one FFI framework: cave-gen was
  migrated off `meowtonin` onto byondapi so `verdigris` links a single BYOND API.)

Recent hardening (already landed): ban/admin/stats SQL is fully parameterized; all verdigris
`#[byond_fn]` entry points are wrapped in `panic_safe!`; the tgui Rules-of-Hooks / XSS audit
findings are fixed; the unit-test suite was audited for fake-passes and made genuinely
falsifiable.

## TL;DR

> One unified tree — put code in the matching `code/`/`maps/`/`icons/` location and
> edit any file freely (no modular folders, no edit markers, no upstream merges).
> Register every new `.dm` in `deepquarry.dme`, use absolute type paths, follow the
> DM standards in §3, drop a changelog YAML, and squash before merge.

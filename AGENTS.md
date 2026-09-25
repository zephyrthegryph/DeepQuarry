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
- `bin/test.cmd` — build and boot the unit-test world (see §4a).
- `bin/tgui-build.cmd` / `bin/tgui-dev.cmd` / `bin/tgui-fix.cmd`.
- `bin/clean.cmd`.

`tools/build/build.ts` (Juke) orchestrates the DM build. Two fork-specific steps:

- **Icon repack** (`tools/dq_icons/`): regenerates `.dmi` from `png` + `dmi.toml`
  into `icons/gen/` before the DM compile (dirty-checked; no-ops when clean).
- **verdigris** (`tools/build/build.ts` `VerdigrisTarget`): builds the Rust FFI
  library (`verdigris.dll` on Windows, `libverdigris.so` on Linux) when its source
  is stale. You can also build it directly with `verdigris/build-windows.sh` /
  `verdigris/build-linux.sh`. The compiled library is a gitignored per-platform
  artifact; the DM game calls it through the generated `vg_*` procs in
  `code/__defines/verdigris/_bindings.dm` (`tools/build/build.sh verdigris-bindings`
  regenerates them; see `verdigris/README.md`).

**Worktrees and DM-only work:** set `DQ_PREBUILT_VERDIGRIS=1` to reuse an existing `verdigris.dll` instead of compiling the Rust workspace (each fresh worktree otherwise rebuilds it from scratch). Rust work should set `RUSTC_WRAPPER=sccache` so worktrees share compiled dependencies. The build also honours `CARGO_TARGET_DIR`.

**Worktrees and DM-only work:** set `DQ_PREBUILT_VERDIGRIS=1` to reuse an existing `verdigris.dll` instead of compiling the Rust workspace (each fresh worktree otherwise rebuilds it from scratch). Rust work should set `RUSTC_WRAPPER=sccache` so worktrees share compiled dependencies. The build also honours `CARGO_TARGET_DIR`.

Runtime DMI note: because repacked `.dmi` live only in `icons/gen/`, code that reads
DMI metadata at runtime via rust-g resolves the `icons/gen/` copy automatically
(`icon_metadata()`, `universal_icon.to_list()`).

The DM linter (`SpacemanDMM`) runs as part of the build and in CI — heed every
warning.

### 4a. Testing

`doc/testing.md` is the full reference. The short version:

- **While developing, run only the tests you touch**, with
  `bash tools/dq_focused_test.sh /datum/unit_test/<name> [...]`. It works from
  a git worktree. It costs the compile plus about 25 seconds.
- **Run the full suite only at integration** (before merging, or when asked).
  It costs the compile plus about four minutes.

| What | Command |
|---|---|
| Full unit-test suite (test map) | `bin/test.cmd` or `tools/build/build.sh dm-test` |
| Only some tests | `bash tools/dq_focused_test.sh /datum/unit_test/<name> [...]` |
| Same, on Southern Cross | `bash tools/dq_focused_test.sh --full-map /datum/unit_test/<name>` |
| DM and TGUI lint | `tools/build/build.sh lint` (other CI checks: `doc/testing.md`) |
| TGUI tests | `tools/build/build.sh tgui-test` |
| Rust | `cd verdigris && cargo test --package verdigris` |
| Flaky, or caused by my change? | `tools/build/build.sh test-repeat --runs=5` · `tools/build/build.sh test-baseline` |
| Memory, tick cost, overruns | `bin/bench.cmd` or `tools/build/build.sh bench [--scenario=a,b] [--runs=3]`, then `bench-compare` |

Measure before and after any performance or memory change with `bench`; don't write
one-off profiling tests or scripts. Add a scenario under `code/modules/benchmarks/`
instead. Results and history live in `data/bench/` and `data/test-runs/`. If another
agent's unfinished work breaks the build, `DQ_WIP_TREE=1` lets test and bench builds
skip their dangling includes.

Never commit a `TEST_FOCUS(...)` line in `code/modules/unit_tests/dq_focus.dm`;
CI rejects it.

---

## 5. TGUI

- `tgui/` is TypeScript-only with Biome (formatter/linter) and Bun (runtime).
- `bin/tgui-fix.cmd` (or `bun run tgui:fix` at the repo root) auto-fixes;
  `tools/build/build.sh lint` checks Biome and TypeScript.
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
`refactor`, `code_imp`, `config`, `admin`, `server`, `wip`. The nightly
`compile_changelogs` workflow rolls the stubs into `html/changelogs/archive/`
(which the in-game changelog reads) and deletes them.

---

## 7. PR checklist

- [ ] New `.dm` files `#include`d in `deepquarry.dme`.
- [ ] Absolute type/proc paths only; no `:` operator on subtype access.
- [ ] `Destroy()` nulls refs / unregisters signals / returns the right `QDEL_HINT_*`.
- [ ] Signal handlers start with `SIGNAL_HANDLER`; callbacks use the `*_PROC_REF` macros.
- [ ] Time args use `SECONDS`/`MINUTES`/`HOURS`.
- [ ] DreamChecker (`SpacemanDMM`) passes locally.
- [ ] TGUI (if changed): `tools/build/build.sh lint tgui-test` clean.
- [ ] Unit tests pass (`bin/test.cmd`), and `dq_focus.dm` is empty.
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

- **Atmospherics — LINDA on a Rust backend.** LINDA (the vendored /tg/ atmos under
  `code/ATMOSPHERICS/`) is the only engine; ZAS/XGM are gone. Gas math, turf diffusion,
  decompression and heat conduction (superconductivity) run in the auxmos arena inside
  Verdigris, driven from `SSair.fire()`. `code/ATMOSPHERICS/README.md` is the reference.
  **`/datum/gas_mixture` is an opaque handle.** There is no public `temperature`/`volume`
  var: read with `return_temperature()`/`return_volume()`, write with
  `set_temperature()`/`set_volume()`, and cache reads in hot loops because each call crosses
  the FFI. Atoms (turfs included) have one temperature API in `code/modules/heat/heat.dm`:
  `get_temperature()` / `get_interior_temperature()` to read, `add_heat()` to heat,
  `/turf/proc/set_temperature()` for map/admin authority. `return_temperature()` is the gas
  mixture accessor only, and shared thermal constants (`T0C`, `BODYTEMP_NORMAL`,
  `HUMAN_HEAT_CAPACITY`, …) are generated from `verdigris/domains/heat/src/consts.rs`. The `check_grep.sh` "gas mixture mirror writes" lint backs this up.
  The FFI routes are the generated `vg_*` procs; the DM wrappers with real logic live in
  `gas_mixture.dm`, `auxmos_init_bridge.dm` and `dq_linda_turf_air.dm`.
  Verdigris builds on byondapi 0.6.x and **requires BYOND 516.1682+** (older builds crash at
  atmos init on a missing `ByondValue_DecTempRef`). Gas **reactions** deliberately stay in DM.
  `xgm_compat.dm` and `tg_infra_compat.dm` are the fork's stable compatibility API, not
  temporary shims: they carry real ZAS→LINDA semantics (`assume_gas` temperature mixing,
  `c_airblock` bitfields), and `CanZASPass` is a hook many atoms override.
  The **`.air`-on-unsimulated-turf** family (Southern Cross has ~1188 `/turf/unsimulated/floor` that
  inherit `init_air` but are NOT `/turf/open`, so have no `air` var) is now guarded at all three sites:
  `setup_allturfs` append, the difference-pass neighbour loop, AND `add_to_active` (`SSair.dm` — the last
  was reached via **vents** `pipeline/mingle_with_turf` and threw a runtime EVERY vent tick, flooding logs).
  The SSair admin debug panel works again: verb "Debug Atmospherics" (Debug→Investigate) →
  `SSair.tgui_interact` → `AtmosControlPanel.tsx` (was dead: nonexistent interface + `ui_*` names when this
  fork's tgui calls `tgui_*`).
- **Expeditions and Flight Operations.** The old quarry mode is gone. `SSexpedition`
  (`code/modules/expedition/`) generates sites on demand: it allocates or recycles a
  z-level (`load_new_z()`), carves it with the `cave_system` automata or builds a generated
  station, bridges it into multi-z atmos, and populates POIs, loot and a
  `/datum/expedition_mission` objective. Sites are released and wiped when the crew leaves;
  z-levels go back into a `free_z` pool. Crews reach sites by flying: `SSflight_operations`
  (`code/modules/flight_operations/`) owns vessels, destinations, berths and flight plans,
  and the Flight Operations console plots expedition contracts as short-jump destinations.
  Admin debug verbs ("Generate Expedition Site" / "Generate Expedition Mission") jump
  straight to a site. Lifecycle risks are tracked in `doc/generated_site_lifecycle_audit.md`.
- **Material science and engineering.** The science core is physical material work
  (`code/modules/material_science/`): crucibles, alloys with measurable structure,
  layered composites, reagent baths, slime coatings, and exotic feedstocks from
  expeditions. Engineered materials change how assemblies behave (cable heating, pipe
  pressure and corrosion, heat exchange, power cells, emitters, armour, ammunition).
  `doc/material_engineering_implementation.md` describes the model and
  `doc/material_engineering_playtest.md` how to exercise it in game. The earlier
  "substance" system was removed in favour of this.
- **Variants.** Families of subtypes that differ only in data are collapsed into one type
  plus a registry to save memory. See `code/datums/variants/README.md`.
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
  `set_material`. This is how engineered and exotic materials become lathe-buildable without one techweb
  entry per material. Design backend: `effective_materials()`/`material_choice_valid()` (`designs.dm`). Both build
  paths thread `chosen_material`: protolathe family `_production.dm` (`build`/`do_make_item`) AND autolathe
  `autolathe.dm` (`make`/`do_make_item`). UI: one shared `Fabrication/SelectableRecipe.tsx` (native row +
  dropdown + x1/x5/x10/max), used by both `Fabricator.tsx` and `Autolathe.tsx` via an `onBuild` callback;
  `materialChoices` in `Types.ts`. Sample designs + node: `designs/material_selectable.dm` (Material
  Knife/Sword, `build_type = AUTOLATHE | PROTOLATHE`, starting node). The lathe material container allows
  any `/datum/material` subtype. Biome lint/format clean (root
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
  hooks. Hits reach it through one path: an entry point (`bullet_act`, `hitby`, `ex_act`, `emp_act`,
  `fire_act`, `blob_act`, `attack_generic`, weapon `attackby`, `electrocute_act`) builds a pooled damage
  packet and calls `receive_damage(packet)` (`code/game/atom/damage_packet.dm`, doc/rewrite/damage.md);
  use the `receive_*`/`deal_damage` helpers there instead of calling `take_damage()` from an entry point.
  The old parallel `var/health`/`var/maxhealth` + `healthcheck()`/`CheckHealth()` model is
  **gone** — don't reintroduce it; set `max_integrity` (and `integrity_failure` for a "broken
  but not destroyed" state) and route damage through `take_damage()`. Turfs/walls keep their own
  `damage`-var model (as upstream TG does). A few entities run self-contained damage backed by
  obj_integrity but with their own combat logic on top: `/obj/mecha` (component armor/deflect)
  and `/obj/item/uav`. Mob/plant/blob health is a separate system and untouched.
- **Health model — body & afflictions, no health pools on ANY mob.** Read
  `doc/body_architecture.md`. Every `/mob/living` has a `/datum/body` (plans: humanoid,
  simple, simple/machine, simple/machine/robot) in `code/modules/body/`. There is no
  `health`/`maxHealth`/`*loss`, `adjust*Loss`, `apply_damage`, `updatehealth`, `getMaxHealth` —
  those are deleted. Harm = `L.injure(INJURY_*, amount, zone, source, armor, affliction)`;
  healing = `L.mend(TREAT_*, amount, zone)` / `fully_heal()`; questions = `vitality()`,
  `is_critical()`, `get_endurance()`, `injury_load(INJURY_CATEGORY_*)`. Mob toughness is
  `endurance`. Everything harmful is a `/datum/affliction` (limb wounds too; limb integrity is
  `E.get_trauma()`/`get_burn()`, derived). Afflictions declare `biology` and `body_plans`;
  treatment tags declare biology — never branch on `isSynthetic()` for damage/heal. Reagents
  heal only via `treatment_tags` (`code/modules/body/treatment.dm`). Triggers
  (`/datum/affliction_trigger`) create afflictions; symptoms are singletons that ACCUMULATE.
  Vital systems (airway / breathing / cardiac rhythm, `medical/conditions/vital_systems.dm`)
  are afflictions too; see the doc. Also BUILT (all in the doc):
  - **Physiology / oxygen debt** (`code/modules/body/physiology.dm`): ventilation,
    oxygenation, perfusion and an oxygen debt; there is no `INJURY_ASPHYXIA` — express a
    cause as a factor, support/restriction or breath quality, else `add_oxygen_debt()`.
  - **Stabilisation** (`code/modules/medical/stabilisation/`): tourniquets
    (`flow_occluded()`), field items, and stasis on the biology clock (stasis modifiers hold
    `EFFECT_CLOCK_BIO_INHIBIT`), read once per frame by `body.advance_stasis()`; systems check
    `ctx.in_stasis()` / `inStasisNow()`.
  - **Surgery as treatments** (`code/modules/surgery/`): steps deliver `TREAT_*` through
    `mend()`; access state is the `surgical_incision` affliction (no `op_stage`); organs
    past saving answer `is_beyond_repair()`.
  - **Diagnosis** (`code/modules/medical/diagnosis/`): readouts go through
    `diagnose(profile)` and renderers; no four-number damage readouts.
  - **Hibernation**: life systems sleep by rule and wake on events (see the Mob life entry).
- **Body factors — every numeric mob stat.** `code/modules/body/factors.dm`, defines in
  `code/__defines/body_factors.dm`. Slowdown, accuracy, evasion, attack speed, incoming
  injury per category, stun duration, healing received, metabolism, bleeding, analgesia,
  vitals readouts, armour, conductivity, action blocks, … are `BF_*` factors with one combine
  rule each. Read them with `L.factor(BF_X)`. Sources declare static `alist` tables:
  affliction `factors` (scaled by severity; a stage's `"factors"` applies at full value),
  reagent `factors` / `species_factors` (scaled by dose), modifier `factors`, species
  `factor_baseline`, trait/perk `factors`, form `factors`, item `worn_factors`. The body
  caches one flat list (null at baseline) and recomputes on `BODY_DIRTY_FACTORS`. There is
  no `chem_effects`/`add_chemical_effect`, no `mechanical_effects`/`vital_effects`/`od_boost`
  and no numeric modifier fields; `tools/ci/check_grep.sh` rejects them. Brief non-reagent
  effects are short modifiers (`/datum/modifier/numbness`, `withdrawal_strain`, …).
- **Mob Life runs on the object model.** Read `doc/rewrite/life_on_om.md`. Every `/mob/living`
  carries the `life` behaviour (`code/modules/mob/living/life/life_om.dm`): one frame per
  `LIFE_CYCLE` (6 s, fixed steps, catch-up capped at 2) runs an ordered list of
  `/datum/life_system` flyweights composed per mob type (`life_frame()`). There is no `Life()`
  proc and no SSmobs Life loop. Don't add `handle_*` hooks on mobs: add a system, or a variant
  whose path mirrors the mob path (`breathing/carbon/human`). Code outside Life uses
  `refresh_hud()`, `refresh_vision()`, `refresh_glow()` or `run_life_system()`; components tick
  via `add_trait_life_system()`. Observers (ghosts, AI eyes, blob) run `upkeep()` on their own
  behaviour. Life content is written per frame, so `LIFE_CYCLE` sets its per-second balance.
  **Mobs are event-driven and hibernate, players included** (doc §5):
  - A system sleeps when its `idle(self)` holds after it ticks, and wakes when a mob change
    channel in its `wake_on` (`LIFE_WAKE_ON_*`) is raised. `rewake_delay()` sets a slow timer
    for work that still drifts; `woken_by` documents the producers. The default `idle()` is
    FALSE, so a new system stays awake until you give it a rule.
  - A mob with nothing awake leaves the ring (`om_sleep`) until a change or a timer.
  - Anything that changes what a system reads must raise the channel:
    `om_changed(L, CHANGE_MOB_HEALTH|STATUS|LOC|EQUIPMENT|CONDITIONS|STAT|CLIENT)`, or go through
    a producer that does: `injure`/`mend`, `body.invalidate()`, the status setters, `Moved`,
    equip/unequip, `set_stat`, Login, modifiers.
  - `life_hibernate()` and `life_resume()` are the only procs that park and unpark a mob;
    `check_grep.sh` rejects direct writes to `life_hibernating`/`life_asleep`.
  - Stun, weaken and paralysis are timed contributions (`EFFECT_STUNNED`/`WEAKENED`/
    `PARALYZED`): set them with `Stun()`/`SetStunned()`/`AdjustStunned()` etc. (units of
    `LIFE_CYCLE`), read them with `is_stunned()`/`get_stunned()`. There are no counters.
  - Stasis holds `EFFECT_CLOCK_BIO_INHIBIT` (the biology clock); absorbed prey and bodies kept
    for reforming are suspended (`suspend_life()`/`resume_life()`).
  - A 30 s audit logs `MOB_HIBERNATE_AUDIT: MISSED WAKE` and wakes the mob when a producer
    was forgotten. It always runs in test builds and fails the run on a miss. On servers it's off
    unless the `MOB_HIBERNATION_AUDIT` config flag or the "Toggle Hibernation Audit" verb turns it on.
  - Transition tracing is `GLOB.mob_hibernation_trace`.
- **verdigris (Rust FFI)** is a build artifact, gitignored per-platform. If `cargo` is absent
  the build warns and skips it, and **both** subsystems that depend on it fail at runtime:
  cave-gen (expedition) and — since the auxmos cutover — **atmospherics** (gas math + turf
  processing + superconductivity all run in the Rust arena now, not pure DM). It builds on
  **byondapi 0.6.x** for BYOND 516.1682+. (The whole library is one FFI framework: cave-gen was
  migrated off `meowtonin` onto byondapi so `verdigris` links a single BYOND API.)

Recent hardening (already landed): ban/admin/stats SQL is fully parameterized; every
Verdigris bind is declared with `#[auxmacros::bind]` (panic-safe, generated DM binding); the tgui Rules-of-Hooks / XSS audit
findings are fixed; the unit-test suite was audited for fake-passes and made genuinely
falsifiable.

## TL;DR

> One unified tree — put code in the matching `code/`/`maps/`/`icons/` location and
> edit any file freely (no modular folders, no edit markers, no upstream merges).
> Register every new `.dm` in `deepquarry.dme`, use absolute type paths, follow the
> DM standards in §3, drop a changelog YAML, and squash before merge.

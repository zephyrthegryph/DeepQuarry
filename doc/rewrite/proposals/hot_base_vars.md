# Hot base vars: a declared home for the vars the engine reads every tick (decided 2026-10-25)

Status: **decided** (the coordinator, on the user's delegation). The hot vars stay on their base types; their home is a closed, justified list in
`tools/ci/lint_scopes.toml`. A separate implementation lane makes the lint change; this document is its specification. Rule it amends:
`proposals/base_vars.md` ("every var on a base type gets exactly one home").

## 1. Problem

`proposals/base_vars.md` gives each base-type var one home: trait block, profile record, HUD datum, owning domain / `TRACKED`, sparse slot, relation,
cooldown table, or deletion. A handful of vars fit none honestly, because the engine's own loops read them for most instances every tick, every move or every
overlay flush, and each home adds an indirection on that path:

- a trait block read is a typed read through a datum (`combat_of(I).force`: a proc call and a dereference);
- a sparse slot read is `sparse_get(A, x)`: a proc call and an assoc lookup on a lazy list;
- a profile, HUD or cooldown read is the same shape.

Moving them would not be a cleanup; it would put a call into the atmos step, `Move()`, the overlay queue and the lighting update. Leaving them as base-type
vars with `ALLOW(base_vars)` hides them from the census. So: an honest, countable home.

## 2. The home: `base_var_home_hot`

`tools/ci/lint_scopes.toml`, next to `base_var_home_macros` and `base_var_home_types` (`[lint.base_vars.lists]`):

```toml
# A base-type var the engine reads per tick or per move for most instances. One entry per var; the reason names the hot-path reader (file:line) and
# the indirection a trait or sparse slot would add there. Closed: adding an entry is a design change reviewed with the doc, not an annotation.
base_var_home_hot = [
	{ var = "/atom::flags_1", reason = "SSair.add_to_active reads INITIALIZED_1 per atom activation (code/ATMOSPHERICS/SSair.dm:343); a trait read would add a call per turf update" },
	...
]
```

Lint rules (`base_vars`, `tools/analyze/src/lints/base_vars.rs`):

1. A listed var is homed: it is not a `base_var` site, and its baseline row drops on `analyze baseline --update`.
2. The list is **closed**: the lint fails if an entry has no `reason` of at least 20 characters and 3 words (the `allow_annotations` rule), if the var is not declared
   on the owner it names, or if the count exceeds `hot_ceiling` (set to the list's length at landing; it only falls).
3. A listed var must not be `TRACKED`/`STAT`/`SETTER`: a var that publishes already has a home (listing it is a mistake, and the lint says so).
4. A listed var with no read outside its own file is dead, not hot: the dead-var report (`analyze base-vars-dead`) wins and the entry is a finding.
5. `ALLOW(base_vars)` for a listed var is an unused annotation (`allow_annotations` rejects it): the list replaces it.
6. The VV and map loader treat a listed var as a plain var (no trait routing).

## 3. Criteria: when a var may be listed

All of these hold, and the `reason` shows them:

- **C1, breadth.** Declared on `/atom`, `/atom/movable` or `/mob/living`, and read for most instances of that base type, not a niche of subtypes.
- **C2, a named per-tick path.** Read inside an engine-owned loop that runs per tick, per move, per bump, per atmos activation or per overlay flush, at a file:line the reason cites.
  A read in a verb, an examine, a UI window or a periodic effect does not qualify.
- **C3, no subscribers.** Nothing reactive depends on it (no draw, `on_change`, stat hop or `derives()` reads it). A var that reactive code reads is `TRACKED` with a setter
  and has a home already. The listed vars are engine bookkeeping or flag words whose writers publish nothing.
- **C4, the indirection is real.** The alternative home adds a proc call or a dereference on that path (trait, sparse, profile, HUD, cooldown). A var read once per instance
  at init (`init_from_table`) does not qualify.
- **C5, closed.** At most `hot_ceiling` entries; a new entry replaces nothing and so needs review. Revisit when benchmarks resume (`no-bench-until-end`): an entry the
  measurement shows costless to move, moves and leaves the list.

## 4. Census

Starting from the 238 `base_var` rows on `origin/master` (`tools/ci/base_vars_baseline.txt`), the vars that meet C1-C4, each with the hot-path reader the entry cites.
Readers are on `origin/master`; "writer" names the per-move writer where the var is bookkeeping.

| Var | Declared | Hot-path reader (file:line) |
|---|---|---|
| `/atom::flags_1` | `code/ATMOSPHERICS/atom_flags_1.dm:10` (`var/tmp`) | `SSair.add_to_active` (`code/ATMOSPHERICS/SSair.dm:343`) and the LINDA signal gates read `INITIALIZED_1` per activation; `/atom/Initialize()` sets it (`atoms_initializing_EXPENSIVE.dm:79`) |
| `/atom::can_atmos_pass` | `code/ATMOSPHERICS/environmental/LINDA_system.dm:3` | the air-block mask folds every object's value per adjacency (`LINDA_system.dm:58`, `can_atmos_pass()` at `:5`) each time a turf's mask is recomputed |
| `/atom/movable::pressure_resistance` | `code/ATMOSPHERICS/environmental/LINDA_turf_tile.dm:330` | the pressure-displacement step divides by it for every movable in an active turf (`:338-339`) |
| `/atom::flags` | `code/game/atom/_atom.dm` (declaration in the atom block) | the bitfield (`OPENCONTAINER`, `ATOM_INITIALIZED`, ...) read across `reagents`, `Initialize` and the container checks (`_atom.dm:126-135`); its lifecycle bits are written while an atom is materialized, which can happen inside a draw (`exclude_memo` in `lint_scopes.toml` already says so) |
| `/atom::pass_flags` | `code/game/atom/_atom.dm:12` | `pass_flags & passflag` on every `CanPass()` / projectile pass test (`_atom.dm:439`) |
| `/atom/movable::movement_type` | `code/game/atoms_movable.dm:24` | `Enter()` and `CanPass()` per move (`code/game/turfs/turf.dm:335, :345`, `CHECK_BITFIELD(mover.movement_type, UNSTOPPABLE)`) |
| `/atom/movable::last_move` | `code/game/atoms_movable.dm:6` | written by every `Move()` (`:286`); read by pushing, buckling and inertia |
| `/atom/movable::move_speed` | `code/game/atoms_movable.dm:9` | written by every `Move()` (`:294`, `world.time - l_move_time`) |
| `/atom/movable::l_move_time` | `code/game/atoms_movable.dm:10` (`EXPIRY_TMP_DECLARE`) | the baseline of `move_speed`, every move (`:294`) |
| `/atom/movable::moving_diagonally` | `code/game/atoms_movable.dm` | the diagonal-step state machine in `Move()` (`:232-245`) |
| `/atom/movable::throwing` | `code/game/atoms_movable.dm:12` | `Bump()` finalizes a flight (`:376-377`); lava and turf `Enter` read it per entering movable (`code/game/turfs/simulated/lava.dm:88`) |
| `/atom::our_overlays` | `code/game/atom/_atom.dm:29` (`var/tmp`) | the overlay queue (`code/controllers/subsystems/overlays.dm`): every `add_overlay` / `cut_overlays` / flush reads and rewrites it |
| `/atom::light_sources` | `code/modules/lighting/lighting_atom.dm:10` (`var/tmp`) | `Moved()` walks every light source on the mover (`code/game/atoms_movable.dm:322`) |
| `/atom/movable::blocks_emissive` | `code/modules/lighting/lighting_atom.dm:17` | the emissive blocker overlay build on every overlay update (`code/modules/lighting/emissive_blocker_overlays.dm:13`) |
| `/mob::m_intent` | `code/modules/mob/mob_defines.dm:80` | every step: `living_movement.dm:20` (walk vs run delay), `mob_movement.dm:21`, `carbon.dm:51-54` (hunger cost of running per step) |
| `/mob/living::now_pushing` | `code/modules/mob/living/living_defines.dm:14` | every bump: `living_movement.dm:51-53`, `carbon.dm:382` |
| `/mob::track_blood` | `code/modules/detectivework/tools/rag.dm:5` (and `:13`) | every step onto a simulated turf: `code/content/turfs/simulated.dm:108-116` (`H.track_blood`, `S.track_blood--`) |

**17 vars** of 238 rows (7%). `hot_ceiling = 17`.

Considered and **not** listed (each has a real home, or fails a criterion):

| Var | Why not |
|---|---|
| `/mob::bodytemperature`, `/atom::atom_integrity`, `/atom::uses_integrity` | live simulation state that reactive code reads (C3): `TRACKED` with a setter |
| `/atom::germ_level` | read per interaction, not per tick (C2); a domain var (contamination) |
| `/atom::realized_overlays`, `/atom::realized_underlays` | `var/tmp` copies the overlay system builds only so VV can show them (`overlays.dm:174-194`): not read per tick (C2). Delete, or build them on demand in VV |
| `/atom::managed_vis_overlays`, `/atom/movable::recursive_move`, `/atom/movable::overlay_light`, `/atom::light` | owned or referenced datums: relations (`owns_one`/`ref_one`) already home them |
| `/atom::light_flags` | read when the flag is written (`lighting_atom.dm:166`), not per tick (C2): a light trait field |
| `/atom::simulated` | no per-tick reader found in the engine (the `simulated` matches are the `/turf/simulated` type path); left out (section 7); it may be a trait |
| `/atom/movable::old_x`, `old_y`, `throw_source`, `throw_range` | no engine reader found; the dead sweep decides (`throw_source` is a relation already, `atoms_movable.dm:147`) |
| `/atom/movable::latent_touched_at`, `latent_refused_until`, `/mob::last_move_time` | timers: the cooldown table |
| `/mob::inertia_dir` | written by throws and extinguishers (`thrownthing.dm:220`, `extinguisher.dm:143`); no per-move reader confirmed: left out (section 7) |
| `/atom::init_from_table` | read once per atom at init (C4): a type trait |
| `/obj::explosion_resistance`, `/obj::insulation`, `/atom::armor_spec`, `/atom::armor_override` | read per explosion or per hit, not per tick (C2): trait fields |

## 5. Per-tick read cost argument

The argument is structural, not measured (benchmarks are off until the rewrite ends, `no-bench-until-end`):

- A DM var read on `src` is one instruction. A trait read is a proc call (`combat_of()`) plus a typed dereference of the shared datum; a sparse read is a proc call plus
  an assoc lookup on a lazy list that may be null. In BYOND a proc call costs about an order of magnitude more than a var read (to be measured at the end, not asserted as a number).
- The listed reads sit in loops whose iteration count is the world's atom count: the atmos step touches every movable in an active turf; `Move()` runs for every moving thing,
  several thousand times a second at a busy moment; the overlay queue flushes per icon update; `Moved()` walks light sources. One added call on each is a visible fraction of that
  loop, and the loops are the ones that decide tick overrun (`KERNEL_OVER_BUDGET`).
- None of these vars is something the reactive layer reads (C3), so keeping them as plain vars does not cost the framework a hop or a generated read; they are outside the
  closed read walk by design, like the engine's own bookkeeping.
- The reverse cost, a list that keeps growing, is bounded by C5: the lint refuses a new entry without review, and the ceiling falls as entries move or die.

## 6. Implementation (a separate lane)

1. Add `base_var_home_hot` and `hot_ceiling` to `[lint.base_vars.lists]` with the 17 entries and their reasons.
2. `base_vars` lint: accept a listed var as a home; the five checks of section 2; baseline drops 17 rows.
3. Dead-var report: skip listed vars for the "no reads" finding only where the entry names a reader; flag one whose cited reader no longer reads it.
4. Delete any `ALLOW(base_vars)` on a listed var; `allow_annotations` will name them.
5. Tests: a fixture with a listed var, one without a reason, one `TRACKED` listed var (refused), one over the ceiling.
6. `proposals/base_vars.md` table gains a row "Engine hot path -> declared list" and `final_api.html` section 6 ("Homes for base-type vars") a sentence.

## 7. Left out until confirmed

`/mob::inertia_dir` and `/atom::simulated` are **not** on the list. No per-tick or per-move reader of either was confirmed (`inertia_dir` is written by throws and extinguishers, `thrownthing.dm:220`,
`extinguisher.dm:143`; the `simulated` matches are the `/turf/simulated` type path). The criteria rule and, in doubt, a var stays out; either joins only with a cited reader at a file:line in a reviewed change.

When benchmarks resume, a one-time measurement of moving one entry (say `pass_flags` into a trait) decides whether the list can shrink; the list is not a promise to keep them.

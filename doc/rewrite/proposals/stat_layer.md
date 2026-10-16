# Proposal: the stat layer for body factors (phase 1, design only)

Status: approved 2026-10-16 (decisions D1 to D10 as recommended); waves 0 to 2 in progress, wave 3 deferred. Branch `rewrite/stat-layer` (from origin/master `c3cb037784`). Scope: doc section 5
(`final_api.html`), the body-factor (`BF_*`) system in `code/modules/body/factors.dm`, and the leftovers of the old grant and
contribution store.

## 0. Summary

1. **Most of section 5 is already on master.** `STAT()`, `contributes()`, `contributes_to()`, `hold()`, `hold_until()`,
   `hold_override()`, `release()`, `release_all()`, `held_by()`, `held_by_source()`, `hold_left()`, `grant()`/`revoke()`, statuses,
   standings, the inline recompute with a marked drain, hops, the staleness checker and generated reads all live in
   `code/engine/stats/` (2.7k lines) and are used by machines, statuses, `alpha_mult`, relevance, stasis rate and traits. The AGENTS.md
   table row "Numbers/flags composed from sources ... **new**" is stale: only the *body factors* are still the old mechanism.
   `om_apply`, `om_hold`, `om_grant` and the rest of the old store have **zero callers** in `code/`; they survive only in
   `doc/rewrite/archive/`.
2. **Body factors are the one big remaining hand-rolled stat system**: 70 factors plus an armour family, folded by
   `/datum/body/recompute_factors()` into a flat cache `body.factors` that sources dirty with `BODY_DIRTY_FACTORS`. It is a private,
   second implementation of what `stat_compute()` does. The migration is therefore not "invent a stat layer"; it is **move the factor
   sources onto the existing stat store and retire the private one**, plus a handful of small engine gaps (section 3).
3. **The risk is balance neutrality, not the engine.** The old fold has behaviour the stat engine lacks today: final clamping to bounds,
   a different `MAX` baseline rule, "every dirty event re-reads every source at its current dose/severity", and a different float
   multiplication order. Each is called out with a decision and a parity oracle (3.6) that proves identical output before anything is
   deleted.
4. No engine prototype was written. Every engine change in section 3 is small and independent; the one non-trivial piece (`hold_table`)
   should be the first commit of wave 0 together with its unit test, not throwaway code now.

## 1. Census

Counts are from `git grep` on the branch.

* `BF_*` references: **691 in production code** (excluding `code/__defines/body_factors.dm`; another 100 sit in `factors.dm` itself) and
  **152 in 21 unit-test files** (70 of them in `dq_body_factor_tests.dm`). The brief's "~779" is roughly production plus the defines.
* About 110 production read sites and 30+ source declaration files. Heaviest files: `factors.dm`, `reagents/content/medicine.dm` (28),
  `body/physiology.dm` (24), `medical/conditions/vital_systems.dm` (22), `human/life.dm` (21), `trauma.dm` (20),
  `_modifiers/{medical,traits,modifiers_misc}.dm`, `species/station/station.dm` (14).

### 1.1 Per factor

**prod** = production references (excluding the define and `factors.dm`); **tables** = sites giving the factor a value in a source
table (`BF_X = value`); **reads** = direct `factor(BF_X)` / `get_factor` / `supported_factor` sites (indirect reads through helpers such as
`injury_armor()`, `incoming_injury_factor()`, `action_blocked()`, `baseline_factor()` and the `factors[...]` index reads in
`tick_factor_effects()` are not counted); **tests** = references in unit tests. Rule, base and range come from
`build_body_factor_defs()`.

| factor | rule | base | range | prod | tables | reads | tests |
|---|---|---|---|---|---|---|---|
| BF_AIRWAY | MULT | 1 | 0..1 | 12 | 1 | 1 | 13 |
| BF_RESP_DRIVE | MULT | 1 | 0..2 | 11 | 2 | 2 | 1 |
| BF_LUNG_MECHANICS | MULT | 1 | 0..1 | 8 | 2 | 1 | 0 |
| BF_GAS_EXCHANGE | MULT | 1 | 0..1 | 10 | 3 | 1 | 0 |
| BF_PUMP | MULT | 1 | 0..2 | 19 | 5 | 4 | 1 |
| BF_CIRCULATION | MULT | 1 | 0..2 | 10 | 4 | 2 | 0 |
| BF_DEMAND | MULT | 1 | 0..4 | 19 | 15 | 2 | 0 |
| BF_PROGRESSION | MULT | 1 | 0..4 | 3 | 0 | 3 | 0 |
| BF_METABOLISM | MULT | 1 | 0..10 | 28 | 24 | 3 | 1 |
| BF_BLEEDING | MULT | 1 | 0..10 | 16 | 13 | 1 | 0 |
| BF_HEALING | MULT | 1 | 0..10 | 5 | 2 | 2 | 0 |
| BF_ANALGESIA | ADD | 0 | unbounded | 47 | 37 | 7 | 6 |
| BF_PAIN | ADD | 0 | 0..inf | 7 | 6 | 1 | 4 |
| BF_SEDATION | ADD | 0 | 0..inf | 3 | 0 | 2 | 0 |
| BF_ARRHYTHMIA_RISK | ADD | 0 | 0..inf | 0 | 0 | 0 | 0 |
| BF_HEART_RATE | ADD | 0 | unbounded | 44 | 41 | 2 | 7 |
| BF_TEMPERATURE | ADD | 0 | unbounded | 18 | 11 | 2 | 2 |
| BF_BP_SYSTOLIC | ADD | 0 | unbounded | 30 | 27 | 2 | 2 |
| BF_BP_DIASTOLIC | ADD | 0 | unbounded | 11 | 8 | 2 | 0 |
| BF_O2_SAT | ADD | 0 | -100..100 | 21 | 18 | 2 | 2 |
| BF_RESP_RATE | ADD | 0 | unbounded | 17 | 14 | 2 | 0 |
| BF_SLOWDOWN | ADD | 0 | -10..20 | 118 | 114 | 3 | 57 |
| BF_PENALTY_SCALE | MULT | 1 | 0..4 | 18 | 14 | 3 | 2 |
| BF_HASTE | MAX | 0 | 0..1 | 3 | 1 | 2 | 4 |
| BF_ACCURACY | ADD | 0 | unbounded | 44 | 41 | 3 | 6 |
| BF_DISPERSION | ADD | 0 | unbounded | 13 | 10 | 3 | 2 |
| BF_EVASION | ADD | 0 | unbounded | 28 | 27 | 1 | 2 |
| BF_ATTACK_SPEED | MULT | 1 | 0.1..10 | 20 | 18 | 2 | 2 |
| BF_MELEE_DAMAGE | MULT | 1 | 0..10 | 27 | 22 | 5 | 1 |
| BF_VISION | MULT | 1 | 0..2 | 0 | 0 | 0 | 1 |
| BF_HEARING | MULT | 1 | 0..2 | 0 | 0 | 0 | 0 |
| BF_MOTOR_CONTROL | MULT | 1 | 0..1 | 23 | 22 | 2 | 0 |
| BF_DARKSIGHT | MAX | 0 | 0..1 | 6 | 2 | 4 | 0 |
| BF_SIGHT_FLAGS | FLAGS | 0 | 0..inf | 4 | 2 | 2 | 0 |
| BF_ACTION_BLOCKS | FLAGS | 0 | 0..inf | 6 | 6 | 2 | 4 |
| BF_INCOMING_ALL | MULT | 1 | 0..10 | 23 | 22 | 1 | 0 |
| BF_INCOMING_PHYSICAL | MULT | 1 | 0..10 | 43 | 43 | 0 | 4 |
| BF_INCOMING_THERMAL | MULT | 1 | 0..10 | 44 | 44 | 0 | 0 |
| BF_INCOMING_TOXIC | MULT | 1 | 0..10 | 11 | 11 | 0 | 0 |
| BF_INCOMING_GENETIC | MULT | 1 | 0..10 | 2 | 2 | 0 | 0 |
| BF_INCOMING_NEURAL | MULT | 1 | 0..10 | 0 | 0 | 0 | 0 |
| BF_INCOMING_PAIN | MULT | 1 | 0..10 | 13 | 13 | 0 | 0 |
| BF_DISABLE_DURATION | MULT | 1 | 0..10 | 41 | 38 | 1 | 2 |
| BF_HEALING_RECEIVED | MULT | 1 | 0..10 | 15 | 14 | 1 | 7 |
| BF_ENDURANCE_FLAT | ADD | 0 | unbounded | 6 | 4 | 1 | 2 |
| BF_ENDURANCE_MULT | MULT | 1 | 0..100 | 22 | 20 | 1 | 0 |
| BF_ICON_SCALE_X | MULT | 1 | 0.1..10 | 15 | 12 | 2 | 0 |
| BF_ICON_SCALE_Y | MULT | 1 | 0.1..10 | 14 | 12 | 2 | 0 |
| BF_PAIN_IMMUNITY | MAX | 0 | 0..1 | 15 | 10 | 2 | 6 |
| BF_PULSE_SHIFT | ADD | 0 | unbounded | 4 | 3 | 1 | 0 |
| BF_PULSE_SET | MAX | -1 | -1..inf | 8 | 6 | 1 | 5 |
| BF_EMP_SHIFT | ADD | 0 | unbounded | 6 | 5 | 1 | 0 |
| BF_EXPLOSION_SHIFT | ADD | 0 | unbounded | 4 | 1 | 3 | 0 |
| BF_HEAT_EXPOSURE | MULT | 1 | 0..10 | 7 | 4 | 2 | 1 |
| BF_COLD_EXPOSURE | MULT | 1 | 0..10 | 6 | 4 | 2 | 1 |
| BF_SIEMENS | MULT | 1 | 0..10 | 13 | 11 | 2 | 4 |
| BF_STABILIZATION | ADD | 0 | 0..inf | 15 | 7 | 8 | 5 |
| BF_ANTIMICROBIAL | ADD | 0 | 0..inf | 12 | 6 | 5 | 0 |
| BF_BLOOD_REGEN | ADD | 0 | 0..inf | 8 | 6 | 1 | 0 |
| BF_INTOXICATION | ADD | 0 | 0..inf | 3 | 2 | 1 | 0 |
| BF_HEPATOTOXICITY | ADD | 0 | 0..inf | 7 | 1 | 6 | 0 |
| BF_ANTIEMETIC | ADD | 0 | 0..inf | 2 | 1 | 1 | 6 |
| BF_ALLERGY | ADD | 0 | 0..inf | 5 | 4 | 1 | 1 |
| BF_WITHDRAWAL | ADD | 0 | 0..inf | 18 | 4 | 13 | 0 |
| BF_NEURAL_REPAIR | ADD | 0 | 0..inf | 5 | 4 | 1 | 0 |
| BF_IMMUNE_SUPPRESSION | ADD | 0 | 0..inf | 4 | 4 | 0 | 0 |
| BF_O2_CARRIAGE | MULT | 1 | 0..2 | 5 | 2 | 1 | 2 |
| BF_TISSUE_UPTAKE | MULT | 1 | 0..2 | 3 | 1 | 1 | 2 |
| BF_CARDIAC_IRRITABILITY | MULT | 1 | 0..10 | 6 | 1 | 2 | 4 |
| BF_STASIS | MAX | 0 | 0..1 | 17 | 6 | 3 | 13 |
| BF_ARMOR(kind), `ARMOR_KIND_COUNT` ids | ADD | 0 | unbounded | 19 | 10 (one per kind) | 1 (`injury_armor`) | in `dq_harm_mitigation`, `dq_body_slot` |

Notes. `BF_SLOWDOWN` dominates (114 table entries: nearly every species, modifier, trait, form, reagent and worn item that touches speed).
`BF_INCOMING_*` (about 115 entries together) is almost all species `factor_baseline`. Four factors have no production use at all
(`ARRHYTHMIA_RISK`, `VISION`, `HEARING`, `INCOMING_NEURAL`; `VISION` has one test reference) and `SEDATION` is read but never written: delete
rather than migrate them (decision D9). `BF_COUNT` (15 refs) and `BF_RULE_*` (about 100 refs) are engine plumbing, not factors.

### 1.2 Who composes (the writers)

Every source declares a **static `alist` table** keyed by `BF_*` ids; `recompute_factors()` folds them in this order (it is also the
float multiplication order):

| # | source | table | folded by | scale | invalidated by |
|---|---|---|---|---|---|
| 1 | afflictions | `factors` (value at severity 100) or the active stage's `"factors"` (52 stage tables) | `accumulate_factors()`; overridden by `airway`, `respiratory_arrest`, `hypovolemic_shock`, `tissue_hypoxia` | `severity / AFFLICTION_SEVERITY_TERMINAL`; stage tables at 1 | add/remove, a `BF_SEVERITY_BAND` (10) crossing (`affliction.dm:192-214,436`) |
| 2 | body effects (modifiers are `/datum/body_effect` types) | `factors` per stack, or the application's own table (`set_body_effect_factors`, 1 user type each in `dark_respite.dm`, `cloak.dm`) | `accumulate_body_effect_factors()` (`body_effects.dm:423`), once per stack | 1 | effect start/end/stack, `set_/reset_body_effect_factors` |
| 3 | stasis | level's `factors` (`BF_STASIS`, MAX) | `accumulate_stasis_factors()` (`stasis.dm:187`) | 1 | `set_stasis` (`stasis.dm:171`) |
| 4 | reagents | `factors`; `species_factors` (22 sites, merged per species tag and cached); `accumulate_special_factors()` (ethanol, allergy, blood reagent) | `accumulate_reagent_factors()` | `dq_chem_dose_scale(volume)`; humanoid `chem_strength_pain` rescales `BF_ANALGESIA` | a dose *band* crossing (`update_reagent_factor_bands`, C12) |
| 5 | species, traits, perks | `factor_baseline` (35 species), `granted_factors` (`grant_factors()`/`revoke_factors()` from traits and perks), synthetic `BF_PAIN_IMMUNITY` grant for `NO_PAIN` | `accumulate_plan_factors()` (`plans/humanoid.dm:327`) | 1 | species set (`species.dm:931`), trait add/remove (`trait.dm:56,111`), `event.dm:210` |
| 6 | forms | `/datum/form.factors` (protean) | `accumulate_plan_factors()` | 1 | `protean/forms.dm:79,87,114` |
| 7 | worn items | `/obj/item.worn_factors` (one writer today: the headset slowdown, `headset.dm:731`) | `accumulate_plan_factors()` over `BODY_SLOT_WORN` | 1 | slot change of an item with `worn_factors` (`slots.dm:364,458`) |
| 8 | supports, restrictions (`add_support`, `add_restriction`) | not factors: floors and multipliers `supported_factor()` applies after the product | `physiology.dm:87-145` | n/a | 31 call sites |

No code writes `body.factors` outside `recompute_factors()`. `body_factor_finalize()` clamps every composed factor to its `[min,max]`.

### 1.3 Who reads

`factor(id)` is a `/mob/living` proc (`body ? body.get_factor(id) : baseline`); `get_factor` checks the dirty flag and rebuilds. Families:

* **Movement** (hottest): `human_movement.dm:11-34,94` (`HASTE`, `SLOWDOWN`, `PENALTY_SCALE`, plus `species.baseline_factor()` which re-folds the
  species table on every call), `simple_mob.dm:311-314`, `say.dm:175`.
* **Combat out**: `item_attack.dm:276,324`, `gun.dm:690`, `weapons.dm:99`, `simple_mob/combat.dm`, `tension.dm`, `debug.dm:28`.
* **Combat in**: `injure()` pipeline (`injury.dm:195,227,301`: armour, healing received, endurance), `incoming_injury_factor()`,
  `living_defense.dm:116,359`, `statuses.dm:93` (`DISABLE_DURATION`), human/silicon/simple explosion and exposure reads.
* **Physiology** (`physiology.dm`, 24 refs): oxygen-transport chain, heart rate, blood pressure, through `supported_factor()`. Any factor change
  invalidates `BODY_DIRTY_VITALS | BODY_DIRTY_PHYSIOLOGY` (`factors_equal()`).
* **Medicine and organs**: `ANALGESIA`, `SEDATION`, `PAIN`, `ANTIMICROBIAL`, `WITHDRAWAL`, `HEPATOTOXICITY`, `STABILIZATION`, `NEURAL_REPAIR`, `BLEEDING`,
  `BLOOD_REGEN`, `PROGRESSION`, `ANTIEMETIC`, `ALLERGY`.
* **Senses and readouts**: `DARKSIGHT`, `SIGHT_FLAGS`, `ICON_SCALE_X/Y` (`living.dm:717`), `PULSE_*`, `TEMPERATURE`, the vitals readouts (`vitals.dm`).
* **Dependants**: `factor_dep(id)` (`engine/change/derived.dm:130`, `derived_factors_recomputed()`, `GLOB.derived_factor_watch`) lets a derived
  entity depend on a factor; `library/present/body_factor_notifications.dm` publishes the same change.

### 1.4 `om_grant` and the old store: leftovers

* `om_grant`, `om_grant_for`, `om_revoke`, `om_has_grant`, `om_apply`, `om_hold`, `om_release`, `om_has`, `om_value_of`, `om_apply_until`, `GRANT_*`:
  **0 matches in `code/`** (`doc/rewrite/archive/framework_fixes.md` only). Nothing to convert; section 5's "Replaces" list is already done for these.
* `grant(E, what, source)` has live callers (about 25 behaviours, `rotatable.dm`, trait grants in `trait.dm`). Not part of this work.
* Parallel stat-like state that section 5 still names for deletion, on master today:
  * `body.factors` and its dirty machinery (this proposal);
  * `species.granted_factors`, `grant_factors()`, `revoke_factors()` (a private grant store for factor tables);
  * `body_effect_factors` (per-application table swap) and the per-type stack counter, which parallels the existing `body_effect_counts` SUM_PER_KEY stat;
  * `body.supports` (D5);
  * `species.baseline_factor()`.

## 2. What of section 5 exists on master, and what is missing

| Doc 5 item | On master | Where | Gap for body factors |
|---|---|---|---|
| `STAT(T, name, RULE, base, schema, reapply, units, virtual)` | yes, 121 declarations | `code/engine/stats/def.dm`, `code/contracts/ids/stats.dm` | none to declare; collisions of names with existing vars (section 3.1) |
| rules ALL ANY SUM PRODUCT MAX MIN TOP SET MASK_AND MASK_OR SUM_PER_KEY FORMULA | yes | `rules.dm` | no clamp; `MAX/MIN` base rule differs from `BF_RULE_MAX/MIN`; masks limited to 24 bits (fine: SEE_* and `ACTION_BLOCK_*` fit) |
| `hold`, `hold_until`, `hold_override`, `release`, `release_all`, `held_by(_source)`, `hold_left` | yes (`outlives_source` instead of the doc's `bound`) | `store.dm` | one hold per call: no table form, no scale, no stack count |
| inline recompute, marked drain, hops, `stat_value()` cache | yes | `recompute.dm`, `contributes.dm` | fast path only for ALL/ANY/SUM; per-stat recompute scans every hold of the entity |
| `contributes()`, `contributes_to()`, `when()` gating | yes (used by machines, `powered.dm`) | `contributes.dm` | value from a `PROC_REF` recomputes on its declared reads only; no band concept |
| statuses, `immune_to` | yes | `status.dm`, `library/mob/statuses.dm` | n/a |
| `grant`/`revoke`/`granted` | yes | `activation.dm`, `engine/declare/*` | n/a |
| `reapply = REAPPLY_MAX/EXTEND/REPLACE` | yes | `store.dm` | n/a |
| generated reads, staleness checker | yes | `change/staleness.dm`, `_generated/` | checker verifies cache vs `stat_compute`; nothing verifies the *sources* (section 3.6) |
| `hold(..., bound = TRUE)`, `toggles_hold` op part | `bound` named `outlives_source` (inverted); `toggles_hold` is an op part, new | | not needed here |
| stat var writes by the engine only | yes | `stat_store()` | callers that write a stat var directly must be converted (`evasion`) |

Missing for body factors, in priority order: **(G1)** `hold_table` (many rows, one source, one settle) with scale and stacks;
**(G2)** bounds clamp; **(G3)** fast path and per-stat hold index; **(G4)** `MAX/MIN` base rule parity; **(G5)** a source-refresh discipline
that matches the old "refresh everything on any dirty event"; **(G6)** a parity oracle. Everything else already exists.

## 3. Engine design

### 3.1 Declaration and naming

One `STAT(/mob/living, <name>, RULE, base = ..., bounds = list(lo, hi), schema = num(...))` per factor, in `code/contracts/ids/stats.dm` style (a new
file `code/contracts/ids/body_stats.dm`). Rules map as doc 5 says: MULT is PRODUCT, ADD is SUM, MAX and MIN unchanged, FLAGS is MASK_OR.

* **Names** are the lowercased factor without `BF_`: `slowdown`, `penalty_scale`, `haste`, `incoming_physical`, `armor_blunt` and so on.
  Stat vars are real vars on `/mob/living` (decision D2), so a name must not collide with an existing `/mob/living` or `/atom` var. A scan of the
  current tree finds three collisions: `evasion` (`living_defines.dm:25`, the mob's own base evasion, currently read as `evasion + factor(BF_EVASION)`),
  `icon_scale_x` and `icon_scale_y` (`atoms_movable.dm:18`, the base scale that `get_icon_scale_x()` multiplies by the factor). Resolution (D3): `evasion`
  *becomes* the stat (its initial value is the type-level constant contribution, exactly the doc's `light_range = 4` rule; direct writers are converted
  to holds); the two scale factors get their own names, `scale_mult_x` and `scale_mult_y`.
* **Indexed families.** `BF_ARMOR(kind)` and `BF_INCOMING(category)` take a runtime index. Declare one stat per member
  (`armor_blunt` .. `armor_blast`, `incoming_physical` .. `incoming_pain`), as doc 5 says, and keep two **static lookup lists** `armor_stat_ids[kind]` and
  `incoming_stat_ids[category]` for the dynamic call sites (`injury_armor(kind, zone)`, `incoming_injury_factor(category)`); every other site names its stat.
  Stat ids are per name and generated (`analyze gen declare_ids`), so they are *not* contiguous: no arithmetic on ids.
* **Cost of real vars.** About 70 vars x 8 B = roughly 560 B per `/mob/living` and 70 extra var initialisations per mob. Mob counts are in the hundreds
  to low thousands, so this is under 1 MB and well below one `New()` of a human. `stat_holder_init()` already skips a stat that has no type-level
  contribution, formula or map edit (`recompute.dm:326-341`), so mob init does not recompute 70 stats; the body stats have none of those.

### 3.2 Storage

Reuse the stat record (`rec.holds`: rows of stat, source, value, deadline, priority, flags, clock, reason, serial). No new store. One source holds once per
stat, which is exactly the factor model (a source's table has one value per factor).

**Source identity** (a row's source must be a live datum or a `SRC_*` flyweight):

| source | holder row source |
|---|---|
| affliction | the affliction instance (deleted with the affliction releases its rows) |
| body effect, modifier | the body effect *definition* datum (`body_effect_def(path)`, shared); stacks are carried in the value (below) |
| stasis | the stasis level definition, plus the existing `stasis_rate_source` flyweight for the rate path |
| reagent | the reagent *prototype* datum (`chemical_reagents[id]`); the holder is the mob, so one prototype can be the source on many mobs; the row is released with `release_all(mob, prototype)` when the reagent leaves |
| species factor baseline, trait or perk grant, `NO_PAIN` | the species instance (traits: the trait datum, so `revoke_factors` is `release_all(H, trait)`) |
| form | the form instance |
| worn item | the item |

A shared prototype source is safe: rows live on the *mob's* record, the mob's destruction drops its record, and `stat_sources_teardown()` only matters for
sources that die before the holder.

### 3.3 `hold_table` (G1)

```
hold_table(datum/E, source, alist/table, scale = 1, stacks = 1, priority = PRIORITY_DEFAULT)   // returns TRUE
release_table(datum/E, source)                                                                 // = release_all(E, source)
```

For every `(stat id, value)` in the table it applies the per-rule contribution the old `body_factor_accumulate()` applies, so the *data tables stay unchanged*:

| rule | contribution held at `scale`, `stacks` |
|---|---|
| PRODUCT (MULT) | `max(0, 1 - (1 - v) * scale) ^ stacks` |
| SUM (ADD) | `v * scale * stacks` |
| MAX, MIN | `v * scale` (stacks idempotent) |
| MASK_OR (FLAGS) | `v` (applies only when `scale > 0`) |

It then (a) releases rows this source holds on stats no longer in the table (a table *swap*, which `set_body_effect_factors` needs and dose-band changes
need when a species_factors merge changes the key set), (b) re-places every row with `REAPPLY_REPLACE` (exact, may lower; the default `REAPPLY_MAX` is wrong for
factors), (c) validates each table **once** per (table identity, stat id) using the existing `CACHED_KEY` pattern instead of running `stat_hold_refusal()` per
row, (d) collects the touched stats and settles each **once** at the end (one `stat_recompute()`, one `state_changed()`), so a six-factor species attach does not
run six recompute-and-publish cycles in sequence with intermediate states visible to hooks. `scale <= 0` releases the rows (old behaviour: skipped).

Unchanged rows (same value) are a cheap compare with no recompute, which is what makes eager refresh (G5) affordable.

### 3.4 Recompute and caching (G2, G3, G4)

* **Fast paths.** `stat_compute()` has a no-row-list fast path only for ALL/ANY/SUM and only with no holds. Add PRODUCT, MAX, MIN and MASK_OR. The factor
  stats are mostly PRODUCT or SUM and *most mobs have no holds on most stats*, so this removes a `list()` allocation and a `stat_combine()` call from every
  recompute. Reads are already plain var reads for real-var stats, so the fast path only matters on writes.
* **Per-stat hold index.** `stat_compute()` loops over *all* of an entity's holds and skips those of other stats (`recompute.dm:144-148`). With tables, a
  sick, drugged, equipped human carries 20 to 60 rows; refreshing a 10-row table then costs 10 x 60 row visits. Keep `rec.holds` (oldest first, as the engine
  relies on it) and add `rec.by_stat` ("[id]" -> list of that stat's rows, the same row lists, maintained in `stat_hold_place`/`stat_hold_remove`). Memory: one
  assoc list per entity that holds anything; zero for the common holdless mob.
* **Bounds (G2).** Add `bounds = list(lo, hi)` to `STAT`: applied by `stat_compute()` after the combine and before the override check (an admin override replaces
  the composed value, as doc 5 says for every rule). `schema = num(lo, hi)` stays as the *test-build contribution validator*. Do not derive one from the other: the
  old fold clamps the composed value but lets individual contributions exceed it (an affliction at +30 slowdown, clamped to 20).
* **`MAX`/`MIN` base (G4).** `BF_RULE_MAX` is `max(baseline, contributions)`; the stat rule is "the extreme contribution, or the base when none". They differ only
  when a contribution is below the base. Every MAX factor today (`HASTE`, `DARKSIGHT`, `PAIN_IMMUNITY`, `PULSE_SET` base -1, `STASIS`) has contributions at or above its
  base. Declare `schema = num(base, hi)` on each, so a test build reports a violating hold, and add the table-driven rule test (`dq_e3_stats_tests`) for it. No engine change.
* **Eager, not lazy.** The old cache rebuilds lazily on the first read after an invalidation; the stat engine settles *before the writer's next line*. Reads
  therefore stop paying the stale check and the `factor() -> get_factor() -> factors_stale()` chain (three procs per read, on the movement and `injure()` paths): the
  hot path becomes one var read. The price is moved to the writer: see G5 for why that is no worse than today.

### 3.5 Source refresh discipline (G5): the one real semantic trap

Today **any** dirty event (`BODY_DIRTY_FACTORS`) makes the next read re-fold **every** source at its **current** severity and reagent volume. So a reagent's
analgesia value is refreshed to its exact current dose whenever *anything else* (an equipment move, a different affliction crossing a band) dirties the factors, not
only when its own dose band changes. If each source simply held its value and re-held only on its own trigger, values would sit stale inside a band until the
next unrelated event, so outputs would drift from today's by a small amount, depending on event history. That is a balance change.

Neutral design for waves 1 and 2: keep one body-side entry point

```
/mob/living/proc/refresh_factor_sources()   // re-reads afflictions, effects, stasis, reagents, species, form, worn at current state and hold_table()s each
```

called from exactly the places that call `invalidate(BODY_DIRTY_FACTORS)` / `invalidate_factors()` today (11 sites, listed in 1.2), and nowhere else. It is the old
fold with the output redirected from the flat list into `hold_table()` rows. Unchanged rows are a compare, so the cost is O(sources) per dirty event, which is
what `recompute_factors()` cost *on the next read*; since movement and `Life()` read factors every step and tick, that read happened after nearly every
invalidation anyway. Multiple invalidations inside one proc are coalesced by a `factor_refresh_depth` counter (`refresh_factor_sources()` re-enters as a no-op and
the outermost call flushes), the eager equivalent of lazy dirtying.

End state (wave 3, after `CAPABILITIES` lands): each source is a `contributes(STAT_X, PROC_REF(...))` whose declared reads include a *tracked band var*
(`severity_band`, `dose_band`), so a contribution recomputes exactly when its inputs change and `refresh_factor_sources()` disappears. That is a deliberate,
documented behaviour change (within-band values refresh at the band edge only), to be recorded in `intended_changes.md` when it lands, not smuggled into waves 1 and 2.

### 3.6 Interaction with read-driven tracking, generated setters and the staleness checker

* **Publication.** `stat_recompute()` publishes a real-var stat through `state_changed(E, 0, name)`, so every generated read of `L.slowdown` etc. in a `derived()`,
  `reads =` list or `on_change` is notified like any tracked var. Therefore `factor_dep()`, `derived_factors_recomputed()`, `GLOB.derived_factor_watch` and
  `body_factor_notifications.dm` are *deleted*, replaced by `derived_read(nameof(slowdown))`-style reads of the stat var. `body.factors` is a TRACKED var with a
  generated `set_factors()`; it is deleted outright (no shadow copy, per the "no workaround state" rule).
* **Physiology and vitals invalidation.** `recompute_factors()` invalidates `BODY_DIRTY_VITALS | BODY_DIRTY_PHYSIOLOGY` whenever *any* factor changed. Port it as one
  `on_change` group on `/mob/living`'s block listing the factor stats physiology and vitals actually read (the nine oxygen-transport stats, `heart_rate`, `bp_*`,
  `temperature`, `o2_sat`, `resp_rate`, `analgesia`, `pain`, `sedation`, `stasis`, `pulse_*`). Wave 2c may narrow today's "any of 70" to that list; physiology fully derives
  from its declared reads, so outputs are identical and recompute frequency drops (D8). Note `/mob/living`'s one `CAPABILITIES` block is in protected AI code
  (see `proposals/mob_living_root.md`); the hook goes in a library entry proc included by that block, the option-B pattern already approved.
* **Staleness checker.** `staleness_check_stat()` already compares a stat var against `stat_compute()` on read and on a sampled schedule, so a missed *recompute*
  is caught for free. It cannot catch a **source that did not re-hold** (the hold row is the truth the check recomputes from). New: `factor_oracle(L)` (test builds only,
  `#if defined(UNIT_TESTS)`) is the *old fold kept verbatim* (accumulate over afflictions, effects, stasis, reagents, plan, then `body_factor_finalize()` clamp) returning the
  70-vector. It runs (a) at the end of every unit test for every living mob the test touched, and (b) from the existing `GLOB.staleness_sample` path, asserting
  `|oracle - stat var| <= 1e-5 * max(1, |value|)` for numeric stats and exact for flag and boolean stats. The oracle is deleted in the commit that deletes the tables
  fold (end of wave 2); from then on the declared tables themselves are re-folded by a small independent test helper.
* **Float order.** Old order: afflictions, effects (per stack), stasis, reagents, species, granted, `NO_PAIN`, form, worn. Stat order: row creation order. Floating-point
  multiplication is not associative, so PRODUCT stats can differ in the last bit. Tolerance 1e-5 is far below any balance effect, but a **boundary audit** is part of
  wave 2: grep every consumer that tests a factor with `==`, `>=` or `<` against a constant (`factor(BF_ANALGESIA) >= 50`, `< 1` for motor control, `> STASIS_SLEEP_THRESHOLD`,
  `> 100`) and confirm each sees an exact value at its boundary in the pinned scenarios (D4).

### 3.7 Performance on the hot paths

* **Movement speed** (`movement_delay()` per step): 3 `factor()` calls today (about 9 proc calls and two list indexes each time) become 3 var reads. `baseline_factor(BF_SLOWDOWN)`
  (a full species re-fold per call, feral mobs only) becomes a cached `species_slowdown` computed when the species or its traits change (it is a species property, not a mob stat).
* **Damage** (`injure()`: armour, incoming x2, healing received, endurance x2 per injury): all var reads; the dynamic `armor_stat_ids[kind]` is one list index.
* **Write cost** moves to events: species change, trait add, equipment moving an item with `worn_factors`, effect start/end, affliction add/remove or band crossing, a reagent
  dose-band crossing (C12), stasis. Each is at most one `refresh_factor_sources()` (a few dozen compares plus the changed rows). Reagent bands (the C12 optimisation) stay as the
  *trigger*; only the sink changes.
* **Holdless mob** (the common simple mob): no record, no rows, no cost; reads are var reads of base values.
* Counters for the bench when benches resume (policy: none until the end): `GLOB.stat_evals` per event, a `factor_refreshes` counter, rows held per mob (histogram in the staleness
  report). No benchmark is run for this proposal.

## 4. Mapping and wave plan

### 4.1 `BF_X` to stat form

Name = lowercase factor name unless noted. Rule per the 1.1 table. "var" stats are real vars on `/mob/living`.

| old | new stat | rule | notes |
|---|---|---|---|
| BF_AIRWAY .. BF_HEALING (11 MULT) | `airway resp_drive lung_mechanics gas_exchange pump circulation demand progression metabolism bleeding healing` | PRODUCT, base 1, bounds as table | `pump`, `circulation`, `demand` collide with local var names only in procs (no object var); fine. Reads through `supported_factor()` stay physiology API over the stat var. |
| BF_ANALGESIA .. BF_RESP_RATE (ADD) | `analgesia pain sedation heart_rate temperature bp_systolic bp_diastolic o2_sat resp_rate` | SUM, bounds as table | `pain` is a `/datum/body` var, not a mob var: no collision. `arrhythmia_risk`: delete (D9). |
| BF_SLOWDOWN | `slowdown` | SUM, bounds -10..20 | no `/mob/living` var of that name today; verify at gen. |
| BF_PENALTY_SCALE, BF_HASTE | `penalty_scale` (PRODUCT, 0..4), `haste` (MAX, 0..1) | | |
| BF_ACCURACY, BF_DISPERSION | `accuracy`, `dispersion` | SUM | simple_mob has `projectile_accuracy/dispersion` (different names). |
| BF_EVASION | `evasion` | SUM | adopts the existing var (D3); writers of `evasion` converted to holds. |
| BF_ATTACK_SPEED, BF_MELEE_DAMAGE | `attack_speed`, `melee_damage` | PRODUCT | |
| BF_VISION, BF_HEARING | delete (D9) | | zero production use. |
| BF_MOTOR_CONTROL | `motor_control` | PRODUCT 0..1 | |
| BF_DARKSIGHT | `darksight` | MAX 0..1 | `darksight` is a HUD *screen* var in `hud.dm`, not a mob var; stat lives on the mob. |
| BF_SIGHT_FLAGS, BF_ACTION_BLOCKS | `sight_flags`, `action_blocks` | MASK_OR | SEE_* and ACTION_BLOCK_* are below 24 bits. |
| BF_INCOMING_ALL, BF_INCOMING(cat) | `incoming_all`, `incoming_physical/thermal/toxic/genetic/pain`; `incoming_neural` kept (declared in the injury category list) | PRODUCT 0..10 | `incoming_stat_ids[cat]` for the dynamic call. |
| BF_DISABLE_DURATION, BF_HEALING_RECEIVED | `disable_duration`, `healing_received` | PRODUCT | |
| BF_ENDURANCE_FLAT, BF_ENDURANCE_MULT | `endurance_flat` (SUM), `endurance_mult` (PRODUCT 0..100) | | |
| BF_ICON_SCALE_X/Y | `scale_mult_x`, `scale_mult_y` | PRODUCT 0.1..10 | not `icon_scale_*` (existing atom vars, D3). |
| BF_PAIN_IMMUNITY | `pain_immunity` | MAX 0..1 | |
| BF_PULSE_SHIFT, BF_PULSE_SET | `pulse_shift` (SUM), `pulse_set` (MAX, base -1, schema min -1) | | |
| BF_EMP_SHIFT, BF_EXPLOSION_SHIFT | `emp_shift`, `explosion_shift` | SUM | |
| BF_HEAT_EXPOSURE, BF_COLD_EXPOSURE, BF_SIEMENS | `heat_exposure`, `cold_exposure`, `siemens` | PRODUCT | |
| BF_STABILIZATION .. BF_IMMUNE_SUPPRESSION (ADD, 0..inf) | `stabilization antimicrobial blood_regen intoxication hepatotoxicity antiemetic allergy withdrawal neural_repair immune_suppression` | SUM, bounds 0..inf | `allergy` as a mob var name: no collision found; verify at gen. |
| BF_O2_CARRIAGE, BF_TISSUE_UPTAKE, BF_CARDIAC_IRRITABILITY | `o2_carriage`, `tissue_uptake`, `cardiac_irritability` | PRODUCT | |
| BF_STASIS | `stasis` | MAX 0..1 | the stasis *clock rate* is already the stat `clock_rate_bio`; `stasis` stays the factor the life processes read until the stasis chain is converted. |
| BF_ARMOR(kind) | `armor_blunt .. armor_blast` (one per `ARMOR_KIND_COUNT`) | SUM | `armor_stat_ids[kind]`. |

The tables' data (`alist(BF_SLOWDOWN = 0.5, ...)`) is unchanged in waves 0 to 2: `hold_table()` takes a BF-keyed alist and a `bf_to_stat` static list translates
the key. Content moves to `contributes(STAT_X, value)` in wave 3.

### 4.2 Waves

Order is chosen so each wave is mergeable on its own, leaves master green, and removes legacy code in the same commit that converts its last caller (a ratchet
`BF_` baseline is added in wave 1 and tightened after each wave; the hard ban lands with wave 2d).

| wave | content | proves balance-neutrality by | deletes |
|---|---|---|---|
| **0 engine** | G1 `hold_table`/`release_table`, G2 `bounds`, G3 fast paths and `rec.by_stat`, 70+family `STAT` lines (no readers), `factor_oracle` (test-only), pin generator. New table-driven rule tests (bounds, MAX/MIN base, scaled MULT, stacks, table swap). | `dq_e3_stats_tests` and the new rule tests; the **pin** `snapshots/factors/` committed from the OLD fold before any wave-1 edit: for every source type with a table x scale in {0, 0.25, 0.5, 1} x stacks in {1, 2, 3}, and every species, its 70-vector | nothing |
| **1 sources onto the store** | `refresh_factor_sources()` replaces `recompute_factors()`; `factor(id)` becomes `stat_value()` of the translated id (legacy call kept, honestly counted, never aliased); `granted_factors` stays; flat `body.factors`, `factors_stale`, dirty flag handling for factors deleted. Reagent bands and affliction bands stay as triggers. | oracle runs at the end of every test and on the staleness sample; pins reproduced within 1e-5; existing `dq_body_factor_*` (13 tests), `dq_body_effect_tests`, `dq_stabilisation_tests`, `dq_property_tests` | `body.factors`, `get_factor`, `factors_equal`, `factor_dep`, `derived_factors_recomputed`, `body_factor_notifications.dm` |
| **2a consumers: movement and combat out** | `factor(BF_SLOWDOWN/HASTE/PENALTY_SCALE/ACCURACY/DISPERSION/ATTACK_SPEED/MELEE_DAMAGE/EVASION/ICON_SCALE_*)` become var reads; `species.baseline_factor` cache; `evasion` writers converted; `scale_mult_*` | `dq_body_factor_movement`, `dq_body_factor_consumers`, `dq_harm_mitigation` (hit chance), a new `dq_factor_hot_reads` that asserts every converted read equals the oracle for 20 random sources | those `factor()` call sites |
| **2b combat in** | `incoming_*`, `armor_*`, `disable_duration`, `healing_received`, `endurance_*`, `emp_shift`, `explosion_shift`, `siemens`, exposures | `dq_harm_mitigation`, `dq_body_factor_energy_shield`, `dq_surgery_tests`, injury trace snapshot (`Trace Injury Mitigation` output pinned per species) | |
| **2c physiology, vitals, stasis** | the oxygen-transport chain, `heart_rate`, `bp_*`, `temperature`, `o2_sat`, `resp_rate`, `pulse_*`, `stasis`; the `on_change` group replaces `factors_equal` invalidation (optionally narrowed, D8) | `dq_physiology_tests`, `dq_vital_systems_tests`, `dq_medical_*` suites, a physiology vector pin per scenario (arrest, choking, CO, cyanide) | `factors_equal` remainder |
| **2d medicine, organs, senses** | `analgesia pain sedation antimicrobial withdrawal hepatotoxicity stabilization neural_repair bleeding blood_regen progression antiemetic allergy darksight sight_flags pain_immunity motor_control` ... ; delete `factor()`; `legacy_forms` hard-bans `factor(` and `BF_` outside the compatibility table | `dq_medical_*`, `dq_stabilisation`, `dq_medpod_*`, withdrawal and liver tests; full `BF_` ratchet reaches only the data tables | `/mob/living/factor()`, `invalidate_factors()` callers except the refresh entry |
| **3 content to declarations (blocked on `CAPABILITIES`)** | species, traits, modifiers, forms, items, reagents, afflictions declare `contributes(STAT_X, ...)`; `BF_` keys become `STAT_` keys; `granted_factors`, `body_effect_factors`, per-type stack counter, `refresh_factor_sources()` go; `severity_band`/`dose_band` become tracked reads | the pin again, plus an `intended_changes.md` entry for the within-band refresh change | the rest of `factors.dm` |

Wave 3 is listed for completeness; nothing in it can be written until the one-block `CAPABILITIES` form exists on master. Waves 0 to 2 use only forms already on master.

### 4.3 Test and pin inventory

Existing tests that already exercise factors and are the safety net: `dq_body_factor_tests.dm` (combine math, lazy storage, modifier recompute, affliction bands and stages,
reagent dose, worn equipment, species baseline, consumers, movement, healing and blocks, energy shield, book text), `dq_body_effect_tests`, `dq_stabilisation_tests`, `dq_medical_*`
(`p1`, `k_a`, `k_b`, `med7_expo`), `dq_physiology_tests`, `dq_vital_systems_tests`, `dq_surgery_tests`, `dq_harm_mitigation_tests`, `dq_property_tests`, `dx_deps_tests`.
New (named, none written yet): `dq_factor_oracle_parity`, `dq_factor_table_pin` (the committed vector pin), `dq_factor_species_pin` (every species), `dq_factor_reagent_sweep` (every reagent with a table at 0.25x, 1x, 2x, 4x dose),
`dq_factor_affliction_sweep` (every afflicted type at severity 10..100 and every stage), `dq_factor_effect_sweep` (every body effect and modifier, stacks 1..3), `dq_stat_hold_table` (G1 semantics: swap, scale, stacks,
release, refresh no-op), `dq_stat_bounds`, `dq_stat_fast_paths` (fast path equals general path for every rule). All run with `bash tools/dq_focused_test.sh`; none needs the full suite.

## 5. Decisions

All of D1 to D10 were approved as recommended on 2026-10-16. Each entry keeps its recommendation text as the record of what was approved.

Each has a recommendation; the first five change the work, the rest are cleanups.

**D1. Scope of the follow-up.** **[approved 2026-10-16]** Do waves 0 to 2 now and leave wave 3 until the one-block `CAPABILITIES` form lands, or wait and do it all at once?
Recommendation: waves 0 to 2 now. They use only forms on master, remove the second composition engine and the 691 `BF_` references from production code paths, and wave 3 then
becomes a pure data move.

**D2. Real vars or virtual stats for the 70.** **[approved 2026-10-16]** Real vars cost about 560 B per `/mob/living` and give the doc's "reads are plain var reads"; virtual stats save the memory but a
holdless virtual PRODUCT stat composes on every read until first recomputed (`stat_value()`), which is worse on the movement and `injure()` paths.
Recommendation: real vars for all.

**D3. Names that collide with existing vars** **[approved 2026-10-16]** (`evasion`, `icon_scale_x`, `icon_scale_y`). Recommendation: `evasion` becomes the stat (its initial value is the type constant; convert direct writers
to holds); the two scale factors are named `scale_mult_x` and `scale_mult_y` and `get_icon_scale_x()` multiplies the existing base by them.

**D4. What "identical numeric output" means.** **[approved 2026-10-16]** The new fold multiplies PRODUCT contributions in a different order than the old one (row creation order versus afflictions, effects, stasis, reagents, plan), so the last float bit can differ.
Recommendation: relative tolerance 1e-5 for numeric stats in the oracle and pins, exact for flags and booleans, plus the wave-2 boundary audit of consumers that compare a factor to a constant. If bit-exact is required instead, the engine must sort a
stat's rows by an explicit `fold_order` column (cheap: one extra row field) at the cost of a sort per recompute of a multi-row PRODUCT stat; I advise against it.

**D5. Supports and restrictions** **[approved 2026-10-16]** (`add_support`, `add_restriction`, `set_support`, 31 callers): floors and multipliers applied *after* the product to a physiology input, with duration and a `still_valid` callback.
Recommendation: out of scope for this work. They are not factors (a bag-valve mask floors the *drive input*, deliberately after the airway product), and forcing them into holds on the same stat would change where the floor applies.
Revisit with `hold_override`-style priority only if a design for them appears in doc 14.

**D6. Eager source refresh versus per-source triggers.** **[approved 2026-10-16]** Recommendation: waves 1 and 2 keep `refresh_factor_sources()` on exactly today's dirty events (balance-neutral, section 3.5); wave 3 replaces it with tracked band reads and records the
within-band change in `intended_changes.md`. The alternative, per-source triggers from wave 1, is simpler but changes values inside doses and severity bands depending on event history.

**D7. `MAX/MIN` base.** **[approved 2026-10-16]** Recommendation: no engine change; declare `schema = num(base, hi)` on every MAX factor and assert it in test builds (section 3.4). Alternative: a `floor_base = TRUE` stat option that makes `MAX` mean `max(base, contributions)`.

**D8. Narrow the physiology invalidation** **[approved 2026-10-16]** from "any of the 70 factors changed" to the factors physiology and vitals actually read. Recommendation: yes, in wave 2c, with the physiology vector pin; it cuts recompute frequency and cannot change
outputs because physiology derives from its declared reads.

**D9. Delete dead factors.** **[approved 2026-10-16]** `ARRHYTHMIA_RISK`, `VISION` (one test reference), `HEARING`, and `SEDATION` (read, never written; keep only if a planned source exists). `INCOMING_NEURAL` is declared with 0 table entries but is a real category.
Recommendation: delete `arrhythmia_risk`, `vision`, `hearing`; keep `sedation`, `incoming_neural`; fix the `dq_body_factor_book_text` test accordingly. This is dead code, not a behaviour change.

**D10. Hard ban.** **[approved 2026-10-16]** Recommendation: when wave 2d lands, add `factor(`, `BF_*` outside the compatibility translation table to the `legacy_forms` banned list with an empty baseline, per AGENTS.md section 3b ("the commit that lands a replacement adds its ban and converts the callers").

## 6. Notes for the follow-up lane

* Update the AGENTS.md section 3a row "Numbers/flags composed from sources" to say that `STAT`, `contributes`, `hold`, `release`, `grant` exist, and that only the factors and `stat(...)` entry form are old. (Not edited here.)
* `invalidate_factors()` call sites to route through `refresh_factor_sources()`: `affliction.dm:192,214,436`, `trauma.dm:169`, `body.dm:152,166`, `body_effects.dm:199,207,289,342,368,382`, `stasis.dm:171`,
  `human.dm:1425`, `species.dm:931`, `station.dm:666`, `event.dm:210`, `trait.dm:56,111`, `protean/forms.dm:79,87,114`, `slots.dm:364,458`, `attach.dm:218,261`.
* `/mob/living`'s one `CAPABILITIES` block is in protected-AI code; use the library entry proc pattern from `proposals/mob_living_root.md` option B for the `on_change` group.
* Per project policy: no benchmarks and no full suite during this work; run only the tests named per wave with `tools/dq_focused_test.sh`.

## 7. Implementation notes (waves 0 to 2, 2026-10-16)

What was built, and where it departs from the text above. Wave 3 is not started.

* **Engine** (`code/engine/stats/`): `bounds = list(lo, hi)` on `STAT` (clamp after the combine, before an override); the no-row fast path for PRODUCT, MAX, MIN and
  MASK_OR; `rec.by_stat` (per-stat row index, kept by `stat_rows_add()` / `stat_hold_remove()`); `hold_table()`, `release_table()`, `hold_tables_begin()` /
  `hold_tables_end()` (`tables.dm`: rows carry `HF_TABLE` and a `part`; a pass releases the table rows no call placed and settles every changed stat once;
  `hold_tables_end(E, moved)` lists the stats that ended different); `stat_fold_tables()` (pure fold of tables for one stat).
* **Names.** The 67 factors keep the planned names except `metabolism_mult` (not `metabolism`: `/mob/living/var/metabolism` already exists in the vore code and
  renaming that var would be a new `base_vars` site). Armour is `armor_<kind>` and incoming is `incoming_<category>`; the dynamic reads are `switch`es.
* **D7 schema.** `schema = num(base, INFINITY)` on the MAX stats, not `num(base, hi)`: a table scaled by a dose of 2 or 4 legitimately contributes 2 or 4, which the
  pin found; `bounds` holds the composed value to `hi`. The test builds assert that a MAX contribution is not below the base.
* **D8 narrowing** is inline, not an `on_change` group. A refresh dirties the cached vitals and the physiology when a stat in `GLOB.factor_vitals_stats` moved (the
  first pass dirties them whichever moved, as the old first recompute did). An `on_change` hook runs at the marked drain, after the writer's next line, and the
  physiology tests read right after a write; the inline form keeps that, and the physiology vector pin (`snapshots/factors/physiology.txt`, recorded from the old
  code) is identical.
* **D6 triggers.** `invalidate(BODY_DIRTY_FACTORS)` is the trigger and is never stored: `invalidate()` calls `refresh_factors()`. A reagent change settles at
  `on_reagent_change()` (volumes re-read, bands compared, the treatment snapshot left stale). Writers of a source table that bypass those events call
  `invalidate_factors()` (`headset/event.equipped()`).
* **D10.** `BF_*`, `factor(`, and the old fold's names are hard-banned (`legacy_forms`, empty baseline); `legacy_forms` gained prefix names (`BF_*`). The
  compatibility table existed through waves 1 to 2c (`code/modules/body/factor_compat.dm`); 2d renamed every table key `BF_X` to `STAT_X` and deleted it.
* **The oracle stays.** `dq_factor_oracle.dm` is the old fold over the stat ids (its own accumulate and clamp), used by the end-of-test audit, the parity test, the
  random-source test and the table pin. It is test code; deleting it is a choice for wave 3, when the tables become declarations.
* **Behaviour that differs** is listed in `doc/rewrite/intended_changes.md` (when a factor settles; `tissue_hypoxia` follows its severity).
* **Pre-existing failures** the runs showed on the base commit too (not caused by this work): `dq_body_pin/liver_toxin_overload`,
  `dq_medical_trial_deferred_availability` (order dependent), `dq_mob_init_forms_bodies`, `dq_medpod/sleeper_injects` (a purity violation: a requirement
  reads `vitality()` while the vitals are dirty).

### 7.1 Boundary audit (D4)

The reads that compare a factor with a constant, after the conversion (every other read multiplies, adds or branches on truth):

| read | stat and rule | at its boundary |
|---|---|---|
| `motor_control < 1` (`factor_effects_due()`, `tick_factor_effects()`) | PRODUCT 0..1 | every table value is at most 1, so any contribution leaves the product below 1 and none leaves it exactly 1 (neutral rows are not held) |
| `penalty_scale < 1` (`say.dm`) | PRODUCT 0..4 | tables carry values on both sides of 1, so a product that cancels back to 1 (0.8 x 1.25) is the one case the multiplication order could move by a last bit; no table pair does it, and the pins hold every table alone |
| `analgesia >= 50` (`limb_state.dm`), `> power` (`pain.dm`), `> 100` (`life.dm`), `< 60` (`mob_grab_specials.dm`) | SUM | the pinned values are multiples of 0.25 times integers (50, 75, 200, 225): exact in binary under any order; a dose scale that is an arbitrary float sums with rounding of about 1e-14, far from any threshold the tables reach |
| `stasis > STASIS_SLEEP_THRESHOLD` (`life.dm`) | MAX 0..1 | a maximum, never a sum: order cannot move it |
| `allergy > 0` (`life.dm`, `life_medical_due()`) | SUM 0..inf | zero exactly when nothing contributes |
| `pump <= 0` (`physiology.dm`), `resp_drive < SUPPORT_BVM_DRIVE` | PRODUCT | a table value of 0 gives exactly 0 under any order; the drive compares with a support floor of 0.4 |

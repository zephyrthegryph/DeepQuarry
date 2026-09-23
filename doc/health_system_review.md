# Health System Review and Consolidation Design

Review date: 2026-09-22. Scope: the body/affliction core (`code/modules/body/`), the
medical framework (`code/modules/medical/`), organs, surgery, human/silicon/simple mob
life code, reagents, and every device or UI that reads patient state.

Method: three parallel review passes, then every claim re-checked against the code by
hand. Section 2 lists what the re-check changed. Line numbers are current as of the
vital-systems work that landed the same day.

---

## 1. Summary

The new core (`injure`/`mend`, afflictions, singleton symptoms, triggers, treatment tags,
per-part biology, body plans, derived limb and organ integrity) is a sound foundation.
The problems are around it:

1. **The old model still runs in parallel.** Pain is computed twice (the body, plus the
   `shock_stage` state machine). Pulse is computed three ways. Consciousness is decided
   in the body but applied in two places. And the four damage pools survive under new
   names: 333 `injury_load()` calls in 60 files, so crew monitors, cryo, medbots and the
   defibrillator still think in brute/burn/toxin/oxygen.
2. **There are five separate effect systems instead of one.** Modifiers (~40 hand-read
   fields, 71 hand-written loops), `chem_effects` (13 channels), affliction
   `mechanical_effects`, affliction `vital_effects`, and `od_boost`. An effect only works
   in the system it was written for. This is the main thing standing between the medical
   system and the "multiplicative" design goal.
3. **Harm and healing bypass the pipeline.** About a dozen callers damage limbs directly,
   about 25 damage internal organs directly (`injure()` cannot target an internal organ),
   and about 40 heal organs or wounds directly. Reagents still heal organs directly on top
   of their treatment tags, so organs heal about twice as fast as tuned.
4. **Diagnosis is re-derived by every device**: about 1,700 lines across eight procedures.
   Two of them are a 425-line procedure and its 75%-identical admin copy. The handheld
   health analyzer still shows the old "Suffocation/Toxin/Burns/Brute" readout.
5. **Seven live bugs** (section 3), including one regression from the migration: brains
   can no longer be put into an MMI.

The design in section 5 has three pillars:

- **Body factors**: one shared effect model. Afflictions, reagents, modifiers, species,
  equipment and interventions all write to named factors, and everything reads from
  them. This makes the system multiplicative.
- **Generic physiology**: airway, ventilation, oxygenation, perfusion and delivery are
  derived from those factors each tick. Their consequences (hypoxia, ischemia, arrest,
  unconsciousness) are shared by every cause.
- **One diagnosis model**: `body.diagnose(profile)` and `body.treatment_demand(profile)`.
  Every scanner, monitor, bot and UI formats the same report.

Section 7 is a phased plan. Phase 0 (bug fixes) and phase 1 (core consolidation) change
no design and can start immediately.

---

## 2. What the re-check changed

**Confirmed as reported:** the MMI bug, the oxygen pump healing surgery-only lesions,
double surgical repair, the sleep "healing" no-op, the `shock_stage` second pain model,
pulse outside the body, the six organ-healing entry points, the triplicated treatment
loop, uncached treatment levels, direct limb-damage callers, scanners re-deriving status,
fracture state set in two places, the duplicated robotic-organ surgery step, and the
leftover UI keys.

**Corrected:**

- *Simple mobs defining `death()` twice* is not a bug. Both definitions chain through
  `..()`. It is a style problem (one proc split across two files).
- *The decompression `isSynthetic()` check in `handle_environment`* is correct. It
  exempts only synthetics that have a pressure-seal NIF.
- *The AI dying twice* is a split decision, not a wrong outcome. The mob's check fires at
  vitality below 0.5%, where the body would say dead at 0. The backup capacitor is a
  legitimate second death condition, but it belongs in the body.
- *"life.dm decides unconsciousness"*: the body decides (`body.is_unconscious()`), and
  life.dm re-implements applying it.

**Missed by the first report, now included:**

- The scanners: health analyzer (425 lines) and admin copy (427 lines, 75% identical),
  body scanner printout (285), medical kiosk (204), grab organ inspection (115).
- The four damage pools surviving as `injury_load` categories (333 calls).
- The five parallel effect systems.
- Pain relief booked twice (`CE_PAINKILLER` and `TREAT_ANALGESIC`).
- Reagents healing organs directly (a contract violation, and the cause of the
  double-healing balance issue).
- The brain special-case module `medical/organ_decay/brain.dm`, still live beside
  lesions.
- `injure()` cannot target internal organs.
- A second invalidation framework: human `dq_medical_dirty` domains beside the body's
  `vitals_dirty`.
- An energy-weapon synthetic penalty that became dead code in the migration.

---

## 3. Live bugs

| # | Bug | Where | Effect | Fix |
|---|---|---|---|---|
| 1 | Brains can't go into an MMI | `carbon/brain/MMI.dm:53` | Brains used to set `health = 400`. The migration removed it, so `B.health` is now the generic item var, null, and `null <= 0` is true. Every brain is "well and truly dead". | Check brain death through the organ: `B.status & ORGAN_DEAD`, or lesion integrity at max. |
| 2 | Oxygen pump closes surgery-only lesions | `machinery/oxygen_pump.dm:354` → `organ_integrity.dm:104` | `L.take_damage(-1)` heals in full-repair mode, ignoring drug floors. A pump slowly closes perforations. | Use `mend()` with a respiratory tag, and make negative `take_damage` an error. |
| 3 | Surgical organ repair heals up to twice its budget | `body/parts/organ_integrity.dm:186-187` | The full amount goes through `TREAT_SURGICAL_REPAIR`, then again through `TREAT_RESECTION`. | Pass only the remainder to the second call. |
| 4 | Drugs heal organs twice | `reagents/medicine.dm:235, :704, :730`; `medical/organ_decay/brain.dm:63, :126` | Direct `heal_damage()` runs on top of the treatment-tag healing, so organs recover about 2× the tuned rate. | Delete the direct heals; tags only. |
| 5 | The energy-gun drain penalty on synthetics does nothing | `projectiles/guns/energy.dm:95` | `injure(INJURY_TOXIN)` on a synthetic body is filtered to 0. | Give it a `power_fault` affliction. |
| 6 | Sleep "limb healing" is a no-op | `human/life.dm:1325` | Writes `damage -= 1` on a limb whose damage is derived from wounds; the next recalculation overwrites it. | Delete. Sleep boosts natural regeneration instead (5.6). |
| 7 | The cyborg analyzer's "System instability" always reads 0 | `robot/analyzer.dm:161` | It reads toxic load, which synthetic bodies never accumulate. | Show synthetic faults from diagnosis. |

Bugs 8–19 came from the life, cyborg and protean pass and are listed in
`doc/mob_life_architecture.md` §3. They include robots ticking their body twice, EMPs
hitting cyborgs two to four times, and a frozen body in protean blob form.

---

## 4. Architecture debt (verified)

### 4.1 The old model survives in parallel

**Pain is modelled twice.**
- The body computes pain in `humanoid/recompute_vitals`.
- Separately, `handle_shock` (`human/life.dm:1905`, 65 lines) runs a `shock_stage`
  counter that blurs, weakens and paralyses on its own thresholds.
- About 12 places write `shock_stage` directly:
  - limb damage (`organ_external.dm:333, :478`) and dismemberment (`:1085`, +60)
  - `mob.dm:1062`
  - species cold and heat (`station.dm:1601, :1765`) and shadekin light (`station.dm:698, :712`)
  - xenochimera, changeling revive, and a modifier that stashes shock
- It is read by movement (`human_movement.dm:35, :59`) and gun accuracy (`gun.dm:711`).
- Painkillers are also booked twice. `CE_PAINKILLER` is subtracted from pain in the body,
  while `TREAT_ANALGESIC` heals the `acute_pain` affliction.

**Pulse is computed three ways.**
- The `pulse` enum is built in `handle_pulse` (`life.dm:1970`, 90 lines) from modifier
  `pulse_set_level`/`pulse_modifier`, blood volume, brain efficiency and the
  `GLOB.tachycardics`/`bradycardics` reagent lists.
- `vitals.dm` synthesizes bpm from that enum plus additive affliction `vital_effects`.
- The new `cardiac_arrhythmia` rhythm now gates both.

**Consciousness is decided once and applied twice.**
- The base `update_consciousness` applies paralysis, sleep and stat.
- The humanoid plan stubs it out, and `life.dm:1260` re-implements it.
- `Paralyse`/`Sleeping` also come straight from shock, radiation (`handle_radiation`) and
  N2O (`handle_breath`).

**The four damage pools survive under new names: 333 `injury_load()` calls in 60 files.**
- Player-facing readouts:
  - crew monitor (`datums/repositories/crew.dm:47-50`: oxy/tox/fire/brute)
  - operating computer (`computer/Operating.dm:70-76`, still with `health`/`maxHealth = 100` keys)
  - cryo UI (`cryo.dm:119-122`), sleeper, body scanner
  - health analyzer, still showing Suffocation/Toxin/Burns/Brute with the old
    `300 - …` fake-death formula (`scanners/health.dm:79-90`)
- Automation:
  - medbots pick drugs by category load (`bot/medbot.dm:464-467`)
  - cryo decides by load (`cryo.dm:229-238`)
  - defibrillator revival mends by load category (`defib.dm:439-440` wipes the entire
    asphyxia load in one shock)
- Records: the death log still exports `bruteloss`/`fireloss`/`oxyloss`
  (`subsystems/mobs.dm:186-189`).

### 4.2 Five effect systems instead of one

| System | Combine rule | Written by | Read by |
|---|---|---|---|
| `/datum/modifier` fields: ~40 of them (slowdown, accuracy, evasion, `incoming_*_percent`, `metabolism_percent`, `bleeding_rate_percent`, `pulse_*`, …) | hand-coded per field | modifiers only | 71 hand-written `for(var/datum/modifier …)` loops |
| `chem_effects[CE_*]`: 13 channels | per-tick add/max | reagents (79 `add_chemical_effect` calls) | 37 reads |
| affliction `mechanical_effects` (slowdown, accuracy, drop chance, blocked verbs, emotes) | summed, capped | 29 afflictions | movement, combat, verbs |
| affliction `vital_effects` (pulse, temperature, BP, SpO2 offsets) | additive | afflictions (20 overrides) | monitor readouts only |
| `od_boost` | summed | overdose afflictions | a few consumers |

On top of these, afflictions carry `pain_at_max` and `consciousness_at_max`, and species
carry their own multipliers.

Because each system only reaches its own consumers:
- A modifier cannot lower oxygen saturation.
- An affliction cannot change how fast reagents metabolise.
- A `vital_effects` pulse offset changes the number on the monitor but not the heart.

Every new effect therefore needs new code in the consumer. That is the "additive"
pattern the server design doc wants to leave behind.

### 4.3 Harm and healing bypass the pipeline

**Limb damage is public.**
- `organ/external/take_damage(brute, burn, sharp, edge, …)` has about a dozen direct
  callers outside the body:
  - handcuffs `:143`, mousetrap `:39`, glass shards `:136`, traps `:387`, `items.dm:786`
  - implant meltdown `:58`, genetics side effects `:49, :65`, pAI folding `:51`
  - changeling absorb `:60`, archaeology sword `:120`
- These skip `COMSIG_LIVING_INJURE`, modifiers, species multipliers and armour. Limbs
  also apply their own `brute_mod`/`burn_mod`.
- There are two more pre-damage signals, one for limbs and one for organs. Only
  godmode listens to them.

**`injure()` cannot target an internal organ.**
- `resolve_zone()` returns the organ, but `humanoid/receive_injury` handles only
  external limbs and otherwise spreads the hit across limbs (`humanoid.dm:61-70`).
- So about 25 callers damage organs directly: surgery slips, diseases, flashers,
  welders, laser pointers, leeches, the VR pod.

**Healing goes around `mend()`.**
- About 40 direct `heal_damage()` calls outside the body:
  - spells (mend organs, cult runes and constructs)
  - species (protean, xenomorph, `station.dm:2015`, shadekin)
  - modifiers (unholy, horror), admin effects, lasertag
  - organs healing themselves (liver, spleen, horror organs), and the reagents above
- Two sibling types share the proc name with different signatures:
  limb `heal_damage(brute, burn, internal, robo_repair)` and organ
  `heal_damage(amount, mode)`.

**An internal organ can be healed six ways:**
1. `heal_damage` in one of three `LESION_HEAL_*` modes
2. negative `take_damage`
3. `mend`
4. `receive_tagged_treatment`
5. `lesion.heal`
6. `surgically_repair_organ`

Only some of these apply drug floors and drug efficiency.

**`isSynthetic()` still decides harm or healing at about 12 sites.**
- Several are redundant with the body's biology filter: contaminated water, the
  recharge station, the fabrication swarm.
- One is dead: the energy gun (bug 5).
- A few check the whole body where the part matters: ionic rapier, cult sphere, and 7
  branches in `handle_radiation`.

### 4.4 Core internals

**The treatment loop exists three times**, in `affliction.dm:267-278`, `wounds.dm:285-297`
and `lesions.dm:213-225`.
- Wound and lesion ticks replace the base tick completely. Wounds therefore skip symptom
  ticking, progression triggers, `worsened_by_tags` and `cured_by`.
- Lesions re-implement the symptom-band logic.

**The humanoid `mend` has two paths** (`humanoid.dm:283-310`).
- The base path sends wounds to `receive_treatment`, which only shortens bleeding.
- A second loop then heals limbs, for four tags hard-coded in a `switch`.
- Vitals are recomputed twice.

**`afflict()` constructs afflictions without their location** (`body.dm:131`). A lesion
created this way is configured for no organ: generic name, wrong repair tag. This is
latent; no caller does it yet.

**Contract telemetry lives in the base affliction** (`affliction.dm:157-178`). Wounds and
lesions override it with empty procs just to opt out.

**`body.Destroy` clears `A.body` before `qdel`**, so `on_removed` and its signals never
run.

**The brain special case survives** in `medical/organ_decay/brain.dm`: damage bands,
decay rates and direct alkysine healing, all beside the lesion model.

**There are two invalidation frameworks.**
- Human `dq_medical_dirty` domains (`medical/emergent.dm`) sit beside the body's
  `vitals_dirty`.
- `emergent.dm` spawns syndromes (for example respiratory failure) by polling organ
  thresholds.

**`recompute_vitals` does three jobs** (pain, consciousness and vitality in one proc).
It also reads species, `chem_effects` and slurring directly, and uses unnamed numbers
(1.2, 30, 15, 20, 0.5).

### 4.5 Diagnosis is re-derived by every device

| Procedure | Lines | Where |
|---|---|---|
| `healthanalyzer/scan_mob` | 425 | `devices/scanners/health.dm:45` |
| `/mob/living/scan_mob` (admin, 75% identical copy) | 427 | `admin/health_scan.dm:7` |
| `bodyscanner/generate_printing_text` | 285 | `machinery/adv_med.dm:213` |
| body scanner data and bands | 438 | `medical/bodyscanner/data.dm`, `qualitative.dm` |
| `medical_kiosk/medical_scan` | 204 | `machinery/medical_kiosk.dm:122` |
| `robotanalyzer/do_scan` | 191 | `robot/analyzer.dm:29` |
| `grab/inspect_organ` | 115 | `mob/mob_grab_specials.dm:1` |
| scanner strip | 76 | `medical/scanner_strip.dm` |

These eight procedures have their own thresholds, and fake death is handled separately
in two of them (analyzer `fake_oxy`, and the body scanner's hard-coded "brain 200 /
lungs 25"). The organic analyzer prints "ERROR" for synthetics. None of them reads the
symptom audiences the design is built around.

### 4.6 Surgery has two frameworks

- **Legacy steps mutate state directly.** For example, `bones.dm:184` clears
  `ORGAN_BROKEN`.
- **`/datum/dq_surgery` records cure afflictions** when a step with a matching
  `completion_step` typepath completes (13 records, `medical/surgery/integration.dm`).
- **The flag and the affliction can disagree.**
- **Duplicated step:** `fix_organic_organ_robotic` (`organs_internal.dm:136`) duplicates
  `robotics/fix_organ_robotic` (`robotics.dm:298`).

### 4.7 God procedures

| Procedure | Lines | Where | Fate under this design |
|---|---|---|---|
| human `examine` | 458 | `human/examine.dm:1` | split; vitals from `diagnose(glance)` |
| admin `scan_mob` | 427 | `admin/health_scan.dm:7` | deleted → diagnosis renderer |
| `healthanalyzer/scan_mob` | 425 | `scanners/health.dm:45` | deleted → diagnosis renderer |
| `handle_breath` | 306 | `human/life.dm:539` | atmos intake only; oxygen logic → physiology |
| `bodyscanner/generate_printing_text` | 285 | `adv_med.dm:213` | paper renderer |
| `handle_regular_hud_updates` | 224 | `life.dm:1435` | dedupe (32 lines copied from `handle_hud_icons_health`), split |
| `medical_kiosk/medical_scan` | 204 | `medical_kiosk.dm:122` | diagnosis + `treatment_demand` |
| `handle_regular_status_updates` | 193 | `life.dm:1237` | consciousness → body; rest split |
| `robotanalyzer/do_scan` | 191 | `analyzer.dm:29` | synthetic diagnosis profile |
| `handle_environment` | 188 | `life.dm:868` | one `temperature_damage()` shared by body and belly |
| `robot/attackby` | 180 | `robot.dm:611` | per-tool `*_act` procs |
| limb `take_damage` | 179 | `organ_external.dm:395` | internal to the body; split in four |
| `handle_hud_list` | 165 | `life.dm:2086` | reads diagnosis and factors |
| AI `Life` | 163 | `ai/life.dm:1` | power / vision / APU split; death → body |
| `handle_radiation` | 158 | `life.dm:274` | radiation affliction staged by dose |
| `droplimb` | 136 | `organ_external.dm:1031` | message / remains / detach |
| reagent `on_mob_life` | 124 | `_reagents.dm:82` | uptake pipeline reading factors |
| `grab/inspect_organ` | 115 | `mob_grab_specials.dm:1` | palpation diagnosis profile |
| `perform_cpr` | 97 | `human_attackhand.dm:555` | becomes a support |
| `handle_pulse` | 90 | `life.dm:1970` | deleted → physiology readout |
| `defib/do_revive` | 80 | `defib.dm:370` | cardioversion tag + physiology |
| `handle_shock` | 65 | `life.dm:1905` | deleted → traumatic shock affliction |

### 4.8 Performance

- **Treatment levels are rebuilt once per affliction per tick** (`treatment.dm:458`).
  - Each rebuild walks every reagent holder.
  - For each tagged reagent it walks every affliction again (`reagent_cure_modifier`).
  - Cost is roughly A·R·A per mob per tick. A badly wounded human is the worst case.
- **Every `injure()` call does a full recompute and status evaluation, and allocates a
  list.** `injure_many` multiplies this.
- **Removing one lesion recalculates the organ three times**, and each pass scans every
  affliction on the body.
- **Location lookups are linear scans**: `afflictions_at`, `get_wounds` and
  `get_lesions`. There is no location index.

### 4.9 Keep as is

These are solid and the design builds on them:
- `injure`/`mend` as the verbs
- afflictions with stages, triggers and outcomes
- accumulating singleton symptoms with audiences
- treatment tags with biology
- per-part biology
- body plans
- wound- and lesion-derived integrity
- `COMSIG_LIVING_INJURE` / `COMSIG_LIVING_INJURED`
- the reference book generated from data
- the audit tests

---

## 5. Target architecture

### 5.1 Principles

1. **The body is the only authority on physiological state.** Code outside the body
   asks (queries) or tells (`injure`, `mend`, supports). Nothing else writes organ
   damage, `stat`, pulse or pain for health reasons.
2. **Anything that changes how a body works is a contribution to a named body factor.**
   Sources and consumers never know about each other. Adding either side needs no
   change on the other side. This is what makes the system multiplicative.
3. **Mechanisms, not items.** Treatment tags are the only way to heal. Supports are the
   only way to prop up a failing function. Any source may deliver either: a drug, a
   tool, a machine, a spell, a species power, a material property.
4. **Diagnosis is a report, not a formula.** The body produces one structured diagnosis.
   Devices differ only in what their sensors can see and how they present it.
5. **Plans adapt one model to their anatomy.** Humanoid, synthetic, simple and machine
   bodies share the factors and the physiology vocabulary, each with its own formulas.
6. **No parallel paths.** Each phase deletes what it replaces, with no long-lived shims.

### 5.2 Layers

```
 SOURCES (write)                  BODY (owns state)                          CONSUMERS (read)
 ───────────────                  ─────────────────                          ────────────────
 injure(kind, amt, target) ──►   receive_injury ─► afflictions               movement, combat, HUD
 mend(tag, amt, target)    ──►   shared treatment loop ─► afflictions        examine, scanners, UIs
 add_support(...)          ──►   supports (floors on factors)                medbots, kiosks, AED
 reagents ─ tags, factors  ──►   treatment snapshot (once per tick)          machines (cryo, sleeper)
 afflictions ─ factors     ──►   body factors (flat list, recomputed         contracts (signals)
 modifiers ─ factors       ──►     when dirty)                               book (documents factors)
 species ─ baselines       ──►   physiology.derive(): airway → ventilation
 environment ─ breath,     ──►     → oxygenation; pump → perfusion → delivery;
   temperature                     oxygen debt → hypoxia / ischemia / rhythm
                                 consciousness, pain, vitality, death
                                 diagnose(profile)  treatment_demand(profile)
```

### 5.3 Body factors: the shared effect model

A **body factor** is a named quantity that any number of sources contribute to and any
number of consumers read. Factors replace `mechanical_effects`, `vital_effects`,
`od_boost` and `chem_effects`, and in the end the numeric modifier fields.

**Definitions.** Int defines in a new `code/__defines/body_factors.dm`. The prefix `BF_`
is unused; `CHANNEL_*` is taken by radio. Each has a static `/datum/body_factor_def`
entry: name, combine rule (`BF_MULT`, `BF_ADD`, `BF_MIN`, `BF_MAX`), baseline, bounds,
and book text. A first set:

| Factor | Rule | Meaning |
|---|---|---|
| `BF_AIRWAY` | mult | airway patency |
| `BF_RESP_DRIVE` | mult | spontaneous breathing drive |
| `BF_LUNG_MECHANICS` | mult | chest wall and lung expansion |
| `BF_GAS_EXCHANGE` | mult | alveolar exchange |
| `BF_PUMP` | mult | cardiac output (synthetic: power delivery) |
| `BF_CIRCULATION` | mult | vascular tone (synthetic: coolant circulation) |
| `BF_DEMAND` | mult | metabolic demand (fever up; cold and stasis down) |
| `BF_PROGRESSION` | mult | speed at which afflictions progress |
| `BF_METABOLISM` | mult | reagent processing rate |
| `BF_BLEEDING` | mult | bleed rate |
| `BF_HEALING` | mult | natural regeneration and incoming healing |
| `BF_ANALGESIA` | add | pain relief (points) |
| `BF_PAIN` | add | extra pain (points) |
| `BF_SEDATION` | add | consciousness reduction (points) |
| `BF_ARRHYTHMIA_RISK` | add | hazard of rhythm deterioration |
| `BF_HEART_RATE` | add | heart-rate drive (readout) |
| `BF_SLOWDOWN` | add | movement delay |
| `BF_ACCURACY` | add | ranged accuracy |
| `BF_MOTOR_CONTROL` | mult | fine motor control (drops, tremor) |
| `BF_VISION` / `BF_HEARING` | mult | senses |
| `BF_ACTION_BLOCKS` | flags | blocked actions (typing, holding with an arm, …) |

**Declaring contributions.** Sources declare static tables, never per-tick code:

```dm
/datum/affliction/airway_edema
	factors = list(BF_AIRWAY = 0.2, BF_HEART_RATE = 15)   // values at severity 100

/datum/reagent/oxycodone
	factors = list(BF_ANALGESIA = 60, BF_RESP_DRIVE = 0.5, BF_SEDATION = 20)   // at standard dose

/datum/species/diona
	factor_baseline = list(BF_METABOLISM = 0.6, BF_DEMAND = 0.7)
```

- Afflictions scale by severity. Stages may return a different static list.
- Reagents scale by the existing dose curve.
- Modifiers contribute at full value.

For a multiplicative factor, a declared value `f` at severity `s` contributes
`1 - (1 - f) * s/100`. For an additive factor it contributes `f * s/100`.

**Storage and cost.**
- `body.factors` is a flat list indexed by `BF_*` (AGENTS.md §3e).
- It stays `null` while every factor is at baseline, which is most bodies (lazy, §3a).
- It is recomputed only when marked dirty: an affliction is added or removed or crosses
  a severity band, a modifier changes, reagents change, or a support changes.
- The recompute visits each source's static table once and allocates nothing per tick.
- `L.factor(BF_X)` returns the cached value.

**Worked example.**
- Partial choking: `BF_AIRWAY 0.1` at severity 50 → 0.55.
- Allergic swelling: `BF_AIRWAY 0.2` at severity 60 → 0.52.
- Together: 0.55 × 0.52 = 0.29.

Neither alone closes the airway; both together nearly do. No code anywhere knows that
choking and swelling interact.

**The book.** The reference book reads `factors`, so every affliction and drug documents
its effects automatically. For example: "Airway: −80% at full severity".

### 5.4 Physiology: generic vital systems

A per-body `/datum/physiology` (a plan-specific subtype) runs once per tick after the
factors, and holds the derived values. Humanoid organic formulas:

```
ventilation  = max(BF_RESP_DRIVE, drive_support) × BF_LUNG_MECHANICS × BF_AIRWAY
oxygenation  = saturate(ventilation × BF_GAS_EXCHANGE × breath_quality)
output       = rhythm_output(heart rhythm) × BF_PUMP            (floored by CPR/bypass supports)
perfusion    = output × volume_factor(blood volume) × BF_CIRCULATION
delivery     = oxygenation × perfusion
demand       = BF_DEMAND
shortfall    = max(0, CRITICAL_RATIO × demand − delivery)
oxygen_debt += shortfall × dt      (repaid while delivery exceeds demand)
```

- **`breath_quality`** comes from atmos. `handle_breath` keeps gas intake, toxic gases
  and temperature, and reports quality from 0 to 1 instead of applying damage.
- **`saturate()`** is a plateau. Mild loss of ventilation barely moves oxygenation;
  severe loss collapses it, like the real dissociation curve.
- **The support placement encodes the rules.** A bag-valve mask supports the *drive*,
  so it cannot push past a closed airway. Nothing special-cases that.

Consequences are shared by every cause:
- `oxygen_debt` drives the existing `tissue_hypoxia` affliction.
- Shortfall at the brain grows ischemic lesions.
- Shortfall raises the rhythm-deterioration hazard, so hypoxic arrest emerges on its own.

**Rhythm.** The heart's rhythm (sinus, tachy, VF, asystole; later brady, VT, PEA) stays
on the existing `cardiac_arrhythmia` affliction.
- Transitions are hazards from `BF_ARRHYTHMIA_RISK` plus shortfall.
- A defibrillator delivers `TREAT_CARDIOVERSION`, which acts only on shockable rhythms.
- Vasopressors raise `BF_CIRCULATION` and the asystole-to-VF conversion hazard.

**Consciousness.**
`100 − Σ affliction penalties − BF_SEDATION − max(0, pain − tolerance) − brain hypoperfusion penalty`.
- `stat` is applied in exactly one place, `body.update_consciousness()`; the life.dm
  copy is deleted.
- Graded bands (alert, drowsy, obtunded, unresponsive) feed `BF_VISION`, speech and
  similar factors.

**Pain and shock.**
- Pain = afflictions + wound load + `BF_PAIN` − `BF_ANALGESIA`.
- Traumatic shock becomes an affliction whose severity climbs while pain is above
  tolerance or perfusion is low. Its factors (slowdown, accuracy, weaken chance) replace
  `shock_stage`, `handle_shock` and all of their writers.
- `CE_PAINKILLER` becomes `BF_ANALGESIA`.

**Asphyxia is an outcome, not an injury.** Lack of oxygen is a state the body computes
from breathing, airway, blood and circulation. Sources say what physically happens, and
the physiology decides whether that suffocates the patient. `INJURY_ASPHYXIA` and
`INJURY_CATEGORY_ASPHYXIA` are deleted. The 84 current uses split like this:

| Group | Uses | Examples | Becomes |
|---|---|---|---|
| The breathing model itself | ~25 | `handle_breath`'s own suffocation calls, blood loss, lung failure, arrest, pneumothorax, dyspnea symptoms | deleted; the physiology produces the outcome |
| Things done to the airway or chest | ~12 | chokehold grab, leash, mech clamp, constriction abilities | a support-style **restriction** on `BF_AIRWAY` or `BF_LUNG_MECHANICS` for as long as it lasts |
| What is being breathed | ~10 | drowning, toilet dunking, smoke clouds, cigarettes, dust anomalies, belly digestion | breath quality, reported by the Breathing system |
| Chemicals | ~12 | lexorin, cyanide-type toxins, overdose side effects | factors: `BF_GAS_EXCHANGE`, a new `BF_O2_CARRIAGE` (carbon monoxide), a new `BF_TISSUE_UPTAKE` (cyanide) |
| No mechanism at all | ~15 | spells, admin damage, changeling fake death, spawn-in injuries, AI card | an explicit `add_oxygen_debt(amount, source)`; simple bodies map it to load |
| Tests and data definitions | ~10 | | updated |

This buys:
- **Protections work without code.** Internals stop smoke. A ventilator saves a drowning
  victim once out of the water. A bag-valve mask does nothing against a chokehold.
- **Diagnostic puzzles.**
  - Cyanide shows normal oxygen saturation with tissue hypoxia.
  - Carbon monoxide fools a basic oximeter.
  - Lexorin shows low saturation with a clear airway.
- **The last of the four damage pools is gone.**

Species and modifier resistances to asphyxia become `BF_DEMAND` or a hypoxia-tolerance
factor. `TREAT_OXYGENATION` pays debt down. The defibrillator's one-shot asphyxia wipe
goes away.

**Readouts.**
- SpO2 = smoothed oxygenation.
- Heart rate comes from the rhythm and `BF_HEART_RATE`.
- Blood pressure comes from output × circulation × volume.
- Breathing rate comes from drive and supports.

`vitals.dm` reads these; `vital_effects` is deleted.

**The vital-systems work that just landed** (airway obstruction and edema, respiratory
arrest, pneumothorax, cardiac arrhythmia, the bag-valve mask, airway kit and
decompression needle, the defibrillator rhythm check) is kept as content.
- Its binary gates (`breath_blocked()`, `has_cardiac_output()`, the fixed CPR window
  and damage constants) become factor contributions and supports.
- Its six unit tests are the behavioural spec for this phase. For example, "CPR cuts
  arrest damage to about 35%" is what the new constants are tuned to reproduce.

### 5.5 Supports and interventions

A support is a temporary floor or multiplier on a factor, owned by a source:

```dm
/datum/body_support
	var/factor            // BF_* id
	var/floor             // value = max(value, floor), applied after the product
	var/multiplier        // or value *= multiplier
	var/datum/weakref/source
	var/expires_at
	var/datum/callback/still_valid   // performer adjacent, machine powered, bag closed…
```

`body.add_support(source, factor, floor, duration, still_valid)` and
`body.remove_supports(source)`.

| Intervention | Mechanism | Trade-off |
|---|---|---|
| CPR (each cycle) | `BF_PUMP` floor 0.25 for 7 s; rescue breaths floor drive at 0.3 | tires the performer; chance of rib fracture |
| Bag-valve mask | drive floor 0.8 while squeezing | useless if the airway is closed |
| Ventilator (machine) | drive floor 1.0 while attached and powered | medbay only |
| Airway kit / intubation | `BF_AIRWAY` floor 0.9 | skill check; failure causes airway trauma |
| Needle decompression | `TREAT_DECOMPRESSION` | temporary; the lung still needs a chest tube or surgery |
| Defibrillator / public AED | `TREAT_CARDIOVERSION` | shockable rhythms only; the AED reads rhythm from diagnosis |
| Tourniquet | limb `BF_BLEEDING` 0 and limb perfusion 0 | after N minutes the limb gains ischemic lesions |
| Oxygen mask | better breath quality via atmos | needs a tank |
| Stasis bag | `BF_DEMAND` ×0.05, `BF_PROGRESSION` ×0.1; diagnosis sees only "in stasis" | a reperfusion-injury affliction on exit, scaled by time inside |
| Cryo cell | cold (`BF_DEMAND`, `BF_PROGRESSION` low) plus the cryo drugs' tags | |

This gives the field-versus-medbay split the design doc asks for:
- Field kit raises floors so delivery stays above the critical ratio and the debt stops
  growing. The patient survives transport.
- Definitive treatment (surgery, targeted drugs) removes the cause.

It also covers low population:
- Public AEDs, and a kiosk that gives advice from `treatment_demand`.
- Medbots with a basic sensor profile.
- Expensive broad-spectrum drugs (wide tag profiles).
- Stasis for waiting on a doctor, at the documented cost.

### 5.6 Harm and healing: one pipeline

**Harm.** `injure(kind, amount, target, source, armor, affliction, flags)`, where
`target` is a zone, a limb, an internal organ or a robot component.
- For an internal organ, the plan maps kind to lesion through one static table:
  - blunt → contusion
  - cut → laceration
  - pierce → perforation (laceration on a solid organ)
  - toxin and radiation → toxic injury
  - neural → a brain lesion of that kind
  - asphyxia → oxygen debt
- The ~25 direct organ-damage callers and ~12 limb-damage callers move to `injure()` and
  gain signals, modifiers, species multipliers and armour.
- Limb `take_damage` is renamed to an internal body proc, so the compiler finds every
  old caller. A `check_grep` rule keeps organ and limb damage and healing procs inside
  `code/modules/body/` and the organ files. (`PRIVATE_PROC` cannot express "callable
  from the body plans only".)
- `brute_mod`/`burn_mod` become part multipliers inside `body.injury_multiplier(kind, part)`.
- The two organ pre-damage signals are deleted. Their only listener, godmode, already
  has `COMSIG_LIVING_INJURE`.

**Healing.** `mend(tag, amount, target)` is the only way to heal.
- The `LESION_HEAL_*` modes are deleted.
- Natural regeneration becomes a treatment source: a `TREAT_REGENERATION` level from
  species × nutrition × sleep × `BF_HEALING`. This is where "sleep helps you heal"
  properly lives.
- Admin, magic and species restoration uses `TREAT_RESTORATION` (all biologies, full
  repair) or `fully_heal()`.
- Reagents only declare tags and factors. The direct heals (bug 4) are deleted, and the
  tags are rebalanced once.

**Biology.** `has_biology(flag, target)` asks the body. `isSynthetic()` stays for
flavour text only. A lint rule forbids it inside `code/modules/body/`, the conditions and
the reagents, and the other sites from 4.3 are converted.

### 5.7 Affliction lifecycle

**Construction.** Always `new type(location)`. `configure(location)` is a virtual hook
for every affliction, which fixes the latent `afflict()` bug.

**One tick pipeline, one override point:**
```dm
/datum/affliction/proc/tick()
	apply_treatment(body.treatment_levels())   // shared loop: treated_by, worsened_by_tags, cured_by
	progress()                                 // drift / progression (wounds: autoheal; lesions: drift)
	update_symptoms()
	fire_progression_triggers()

/datum/affliction/proc/receive_tagged_treatment(tag, amount, continuous)   // the one place subtypes customise treatment
```
Wounds override `receive_tagged_treatment` and `progress()` (hemostatic shortens
bleeding; tissue repair heals damage). Lesions override the same two for drug floors and
full-repair tags. The limb loop in `humanoid/mend` is deleted.

**Treatment snapshot.** `body.treatment_levels()` returns a list cached for the tick.
- Its sources: reagents, supports that provide tags (an oxygen mask provides
  oxygenation), natural regeneration, and environment (cryo).
- It is invalidated from the existing `on_reagent_change` hook and from support
  changes.
- `reagent_cure_modifier` is folded into the same build.

**Indexes and dirty flags.**
- `afflictions_by_location` makes location lookups O(1).
- Organ integrity is recalculated lazily, like limbs.
- `injure()` marks vitals dirty and runs a cheap death check. The full recompute runs
  once per tick, or on a query.
- The `dq_medical_dirty` domains merge into body invalidation, and the `emergent.dm`
  syndromes read factors and physiology instead of polling organ thresholds.

**Signals.** `COMSIG_AFFLICTION_SEVERITY_CHANGED` replaces the contract code in the base
class. Contracts subscribe, and the wound/lesion opt-outs are deleted.

**Teardown.** `body.Destroy` removes afflictions through `remove_affliction`.

### 5.8 Diagnosis

```dm
/datum/diagnostic_profile
	var/audiences      // SYMPTOM_AUDIENCE_* this device can perceive
	var/biology        // which parts its sensors read (organic, synthetic, both)
	var/vitals         // VITALS_PULSE | VITALS_BP | VITALS_SPO2 | VITALS_RHYTHM | VITALS_TEMP | VITALS_RESP
	var/part_detail    // none | bands | numbers
	var/reveal_lesions // internal findings (body scanner, exploratory surgery)
	var/noise          // reading jitter

/datum/body/proc/diagnose(datum/diagnostic_profile/P)          // → /datum/diagnosis
/datum/body/proc/treatment_demand(datum/diagnostic_profile/P)  // → TREAT_* → urgency
```

**The report.** A `/datum/diagnosis` carries vitals readings, findings (symptoms and
lesion findings with location and band), per-part integrity bands, and an overall band.
Fake death is applied once, inside `diagnose()`.

**Renderers.** A chat renderer, a TGUI data renderer and a paper renderer, used by every
device. Each scanner becomes a profile plus a renderer, about 30 lines. The eight
procedures in 4.5 go away.

**Profiles:**
- **Glance / examine:** public symptoms.
- **Health analyzer:** pulse, SpO2, temperature, visible and scannable surface findings.
- **Advanced analyzer:** adds BP, rhythm and bands.
- **Body scanner:** adds lesions and numbers.
- **Robot analyzer:** synthetic sensors, which replaces the "ERROR" branch.
- **Palpation:** grab inspection.
- **Admin:** everything.

**Automation.** Medbots, the sleeper's auto-inject, the kiosk and cryo use
`treatment_demand()` through *their own* profile. They see what their sensors can see,
so a trained doctor stays better than a bot.

**`injury_load`** becomes an internal query: simple bodies, analytics, the death log. It
is no longer a UI.

### 5.9 Surgery on the new APIs

This is the approved redesign, placed on these APIs:
- **Procedures are data** that target afflictions.
- **Access layers are incision afflictions.**
- **Tools deliver mechanisms** (`TREAT_SURGICAL_REPAIR`, `TREAT_RESECTION`,
  `TREAT_HEMOSTATIC`, bone setting) with a quality.
- **Outcomes are graded** by skill, tool quality, anaesthesia (`BF_ANALGESIA`,
  `BF_SEDATION`) and patient movement, and failures create complication afflictions.
- **Exploratory surgery is a diagnosis profile** that reveals lesion findings.
- **`ORGAN_BROKEN` is derived** from the fracture affliction.
- **One registry** serves the runtime and the book. The completion-step hook and the
  duplicated robotic step are deleted.
- **Synthetic maintenance** uses the same procedures with synthetic tags.

### 5.10 Body plans and species

| Body | Physiology | Notes |
|---|---|---|
| Humanoid, organic | the full chain (5.4) | |
| Humanoid, synthetic (FBP) | pump = power delivery (`power_fault`), circulation = coolant (`coolant_leak`), demand = processing heat; debt becomes heat or brownout (`thermal_runaway`, `processor_corruption`) | airway and ventilation pinned at 1 |
| Mixed parts | harm and healing per part (already true); physiology from the core's biology | a prosthetic heart can fault but not fibrillate |
| Species without lungs or heart | species baselines pin the factors | deletes `should_have_organ` branches in life code |
| Simple | delivery = 1 − load ratio; affliction factors still slow them and spoil their aim | venoms and poisons work through factors |
| Machine / robot | components as parts; pump = cell power | the AI's backup capacitor becomes a pump source in an AI plan, giving one death rule |

Because the factors are named by function, one source can act on every body type. An
anomalous material that "slows circulation" slows blood in an organic and coolant in a
synthetic.

### 5.11 Hooks into other systems

- **Atmos:** breath quality, toxic gases (existing triggers), temperature feeding
  `BF_DEMAND` and `BF_PROGRESSION`.
- **Materials:** material behaviours on weapons and implants act through the injury
  source. Radioactive weapons cause radiation afflictions, toxic materials poison, and
  implant biocompatibility drives rejection.
- **Chemistry:** tags plus factors. Overdoses and interactions stay afflictions with
  factors.
- **Species:** parameter packs (factor baselines, breath gas, pain tolerance) instead of
  code branches.
- **Contracts:** signals for severity change, stabilisation, revival and confirmed
  diagnosis.
- **Expeditions:** fauna venoms and exotic afflictions are data.
- **Equipment:** modifiers declare factors.

### 5.12 What the multiplicative design buys

- **Opioids:** one drug that lowers `BF_RESP_DRIVE` and adds `BF_ANALGESIA` makes
  treating pain risk respiratory arrest. The trade-off comes from data.
- **Vasopressors:** one drug that raises `BF_CIRCULATION` helps septic shock,
  anaphylaxis, hypovolaemia and PEA. The House MD loop "treat the symptom to buy time
  for the diagnosis" falls out of shared factors.
- **Cold:** a cold expedition site lowers `BF_DEMAND`, so a frozen patient in arrest
  survives longer. The stasis bag and the cryo cell use the same mechanism.
- **Synthetics:** a coolant leak in a hot room gives more heat demand × less circulation,
  so runaway comes sooner.
- **Materials:** a toxic-material blade poisons, and a slime-coated dressing that carries
  `TREAT_HEMOSTATIC` works wherever bleeding does.
- **New factors and sources:** a new factor is read by every consumer that cares, and a
  new source reaches every factor. Neither side needs code for the other.

---

## 6. What happens to today's code

| Today | Becomes |
|---|---|
| `shock_stage`, `handle_shock` | traumatic shock affliction plus `BF_PAIN`/`BF_SLOWDOWN`/`BF_ACCURACY` |
| `handle_pulse`, tachycardic/bradycardic lists, modifier `pulse_*` | physiology readout; reagent `BF_HEART_RATE`; rhythm hazards |
| `vitals.dm` `vital_effects` | readouts from physiology |
| `mechanical_effects`, `od_boost` | factors |
| `chem_effects[CE_*]` | reagent factors (`CE_PAINKILLER` → `BF_ANALGESIA`, `CE_SPEEDBOOST` → `BF_SLOWDOWN`, …) |
| modifier numeric fields | modifier factors |
| `breath_blocked()`, `has_cardiac_output()` | derived ventilation and output |
| oxygen logic in `handle_breath` | breath quality plus oxygen debt |
| `organ_decay/brain.dm` | deleted: brain lesions plus ischemia |
| `emergent.dm` threshold polling | syndromes reading physiology |
| direct organ and limb `take_damage` / `heal_damage` | `injure` / `mend` with an organ target |
| `LESION_HEAL_*` modes | tags (`TREAT_REGENERATION`, `TREAT_RESTORATION`) |
| eight scan procedures | `diagnose()` plus renderers |
| `injury_load` in UIs and bots | diagnosis and `treatment_demand` |
| `/datum/dq_surgery` completion hook | procedures targeting afflictions |
| contract code in `on_severity_changed` | signal subscription |
| `INJURY_ASPHYXIA`, `INJURY_CATEGORY_ASPHYXIA` | deleted: mechanisms, breath quality, factors, or `add_oxygen_debt()` |
| `handle_*` hooks in `Life()` | life systems (`doc/mob_life_architecture.md` §4) |

---

## 7. Phased plan

> **Superseded.** The unified roadmap in `doc/mob_life_architecture.md` §8 replaces this
> section. It adds the life scheduler, event-driven activation, and the cyborg and
> protean work, and it renumbers the phases. The phase contents below still describe
> the health work.

Each phase compiles clean, keeps the suite green, deletes what it replaces, and ships
with a changelog. Existing debug and trace logging is kept.

**Phase 0: bug fixes.** The seven bugs in section 3. Small, independent, no design
change.

**Phase 1: core consolidation.** No gameplay design change.
- Shared treatment loop and tick pipeline.
- Treatment snapshot cache.
- Location index and lazy organ integrity.
- `afflict(location)`.
- The telemetry signal, and the `Destroy` fix.
- `injure()` organ targeting, and limb and organ damage procs internal to the body
  (~37 call sites).
- `mend()` as the only heal (~40 call sites), with the `LESION_HEAL_*` modes deleted.
- Direct reagent heals removed and tags rebalanced.
- `humanoid/mend` limb loop deleted.

**Phase 2: body factors.**
- The infrastructure and the book integration.
- Migrate `mechanical_effects`, `vital_effects` (readouts stay as-is until phase 3),
  `od_boost` and `chem_effects`.
- Convert modifiers' numeric fields to factor declarations. This is mechanical: each
  `slowdown = 2` becomes `factors = list(BF_SLOWDOWN = 2)`. The 71 loops become factor
  reads.
- The combat fields (armour, evasion, `incoming_*`) can be a second pass (see decision 1).

**Phase 3: physiology.**
- Physiology datum and plan adapters (humanoid organic, synthetic, simple, machine).
- Oxygen debt, rhythm hazards, supports.
- Consciousness applied in one place; traumatic shock affliction; asphyxia as debt.
- Delete `handle_shock`, `handle_pulse`, the oxygen part of `handle_breath`,
  `organ_decay/brain.dm`, `vital_effects`, `breath_blocked()`/`has_cardiac_output()`.
- CPR, BVM, defibrillator and airway kit become tags and supports.
- The vital-systems tests stay green as the spec.

**Phase 4: diagnosis.**
- `diagnose()`, profiles, renderers, `treatment_demand()`.
- Rewrite the eight scan procedures and the UI data procs (crew monitor, cryo, sleeper,
  operating computer, kiosk, medigun), with matching TGUI changes.
- Medbots, cryo and sleeper automation move to `treatment_demand`.

**Phase 5: surgery** on the phase 1–4 APIs (5.9).

**Phase 6: stabilisation content.**
- Ventilator, tourniquet, public AED, stasis bag with reperfusion injury, cryo as cold.
- Kiosk advice, medbot profiles.

**Phase 7: cleanup.**
- Split the remaining god procedures (4.7).
- The `isSynthetic` sweep with its lint rule.
- Drop the `dq_` prefixes in the body core; name the magic numbers; merge the split
  `simple_mob/death()`.

Phases 0 and 1 are safe to start now. Phases 2 and 3 are the design change. Phase 4 is
the largest player-visible change.

---

## 8. Testing and enforcement

**Unit tests:**
- Factor math: combining, severity scaling, supports applied after the product.
- Physiology scenarios:
  - choking plus swelling stack
  - a bag-valve mask can't bypass a closed airway
  - CPR slows the debt
  - stasis stops the clock
  - cold slows arrest damage
  - an opioid overdose causes apnoea
  - a synthetic coolant leak plus heat
- Diagnosis: profile visibility, fake death, synthetic sensors.
- Heal and harm: organ targeting, one heal path, no double heals.

**Existing tests:** the vital-systems, lesion, medical, surgery and audit tests stay
green throughout. They are the behavioural spec for phases 1 and 3.

**`check_grep` rules (added in the phase that makes them true):**
- no `.damage` writes on organs outside `code/modules/body/`
- no `take_damage(`/`heal_damage(` on organs outside the body
- no `shock_stage` (phase 3)
- no `add_chemical_effect(` (phase 2)
- no `INJURY_ASPHYXIA` or `INJURY_CATEGORY_ASPHYXIA` (physiology phase)
- no `isSynthetic()` inside the body, the conditions or the reagents

**Performance test:** 50 heavily wounded humans ticking with reagents in their blood; the
per-tick cost must not regress.

---

## 9. Risks

- **Concurrent edits.** Another session is actively editing atmos and nearby code.
  Phase 3 touches `handle_breath`/`handle_environment`, so coordinate or land it in a
  quiet window.
- **Balance drift.** Removing the double organ heal and replacing fixed arrest constants
  with physiology changes timings. The existing tests pin the important ones; the rest
  need a playtest pass.
- **Player-facing UI change.** Replacing the four-number readouts (decision 2) is the
  biggest visible change and touches TGUI.
- **Scope.** Phases 2 and 3 touch many files but mostly mechanically. Each phase lands
  on its own.

---

## 10. Decisions

1. **Modifier conversion scope: decided.** Medical and physiological fields first,
   combat fields in a follow-up, both fully converted, with no adapter.
2. **Four-number readouts: decided.** Brute/burn/toxin/oxygen numbers on the crew
   monitor, analyzers and machines are replaced by vitals plus findings.
3. **Asphyxia: revised.** The earlier proposal was to reinterpret `INJURY_ASPHYXIA` as
   oxygen debt. The recommendation is now to delete it and express each source as a
   mechanism (see 5.4), keeping an explicit `add_oxygen_debt()` for effects with no
   mechanism. *Awaiting confirmation.*
4. **Order.** See the unified roadmap and its decisions in
   `doc/mob_life_architecture.md` §8 and §10.

# Body & Affliction Architecture

This document is the contract for how living things take harm, heal, fall
unconscious and die. It **replaces** the old health model entirely: there is no
`health`, `maxHealth`, `bruteloss`/`fireloss`/`toxloss`/`oxyloss`/`cloneloss`/
`halloss`/`brainloss`, `updatehealth()`, `adjust*Loss()`, `apply_damage()`,
`take/heal_overall_damage()`, `take/heal_organ_damage()`, `getMaxHealth()`,
`get_crit_point()` on any mob. Code that needs any of those concepts uses the
APIs below.

Design goals (from the medical design doc): afflictions are the root cause of
every harm; symptoms are the evidence; treatment is by mechanism; death is organ
death, not a number running out; synthetic and organic bodies are first-class,
declared — not special-cased with `isSynthetic()` at call sites.

---

## 1. Vocabulary

| Term | Type | Meaning |
|---|---|---|
| **Body** | `/datum/body` | One per `/mob/living`. Owns afflictions, computes vitals, decides consciousness and death. |
| **Body plan** | subtype of `/datum/body` | How a kind of mob is built: `humanoid`, `simple`, `robot`, `ai`. |
| **Part** | an organ (`/obj/item/organ`), a robot component (`/datum/robot_component`), or null (whole body) | Where an affliction is located. |
| **Biology** | `BIOLOGY_*` bitflag | What a part (or the whole body) is made of: organic, synthetic, nanoform. |
| **Injury** | `INJURY_*` int | *What happened*: blunt, cut, pierce, burn, frostbite, corrosive, electric, toxin, asphyxia, radiation, cellular, neural, pain, digestion. Replaces BRUTE/BURN/TOX/OXY/CLONE/HALLOSS for mobs. |
| **Affliction** | `/datum/affliction` | A root-cause problem with a severity (0–100) or a load (points), stages, progression, symptoms and treatments. Was `/datum/medical_issue/condition`. Wounds are afflictions too. |
| **Trigger** | `/datum/affliction_trigger` | Data rule that *creates* afflictions (injury events, organ integrity thresholds, progression gates, metrics). Was `/datum/dq_cause`. |
| **Symptom** | `/datum/affliction_symptom` | Stateless presentation (flyweight singleton per type, `affliction_symptom(type)`). Was `/datum/medical_symptom`. |
| **Treatment tag** | `TREAT_*` string | A healing mechanism. Afflictions list the tags that help/hurt them; reagents, tools, machines and powers provide tags. |

Organs (internal & external) expose a structural `damage` number for their
integrity — that is anatomy, not one of the removed damage pools — but it is
never written directly. External limbs' integrity is **derived** from the
wound afflictions located on them; internal organs' integrity is **derived**
from the lesion afflictions located on them (§6).

---

## 2. Harm in: the injury pipeline

```dm
/mob/living/proc/injure(kind, amount, zone = null, atom/source = null, armor = 0, affliction = null, flags = NONE)
```

- `kind` — `INJURY_*`. Pick the kind that describes *what physically happened*.
  Sharp+edge weapon → `INJURY_CUT`; sharp without edge → `INJURY_PIERCE`; blunt
  → `INJURY_BLUNT`; laser/fire/heat → `INJURY_BURN`; cold → `INJURY_FROSTBITE`;
  acid/bioacid → `INJURY_CORROSIVE`; shock → `INJURY_ELECTRIC`; poison →
  `INJURY_TOXIN`; suffocation → `INJURY_ASPHYXIA`; rads → `INJURY_RADIATION`;
  clone/DNA → `INJURY_CELLULAR`; brain → `INJURY_NEURAL`; stun/agony/"halloss"
  → `INJURY_PAIN`; vore digestion → `INJURY_DIGESTION`.
- `zone` — the **target**: a `BP_*` zone, a limb, an **internal organ**
  or a robot component (null = spread/systemic). An internal organ target
  becomes a lesion on that organ: the humanoid plan maps the kind to a lesion
  through one static table (`organ_lesion_for_injury()`: blunt, burn,
  electric, neural → contusion; cut → laceration; pierce → perforation, a
  laceration on solid organs; toxin, corrosive, radiation, cellular,
  digestion → toxic injury; frostbite, asphyxia → ischemic injury; pain → no
  effect). A lesion typepath as `affliction` picks the kind directly. An organ
  the body no longer has is not a target (the injury applies 0).
- `source` — the weapon/reagent/turf/mob responsible (logging, triggers).
- `armor_pen` — armour points ignored when the hit is armoured.
- `affliction` — optional typepath to create *instead of* the body plan's
  default response. **This is how unique afflictions are introduced**: spider
  venom passes `/datum/affliction/envenomation`, phoron passes
  `/datum/affliction/phoron_poisoning`, etc.
- Returns the amount actually applied after every mitigation (use it for
  nutrition payouts, feedback, etc. — never snapshot-and-diff).

Pipeline (one place, `code/modules/body/injury.dm`):
1. `COMSIG_LIVING_INJURE` (components may cancel/modify; godmode and lite
   godmode listen here — lite godmode cancels injuries aimed at internal
   organs and neural injury). The amount list is only allocated when
   something listens.
2. The mitigation stages, in order (INJURE_IGNORE_RESISTANCE skips b-d):
   a. Armour for the hit part and kind, only for hits from outside the body
      (`INJURE_ARMORED`): `injury_armor(kind, zone)` minus `armor_pen`, +/-25%.
      Armour can turn a cut or pierce into blunt trauma.
   b. Energy shields (`COMSIG_LIVING_SHIELD_INJURY`; they drain a cell).
   c. Resistance factors: `BF_INCOMING_ALL` x `BF_INCOMING(category)` —
      modifiers, forms, reagents, traits and species `factor_baseline`.
   d. Body/species/part multiplier: `body.injury_multiplier(kind, part)` —
      species immunities (NO_POISON, NO_PAIN, NO_DNA), biology, and the
      **part multiplier** (a limb's `brute_mod` for physical, `burn_mod` for
      thermal injury; spread injuries apply each limb's own).
   Each stage is recorded for `COMSIG_LIVING_INJURY_EXPLAINED` listeners and
   the admin verb "Trace Injury Mitigation".
3. `body.receive_injury(kind, amount, target, source, affliction, flags)` —
   the body plan resolves it into afflictions (§4).
4. `COMSIG_LIVING_INJURED` post-signal, pain flash, HUD invalidation.
5. `body.on_status_changed()`: marks the vitals dirty and runs the cheap
   death check only. The full vitals recompute runs once per tick, or on the
   next query (`vitality()`, `is_unconscious()`, `current_pain()`).

Limb and organ damage procs are **body-internal**:
`limb.apply_wound_damage()`, `limb.heal_wound_damage()` (detached limbs
only), `organ.apply_lesion_damage()`, `organ.restore_lesions()` (detached
organs only) and `organ.bench_damage()` (a loose organ). Outside
`code/modules/body` and `code/modules/organs` code calls `injure()` /
`mend()`; `tools/ci/check_grep.sh` ("organ damage outside the body") enforces
it. `/obj/item/organ/take_damage()` is the item-integrity proc and does
nothing to organs. There are no organ pre-damage signals.

Convenience wrappers: `injure_many(alist(kind = amount, ...), zone, source, armor_pen)`,
`injure_split(kind, kinds, amount, ...)` and `injure_by(weapon, amount, zone)`
(an armoured hit with the weapon's `injury_kind`, or its `injury_kinds` shares).
Weapons, projectiles, blobs, unarmed attacks (`/datum/unarmed_attack/var/injury_kind`)
and simple mobs (`attack_injury_kind`) declare their kinds directly; object
damage is derived with `injury_kind_obj_damage_type(kind)`.

## 3. Healing in: mend

Healing is always *by mechanism*:

```dm
/mob/living/proc/mend(tag, amount, target = null)  // instant treatment: THE heal path
/mob/living/proc/fully_heal()                      // admin/rejuvenate: clear everything
```

`mend()` is the only way to heal. `mend(TREAT_TISSUE_REPAIR, 10)` reaches
every affliction (at `target` — zone, limb, organ or component — if given)
whose `treatment_rate(tag)` is non-zero and delivers `amount × rate` through
its `receive_tagged_treatment(tag, amount, continuous = FALSE)`. Afflictions
with `shares_mend_budget` (limb wounds, organ lesions) share one `amount`
between them: a kit heals N points across a limb or organ, not N per wound.
Continuous treatment (chemicals in the blood, natural regeneration) is
applied each tick from the body's treatment snapshot (§6). Tools, machines,
magic, species powers and vore heal-bellies call `mend()`. Reagents **never**
heal directly — they declare `treatment_tags` and the tick applies them.

Two body-level mechanisms:
- `TREAT_REGENERATION` — natural regeneration, a continuous source in the
  snapshot: `body.regeneration_level()` (humanoid: config ×
  `REGENERATION_SLEEP_MULT` asleep × `REGENERATION_HUNGRY_MULT` hungry, 0
  starving or dead). Self-healing lesions answer to it while their organ is
  below `natural_heal_ceiling()` (bruise threshold; the brain's is 20%).
- `TREAT_RESTORATION` — admin, magic and species restoration. Every
  biology; full repair of every affliction with a `restoration_rate`
  (wounds including arterial bleeds, lesions ignoring their drug floor,
  load, systemic injury afflictions).

Every tag declares the biology it works on (`treatment_tag_biology()`):
reagent tags work on `BIOLOGY_ORGANIC`; `TREAT_PLATING_REPAIR` /
`TREAT_WIRING_REPAIR` / `TREAT_SYSTEM_RESTORE` / `TREAT_COOLANT` /
`TREAT_CALIBRATION` work on `BIOLOGY_SYNTHETIC`. Species `chem_strength_heal`
scales every reagent-driven level.
A welder on a synthetic arm is `mend(TREAT_PLATING_REPAIR, 15, BP_L_ARM)`.

## 4. Body plans

| Plan | Mobs | Parts | Death | Unconsciousness |
|---|---|---|---|---|
| `humanoid` | `/mob/living/carbon/human` (organic, FBP, protean, diona…) | external + internal organs | brain dead / missing; vital part destroyed (`DQ_VITAL_PART_LETHAL_MULT`× integrity) | consciousness ≤ 0 (§5) |
| `simple` | simple mobs, bots, pAI, alien larva/diona nymph, brainmob, other living | whole body | total load ≥ `endurance` | never (simple creatures fight to the end) — `stunned` etc. still apply |
| `robot` | cyborgs, drones | robot components | total load ≥ 2×`endurance`, or core component destroyed | consciousness from component state (power/processor) |
| `ai` | AI core | whole body | load ≥ 2×`endurance`, or hardware/backup failure | — |

**Default injury responses** are data, keyed by `(kind, biology)`
(the plans' `receive_injury()` and the limb's wound selection):

| Kind | Organic | Synthetic | Simple (any) |
|---|---|---|---|
| blunt | contusion wound | dent | trauma load |
| cut | laceration wound | breach | trauma load |
| pierce | puncture wound | breach | trauma load |
| burn | burn wound | scorching | burn load |
| frostbite | frostbite wound | — (immune) | burn load |
| corrosive | chemical burn wound | corrosion | burn load |
| electric | electrical burn + cardiac stun | scorching + system shock | burn load |
| toxin | toxic poisoning (systemic) | — | toxin load |
| asphyxia | tissue hypoxia (systemic) | — | asphyxia load |
| radiation | adds to `radiation` metric | — | burn load |
| cellular | genetic damage (systemic) | — | toxin load |
| neural | brain organ damage | processor damage (brain organ) | trauma load |
| pain | acute pain (systemic, decays) | — (unless cosmetic pain) | — |
| digestion | digestion (systemic) | corrosion | trauma load |

`—` means the biology is immune: the injury applies 0 and returns 0.

**Plan gating.** Every affliction declares `body_plans` (`BODY_PLAN_HUMANOID`
default, `_SIMPLE`, `_MACHINE`, `_ALL`) as well as `biology`. Anatomy-dependent
afflictions stay humanoid-only; venoms, poisons and occult afflictions opt in to
every plan. On a simple/machine body an affliction harms through
`simple_load_rate` (load per tick at severity 100 in its `injury_category`);
the injury that carried it still lands as immediate load. Only load counts
toward a simple body's death. Simple mobs with a reagent holder get treatment
levels, so medicines work on animals by the same tag mechanism.

**Synthetic afflictions** (`medical/conditions/synthetic.dm`) mirror the
organic diagnostic set for FBPs and robotic limbs: coolant leak → thermal
runaway, actuator misalignment, processor corruption, power fault. Injury
triggers carry a `biology` filter so synthetic parts fire synthetic triggers.
Tools: welder = `TREAT_PLATING_REPAIR`, cable = `TREAT_WIRING_REPAIR`,
multitool = `TREAT_CALIBRATION` (+ `TREAT_SYSTEM_RESTORE` on the head), coolant
reagent = `TREAT_COOLANT`.

**Simple plan**: `/mob/living/var/endurance` (was `maxHealth`) is the only
tuning number. Afflictions are whole-body `load` afflictions in points
(`/datum/affliction/load/trauma|burn|toxin|asphyxia`). Regeneration and repair
call `mend()`. `vitality()` = `1 - total_load/endurance`.

## 5. Consciousness & death (`/datum/body` + each plan's `recompute_vitals()` / `is_dead()`)

Invalidation is one bitfield, `body.dirty` (`BODY_DIRTY_*`), set through
`body.invalidate()`: `VITALS` (the cached vitals), `TREATMENT` (the treatment
snapshot: reagent change, affliction add/remove, every tick), and the trigger
domains `ORGANS` / `METRICS` / `CHEMS` that the human's
`dq_process_dirty_medical_conditions()` consumes once per Life cycle (organ
integrity changes, scalar metrics, the base `/mob/living/on_reagent_change()`).

Each Life tick, `body.life_tick()`:
1. Returns immediately if the body has no afflictions and nothing dirty
   (healthy mobs cost nothing). Humanoids (`always_evaluate`) always run.
2. Ticks afflictions through the shared pipeline (§6).
3. Recomputes the **vitals** once and caches them (humanoid:
   `compute_pain()`, `compute_consciousness()`, `compute_vitality()`, with
   the `PAIN_*` / `VITALITY_*` constants in `code/__defines/body.dm`):
   - `pain` — Σ affliction pain + limb wound load − analgesia.
   - `consciousness` — 100 − Σ affliction consciousness penalties − pain
     penalty (`max(0, pain − tolerance)`).
   - `vitality` — the worst of vital-organ and vital-part failure, injury
     afflictions and lost consciousness.
4. `evaluate_status()`: dead? (`is_dead()` per plan) → `death()`.
   Unconscious if `consciousness <= 0` → `set_stat(UNCONSCIOUS)` + crit trait.

Afflictions contribute through two declarative vars scaled by severity:
`pain_at_max`, `consciousness_at_max` (and `get_vital_effects()` for pulse/BP).
There are no special-cased thresholds anywhere else.

A component can veto death and unconsciousness by answering
`COMSIG_LIVING_BODY_STATUS` with `COMPONENT_BODY_KEEP_ALIVE` (lite godmode).

Queries every other system uses instead of `health`:

| Question | API |
|---|---|
| Alive/dead | `stat` (unchanged) |
| In crit / unconscious from injury | `L.is_critical()` |
| Fraction of wellness left (HUD, AI flee, phases, belly bars, stat panel) | `L.vitality()` → 0..1 |
| Endurance (for scaling damage to a mob's toughness) | `L.get_endurance()` (with modifiers) |
| How hurt by category (medbot, vore payout, analyzers) | `L.injury_load(INJURY_CATEGORY_*)` |
| Is it hurt at all | `L.is_injured()` |
| Specific affliction | `L.body.find_affliction(type)` / `has_affliction(type)` |
| Brain death (needs a resleeve) | `L.is_brain_dead()` → the brain organ's `is_brain_dead()` |

### 5a. Brain death, minds and mind hosts

**Brain death** is decided in one place:
`/obj/item/organ/internal/brain/proc/is_brain_dead()` — the brain is at 100%
damage or the organ is `ORGAN_DEAD`. Brain death needs a resleeve. The
humanoid plan's `is_dead()`, the defibrillator (`can_revive()`),
`check_vital_organs()`, the scanners, the MMI and the brain view all ask it.

**Identity.** `/datum/character_identity` (`code/datums/character_identity.dm`)
is owned by the mind: real name, a DNA reference, every OOC-note field,
languages, flavour text and persistent (MODIFIER_GENETIC) traits. Every
living mob holds a reference in `identity`, bound in one place,
`bind_identity()`, when a mind enters it. Nothing copies identity fields.

**Moving minds.** `transfer_mind(mind, dest, reason)` is the one logged path.
Anything that holds a mind outside a body has a `/datum/component/mind_host`
(the brain organ, MMIs, posibrains, robot intelligence circuits, protean
cores). Its API is `receive_mind()`, `release_mind()` and `adopt_occupant()`,
which moves the view between hosts, e.g. brain → MMI.

**The brain view** (`/mob/living/carbon/brain`) is the mob the client needs.
It is a thin view on its host's brain tissue: harm lands on the organ as
lesions, `mend()` repairs the organ, `vitality()`/`injury_load()` read the
organ, and its stat follows `is_brain_dead()` (`refresh_host_status()`). An
MMI'd brain keeps its lesions, so damage and treatment carry on.

## 6. Afflictions

`/datum/affliction` (`code/modules/body/affliction.dm`):
- `severity` 0–100 (or `load` in points for load afflictions), `progression_rate`,
  `stage` + `get_stages()`, `treated_by` / `worsened_by_tags`, `cured_by`
  (direct reagent pairs), `symptom_pool` / `active_symptoms` (typepaths —
  symptom datums are shared singletons), `biology` (where it may exist),
  `location` (part) or null (systemic), `pain_at_max`, `consciousness_at_max`,
  `body_plans`, `simple_load_rate`. Repeat injuries merge into the existing
  affliction of the same type at the same location (`body.afflict()` is
  find-or-create).
- Construction is always `new type(location)`; `configure(location)` is
  the virtual hook for location-dependent setup (lesions build their
  treatment table and name from the organ), so `afflict(type, organ)` makes
  a correctly configured affliction.
- Lifecycle only through `body.add_affliction()` / `body.remove_affliction()`;
  both keep `afflictions` (flat), `afflictions_by_type` and
  `afflictions_by_location` (O(1) `afflictions_at()`, `get_wounds()`,
  `get_lesions()`) in sync and send `COMSIG_BODY_AFFLICTIONS_CHANGED`.
  `body.Destroy()` removes every affliction through `remove_affliction()`, so
  `on_removed()` and the signals run.
- Every severity change sends `COMSIG_AFFLICTION_SEVERITY_CHANGED`
  `(affliction, old_severity)` on the owner. Contract telemetry (trial
  eligibility, treatment outcomes) is a listener in `code/modules/contracts`
  (`SScontracts`), which ignores wounds, lesions and load.
- **One tick pipeline** (`/datum/affliction/proc/tick()`):
  `apply_treatment(body.treatment_levels())` → `progress()` →
  `update_symptoms()` → `fire_progression_triggers()`. `apply_treatment` is
  the shared loop over `treated_by`, `worsened_by_tags`, `cured_by` and
  `worsened_by`; each treatment arrives through
  `receive_tagged_treatment(tag, amount, continuous = TRUE)`. The only
  override points are `receive_tagged_treatment()` and `progress()` (base:
  progression plus this tick's treatment, snowballing with severity).
- **Treatment snapshot**: `body.treatment_levels()` is built once per tick
  (and again only if reagents change): reagent levels at their dose scale ×
  drug interference (`interferes_with`, folded into the same build) × species
  chem strength, plus `TREAT_REGENERATION`. `body.reagent_volume(id)` and
  `body.reagent_cure_modifier(id)` read the same snapshot.
- `/datum/affliction/wound/*` — located on a limb; keeps the physical wound
  model (damage size, bleeding, bandaged/salved/clamped/disinfected, germs,
  stages, autoheal). Limb integrity (`get_trauma()` / `get_burn()`) is the sum
  of its wounds, cached on change. Wounds override `receive_tagged_treatment`
  (hemostatics run down the bleed; every other mechanism heals wound damage,
  continuous treatment at `continuous_scale`) and `progress()` (none: autoheal
  lives in the limb's `update_wounds()`).
- `/datum/affliction/lesion/*` — located on an internal organ
  (`code/modules/medical/conditions/lesions.dm`): contusion, laceration,
  perforation (hollow organs), necrosis, ischemic_injury, toxic_injury;
  `lesion/synthetic/component_fault` on prosthetic organs. Each carries
  `damage` points; organ `damage` is their sum (`recalc_integrity()`, one
  pass over the organ's own lesions through the location index), so harm goes
  through `injure(kind, amount, organ)` and healing through
  `mend(tag, amount, organ)`. Treatment is the organ's repair tag
  (hepatorenal/cardiac/respiratory/digestive/neural/ocular/tissue);
  lacerations and perforations are only stabilised by drugs
  (`is_stabilised()`) and closed by `TREAT_SURGICAL_REPAIR`; necrosis needs
  `TREAT_RESECTION`. Surgery calls `H.surgically_repair_organ(organ, amount)`:
  one budget, structural repair first, resection gets the remainder. Lesions
  override `receive_tagged_treatment` (drug floors, full-repair tags,
  `drug_efficiency`) and `progress()` (drift, untreated effects, and the
  brain's secondary injury: past 60% a brain swells — ischemic injury grows
  each tick, slowed by neural repair and overdose upsides, drugs act at a
  fraction; past 90% nothing keeps up). Lesions have no `injury_category`
  (organ integrity already feeds vitality and triggers).

### Vital systems (Airway / Breathing / Circulation)

`code/modules/medical/conditions/vital_systems.dm` models the ABCs as
afflictions with real mechanical consequences on humanoids:

| Affliction | Consequence | Cure path |
|---|---|---|
| `airway_obstruction` (choking, aspirated vomit, facial trauma) | severity ≥ 50: airway closed, **no gas exchange** | `TREAT_AIRWAY`: Heimlich (help intent on the chest), airway kit; CPR compressions shift it a little |
| `airway_edema` (allergy `AG_OXY_DMG`, inhalation burn) | severity ≥ 70: airway closed | `TREAT_VASOPRESSOR` (adrenaline, inaprovaline), `TREAT_AIRWAY` |
| `respiratory_arrest` (oxycodone OD, brain herniation, hypoxia ≥ 85) | severity ≥ 40: no spontaneous breaths | `TREAT_VENTILATION` (bag-valve mask, CPR rescue breaths) breathes *for* the patient; the drive recovers once nothing sustains it |
| `pneumothorax` (sharp chest injury, perforated lung lesion) | tension at ≥ 60: asphyxia + lung damage | `TREAT_DECOMPRESSION` (needle, chest tube surgery); an unstabilised lung perforation refills it until surgically repaired |
| `cardiac_arrhythmia` | rhythm state below | `TREAT_DEFIBRILLATION`, `TREAT_CHEST_COMPRESSION`, `TREAT_VASOPRESSOR`, `TREAT_CARDIAC` |

Breathing hook: `/mob/living/carbon/proc/breath_blocked()` (human override:
closed airway, or apneic and not ventilated) makes `breathe()` take no breath,
so `handle_breath(null)` builds tissue hypoxia exactly like vacuum.

Rhythm (`CARDIAC_RHYTHM_*`): **sinus** (post-conversion, settles and resolves)
→ **tachy** (perfusing, climbs toward VF; cardiac drugs settle it, stimulants
worsen it) → **VF** (no output, shockable, decays to asystole) → **asystole**
(no output, *not* shockable; a vasopressor in the blood + compressions
coarsen it to VF). Without output the patient is unconscious
(`consciousness_at_max` 200), takes `INJURY_ASPHYXIA` and anoxic brain
lesions (`lesion/ischemic_injury`) every tick; compressions within the last
7 s cut both to 35%. `handle_pulse()` reads `has_cardiac_output()`; the
defibrillator's rhythm analysis (`can_defib`) refuses asystole and perfusing
rhythms, cardioverts living VF, and converts a fibrillating corpse before
revival. Heart-stopping chems (`potassium_chloride` OD, chlorophoride), heart
failure's Critical stage, strong electrocution and deep hypoxia all
`induce_arrhythmia()`. Instant mechanisms reach afflictions through `mend()`;
afflictions reinterpret them in `receive_tagged_treatment()` (ventilation
sets a ventilated window, defibrillation converts the rhythm) rather than
treating severity. Readouts: `cardiac_rhythm_reading()` on the health analyser
and vitals monitor; symptoms `choking`, `stridor`, `absent_breath_sounds`,
`tracheal_deviation`, `absent_pulse`, `rhythm_finding/*`.

Biology declaration: an affliction's `biology` flags say where it can exist; a
treatment tag's biology says what it can treat; a body part's biology decides
the default injury response. That is the whole synthetic/organic system — no
`isSynthetic()` branches at call sites.

## 7. Species & modifiers

- Species `injury_mods` (flat list indexed by `INJURY_*`) replaces
  `brute_mod`/`burn_mod`/`oxy_mod`/`toxins_mod`/`pain_mod`. `NO_POISON`,
  `NO_PAIN`, no-lungs etc. become `injury_mods[kind] = 0` at species setup.
- `/datum/modifier`: `incoming_injury_percent` (all) and per-category
  `incoming_physical_percent`, `incoming_thermal_percent`,
  `incoming_toxic_percent`, `incoming_asphyxia_percent`,
  `incoming_genetic_percent`, `incoming_pain_percent`; energy shields use
  `effective_physical/thermal/toxic/asphyxia/genetic/pain_resistance`;
  `max_health_flat/percent` → `endurance_flat/percent`.

## 8. Performance & memory rules

- Healthy mobs allocate nothing: all body lists are lazy.
- Vitals computed once per tick, cached; queries recompute only when dirty.
  `injure()` marks them dirty and runs a cheap death check.
- One treatment snapshot per body per tick (not one per affliction).
- Location lookups go through `afflictions_by_location`.
- Treatment tags and injury kinds are `#define` ints indexing flat lists.
- Symptoms are singletons; afflictions store typepaths.
- No list allocation on the injury hot path.

## 9. Migration map (old → new)

| Old | New |
|---|---|
| `adjustBruteLoss(x)` x>0 | `injure(INJURY_BLUNT, x, ...)` (or CUT/PIERCE if sharp) |
| `adjustFireLoss(x)` x>0 | `injure(INJURY_BURN, x, ...)` (FROSTBITE for cold, CORROSIVE for acid, ELECTRIC for shock) |
| `adjustToxLoss(x)` x>0 | `injure(INJURY_TOXIN, x, ...)` (+ `affliction =` a specific poison where it deserves one) |
| `adjustOxyLoss(x)` x>0 | `injure(INJURY_ASPHYXIA, x)` |
| `adjustCloneLoss(x)` x>0 | `injure(INJURY_CELLULAR, x)` |
| `adjustHalLoss(x)` x>0 / agony | `injure(INJURY_PAIN, x)` |
| `adjustBrainLoss(x)` x>0 | `injure(INJURY_NEURAL, x)` |
| negative adjust / heal_* | `mend(TREAT_*, x)` — tag by what heals (tissue repair, burn care, antitoxin, oxygenation, genetic repair, neural repair, analgesic, plating/wiring repair) |
| `organ.take_damage(x, silent, lesion)` | `injure(kind, x, organ, source, affliction = lesion)` |
| `limb.take_damage(brute, burn, sharp, edge)` | `injure(INJURY_BLUNT/CUT/PIERCE/BURN, x, limb, source)` |
| `organ.heal_damage(x, LESION_HEAL_*)`, `limb.heal_damage(b, u)` | `mend(tag, x, organ_or_limb)`; admin/magic/species: `TREAT_RESTORATION` |
| passive organ healing, `organ_decay/brain.dm` | `TREAT_REGENERATION`; brain swelling as lesion drift |
| `dq_medical_dirty` / `DQ_MEDICAL_DIRTY_*` | `body.dirty` / `BODY_DIRTY_*` |
| `apply_damage(x, TYPE, zone, blocked, sharp, edge, src)` | `injure(kind, x, zone, src, blocked)` |
| `take_overall_damage(b, f)` | `injure(...)` per kind with `zone = null` |
| `health`, `health/maxHealth` | `vitality()` |
| `health <= 0`, `health < get_crit_point()` | `is_critical()` |
| `maxHealth`, `getMaxHealth()` | `get_endurance()`; subtype tuning `maxHealth = N` → `endurance = N` |
| `getBruteLoss()` etc. | `injury_load(INJURY_CATEGORY_PHYSICAL)` etc.; per limb `E.get_trauma()` / `E.get_burn()` |
| `rejuvenate`/`revive` heals | `fully_heal()` |
| `updatehealth()` | delete — vitals are recomputed by the body |
| `brute_dam` / `burn_dam` (limb) | `get_trauma()` / `get_burn()` (read-only) |
| `/datum/wound` | `/datum/affliction/wound` |
| `/datum/medical_issue/condition` | `/datum/affliction` |
| `/datum/dq_cause` | `/datum/affliction_trigger` |
| `/datum/medical_symptom` | `/datum/affliction_symptom` |

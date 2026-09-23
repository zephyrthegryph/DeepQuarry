// Body & affliction system defines. See doc/body_architecture.md.

// --- Injury kinds -----------------------------------------------------------
// WHAT physically happened. Flat-list indices — keep contiguous from 1.
#define INJURY_BLUNT      1
#define INJURY_CUT        2
#define INJURY_PIERCE     3
#define INJURY_BURN       4
#define INJURY_FROSTBITE  5
#define INJURY_CORROSIVE  6
#define INJURY_ELECTRIC   7
#define INJURY_TOXIN      8
#define INJURY_RADIATION  9
#define INJURY_CELLULAR   10
#define INJURY_NEURAL     11
#define INJURY_PAIN       12
#define INJURY_DIGESTION  13
#define INJURY_KIND_COUNT 13

// --- Injury categories --------------------------------------------------------
// Coarse groupings used by modifiers, armour-style resistances and load
// queries (the successors of brute / fire / tox / clone / hal). Lack of
// oxygen is not an injury: the physiology computes it (oxygen_debt()).
#define INJURY_CATEGORY_PHYSICAL  1
#define INJURY_CATEGORY_THERMAL   2
#define INJURY_CATEGORY_TOXIC     3
#define INJURY_CATEGORY_GENETIC   4
#define INJURY_CATEGORY_NEURAL    5
#define INJURY_CATEGORY_PAIN      6
#define INJURY_CATEGORY_COUNT     6

// injure() flags
/// Skip modifiers/species multipliers (admin, scripted exact amounts).
#define INJURE_IGNORE_RESISTANCE (1<<0)
/// Don't flash pain / play pain emotes.
#define INJURE_SILENT            (1<<1)
/// The source was a projectile (dismemberment odds, etc).
#define INJURE_PROJECTILE        (1<<2)
/// The harm arrives from outside the body (a weapon, projectile, thrown
/// object, animal, trap, falling debris): injure() applies armour for the hit
/// part and kind as mitigation stage 1.
#define INJURE_ARMORED           (1<<3)

// --- Armour kinds -------------------------------------------------------------
// Armour is asked for by the INJURY_* kind it resists (injury_armor(kind, zone)),
// plus ARMOR_BLAST for explosive shockwaves. Body factors add BF_ARMOR(kind).
#define ARMOR_BLAST       (INJURY_KIND_COUNT + 1)
#define ARMOR_KIND_COUNT  (INJURY_KIND_COUNT + 1)

// --- injure() mitigation stages (the explain facility) --------------------------
#define INJURY_STAGE_ARMOR   "armour"
#define INJURY_STAGE_SHIELD  "shield"
#define INJURY_STAGE_FACTORS "factors"
#define INJURY_STAGE_BODY    "body"

// --- Biology -------------------------------------------------------------------
// What a body part (or a whole body) is made of. Afflictions declare which
// biologies they can exist on; treatment tags declare which they work on.
#define BIOLOGY_ORGANIC   (1<<0)
#define BIOLOGY_SYNTHETIC (1<<1)
#define BIOLOGY_NANOFORM  (1<<2)
#define BIOLOGY_ALL       (BIOLOGY_ORGANIC | BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM)

// --- Treatment tags --------------------------------------------------------------
// Healing MECHANISMS. Strings: they are association-list keys (DM forbids
// numeric keys in list literals).
#define TREAT_HEMOSTATIC       "hemostatic"   // stops bleeding
#define TREAT_TISSUE_REPAIR    "tissue_repair"   // soft-tissue / bruise / cut repair
#define TREAT_BONE_REPAIR      "bone_repair"   // fracture knitting
#define TREAT_BURN_CARE        "burn_care"   // burn / skin repair
#define TREAT_ANTIMICROBIAL    "antimicrobial"   // kills infection
#define TREAT_ANTITOXIN        "antitoxin"   // clears blood toxins
#define TREAT_OXYGENATION      "oxygenation"   // raises tissue oxygen
#define TREAT_NEURAL_REPAIR    "neural_repair"   // brain / nerve repair
#define TREAT_CARDIAC          "cardiac"   // heart repair
#define TREAT_RESPIRATORY      "respiratory"  // lung repair
#define TREAT_HEPATORENAL      "hepatorenal"  // liver / kidney repair
#define TREAT_OCULAR           "ocular"  // eye repair
#define TREAT_ANTIRADIATION    "antiradiation"  // purges radiation
#define TREAT_GENETIC_REPAIR   "genetic_repair"  // repairs cellular / DNA damage
#define TREAT_THERMOREGULATION "thermoregulation"  // normalises core temperature
#define TREAT_BLOOD_RESTORE    "blood_restore"  // rebuilds blood volume
#define TREAT_CIRCULATORY      "circulatory"  // stabilises circulation / blood pressure
#define TREAT_ANALGESIC        "analgesic"  // pain relief
#define TREAT_STIMULANT        "stimulant"  // raises heart rate / BP (harmful to bleeders)
#define TREAT_PLATING_REPAIR   "plating_repair"  // synthetic: structural / plating repair (welder, nanopaste)
#define TREAT_WIRING_REPAIR    "wiring_repair"  // synthetic: wiring / burn repair (cable, nanopaste)
#define TREAT_SYSTEM_RESTORE   "system_restore"  // synthetic: processor / system faults
#define TREAT_COOLANT          "coolant"  // synthetic: coolant replenishment (coolant reagent)
#define TREAT_CALIBRATION      "calibration"  // synthetic: actuator / sensor recalibration (multitool)
#define TREAT_SURGICAL_REPAIR  "surgical_repair"  // operative closure of torn / perforated organ tissue
#define TREAT_RESECTION        "resection"  // surgical removal of dead (necrotic) tissue
// Vital-system mechanisms (code/modules/medical/conditions/vital_systems.dm).
#define TREAT_AIRWAY           "airway"  // clears / secures the airway (Heimlich, airway kit)
#define TREAT_DECOMPRESSION    "decompression"  // vents trapped pleural air (decompression needle, chest tube)
#define TREAT_DEFIBRILLATION   "defibrillation"  // electrical cardioversion of a shockable rhythm (defibrillator)
#define TREAT_CHEST_COMPRESSION "chest_compression"  // CPR compressions: partial perfusion while the heart is stopped
#define TREAT_VASOPRESSOR      "vasopressor"  // epinephrine-type: coaxes asystole toward VF, shrinks airway swelling
#define TREAT_DIGESTIVE        "digestive"  // stomach / intestine / appendix tissue repair
// Field stabilisation mechanisms (code/modules/medical/stabilisation/).
#define TREAT_WOUND_PACKING    "wound_packing"  // packs / dresses a bleeding wound shut (hemostatic gauze, pressure bandage); amount = wounds
#define TREAT_OCCLUSIVE_SEAL   "occlusive_seal"  // airtight seal over an open chest wound (chest seal); amount = wounds
// Body-provided mechanisms.
#define TREAT_REGENERATION     "regeneration"  // natural regeneration: species x nutrition x sleep (body.regeneration_level())
#define TREAT_RESTORATION      "restoration"  // admin / magic / species restoration: every biology, full repair of every restorable affliction
#define TREAT_FEEDSTOCK        "feedstock"  // nanoform: steel fed into the refactory (amount = repair points of steel)
// Surgical mechanisms (code/modules/surgery/). Delivered only by instant mend() from a
// procedure step; no reagent provides them.
#define TREAT_SURGICAL_CLOSURE "surgical_closure"  // closes an organic incision (cautery, sutures)
#define TREAT_PANEL_CLOSURE    "panel_closure"  // synthetic: closes and secures a maintenance panel
#define TREAT_BONE_SETTING     "bone_setting"  // sets a fracture, closes a sawn bone layer (bone gel, bone setter)
#define TREAT_VESSEL_REPAIR    "vessel_repair"  // repairs a torn vessel or arterial bleed (FixOVein)
#define TREAT_TENDON_REPAIR    "tendon_repair"  // rejoins a severed tendon
#define TREAT_FOREIGN_BODY_REMOVAL "foreign_body_removal"  // extracts foreign objects and embedded material
#define TREAT_LITHOTRIPSY      "lithotripsy"  // breaks up deposits with focused ultrasound

// --- Cardiac rhythms (/datum/affliction/cardiac_arrhythmia) ------------------------------
/// Normal rhythm; the arrhythmia is settling and will resolve.
#define CARDIAC_RHYTHM_SINUS    1
/// Fast, unstable but perfusing. Untreated it degenerates to VF.
#define CARDIAC_RHYTHM_TACHY    2
/// Ventricular fibrillation: no output, shockable.
#define CARDIAC_RHYTHM_VF       3
/// Asystole: flatline, no output, NOT shockable.
#define CARDIAC_RHYTHM_ASYSTOLE 4

/// Seconds of assisted breathing one CPR cycle of rescue breaths provides.
#define CPR_RESCUE_BREATH_SECONDS 10
/// How long one CPR compression cycle holds cardiac output at its floor.
#define CPR_COMPRESSION_WINDOW (7 SECONDS)

// --- Body invalidation domains (/datum/body/var/dirty, body.invalidate()) -----------------
/// Cached vitals (pain, consciousness, vitality) are stale.
#define BODY_DIRTY_VITALS    (1<<0)
/// Organ integrity changed: organ-integrity triggers (emergent afflictions) re-run.
#define BODY_DIRTY_ORGANS    (1<<1)
/// A scalar metric (radiation, temperature, neural load) may have changed.
#define BODY_DIRTY_METRICS   (1<<2)
/// Reagents changed: chem-caused afflictions re-run.
#define BODY_DIRTY_CHEMS     (1<<3)
/// The treatment snapshot (treatment_levels()) must be rebuilt.
#define BODY_DIRTY_TREATMENT (1<<4)
/// The trigger domains dq_process_dirty_medical_conditions() consumes.
/// Body factors (code/modules/body/factors.dm) must be recomputed.
#define BODY_DIRTY_FACTORS   (1<<5)
/// The physiology (ventilation, oxygenation, perfusion, delivery) must be
/// recomputed: a factor, support, organ, breath or blood volume changed.
#define BODY_DIRTY_PHYSIOLOGY (1<<6)
#define BODY_DIRTY_CONDITIONS (BODY_DIRTY_ORGANS | BODY_DIRTY_METRICS | BODY_DIRTY_CHEMS)
#define BODY_DIRTY_ALL       (BODY_DIRTY_VITALS | BODY_DIRTY_CONDITIONS | BODY_DIRTY_TREATMENT | BODY_DIRTY_FACTORS | BODY_DIRTY_PHYSIOLOGY)

// --- Natural regeneration (TREAT_REGENERATION) ---------------------------------------------
/// Regeneration level of a fed, awake, living humanoid.
#define REGENERATION_BASE_LEVEL 1
/// Sleeping multiplies the regeneration level.
#define REGENERATION_SLEEP_MULT 2
/// A hungry body regenerates at this fraction; a starving one not at all.
#define REGENERATION_HUNGRY_MULT 0.5
/// Nutrition below which a body counts as hungry / starving for regeneration.
#define REGENERATION_HUNGRY_NUTRITION 250
#define REGENERATION_STARVING_NUTRITION 50

// --- Body plans -----------------------------------------------------------------------
// Which body plans an affliction can exist on. Anatomy-dependent afflictions
// stay humanoid-only; creature/poison/magic afflictions opt in to the others.
#define BODY_PLAN_HUMANOID (1<<0)
#define BODY_PLAN_SIMPLE   (1<<1)
#define BODY_PLAN_MACHINE  (1<<2)
#define BODY_PLAN_ALL      (BODY_PLAN_HUMANOID | BODY_PLAN_SIMPLE | BODY_PLAN_MACHINE)

// --- Severity -------------------------------------------------------------------------
#define AFFLICTION_SEVERITY_MILD      25
#define AFFLICTION_SEVERITY_MODERATE  50
#define AFFLICTION_SEVERITY_SEVERE    75
#define AFFLICTION_SEVERITY_TERMINAL  100

// Symptoms surface / fade when severity crosses a multiple of this.
#define AFFLICTION_SYMPTOM_BAND 30

// Per-tick severity climb at progression_rate 1.0 (≈10 min 0 -> 100 with the
// severity-acceleration multiplier; see affliction.dm).
#define AFFLICTION_BASE_PROGRESSION 0.18

// Reference dose for chemical treatment scaling, and its cap multiple.
#define DQ_CHEM_STANDARD_DOSE 10
#define DQ_CHEM_DOSE_CAP 4.0

// --- Consciousness & death ---------------------------------------------------------------
/// Consciousness at or below this = unconscious.
#define CONSCIOUSNESS_THRESHOLD 0
/// Pain tolerance as a fraction of a humanoid's species total_health. Pain
/// above tolerance subtracts 1:1 from consciousness, so a patient passes out
/// at tolerance + 100 pain.
#define PAIN_TOLERANCE_FRACTION 0.5
/// Vital body parts (head, chest, groin) are destroyed — and the patient
/// dies — at this multiple of their rated integrity.
#define DQ_VITAL_PART_LETHAL_MULT 2
/// Patients who feel no pain go unconscious when a vital part reaches this
/// multiple of its rated integrity (structural failure).
#define DQ_VITAL_PART_CRIT_MULT 1
/// Pain per point of wound load on a limb that can feel it.
#define PAIN_PER_LIMB_DAMAGE 1.2
/// Pain from a broken bone in a limb.
#define PAIN_BROKEN_BONE 30
/// Pain from a dislocated joint.
#define PAIN_DISLOCATION 15
/// Pain masked by slurring intoxication (alcohol and the like).
#define PAIN_SLURRING_RELIEF 20
/// Weight of the worst injury affliction's severity in the vitality readout.
#define VITALITY_AFFLICTION_WEIGHT 0.5
/// Weight of lost consciousness in the vitality readout.
#define VITALITY_CONSCIOUSNESS_WEIGHT 0.5
/// Prosthetic internal organs take this fraction of the damage dealt to them.
#define PROSTHETIC_ORGAN_DAMAGE_MULT 0.8
/// Robots and AIs are destroyed at this multiple of their endurance.
#define DQ_MACHINE_LETHAL_MULT 2

// Hypoxia: oxygen debt at which the brain starts dying, and peak ischemic
// brain lesion damage per second at a debt of 100.
#define DQ_HYPOXIA_BRAIN_DAMAGE 30
#define DQ_HYPOXIA_BRAIN_RATE 0.75

// --- Physiology (code/modules/body/physiology.dm) ------------------------------------------
/// Delivery below this fraction of demand builds oxygen debt.
#define PHYSIOLOGY_CRITICAL_RATIO 0.6
/// Oxygen debt gained per second per unit of shortfall.
#define PHYSIOLOGY_DEBT_RATE 1.7
/// Oxygen debt repaid per second per unit of delivery above the critical ratio.
#define PHYSIOLOGY_REPAY_RATE 2.5
/// Oxygen debt never climbs past this.
#define PHYSIOLOGY_DEBT_MAX 150
/// Changes in blood volume fraction smaller than this don't dirty the physiology.
#define PHYSIOLOGY_BLOOD_EPSILON 0.005
/// Changes in breath quality smaller than this don't dirty the physiology.
#define PHYSIOLOGY_BREATH_EPSILON 0.02
/// Ventilation below this counts as not breathing (no breath is drawn).
#define PHYSIOLOGY_APNEA_VENTILATION 0.05
/// Oxygen debt is logged each time it crosses a multiple of this.
#define PHYSIOLOGY_DEBT_LOG_BAND 25
// Supports: the floors equipment and hands provide.
/// Bag-valve mask: breathing-drive floor while squeezing.
#define SUPPORT_BVM_DRIVE 0.8
/// Rescue breaths during CPR: breathing-drive floor.
#define SUPPORT_RESCUE_BREATH_DRIVE 0.5
/// Chest compressions: cardiac-output floor.
#define SUPPORT_CPR_PUMP 0.4

/// Default endurance for a living mob that doesn't set one.
#define DEFAULT_ENDURANCE 100

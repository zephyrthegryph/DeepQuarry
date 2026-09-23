// Body factors: the unified stat layer. See doc/health_system_review.md §5.3
// and code/modules/body/factors.dm.
//
// A body factor is a named quantity that any number of sources contribute to
// (afflictions, reagents, modifiers, species and traits, forms, worn
// equipment) and any number of consumers read with `L.factor(BF_X)`.
// Every factor has one combine rule, a baseline and bounds, registered once in
// body_factor_defs(). Sources declare static alist tables keyed by these ids,
// e.g. `factors = alist(BF_SLOWDOWN = 1, BF_ACCURACY = -20)`.
//
// Flat-list indices: keep contiguous from 1 and keep BF_COUNT last.

// --- Combine rules -----------------------------------------------------------
/// Product of contributions. A table value `f` at scale `s` contributes
/// `1 - (1 - f) * s` (never below 0).
#define BF_RULE_MULT  1
/// Sum of contributions. A value `f` at scale `s` contributes `f * s`.
#define BF_RULE_ADD   2
/// Highest contribution (and the baseline) wins.
#define BF_RULE_MAX   3
/// Lowest contribution (and the baseline) wins.
#define BF_RULE_MIN   4
/// Bitfield OR of every contribution with a positive scale.
#define BF_RULE_FLAGS 5

// --- Physiology (placeholders the vital systems will read) -------------------
#define BF_AIRWAY            1  // mult: airway patency
#define BF_RESP_DRIVE        2  // mult: spontaneous breathing drive
#define BF_LUNG_MECHANICS    3  // mult: chest wall and lung expansion
#define BF_GAS_EXCHANGE      4  // mult: alveolar exchange
#define BF_PUMP              5  // mult: cardiac output (synthetic: power delivery)
#define BF_CIRCULATION       6  // mult: vascular tone (synthetic: coolant circulation)
#define BF_DEMAND            7  // mult: metabolic demand
#define BF_PROGRESSION       8  // mult: how fast afflictions progress
#define BF_METABOLISM        9  // mult: reagent processing rate (and hunger)
#define BF_BLEEDING          10 // mult: bleed rate
#define BF_HEALING           11 // mult: natural regeneration
#define BF_ANALGESIA         12 // add: pain relief (points)
#define BF_PAIN              13 // add: extra pain (points)
#define BF_SEDATION          14 // add: consciousness reduction (points)
#define BF_ARRHYTHMIA_RISK   15 // add: hazard of rhythm deterioration
#define BF_HEART_RATE        16 // add: heart-rate drive, bpm (readout)
// --- Vital-sign readouts ------------------------------------------------------
#define BF_TEMPERATURE       17 // add: core temperature offset, °C (readout)
#define BF_BP_SYSTOLIC       18 // add: systolic offset, mmHg (readout)
#define BF_BP_DIASTOLIC      19 // add: diastolic offset, mmHg (readout)
#define BF_O2_SAT            20 // add: oxygen saturation offset, % (readout)
#define BF_RESP_RATE         21 // add: respiratory-rate offset, /min (readout)
// --- Combat and mobility ------------------------------------------------------
#define BF_SLOWDOWN          22 // add: movement delay
#define BF_PENALTY_SCALE     23 // mult: scale applied to positive movement penalties
#define BF_HASTE             24 // max: 1 = ignore every slowdown and move at top speed
#define BF_ACCURACY          25 // add: ranged accuracy (%)
#define BF_DISPERSION        26 // add: ranged dispersion
#define BF_EVASION           27 // add: chance to be missed (%)
#define BF_ATTACK_SPEED      28 // mult: attack (click) delay
#define BF_MELEE_DAMAGE      29 // mult: outgoing melee and unarmed damage
// --- Senses -------------------------------------------------------------------------
#define BF_VISION            30 // mult: visual acuity
#define BF_HEARING           31 // mult: hearing
#define BF_MOTOR_CONTROL     32 // mult: fine motor control (below 1: dropped items)
#define BF_DARKSIGHT         33 // max: 1 = sees in the dark
#define BF_SIGHT_FLAGS       34 // flags: SEE_* sight flags granted
#define BF_ACTION_BLOCKS     35 // flags: ACTION_BLOCK_* blocked actions
// --- Harm -------------------------------------------------------------------------------
#define BF_INCOMING_ALL      36 // mult: every incoming injury
/// Per-category incoming injury multiplier: BF_INCOMING_ALL + INJURY_CATEGORY_*.
#define BF_INCOMING(category) (BF_INCOMING_ALL + (category))
#define BF_INCOMING_PHYSICAL 37 // mult (INJURY_CATEGORY_PHYSICAL)
#define BF_INCOMING_THERMAL  38 // mult (INJURY_CATEGORY_THERMAL)
#define BF_INCOMING_TOXIC    39 // mult (INJURY_CATEGORY_TOXIC)
#define BF_INCOMING_GENETIC  40 // mult (INJURY_CATEGORY_GENETIC)
#define BF_INCOMING_NEURAL   41 // mult (INJURY_CATEGORY_NEURAL)
#define BF_INCOMING_PAIN     42 // mult (INJURY_CATEGORY_PAIN)
#define BF_DISABLE_DURATION  43 // mult: stun / weaken / paralysis / sleep / confusion durations
#define BF_HEALING_RECEIVED  44 // mult: every mend() the mob receives
#define BF_ENDURANCE_FLAT    45 // add: toughness points
#define BF_ENDURANCE_MULT    46 // mult: toughness
#define BF_ICON_SCALE_X      47 // mult: sprite width
#define BF_ICON_SCALE_Y      48 // mult: sprite height
#define BF_PAIN_IMMUNITY     49 // max: 1 = feels no pain
#define BF_PULSE_SHIFT       50 // add: pulse-level shift (PULSE_* steps)
#define BF_PULSE_SET         51 // max: forced pulse level (baseline -1 = none)
#define BF_EMP_SHIFT         52 // add: added to EMP severity (higher = weaker)
#define BF_EXPLOSION_SHIFT   53 // add: added to explosion severity (higher = weaker)
#define BF_HEAT_EXPOSURE     54 // mult: share of environmental heat that reaches the body
#define BF_COLD_EXPOSURE     55 // mult: share of environmental cold that reaches the body
#define BF_SIEMENS           56 // mult: electrical conductivity
// --- Chemistry (the old per-tick chemical channels) -------------------------------------
#define BF_STABILIZATION     57 // add: cardiorespiratory stabilisation (inaprovaline)
#define BF_ANTIMICROBIAL     58 // add: antibiotic strength
#define BF_BLOOD_REGEN       59 // add: blood regenerated per tick (units)
#define BF_INTOXICATION      60 // add: alcohol intoxication
#define BF_HEPATOTOXICITY    61 // add: liver toxicity from alcohol
#define BF_ANTIEMETIC        62 // add: vomiting suppression
#define BF_ALLERGY           63 // add: allergic reaction strength
#define BF_WITHDRAWAL        64 // add: withdrawal strain on the organs
#define BF_NEURAL_REPAIR     65 // add: extra brain-lesion repair per tick
#define BF_IMMUNE_SUPPRESSION 66 // add: immune suppression
// --- Oxygen transport (physiology, code/modules/body/physiology.dm) --------------------------
#define BF_O2_CARRIAGE       67 // mult: oxygen the blood carries per unit of saturation (carbon monoxide lowers it; oximeters can't see it)
#define BF_TISSUE_UPTAKE     68 // mult: oxygen the tissues can use from what arrives (cyanide lowers it)
// --- Stabilisation ----------------------------------------------------------------------
/// max: share of life processes suspended, 0..1 (stasis bags, sleepers, cryopods).
/// The body's stasis clock (code/modules/medical/stabilisation/stasis.dm) reads it once
/// per Life() cycle; afflictions, metabolism, breathing and blood skip paused cycles.
#define BF_STASIS            69
/// Stasis deeper than this keeps the patient asleep.
#define STASIS_SLEEP_THRESHOLD 0.5
// --- Armour -----------------------------------------------------------------------------
/// Armour points against one armour kind (INJURY_* or ARMOR_BLAST), added to
/// worn / natural armour. BF_ARMOR(INJURY_BLUNT) .. BF_ARMOR(ARMOR_BLAST).
/// BF_ARMOR(1) is the first id after the last named factor.
#define BF_ARMOR_BASE        69
#define BF_ARMOR(kind)       (BF_ARMOR_BASE + (kind))
#define BF_COUNT             (BF_ARMOR_BASE + ARMOR_KIND_COUNT)

// --- Action blocks (BF_ACTION_BLOCKS) ------------------------------------------------------
/// Can't speak (airway closed, respiratory failure).
#define ACTION_BLOCK_SPEECH     (1<<0)
/// Can't perform surgery.
#define ACTION_BLOCK_SURGERY    (1<<1)
/// Can't hold anything in the left hand.
#define ACTION_BLOCK_HOLD_LEFT  (1<<2)
/// Can't hold anything in the right hand.
#define ACTION_BLOCK_HOLD_RIGHT (1<<3)

/// Afflictions only trigger a factor recompute when severity crosses a band
/// this wide (the contribution uses the severity at the recompute).
#define BF_SEVERITY_BAND 10

/// Highest per-tick chance (%) that poor motor control drops a held item.
#define BF_MAX_DROP_CHANCE 25

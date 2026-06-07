// Authored cause records.
//
// Every cause subtype's setup() populates name, description, the
// rule-specific fields (wound_class, organ, threshold, ...), and one
// or more produces entries via declare(). The registry instantiates
// these once at first access; the runtime dispatchers and the book
// both read from the same data.
//
// Authoring style: one subtype per cause, name and description in
// English (not jargon). For damage_event causes the description should
// finish the sentence "This cause fires when ___."

// --- Damage-event causes ------------------------------------------------

// -- Blunt impacts ----
//
// One cause per region; outcomes inside use per-outcome `threshold`
// (= min damage for that outcome) so a single cause covers both light
// bruising and lung contusion thresholds.

/datum/dq_cause/damage_event/blunt_torso
	name = "Blunt impact to the torso"
	subcategory = "Blunt impact"
	description = "A heavy strike to the chest or abdomen — a fall, a thrown object, a body blow. Bruising forms beneath the skin; a hard enough impact can bruise the lung underneath."
	wound_class = "blunt"
	body_regions = list(BP_TORSO)
	min_damage = 5

/datum/dq_cause/damage_event/blunt_torso/setup()
	..()
	declare(/datum/medical_issue/condition/deep_bruising,       chance = 35)
	declare(/datum/medical_issue/condition/pulmonary_contusion, chance = 40, threshold = 10)


/datum/dq_cause/damage_event/blunt_head
	name = "Blunt impact to the head"
	subcategory = "Blunt impact"
	description = "A strike to the head. The first impact tends to concussion; a second on top of an existing concussion produces a far more serious subdural hematoma."
	wound_class = "blunt"
	body_regions = list(BP_HEAD)
	min_damage = 5

/datum/dq_cause/damage_event/blunt_head/setup()
	..()
	declare(/datum/medical_issue/condition/subdural_hematoma, chance = 50, requires_present = /datum/medical_issue/condition/concussion)
	declare(/datum/medical_issue/condition/concussion,        chance = 50, requires_absent  = /datum/medical_issue/condition/concussion)


// -- Sharp injuries ----

/datum/dq_cause/damage_event/sharp_torso
	name = "Sharp injury to the torso"
	subcategory = "Sharp injury"
	description = "A cut or piercing wound to the chest or abdomen — knife, gunshot, jagged metal. Internal bleeding is common; deep wounds can pierce the pleural cavity."
	wound_class = "sharp"
	body_regions = list(BP_TORSO, BP_GROIN)
	min_damage = 5

/datum/dq_cause/damage_event/sharp_torso/setup()
	..()
	declare(/datum/medical_issue/condition/internal_hemorrhage, chance = 40)
	declare(/datum/medical_issue/condition/tension_pneumothorax, chance = 30, threshold = 15)


/datum/dq_cause/damage_event/sharp_limb
	name = "Sharp injury to a limb"
	subcategory = "Sharp injury"
	description = "A cut to an arm or leg. Shallow cuts risk tendon or nerve disruption; deeper ones can sever an artery and bleed dangerously fast."
	wound_class = "sharp"
	body_regions = list("limb")
	min_damage = 10

/datum/dq_cause/damage_event/sharp_limb/setup()
	..()
	declare(/datum/medical_issue/condition/tendon_severed,   chance = 25, threshold = 10)
	declare(/datum/medical_issue/condition/nerve_damage,     chance = 20, threshold = 15)
	declare(/datum/medical_issue/condition/lacerated_artery, chance = 35, threshold = 20)


// -- Burns ----

/datum/dq_cause/damage_event/burn_head
	name = "Burn injury to the head or face"
	subcategory = "Burns"
	description = "Heat or chemical injury to the face and airway. The upper airway swells and gas exchange suffers."
	wound_class = "burn"
	body_regions = list(BP_HEAD)
	min_damage = 10

/datum/dq_cause/damage_event/burn_head/setup()
	..()
	declare(/datum/medical_issue/condition/airway_burn, chance = 50)


/datum/dq_cause/damage_event/burn_cumulative
	name = "Extensive body burns"
	subcategory = "Burns"
	description = "Burns spread across enough of the body that fluid balance fails and systemic shock sets in."
	wound_class = "burn"
	body_regions = null  // any
	min_damage = 1
	min_cumulative_damage = 25

/datum/dq_cause/damage_event/burn_cumulative/setup()
	..()
	declare(/datum/medical_issue/condition/burn_shock, chance = 100)


/datum/dq_cause/damage_event/burn_limb_severe
	name = "Severe limb burns"
	subcategory = "Burns"
	description = "Deep burns to a limb cause swelling within the muscle compartment. Pressure builds and tissue suffocates."
	wound_class = "burn"
	body_regions = list("limb")
	min_damage = 15
	min_cumulative_damage = 30

/datum/dq_cause/damage_event/burn_limb_severe/setup()
	..()
	declare(/datum/medical_issue/condition/compartment_syndrome, chance = 40)


// -- Bone ----

/datum/dq_cause/damage_event/bone_fracture
	name = "Broken bone"
	subcategory = "Bone"
	description = "A bone has fractured. Without setting, the surrounding tissue grinds against the broken edges with every movement."
	wound_class = "broken_bone"  // pseudo-class; dispatcher emits it when ORGAN_BROKEN flips
	body_regions = null
	min_damage = 0

/datum/dq_cause/damage_event/bone_fracture/setup()
	..()
	declare(/datum/medical_issue/condition/untreated_fracture, chance = 60)


// --- Organ-damage causes ------------------------------------------------
//
// One cause per organ. Each cause carries tiered outcomes (Moderate /
// Severe / Critical) with their own thresholds; the emergent dispatcher
// walks outcomes individually so different downstream conditions emerge
// at different damage levels. The cause's `threshold_pct` is a default
// for outcomes that don't override.

/datum/dq_cause/organ_damage/brain
	name = "Brain damage"
	description = "Injury to the brain itself. Mild loss of cognition starts well before severe neurological collapse, and pressure-driven herniation is the end of the line."
	subcategory = "Organ damage"
	organ = O_BRAIN

/datum/dq_cause/organ_damage/brain/setup()
	..()
	declare(/datum/medical_issue/condition/brain_damage, threshold = 40, tier = "Significant")
	declare(/datum/medical_issue/condition/brain_damage, threshold = 80, tier = "Critical")


/datum/dq_cause/organ_damage/heart
	name = "Heart damage"
	description = "Injury to the heart itself. As pump output falls, perfusion suffers; once the pump fails outright, cardiac arrest follows."
	subcategory = "Organ damage"
	organ = O_HEART

/datum/dq_cause/organ_damage/heart/setup()
	..()
	declare(/datum/medical_issue/condition/heart_damage, threshold = 50, tier = "Moderate")
	declare(/datum/medical_issue/condition/heart_damage, threshold = 70, tier = "Critical")


/datum/dq_cause/organ_damage/lungs
	name = "Lung damage"
	description = "Injury to the lungs themselves. Once they can no longer move enough air, hypoxia spreads to every other organ."
	subcategory = "Organ damage"
	organ = O_LUNGS

/datum/dq_cause/organ_damage/lungs/setup()
	..()
	declare(/datum/medical_issue/condition/respiratory_failure, threshold = 70, tier = "Severe")


/datum/dq_cause/organ_damage/liver
	name = "Liver damage"
	description = "Injury to the liver itself. Past the point of function it can no longer clear metabolites, and toxins accumulate in the bloodstream."
	subcategory = "Organ damage"
	organ = O_LIVER

/datum/dq_cause/organ_damage/liver/setup()
	..()
	declare(/datum/medical_issue/condition/hepatic_failure, threshold = 70, tier = "Severe")


/datum/dq_cause/organ_damage/kidneys
	name = "Kidney damage"
	description = "Injury to the kidneys themselves. They stop clearing waste; electrolytes drift and fluid balance fails."
	subcategory = "Organ damage"
	organ = O_KIDNEYS

/datum/dq_cause/organ_damage/kidneys/setup()
	..()
	declare(/datum/medical_issue/condition/renal_failure, threshold = 70, tier = "Severe")


/datum/dq_cause/organ_damage/eyes
	name = "Eye damage"
	description = "Injury to the eyes themselves — through hypoperfusion or direct trauma — producing blurred or absent vision."
	subcategory = "Organ damage"
	organ = O_EYES

/datum/dq_cause/organ_damage/eyes/setup()
	..()
	declare(/datum/medical_issue/condition/ischemic_vision_loss, threshold = 70, tier = "Severe")


// --- Severity-gate causes -----------------------------------------------
//
// These replace the previous cascade_at + cascade_to fields. The gate
// is identified by (source_condition, threshold). When the source's
// severity crosses threshold, the produces list rolls.

/datum/dq_cause/severity_gate/deep_bruising_to_hemorrhage
	subcategory = "Progression"
	source_condition = /datum/medical_issue/condition/deep_bruising
	threshold = 70

/datum/dq_cause/severity_gate/deep_bruising_to_hemorrhage/setup()
	..()
	name = "Untreated deep bruising"
	description = "Bruising left untreated can deepen into a true internal bleed as the damaged vessels fail."
	declare(/datum/medical_issue/condition/internal_hemorrhage, chance = 35)


/datum/dq_cause/severity_gate/hemorrhage_to_shock
	subcategory = "Progression"
	source_condition = /datum/medical_issue/condition/internal_hemorrhage
	threshold = 75

/datum/dq_cause/severity_gate/hemorrhage_to_shock/setup()
	..()
	name = "Sustained internal hemorrhage"
	description = "Once enough blood has been lost, the body can no longer compensate. Circulation collapses into hypovolemic shock."
	declare(/datum/medical_issue/condition/hypovolemic_shock, chance = 70)


/datum/dq_cause/severity_gate/lacerated_to_shock
	subcategory = "Progression"
	source_condition = /datum/medical_issue/condition/lacerated_artery
	threshold = 65

/datum/dq_cause/severity_gate/lacerated_to_shock/setup()
	..()
	name = "Untreated arterial bleed"
	description = "Continued blood loss from a torn artery progresses to hypovolemic shock if not stopped."
	declare(/datum/medical_issue/condition/hypovolemic_shock, chance = 75)


/datum/dq_cause/severity_gate/burn_shock_to_hypovolemia
	subcategory = "Progression"
	source_condition = /datum/medical_issue/condition/burn_shock
	threshold = 60

/datum/dq_cause/severity_gate/burn_shock_to_hypovolemia/setup()
	..()
	name = "Severe burn shock"
	description = "Heavy burns cause massive fluid loss through damaged skin, driving the patient into hypovolemic shock."
	declare(/datum/medical_issue/condition/hypovolemic_shock, chance = 50)
	declare(/datum/medical_issue/condition/wound_infection, chance = 40)


/datum/dq_cause/severity_gate/fracture_to_infection
	subcategory = "Progression"
	source_condition = /datum/medical_issue/condition/untreated_fracture
	threshold = 80

/datum/dq_cause/severity_gate/fracture_to_infection/setup()
	..()
	name = "Long-untreated fracture"
	description = "An unset fracture eventually invites infection at the wound site."
	declare(/datum/medical_issue/condition/wound_infection, chance = 25)


/datum/dq_cause/severity_gate/compartment_to_necrosis
	subcategory = "Progression"
	source_condition = /datum/medical_issue/condition/compartment_syndrome
	threshold = 80

/datum/dq_cause/severity_gate/compartment_to_necrosis/setup()
	..()
	name = "Untreated compartment syndrome"
	description = "Tissue starved of blood inside a swollen compartment eventually dies. The dead tissue must be removed surgically."
	declare(/datum/medical_issue/condition/tissue_necrosis, chance = 70)


// --- Infection chain ----------------------------------------------------

/datum/dq_cause/severity_gate/wound_to_cellulitis
	category = "Infection"
	subcategory = "Infection chain"
	source_condition = /datum/medical_issue/condition/wound_infection
	threshold = 70

/datum/dq_cause/severity_gate/wound_to_cellulitis/setup()
	..()
	name = "Spreading wound infection"
	description = "Bacteria escape the wound site and spread through the surrounding soft tissue."
	declare(/datum/medical_issue/condition/cellulitis, chance = 60)


/datum/dq_cause/severity_gate/cellulitis_to_sepsis
	category = "Infection"
	subcategory = "Infection chain"
	source_condition = /datum/medical_issue/condition/cellulitis
	threshold = 75

/datum/dq_cause/severity_gate/cellulitis_to_sepsis/setup()
	..()
	name = "Cellulitis breaching the bloodstream"
	description = "Once cellulitis seeds infection into the bloodstream, the whole body's inflammatory response activates: sepsis."
	declare(/datum/medical_issue/condition/sepsis, chance = 60)


/datum/dq_cause/severity_gate/sepsis_to_septic_shock
	category = "Infection"
	subcategory = "Infection chain"
	source_condition = /datum/medical_issue/condition/sepsis
	threshold = 70

/datum/dq_cause/severity_gate/sepsis_to_septic_shock/setup()
	..()
	name = "Decompensated sepsis"
	description = "Sepsis past the point of compensation: blood pressure collapses despite reflexive tachycardia. Septic shock."
	declare(/datum/medical_issue/condition/septic_shock, chance = 70)


// --- Germ-level cause ---------------------------------------------------
//
// Replaces the bridge code in code/modules/medical/infection_bridge.dm.
// Any organ whose germ_level crosses INFECTION_LEVEL_ONE spawns
// wound_infection on it. Wired uniformly through the registry rather
// than special-cased on the organ side.

/datum/dq_cause/germ_level/any_organ_dirty
	name = "Wound contamination"
	description = "Once the bacteria load on a wound passes a threshold, a wound infection forms there."
	organ = null  // sentinel meaning "any organ"
	threshold_level = INFECTION_LEVEL_ONE

/datum/dq_cause/germ_level/any_organ_dirty/setup()
	..()
	declare(/datum/medical_issue/condition/wound_infection)


// --- Metric-threshold causes -------------------------------------------
//
// One cause per environmental/systemic scalar. Tiered outcomes use the
// per-outcome `threshold` to declare each tier's metric value.

/datum/dq_cause/metric_threshold/acute_radiation
	name = "Acute radiation exposure"
	subcategory = "Radiation"
	description = "A high single dose of ionising radiation. Mild doses cause nausea and fatigue; severe doses cause spontaneous bleeding and organ failure."
	metric = "radiation"
	host_organ = O_HEART  // host: bone-marrow stand-in

/datum/dq_cause/metric_threshold/acute_radiation/setup()
	..()
	declare(/datum/medical_issue/condition/acute_radiation, threshold = 50,  tier = "Mild")
	declare(/datum/medical_issue/condition/acute_radiation, threshold = 100, tier = "Moderate")
	declare(/datum/medical_issue/condition/acute_radiation, threshold = 300, tier = "Severe")


/datum/dq_cause/metric_threshold/chronic_radiation
	name = "Chronic radiation dose"
	subcategory = "Radiation"
	description = "Sustained or accumulated radiation exposure over time. Persists after acute symptoms have cleared; clears slowly without treatment."
	metric = "accumulated_rads"
	host_organ = O_HEART

/datum/dq_cause/metric_threshold/chronic_radiation/setup()
	..()
	declare(/datum/medical_issue/condition/chronic_radiation, threshold = 100)


/datum/dq_cause/metric_threshold/toxic_exposure
	name = "Toxin exposure"
	description = "Inhaled, ingested, or injected toxins faster than the liver can process them — phoron leaks, poisoned food, spider venom, untreated liver failure, or chemicals at overdose driving toxin damage directly into the bloodstream."
	metric = "toxloss"
	host_organ = O_LIVER

/datum/dq_cause/metric_threshold/toxic_exposure/setup()
	..()
	declare(/datum/medical_issue/condition/toxic_poisoning, threshold = 30)


/datum/dq_cause/metric_threshold/oxygen_debt
	name = "Oxygen debt"
	description = "Sustained oxygen demand outstrips delivery. Suffocation, severe blood loss, lung damage, or chemicals at overdose that compromise oxygenation all push tissues into hypoxia until the underlying cause is treated."
	metric = "oxyloss"
	host_organ = O_LUNGS

/datum/dq_cause/metric_threshold/oxygen_debt/setup()
	..()
	declare(/datum/medical_issue/condition/tissue_hypoxia, threshold = 30)


/datum/dq_cause/metric_threshold/cold_exposure
	name = "Cold exposure"
	subcategory = "Temperature"
	description = "Body temperature has dropped well below normal. Cold environments, lack of insulation, or shock can cause it."
	metric = "temp_below"
	host_organ = BP_TORSO

/datum/dq_cause/metric_threshold/cold_exposure/setup()
	..()
	declare(/datum/medical_issue/condition/hypothermia, threshold = 20)  // ~17°C below 37°C


/datum/dq_cause/metric_threshold/heat_exposure
	name = "Heat exposure"
	subcategory = "Temperature"
	description = "Body temperature has risen well above normal. Hot environments, fevers, or burns can drive it."
	metric = "temp_above"
	host_organ = BP_TORSO

/datum/dq_cause/metric_threshold/heat_exposure/setup()
	..()
	declare(/datum/medical_issue/condition/heatstroke, threshold = 5)  // ~5°C above 37°C


/datum/dq_cause/metric_threshold/genetic_insult
	name = "Cellular damage"
	description = "DNA-level damage from radiation, cloning failure, or other catalytic insult. Ryetalyn is the specific treatment."
	metric = "cloneloss"
	host_organ = O_BRAIN

/datum/dq_cause/metric_threshold/genetic_insult/setup()
	..()
	declare(/datum/medical_issue/condition/genetic_damage, threshold = 20)


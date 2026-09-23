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

/datum/affliction_trigger/injury/blunt_torso
	name = "Blunt impact to the torso"
	subcategory = "Blunt impact"
	description = "A heavy strike to the chest or abdomen — a fall, a thrown object, a body blow. Bruising forms beneath the skin; a hard enough impact can bruise the lung underneath."
	wound_class = "blunt"
	body_regions = list(BP_TORSO)
	min_damage = 5

/datum/affliction_trigger/injury/blunt_torso/setup()
	..()
	declare(/datum/affliction/deep_bruising,       chance = 35)
	declare(/datum/affliction/pulmonary_contusion, chance = 40, threshold = 10)


/datum/affliction_trigger/injury/blunt_head
	name = "Blunt impact to the head"
	subcategory = "Blunt impact"
	description = "A strike to the head. The first impact tends to concussion; a second on top of an existing concussion produces a far more serious subdural hematoma."
	wound_class = "blunt"
	body_regions = list(BP_HEAD)
	min_damage = 5

/datum/affliction_trigger/injury/blunt_head/setup()
	..()
	declare(/datum/affliction/subdural_hematoma, chance = 50, requires_present = /datum/affliction/concussion)
	declare(/datum/affliction/concussion,        chance = 50, requires_absent  = /datum/affliction/concussion)
	// Smashed face and jaw: blood, teeth and swollen tissue in the airway.
	declare(/datum/affliction/airway_obstruction, chance = 10, threshold = 25)


// -- Sharp injuries ----

/datum/affliction_trigger/injury/sharp_torso
	name = "Sharp injury to the torso"
	subcategory = "Sharp injury"
	description = "A cut or piercing wound to the chest or abdomen — knife, gunshot, jagged metal. Internal bleeding is common; deep wounds can pierce the pleural cavity."
	wound_class = "sharp"
	body_regions = list(BP_TORSO, BP_GROIN)
	min_damage = 5

/datum/affliction_trigger/injury/sharp_torso/setup()
	..()
	declare(/datum/affliction/internal_hemorrhage, chance = 40)
	declare(/datum/affliction/pneumothorax, chance = 30, threshold = 15)


/datum/affliction_trigger/injury/sharp_limb
	name = "Sharp injury to a limb"
	subcategory = "Sharp injury"
	description = "A cut to an arm or leg. Shallow cuts risk tendon or nerve disruption; deeper ones can sever an artery and bleed dangerously fast."
	wound_class = "sharp"
	body_regions = list("limb")
	min_damage = 10

/datum/affliction_trigger/injury/sharp_limb/setup()
	..()
	declare(/datum/affliction/tendon_severed,   chance = 25, threshold = 10)
	declare(/datum/affliction/nerve_damage,     chance = 20, threshold = 15)
	declare(/datum/affliction/lacerated_artery, chance = 35, threshold = 20)


// -- Burns ----

/datum/affliction_trigger/injury/burn_head
	name = "Burn injury to the head or face"
	subcategory = "Burns"
	description = "Heat or chemical injury to the face and airway. The upper airway swells and gas exchange suffers."
	wound_class = "burn"
	body_regions = list(BP_HEAD)
	min_damage = 10

/datum/affliction_trigger/injury/burn_head/setup()
	..()
	declare(/datum/affliction/airway_burn, chance = 50)


/datum/affliction_trigger/injury/burn_cumulative
	name = "Extensive body burns"
	subcategory = "Burns"
	description = "Burns spread across enough of the body that fluid balance fails and systemic shock sets in."
	wound_class = "burn"
	body_regions = null  // any
	min_damage = 1
	min_cumulative_damage = 25

/datum/affliction_trigger/injury/burn_cumulative/setup()
	..()
	declare(/datum/affliction/burn_shock, chance = 100)


/datum/affliction_trigger/injury/burn_limb_severe
	name = "Severe limb burns"
	subcategory = "Burns"
	description = "Deep burns to a limb cause swelling within the muscle compartment. Pressure builds and tissue suffocates."
	wound_class = "burn"
	body_regions = list("limb")
	min_damage = 15
	min_cumulative_damage = 30

/datum/affliction_trigger/injury/burn_limb_severe/setup()
	..()
	declare(/datum/affliction/compartment_syndrome, chance = 40)


// -- Bone ----

/datum/affliction_trigger/injury/bone_fracture
	name = "Broken bone"
	subcategory = "Bone"
	description = "A bone has fractured. Without setting, the surrounding tissue grinds against the broken edges with every movement."
	wound_class = "broken_bone"  // pseudo-class; dispatcher emits it when ORGAN_BROKEN flips
	body_regions = null
	min_damage = 0

/datum/affliction_trigger/injury/bone_fracture/setup()
	..()
	declare(/datum/affliction/untreated_fracture, chance = 60)


// --- Organ-damage causes ------------------------------------------------
//
// One cause per organ. Each cause carries tiered outcomes (Moderate /
// Severe / Critical) with their own thresholds; the emergent dispatcher
// walks outcomes individually so different downstream conditions emerge
// at different damage levels. The cause's `threshold_pct` is a default
// for outcomes that don't override.

/datum/affliction_trigger/organ_integrity/brain
	name = "Brain damage"
	description = "Injury to the brain itself. Mild loss of cognition starts well before severe neurological collapse, and pressure-driven herniation is the end of the line."
	subcategory = "Organ damage"
	organ = O_BRAIN

/datum/affliction_trigger/organ_integrity/brain/setup()
	..()
	declare(/datum/affliction/brain_damage, threshold = 40, tier = "Significant")
	declare(/datum/affliction/brain_damage, threshold = 80, tier = "Critical")


/datum/affliction_trigger/organ_integrity/heart
	name = "Heart damage"
	description = "Injury to the heart itself. As pump output falls, perfusion suffers; once the pump fails outright, cardiac arrest follows."
	subcategory = "Organ damage"
	organ = O_HEART

/datum/affliction_trigger/organ_integrity/heart/setup()
	..()
	declare(/datum/affliction/heart_damage, threshold = 50, tier = "Moderate")
	declare(/datum/affliction/heart_damage, threshold = 70, tier = "Critical")


/datum/affliction_trigger/organ_integrity/lungs
	name = "Lung damage"
	description = "Injury to the lungs themselves. Once they can no longer move enough air, hypoxia spreads to every other organ."
	subcategory = "Organ damage"
	organ = O_LUNGS

/datum/affliction_trigger/organ_integrity/lungs/setup()
	..()
	declare(/datum/affliction/respiratory_failure, threshold = 70, tier = "Severe")


/datum/affliction_trigger/organ_integrity/liver
	name = "Liver damage"
	description = "Injury to the liver itself. Past the point of function it can no longer clear metabolites, and toxins accumulate in the bloodstream."
	subcategory = "Organ damage"
	organ = O_LIVER

/datum/affliction_trigger/organ_integrity/liver/setup()
	..()
	declare(/datum/affliction/hepatic_failure, threshold = 70, tier = "Severe")


/datum/affliction_trigger/organ_integrity/kidneys
	name = "Kidney damage"
	description = "Injury to the kidneys themselves. They stop clearing waste; electrolytes drift and fluid balance fails."
	subcategory = "Organ damage"
	organ = O_KIDNEYS

/datum/affliction_trigger/organ_integrity/kidneys/setup()
	..()
	declare(/datum/affliction/renal_failure, threshold = 70, tier = "Severe")


/datum/affliction_trigger/organ_integrity/eyes
	name = "Eye damage"
	description = "Injury to the eyes themselves — through hypoperfusion or direct trauma — producing blurred or absent vision."
	subcategory = "Organ damage"
	organ = O_EYES

/datum/affliction_trigger/organ_integrity/eyes/setup()
	..()
	declare(/datum/affliction/ischemic_vision_loss, threshold = 70, tier = "Severe")


// --- Severity-gate causes -----------------------------------------------
//
// These replace the previous cascade_at + cascade_to fields. The gate
// is identified by (source_condition, threshold). When the source's
// severity crosses threshold, the produces list rolls.

/datum/affliction_trigger/progression/deep_bruising_to_hemorrhage
	subcategory = "Progression"
	source_condition = /datum/affliction/deep_bruising
	threshold = 70

/datum/affliction_trigger/progression/deep_bruising_to_hemorrhage/setup()
	..()
	name = "Untreated deep bruising"
	description = "Bruising left untreated can deepen into a true internal bleed as the damaged vessels fail."
	declare(/datum/affliction/internal_hemorrhage, chance = 35)


/datum/affliction_trigger/progression/hemorrhage_to_shock
	subcategory = "Progression"
	source_condition = /datum/affliction/internal_hemorrhage
	threshold = 75

/datum/affliction_trigger/progression/hemorrhage_to_shock/setup()
	..()
	name = "Sustained internal hemorrhage"
	description = "Once enough blood has been lost, the body can no longer compensate. Circulation collapses into hypovolemic shock."
	declare(/datum/affliction/hypovolemic_shock, chance = 70)


/datum/affliction_trigger/progression/lacerated_to_shock
	subcategory = "Progression"
	source_condition = /datum/affliction/lacerated_artery
	threshold = 65

/datum/affliction_trigger/progression/lacerated_to_shock/setup()
	..()
	name = "Untreated arterial bleed"
	description = "Continued blood loss from a torn artery progresses to hypovolemic shock if not stopped."
	declare(/datum/affliction/hypovolemic_shock, chance = 75)


/datum/affliction_trigger/progression/airway_burn_to_edema
	subcategory = "Progression"
	source_condition = /datum/affliction/airway_burn
	threshold = 50

/datum/affliction_trigger/progression/airway_burn_to_edema/setup()
	..()
	name = "Deepening inhalation burn"
	description = "A scorched airway swells. Past a point the swelling closes the throat entirely."
	declare(/datum/affliction/airway_edema, chance = 10)


/datum/affliction_trigger/progression/hypoxia_to_respiratory_arrest
	subcategory = "Progression"
	source_condition = /datum/affliction/tissue_hypoxia
	threshold = 85

/datum/affliction_trigger/progression/hypoxia_to_respiratory_arrest/setup()
	..()
	name = "Profound hypoxia"
	description = "A brainstem starved of oxygen stops driving breathing. The patient stops breathing on their own."
	declare(/datum/affliction/respiratory_arrest, chance = 5)


/datum/affliction_trigger/progression/hypoxia_to_cardiac_arrest
	subcategory = "Progression"
	source_condition = /datum/affliction/tissue_hypoxia
	threshold = 90

/datum/affliction_trigger/progression/hypoxia_to_cardiac_arrest/setup()
	..()
	name = "Hypoxic cardiac arrest"
	description = "A heart starved of oxygen fibrillates and stops pumping."
	declare(/datum/affliction/cardiac_arrhythmia, chance = 3)


/datum/affliction_trigger/progression/burn_shock_to_hypovolemia
	subcategory = "Progression"
	source_condition = /datum/affliction/burn_shock
	threshold = 60

/datum/affliction_trigger/progression/burn_shock_to_hypovolemia/setup()
	..()
	name = "Severe burn shock"
	description = "Heavy burns cause massive fluid loss through damaged skin, driving the patient into hypovolemic shock."
	declare(/datum/affliction/hypovolemic_shock, chance = 50)
	declare(/datum/affliction/wound_infection, chance = 40)


/datum/affliction_trigger/progression/fracture_to_infection
	subcategory = "Progression"
	source_condition = /datum/affliction/untreated_fracture
	threshold = 80

/datum/affliction_trigger/progression/fracture_to_infection/setup()
	..()
	name = "Long-untreated fracture"
	description = "An unset fracture eventually invites infection at the wound site."
	declare(/datum/affliction/wound_infection, chance = 25)


/datum/affliction_trigger/progression/compartment_to_necrosis
	subcategory = "Progression"
	source_condition = /datum/affliction/compartment_syndrome
	threshold = 80

/datum/affliction_trigger/progression/compartment_to_necrosis/setup()
	..()
	name = "Untreated compartment syndrome"
	description = "Tissue starved of blood inside a swollen compartment eventually dies. The dead tissue must be removed surgically."
	declare(/datum/affliction/tissue_necrosis, chance = 70)


// --- Infection chain ----------------------------------------------------

/datum/affliction_trigger/progression/wound_to_cellulitis
	category = "Infection"
	subcategory = "Infection chain"
	source_condition = /datum/affliction/wound_infection
	threshold = 70

/datum/affliction_trigger/progression/wound_to_cellulitis/setup()
	..()
	name = "Spreading wound infection"
	description = "Bacteria escape the wound site and spread through the surrounding soft tissue."
	declare(/datum/affliction/cellulitis, chance = 60)


/datum/affliction_trigger/progression/cellulitis_to_sepsis
	category = "Infection"
	subcategory = "Infection chain"
	source_condition = /datum/affliction/cellulitis
	threshold = 75

/datum/affliction_trigger/progression/cellulitis_to_sepsis/setup()
	..()
	name = "Cellulitis breaching the bloodstream"
	description = "Once cellulitis seeds infection into the bloodstream, the whole body's inflammatory response activates: sepsis."
	declare(/datum/affliction/sepsis, chance = 60)


/datum/affliction_trigger/progression/sepsis_to_septic_shock
	category = "Infection"
	subcategory = "Infection chain"
	source_condition = /datum/affliction/sepsis
	threshold = 70

/datum/affliction_trigger/progression/sepsis_to_septic_shock/setup()
	..()
	name = "Decompensated sepsis"
	description = "Sepsis past the point of compensation: blood pressure collapses despite reflexive tachycardia. Septic shock."
	declare(/datum/affliction/septic_shock, chance = 70)


// --- Germ-level cause ---------------------------------------------------
//
// Replaces the bridge code in code/modules/medical/infection_bridge.dm.
// Any organ whose germ_level crosses INFECTION_LEVEL_ONE spawns
// wound_infection on it. Wired uniformly through the registry rather
// than special-cased on the organ side.

/datum/affliction_trigger/infection/any_organ_dirty
	name = "Wound contamination"
	description = "Once the bacteria load on a wound passes a threshold, a wound infection forms there."
	organ = null  // sentinel meaning "any organ"
	threshold_level = INFECTION_LEVEL_ONE

/datum/affliction_trigger/infection/any_organ_dirty/setup()
	..()
	declare(/datum/affliction/wound_infection)


// --- Metric-threshold causes -------------------------------------------
//
// One cause per environmental/systemic scalar. Tiered outcomes use the
// per-outcome `threshold` to declare each tier's metric value.

/datum/affliction_trigger/metric/acute_radiation
	name = "Acute radiation exposure"
	subcategory = "Radiation"
	description = "A high single dose of ionising radiation. Mild doses cause nausea and fatigue; severe doses cause spontaneous bleeding and organ failure."
	metric = "radiation"
	host_organ = O_HEART  // host: bone-marrow stand-in

/datum/affliction_trigger/metric/acute_radiation/setup()
	..()
	declare(/datum/affliction/acute_radiation, threshold = 50,  tier = "Mild")
	declare(/datum/affliction/acute_radiation, threshold = 100, tier = "Moderate")
	declare(/datum/affliction/acute_radiation, threshold = 300, tier = "Severe")


/datum/affliction_trigger/metric/chronic_radiation
	name = "Chronic radiation dose"
	subcategory = "Radiation"
	description = "Sustained or accumulated radiation exposure over time. Persists after acute symptoms have cleared; clears slowly without treatment."
	metric = "accumulated_rads"
	host_organ = O_HEART

/datum/affliction_trigger/metric/chronic_radiation/setup()
	..()
	declare(/datum/affliction/chronic_radiation, threshold = 100)


/datum/affliction_trigger/metric/cold_exposure
	name = "Cold exposure"
	subcategory = "Temperature"
	description = "Body temperature has dropped well below normal. Cold environments, lack of insulation, or shock can cause it."
	metric = "temp_below"
	host_organ = BP_TORSO

/datum/affliction_trigger/metric/cold_exposure/setup()
	..()
	declare(/datum/affliction/hypothermia, threshold = 20)  // ~17°C below 37°C


/datum/affliction_trigger/metric/heat_exposure
	name = "Heat exposure"
	subcategory = "Temperature"
	description = "Body temperature has risen well above normal. Hot environments, fevers, or burns can drive it."
	metric = "temp_above"
	host_organ = BP_TORSO

/datum/affliction_trigger/metric/heat_exposure/setup()
	..()
	declare(/datum/affliction/heatstroke, threshold = 5)  // ~5°C above 37°C

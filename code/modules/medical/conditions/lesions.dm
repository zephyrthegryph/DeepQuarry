// Lesion afflictions — the integrity model of an internal organ.
//
// A lesion is an affliction located on an /obj/item/organ/internal. It carries
// `damage` points; the organ's `damage` is DERIVED from the lesions located on
// it (organ.recalc_integrity(), cached on every change) exactly like a limb's
// integrity is derived from its wounds. Nothing writes organ damage directly:
// harm goes through injure(kind, amount, organ) (the kind picks the lesion),
// healing through mend(tag, amount, organ) or continuous treatment.
//
// Severity is damage as a percentage of the organ's max_damage (display and
// scanner banding only). injury_category is null: organ integrity already
// feeds vitality and the organ_integrity triggers, so lesions must not be
// double counted as injury load.
//
// Repeat injuries of the same kind merge into the existing lesion on that
// organ (organ.add_lesion()).
//
// Treatment (the shared affliction pipeline; lesions override only
// receive_tagged_treatment() and progress()):
//  - Each lesion's treated_by is built from its organ in configure(): the
//    organ's repair mechanism (lesion_repair_tag(): hepatorenal, cardiac,
//    respiratory, digestive, neural, ocular, tissue repair) at
//    `organ_tag_rate`, the kind's own extra mechanisms
//    (get_extra_treatments()), and natural regeneration for kinds that
//    self-heal.
//  - Structural lesions (laceration, perforation) have a `drug_floor`: drugs
//    stop them bleeding / leaking ("stabilised") and shrink them only down to
//    that fraction of their worst size. Only a full-repair mechanism
//    (TREAT_SURGICAL_REPAIR, TREAT_RESTORATION) closes them. Necrosis needs
//    TREAT_RESECTION and responds only weakly to drugs (drug_efficiency).
//  - Natural regeneration (TREAT_REGENERATION) only repairs an organ below
//    its natural_heal_ceiling().
//  - A brain past BRAIN_SALVAGE_FRACTION swells: secondary (ischemic) injury
//    drifts upward each tick, drugs act at a fraction, and past
//    BRAIN_TERMINAL_FRACTION nothing keeps up (the old organ_decay/brain.dm
//    bands, now lesion drift).

/// Multiplier on continuous (per-tick) treatment of lesion damage.
#define LESION_TREATMENT_TICK_SCALE 0.5
/// Blood lost per tick per point of unstabilised laceration damage.
#define LESION_BLEED_PER_DAMAGE 0.02
/// Below this a lesion is considered healed.
#define LESION_HEALED_EPSILON 0.01
/// treated_by rate of natural regeneration on kinds that self-heal (0.05 per
/// tick at regeneration level 1).
#define LESION_REGENERATION_RATE 0.1
/// A continuous treatment keeps a lesion stabilised this long.
#define LESION_STABILISED_WINDOW (3 SECONDS)
/// Brain damage fraction past which the brain swells (secondary injury).
#define BRAIN_SALVAGE_FRACTION 0.6
/// Brain damage fraction past which the swelling outpaces any treatment.
#define BRAIN_TERMINAL_FRACTION 0.9
/// Secondary brain injury per tick in the salvage band.
#define BRAIN_EDEMA_RATE 0.4
/// Secondary brain injury per tick in the terminal band.
#define BRAIN_TERMINAL_EDEMA_RATE 2.5
/// Neural repair in the blood slows the swelling to this fraction.
#define BRAIN_EDEMA_TREATED_MULT 0.4
/// Drugs act on a swollen brain's lesions at this fraction.
#define BRAIN_SWOLLEN_TREATMENT_MULT 0.2

/datum/affliction/lesion
	name = "organ lesion"
	catalogued = FALSE
	category = "Organ"
	clinical_description = "Structural damage to an internal organ."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	injury_category = null
	progression_rate = 0
	severity_per_injury = 0
	pain_at_max = 0
	min_symptoms = 0
	max_symptoms = 2
	restoration_rate = 1
	// "Repair N points of this organ": one budget across its lesions.
	shares_mend_budget = TRUE

	/// Integrity points this lesion takes off its organ.
	var/damage = 0
	/// Worst damage this lesion has reached; drug_floor is a fraction of it.
	var/peak_damage = 0
	/// world.time a continuous treatment mechanism last acted on this lesion
	/// (see is_stabilised(): halts bleeding, leaking and necrotic spread).
	var/tmp/stabilised_at = 0

	// --- Defined by the lesion kind ---
	/// Short noun for the lesion ("contusion", "laceration"…).
	var/lesion_noun = "lesion"
	/// Damage change per tick with no treatment: negative self-heals,
	/// positive progresses (only while not stabilised).
	var/drift = 0
	/// Natural recovery (passive organ regeneration) may heal this kind.
	var/self_heals = TRUE
	/// Rate of the organ's own repair mechanism against this kind (0 = none).
	var/organ_tag_rate = 1
	/// Fraction of peak damage non-surgical treatment can't heal below.
	var/drug_floor = 0
	/// Multiplier on continuous (drug) partial healing (necrosis barely responds).
	var/drug_efficiency = 1
	/// Scanner finding that always presents (what diagnosis finds).
	var/finding_symptom

/datum/affliction/lesion/on_added()
	. = ..()
	sync()

/datum/affliction/lesion/on_removed()
	. = ..()
	var/obj/item/organ/internal/O = location
	if(istype(O))
		O.recalc_integrity()

/// Build the organ-dependent parts: treatment table, display name, symptoms.
/// With no organ (reference prototypes) the generic tissue-repair tag stands
/// in for the organ's own.
/datum/affliction/lesion/configure(location)
	var/obj/item/organ/internal/O = istype(location, /obj/item/organ/internal) ? location : null
	treated_by = list()
	if(organ_tag_rate)
		treated_by[O ? O.lesion_repair_tag() : TREAT_TISSUE_REPAIR] = organ_tag_rate
	var/list/extra = get_extra_treatments()
	for(var/tag in extra)
		treated_by[tag] = max(treated_by[tag], extra[tag])
	if(self_heals)
		treated_by[TREAT_REGENERATION] = LESION_REGENERATION_RATE
	name = O ? lesion_name(O) : initial(name)
	symptom_pool = list()
	if(finding_symptom)
		symptom_pool[finding_symptom] = 100
	var/list/organ_pool = lesion_symptoms(O?.organ_tag)
	for(var/symptom_type in organ_pool)
		symptom_pool[symptom_type] = organ_pool[symptom_type]

/// Mechanisms beyond the organ's repair tag: TREAT_* -> rate. Static per kind.
/datum/affliction/lesion/proc/get_extra_treatments()
	return null

/// Mechanisms that fully repair this kind (ignore drug_floor). Static per kind.
/datum/affliction/lesion/proc/get_full_repair_tags()
	return null

/datum/affliction/lesion/proc/lesion_name(obj/item/organ/internal/O)
	return "[O.name] [lesion_noun]"

/// Symptom pool for this kind on an organ with `organ_tag`. Static lists.
/datum/affliction/lesion/proc/lesion_symptoms(organ_tag)
	return null

/// Push damage into severity and the organ's integrity cache.
/datum/affliction/lesion/proc/sync()
	var/obj/item/organ/internal/O = location
	var/scale = (istype(O) && O.max_damage) ? O.max_damage : 100
	set_severity(100 * damage / scale)
	if(istype(O))
		O.recalc_integrity()

/// Grow the lesion by `amount`.
/datum/affliction/lesion/proc/add_damage(amount)
	if(amount <= 0)
		return
	damage += amount
	peak_damage = max(peak_damage, damage)
	sync()

/// Heal up to `amount`. `full` ignores the drug floor. Returns the amount
/// healed. A lesion healed to nothing removes itself.
/datum/affliction/lesion/proc/heal(amount, full = FALSE)
	if(amount <= 0 || damage <= 0)
		return 0
	// A dead brain (is_brain_dead()) needs a resleeve: no mechanism repairs it.
	var/obj/item/organ/internal/organ = location
	if(istype(organ) && organ.is_beyond_repair())
		return 0
	var/floor = full ? 0 : peak_damage * drug_floor
	var/healed = clamp(damage - floor, 0, amount)
	if(healed <= 0)
		return 0
	damage -= healed
	if(damage <= LESION_HEALED_EPSILON)
		damage = 0
		var/obj/item/organ/internal/O = location
		if(istype(O))
			O.remove_lesion(src)
		else
			qdel(src)
		return healed
	sync()
	return healed

/datum/affliction/lesion/proc/is_full_repair(tag)
	if(tag == TREAT_RESTORATION)
		return TRUE
	var/list/full = get_full_repair_tags()
	return full && (tag in full)

/// Is a continuous treatment holding this lesion (no bleeding, leaking or
/// spreading)?
/datum/affliction/lesion/proc/is_stabilised()
	return stabilised_at && world.time - stabilised_at <= LESION_STABILISED_WINDOW

/// Natural regeneration only repairs an organ that isn't badly hurt.
/datum/affliction/lesion/proc/can_regenerate()
	var/obj/item/organ/internal/O = location
	return istype(O) && O.damage < O.natural_heal_ceiling()

/// Is this lesion on an organic brain past BRAIN_SALVAGE_FRACTION?
/datum/affliction/lesion/proc/on_swollen_brain()
	var/obj/item/organ/internal/brain/B = location
	return istype(B) && B.robotic < ORGAN_ROBOT && B.max_damage && B.damage >= B.max_damage * BRAIN_SALVAGE_FRACTION

/// The one lesion on brain `B` that carries its swelling: the ischemic
/// injury if there is one, else the first lesion.
/proc/brain_swelling_carrier(obj/item/organ/internal/brain/B)
	var/datum/affliction/lesion/carrier = B.find_lesion(/datum/affliction/lesion/ischemic_injury)
	if(carrier)
		return carrier
	for(var/datum/affliction/lesion/L as anything in B.get_lesions())
		return L

/// Fraction of a partial (non-surgical) treatment that takes: a swollen
/// brain responds poorly.
/datum/affliction/lesion/proc/treatment_response()
	if(on_swollen_brain())
		return BRAIN_SWOLLEN_TREATMENT_MULT
	return 1

// --- Affliction integration -------------------------------------------------

/// An injury routed straight to this lesion (affliction = lesion type).
/datum/affliction/lesion/receive_injury(amount, kind, atom/source)
	var/obj/item/organ/internal/O = location
	if(istype(O))
		amount = min(amount, max(0, O.max_damage - O.damage))
	add_damage(amount)
	return amount

/// Lesions respond to WHICH mechanism treats them: full-repair tags close the
/// lesion, everything else only shrinks it to its drug floor. Continuous
/// (drug) treatment also stabilises the lesion and is scaled to the tick.
/datum/affliction/lesion/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(tag == TREAT_REGENERATION)
		if(!can_regenerate())
			return 0
	else if(continuous)
		stabilised_at = world.time
	if(continuous)
		amount *= LESION_TREATMENT_TICK_SCALE
	if(is_full_repair(tag))
		return heal(amount, TRUE)
	// A swollen brain takes a drug dose as one organ, through the lesion
	// carrying the swelling, so the dose can't outpace the swelling by being
	// counted once per lesion.
	if(continuous && on_swollen_brain() && brain_swelling_carrier(location) != src)
		return 0
	amount *= treatment_response()
	if(continuous && tag != TREAT_REGENERATION)
		amount *= drug_efficiency
	return heal(amount, FALSE)

/datum/affliction/lesion/load_value()
	return 0

/// Detached organs decay through their own process(); lesions hold still.
/datum/affliction/lesion/tick_offline()
	return

/// Drift (self-healing or spreading), the brain's secondary injury, and the
/// untreated lesion's effects.
/datum/affliction/lesion/progress()
	if(damage <= 0)
		return
	var/stable = is_stabilised()
	if(drift > 0 && !stable)
		var/obj/item/organ/internal/O = location
		var/room = istype(O) ? max(0, O.max_damage - O.damage) : drift
		add_damage(min(drift, room))
	else if(drift < 0 && !on_swollen_brain())
		// A swollen brain doesn't recover on its own.
		heal(-drift, TRUE)
	if(QDELETED(src) || !body)
		return
	secondary_injury()
	if(QDELETED(src) || !body)
		return
	if(!stable)
		lesion_effects()

/// A brain past BRAIN_SALVAGE_FRACTION swells: ischemic secondary injury
/// grows every tick (slowed by neural repair in the blood, pushed back by
/// overdose upsides in the salvage band only). One lesion per brain carries
/// it: the ischemic injury if there is one, else the first lesion.
/datum/affliction/lesion/proc/secondary_injury()
	var/obj/item/organ/internal/brain/B = location
	if(!istype(B) || B.robotic >= ORGAN_ROBOT || !B.max_damage)
		return
	var/fraction = B.damage / B.max_damage
	if(fraction < BRAIN_SALVAGE_FRACTION)
		return
	if(brain_swelling_carrier(B) != src)
		return
	var/rate
	if(fraction >= BRAIN_TERMINAL_FRACTION)
		rate = BRAIN_TERMINAL_EDEMA_RATE
	else
		rate = BRAIN_EDEMA_RATE
		if(body.treatment_levels()?[TREAT_NEURAL_REPAIR])
			rate *= BRAIN_EDEMA_TREATED_MULT
		rate -= owner?.factor(BF_NEURAL_REPAIR)
	if(rate > 0)
		var/room = max(0, B.max_damage - B.damage)
		if(room > 0)
			B.add_lesion(/datum/affliction/lesion/ischemic_injury, min(rate, room))
	else if(rate < 0)
		heal(-rate, FALSE)

/// Per-tick effect of an untreated lesion (bleeding, leaking).
/datum/affliction/lesion/proc/lesion_effects()
	return


// --- Organic kinds ------------------------------------------------------------

/// Blunt bruising of the organ. Slowly heals on its own.
/datum/affliction/lesion/contusion
	name = "organ contusion"
	finding_symptom = /datum/affliction_symptom/lesion_finding/contusion
	lesion_noun = "contusion"
	clinical_description = "Bruised organ tissue from blunt force. Heals slowly on its own; the organ's repair drug speeds recovery."
	drift = -0.02

/datum/affliction/lesion/contusion/get_extra_treatments()
	var/static/list/L = list(TREAT_TISSUE_REPAIR = 0.25, TREAT_SURGICAL_REPAIR = 1)
	return L

/datum/affliction/lesion/contusion/get_full_repair_tags()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR)
	return L

/datum/affliction/lesion/contusion/lesion_name(obj/item/organ/internal/O)
	if(O.organ_tag == O_BRAIN)
		return "cerebral contusion"
	return ..()

/datum/affliction/lesion/contusion/lesion_symptoms(organ_tag)
	switch(organ_tag)
		if(O_BRAIN)
			var/static/list/brain = list(/datum/affliction_symptom/headache = 70, /datum/affliction_symptom/confusion = 40, /datum/affliction_symptom/dizziness = 40)
			return brain
		if(O_HEART)
			var/static/list/heart = list(/datum/affliction_symptom/palpitations = 60, /datum/affliction_symptom/chest_pain_crushing = 30)
			return heart
		if(O_LUNGS)
			var/static/list/lungs = list(/datum/affliction_symptom/short_breath = 60, /datum/affliction_symptom/sharp_chest_pain = 30)
			return lungs
		if(O_EYES)
			var/static/list/eyes = list(/datum/affliction_symptom/blurred_vision = 70)
			return eyes
		if(O_LIVER, O_KIDNEYS, O_STOMACH, O_INTESTINE, O_SPLEEN, O_APPENDIX)
			var/static/list/abdo = list(/datum/affliction_symptom/abdominal_tenderness = 70)
			return abdo
	return null

/// A tear through the organ. Bleeds internally; drugs only stabilise it.
/datum/affliction/lesion/laceration
	name = "organ laceration"
	finding_symptom = /datum/affliction_symptom/lesion_finding/laceration
	lesion_noun = "laceration"
	clinical_description = "A tear through the organ that bleeds into the body cavity. Drugs slow the bleeding and stabilise it; only surgical repair closes it."
	drift = 0
	self_heals = FALSE
	organ_tag_rate = 0.3
	drug_floor = 0.5

/datum/affliction/lesion/laceration/get_extra_treatments()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR = 1, TREAT_HEMOSTATIC = 0.1, TREAT_TISSUE_REPAIR = 0.2)
	return L

/datum/affliction/lesion/laceration/get_full_repair_tags()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR)
	return L

/datum/affliction/lesion/laceration/lesion_effects()
	var/mob/living/carbon/human/H = owner
	if(istype(H) && !(H.species?.flags & NO_BLOOD))
		H.remove_blood(damage * LESION_BLEED_PER_DAMAGE)

/datum/affliction/lesion/laceration/lesion_symptoms(organ_tag)
	var/static/list/L = list(/datum/affliction_symptom/pallor = 60, /datum/affliction_symptom/abdominal_tenderness = 40, /datum/affliction_symptom/internal_pressure = 40)
	return L

/// A hole through a hollow organ (stomach, intestine, lungs). Leaks contents
/// into the body cavity, seeding infection.
/datum/affliction/lesion/perforation
	name = "organ perforation"
	finding_symptom = /datum/affliction_symptom/lesion_finding/perforation
	lesion_noun = "perforation"
	clinical_description = "A hole through a hollow organ, leaking its contents and seeding infection. Antimicrobials hold the infection back; only surgical repair closes it."
	drift = 0
	self_heals = FALSE
	organ_tag_rate = 0.3
	drug_floor = 0.6

/datum/affliction/lesion/perforation/get_extra_treatments()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR = 1, TREAT_ANTIMICROBIAL = 0.1)
	return L

/datum/affliction/lesion/perforation/get_full_repair_tags()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR)
	return L

/datum/affliction/lesion/perforation/lesion_effects()
	var/obj/item/organ/internal/O = location
	if(istype(O))
		O.adjust_germ_level(1 + round(damage / 20))
	// A holed lung leaks air into the chest (pneumothorax keeps growing while
	// this lesion is unstabilised; see vital_systems.dm).
	var/mob/living/carbon/human/H = owner
	if(istype(O) && O.organ_tag == O_LUNGS && istype(H) && !H.body.has_affliction(/datum/affliction/pneumothorax))
		H.body.afflict(/datum/affliction/pneumothorax, H.get_organ(BP_TORSO))

/datum/affliction/lesion/perforation/lesion_symptoms(organ_tag)
	if(organ_tag == O_LUNGS)
		var/static/list/lungs = list(/datum/affliction_symptom/short_breath = 70, /datum/affliction_symptom/sharp_chest_pain = 50)
		return lungs
	var/static/list/gut = list(/datum/affliction_symptom/abdominal_tenderness = 80, /datum/affliction_symptom/nausea = 40, /datum/affliction_symptom/fever_sensation = 30)
	return gut

/// Dead tissue. Spreads on its own until treated; needs resection.
/datum/affliction/lesion/necrosis
	name = "organ necrosis"
	finding_symptom = /datum/affliction_symptom/lesion_finding/necrosis
	lesion_noun = "necrosis"
	clinical_description = "Dead organ tissue from infection, ischemia or toxins. It spreads on its own; antimicrobials slow it, strong regeneratives barely touch it, resection removes it."
	drift = 0.05
	self_heals = FALSE
	organ_tag_rate = 0
	drug_efficiency = 0.25

/datum/affliction/lesion/necrosis/get_extra_treatments()
	var/static/list/L = list(TREAT_RESECTION = 1, TREAT_GENETIC_REPAIR = 0.2, TREAT_ANTIMICROBIAL = 0.02)
	return L

/datum/affliction/lesion/necrosis/get_full_repair_tags()
	var/static/list/L = list(TREAT_RESECTION)
	return L

/datum/affliction/lesion/necrosis/lesion_name(obj/item/organ/internal/O)
	return "necrotic [O.name] tissue"

/datum/affliction/lesion/necrosis/lesion_symptoms(organ_tag)
	var/static/list/L = list(/datum/affliction_symptom/fever_sensation = 60, /datum/affliction_symptom/fatigue = 50, /datum/affliction_symptom/pallor = 30)
	return L

/// Oxygen starvation of the tissue.
/datum/affliction/lesion/ischemic_injury
	name = "ischemic organ injury"
	finding_symptom = /datum/affliction_symptom/lesion_finding/ischemic
	lesion_noun = "ischemic injury"
	clinical_description = "Tissue damaged by oxygen starvation. Responds to the organ's repair drug and oxygenation."

/datum/affliction/lesion/ischemic_injury/get_extra_treatments()
	var/static/list/L = list(TREAT_OXYGENATION = 0.3, TREAT_SURGICAL_REPAIR = 1)
	return L

/datum/affliction/lesion/ischemic_injury/get_full_repair_tags()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR)
	return L

/datum/affliction/lesion/ischemic_injury/lesion_name(obj/item/organ/internal/O)
	if(O.organ_tag == O_BRAIN)
		return "anoxic brain injury"
	return ..()

/datum/affliction/lesion/ischemic_injury/lesion_symptoms(organ_tag)
	switch(organ_tag)
		if(O_BRAIN)
			var/static/list/brain = list(/datum/affliction_symptom/confusion = 60, /datum/affliction_symptom/drowsy = 50)
			return brain
		if(O_HEART)
			var/static/list/heart = list(/datum/affliction_symptom/chest_pain_crushing = 60, /datum/affliction_symptom/palpitations = 40)
			return heart
		if(O_EYES)
			var/static/list/eyes = list(/datum/affliction_symptom/blurred_vision = 70)
			return eyes
	var/static/list/L = list(/datum/affliction_symptom/fatigue = 50)
	return L

/// Tissue poisoned by toxins (typically liver and kidneys).
/datum/affliction/lesion/toxic_injury
	name = "toxic organ injury"
	finding_symptom = /datum/affliction_symptom/lesion_finding/toxic
	lesion_noun = "toxic injury"
	clinical_description = "Tissue damaged by toxins the organ was clearing. Responds to the organ's repair drug and antitoxins."

/datum/affliction/lesion/toxic_injury/get_extra_treatments()
	var/static/list/L = list(TREAT_ANTITOXIN = 0.3, TREAT_SURGICAL_REPAIR = 1)
	return L

/datum/affliction/lesion/toxic_injury/get_full_repair_tags()
	var/static/list/L = list(TREAT_SURGICAL_REPAIR)
	return L

/datum/affliction/lesion/toxic_injury/lesion_symptoms(organ_tag)
	switch(organ_tag)
		if(O_LIVER)
			var/static/list/liver = list(/datum/affliction_symptom/jaundice = 70, /datum/affliction_symptom/nausea = 40)
			return liver
		if(O_KIDNEYS)
			var/static/list/kidneys = list(/datum/affliction_symptom/fatigue = 50, /datum/affliction_symptom/nausea = 40)
			return kidneys
	var/static/list/L = list(/datum/affliction_symptom/nausea = 40)
	return L


// --- Synthetic kinds ------------------------------------------------------------
// Prosthetic organs (robotic >= ORGAN_ROBOT) take component faults, repaired by
// plating / wiring work or a system restore. They never self-heal.

/datum/affliction/lesion/synthetic
	catalogued = FALSE
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	self_heals = FALSE
	organ_tag_rate = 0
	drift = 0

/datum/affliction/lesion/synthetic/component_fault
	name = "component fault"
	finding_symptom = /datum/affliction_symptom/lesion_finding/component_fault
	lesion_noun = "component fault"
	clinical_description = "Damaged components inside a prosthetic organ. Repaired by plating and wiring work or a system restore."

/datum/affliction/lesion/synthetic/component_fault/get_extra_treatments()
	var/static/list/L = list(TREAT_PLATING_REPAIR = 1, TREAT_WIRING_REPAIR = 1, TREAT_SYSTEM_RESTORE = 1)
	return L

/datum/affliction/lesion/synthetic/component_fault/get_full_repair_tags()
	var/static/list/L = list(TREAT_PLATING_REPAIR, TREAT_WIRING_REPAIR, TREAT_SYSTEM_RESTORE)
	return L

// --- Scanner findings -------------------------------------------------------------
// What an advanced scan reports for each lesion kind: the specific thing a
// diagnosis finds and a surgeon targets.

/datum/affliction_symptom/lesion_finding
	name = "organ lesion"
	category = "Diagnosable"
	audiences = SYMPTOM_AUDIENCE_SCANNER

/datum/affliction_symptom/lesion_finding/contusion
	name = "organ contusion"
	clinical_description = "Bruised, swollen organ tissue."
	scanner_phrase = "contused organ tissue"

/datum/affliction_symptom/lesion_finding/laceration
	name = "organ laceration"
	clinical_description = "A tear through an organ, bleeding into the body cavity."
	scanner_phrase = "torn organ tissue with active internal bleeding"

/datum/affliction_symptom/lesion_finding/perforation
	name = "organ perforation"
	clinical_description = "A hole through a hollow organ, leaking its contents."
	scanner_phrase = "perforated hollow organ leaking into the body cavity"

/datum/affliction_symptom/lesion_finding/necrosis
	name = "organ necrosis"
	clinical_description = "A region of dead organ tissue."
	scanner_phrase = "necrotic organ tissue; resection indicated"

/datum/affliction_symptom/lesion_finding/ischemic
	name = "ischemic organ injury"
	clinical_description = "Organ tissue damaged by oxygen starvation."
	scanner_phrase = "hypoperfused organ tissue with ischemic damage"

/datum/affliction_symptom/lesion_finding/toxic
	name = "toxic organ injury"
	clinical_description = "Organ tissue damaged by the toxins it was clearing."
	scanner_phrase = "toxic injury to filtering organ tissue"

/datum/affliction_symptom/lesion_finding/component_fault
	name = "component fault"
	category = "Hardware"
	clinical_description = "Faulted components inside a prosthetic organ."
	scanner_phrase = "internal component fault in prosthetic organ"

#undef LESION_TREATMENT_TICK_SCALE
#undef LESION_BLEED_PER_DAMAGE
#undef LESION_HEALED_EPSILON
#undef LESION_REGENERATION_RATE
#undef LESION_STABILISED_WINDOW
#undef BRAIN_SALVAGE_FRACTION
#undef BRAIN_TERMINAL_FRACTION
#undef BRAIN_EDEMA_RATE
#undef BRAIN_TERMINAL_EDEMA_RATE
#undef BRAIN_EDEMA_TREATED_MULT
#undef BRAIN_SWOLLEN_TREATMENT_MULT

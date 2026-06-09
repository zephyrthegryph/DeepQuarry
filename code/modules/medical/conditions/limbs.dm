// Limb-specific conditions.
//
// Most of these are heavy on mechanical effects rather than vital
// effects — losing the use of an arm matters more than the patient's
// pulse going up by five.
//
//   lacerated_artery       — sharp limb bleed; cascades to hypovolemia
//   tendon_severed         — arm/leg function lost until surgery
//   nerve_damage           — partial loss of feeling; chem-curable
//   compartment_syndrome   — crush/burn → tissue dying, terminal-class
//   tissue_necrosis        — terminal limb dysfunction (cascade endpoint)
//
// `pick_cascade_target()` overrides exist for conditions whose effect
// depends on knowing which limb is affected (e.g., tendon_severed on
// arm vs leg branches the mechanical effects).

/datum/medical_issue/condition/lacerated_artery
	name = "lacerated artery"
	category = "Limbs"
	clinical_description = "A torn artery in a limb. Blood loss is rapid and obvious; direct pressure or a tourniquet is the only way to stop it."
	progression_rate = 2.0
	cured_by = list(REAGENT_ID_BICARIDAZE = 1.0, REAGENT_ID_TRICORDRAZINE = 0.5)
	worsened_by = list(REAGENT_ID_HYPERZINE = 0.8)
	symptom_pool = list(
		/datum/medical_symptom/bleeding_visible = 90,
		/datum/medical_symptom/sharp_pain       = 70,
		/datum/medical_symptom/pallor           = 60,
		/datum/medical_symptom/dizziness        = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	// No vital_effects — pulse and BP are derived from actual blood
	// volume; the bleed itself drives them through vitals.dm.
	mechanical_effects = list(
		"slowdown" = 0.5,
		"drop_held_prob" = 2,
		"spontaneous_emotes" = list("wince", "groan"),
		"spontaneous_emote_prob" = 3,
	)

// Arterial bleed — drains much faster than passive hemorrhage AND
// splatters visibly. Player's blood pool drops noticeably between
// checks, and the floor under them gets bloody.
/datum/medical_issue/condition/lacerated_artery/tick_condition()
	. = ..()
	if(severity <= 0 || !owner || !istype(owner, /mob/living/carbon/human))
		return
	var/mob/living/carbon/human/H = owner
	if(!H.vessel)
		return
	// Roughly 3× the rate of internal_hemorrhage. At severity 50 that's
	// ~0.9 units/tick → 27 units/min. `drip` calls `remove_blood`
	// internally and then splatters — leaves a visible blood trail.
	var/drain = (severity / 100) * 1.8
	if(drain > 0)
		H.drip(drain)

/datum/medical_issue/condition/lacerated_artery/damage_scaling()
	. = 1.0
	if(affectedorgan)
		var/obj/item/organ/external/E = affectedorgan
		if(istype(E))
			. *= dq_damage_scale(E.brute_dam, 10, 50, 0.7, 2.2)
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		if(H.vessel && H.species)
			var/blood_now = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
			var/blood_max = H.species.blood_volume
			if(blood_max > 0)
				var/lost_frac = clamp(1 - (blood_now / blood_max), 0, 1)
				. *= dq_damage_scale(lost_frac, 0, 0.4, 1.0, 1.8)

// Tendon severed. Surgical fix only — chems can't repair it.
// progression_rate=0 means the condition stays at whatever severity it
// spawned at indefinitely (no decay, no growth). It's a permanent
// dysfunction until surgery clears it.
/datum/medical_issue/condition/tendon_severed
	name = "severed tendon"
	category = "Limbs"
	clinical_description = "A cut tendon. The limb won't move properly until it's surgically reattached — medicines won't fix it."
	progression_rate = 0
	// No reagents help. Surgery only.
	cured_by = null
	symptom_pool = list(
		/datum/medical_symptom/sharp_pain      = 60,
		/datum/medical_symptom/burning_limb    = 40,
		/datum/medical_symptom/limb_weakness   = 80,
	)
	min_symptoms = 1
	max_symptoms = 3

/datum/medical_issue/condition/tendon_severed/New()
	..()
	// Spawn with severity 50 so it presents symptoms immediately.
	severity = 50

// Branch mechanical effects on the affected limb. Arms drop items
// (the affected hand can't hold anything); legs heavily slow movement.
//
// `mechanical_effects` only depends on which limb is affected, which is
// stable for the lifetime of the condition. Build the dict once when
// `affectedorgan` is first observed and reuse — the prior version
// reallocated the list literal on every Life tick.
/datum/medical_issue/condition/tendon_severed/tick_condition()
	. = ..()
	if(!affectedorgan)
		return
	if(mechanical_effects)
		return
	switch(affectedorgan.organ_tag)
		if(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND)
			mechanical_effects = list(
				"block_hold_arm" = affectedorgan.organ_tag,
				"drop_held_prob" = 100,
				"spontaneous_emotes" = list("wince at their useless arm"),
				"spontaneous_emote_prob" = 2,
			)
		if(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
			mechanical_effects = list(
				"slowdown" = 2.0,
				"spontaneous_emotes" = list("limps badly"),
				"spontaneous_emote_prob" = 3,
			)

/datum/medical_issue/condition/nerve_damage
	name = "nerve damage"
	category = "Limbs"
	clinical_description = "Peripheral nerves injured by trauma, crushing, or heat. Sensation in the affected limb is partly lost and returns slowly on its own."
	progression_rate = -0.25  // very slow self-heal
	cured_by = list(REAGENT_ID_ALKYSINE = 0.3, REAGENT_ID_BICARIDAZE = 0.2)
	symptom_pool = list(
		/datum/medical_symptom/burning_limb = 50,
		/datum/medical_symptom/throbbing_pain = 30,
		/datum/medical_symptom/absent_reflex = 70,
		/datum/medical_symptom/limb_weakness = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	mechanical_effects = list(
		"accuracy_penalty" = 10,
		"drop_held_prob" = 1,
	)

/datum/medical_issue/condition/nerve_damage/New()
	..()
	severity = 60

/datum/medical_issue/condition/nerve_damage/tick_condition()
	. = ..()
	if(!affectedorgan)
		return
	// Add limb-specific symptom on top of the base pool.
	switch(affectedorgan.organ_tag)
		if(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND)
			// Inject numbness_arm into the pool if not already there.
			if(symptom_pool && !(/datum/medical_symptom/numbness_arm in symptom_pool))
				symptom_pool[/datum/medical_symptom/numbness_arm] = 60
		if(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
			if(symptom_pool && !(/datum/medical_symptom/numbness_leg in symptom_pool))
				symptom_pool[/datum/medical_symptom/numbness_leg] = 60

/datum/medical_issue/condition/compartment_syndrome
	name = "compartment syndrome"
	category = "Limbs"
	clinical_description = "Swelling inside a limb has cut off its own blood supply. Untreated, the tissue inside dies."
	progression_rate = 0.5
	// Surgical decompression is the real cure. Chems only slow it.
	cured_by = list(REAGENT_ID_INAPROVALINE = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/burning_limb     = 90,
		/datum/medical_symptom/sharp_pain       = 80,
		/datum/medical_symptom/throbbing_pain   = 70,
		/datum/medical_symptom/pallor           = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	mechanical_effects = list(
		"slowdown" = 1.0,
		"accuracy_penalty" = 15,
		"drop_held_prob" = 3,
		"spontaneous_emotes" = list("clutch at their limb", "groan in agony"),
		"spontaneous_emote_prob" = 5,
	)

/datum/medical_issue/condition/tissue_necrosis
	name = "tissue necrosis"
	category = "Limbs"
	clinical_description = "Dead tissue in a limb. It does not recover; surgical removal is the only way to stop it from poisoning the rest of the body."
	progression_rate = 0  // permanent until surgery / amputation
	// No chem cure. Surgical removal of dead tissue is the only fix.
	cured_by = null
	symptom_pool = list(
		/datum/medical_symptom/burning_limb       = 60,
		/datum/medical_symptom/numbness_arm       = 50,
		/datum/medical_symptom/numbness_leg       = 50,
		/datum/medical_symptom/cold_mottled_skin  = 80,
	)
	min_symptoms = 2
	max_symptoms = 3
	mechanical_effects = list(
		"slowdown" = 1.5,
		"accuracy_penalty" = 20,
		"spontaneous_emotes" = list("smells faintly of decay"),
		"spontaneous_emote_prob" = 2,
	)

/datum/medical_issue/condition/tissue_necrosis/New()
	..()
	severity = 75

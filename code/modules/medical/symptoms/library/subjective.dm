// Symptom library — starter set for trauma / burn / infection conditions.
// New symptoms live alongside these; one symptom per stanza for grep-ability.
//
// The `patient_messages` and `public_emotes` lists live in per-subtype
// procs rather than instance vars. Each returns a `var/static/list/`
// local, so the message data is allocated exactly once per subtype on
// first read and shared across every active instance. The base class
// returns null for both, so a symptom that never speaks to the patient
// or public allocates no list at all. See _symptom.dm.

// --- Patient-only sensations ---

/datum/medical_symptom/headache
	name = "headache"
	category = "Subjective"
	clinical_description = "Diffuse cranial pain, frequently retro-orbital."
	audiences = SYMPTOM_AUDIENCE_PATIENT
	patient_message_chance = 5

/datum/medical_symptom/headache/get_patient_messages()
	var/static/list/L = list(
		"A dull headache builds behind your eyes.",
		"Your head throbs.",
	)
	return L


/datum/medical_symptom/dizziness
	name = "dizziness"
	category = "Subjective"
	clinical_description = "Transient loss of equilibrium and spatial orientation."
	audiences = SYMPTOM_AUDIENCE_PATIENT
	patient_message_chance = 5

/datum/medical_symptom/dizziness/get_patient_messages()
	var/static/list/L = list(
		"The room sways for a moment.",
		"You feel briefly lightheaded.",
		"Your balance feels off.",
	)
	return L


/datum/medical_symptom/blurred_vision
	name = "blurred vision"
	category = "Subjective"
	clinical_description = "Reduced visual acuity, particularly at the periphery."
	audiences = SYMPTOM_AUDIENCE_PATIENT

/datum/medical_symptom/blurred_vision/get_patient_messages()
	var/static/list/L = list(
		"Your vision blurs at the edges.",
		"It's hard to focus your eyes.",
	)
	return L


/datum/medical_symptom/internal_pressure
	name = "internal pressure"
	category = "Subjective"
	clinical_description = "Vague visceral pressure without clear localisation; commonly precedes overt hemorrhage."
	audiences = SYMPTOM_AUDIENCE_PATIENT
	patient_message_chance = 3

/datum/medical_symptom/internal_pressure/get_patient_messages()
	var/static/list/L = list(
		"You feel an odd pressure deep inside.",
		"Something doesn't feel right.",
	)
	return L


/datum/medical_symptom/fatigue
	name = "fatigue"
	category = "Subjective"
	clinical_description = "Generalised loss of stamina and concentration disproportionate to recent exertion."
	audiences = SYMPTOM_AUDIENCE_PATIENT

/datum/medical_symptom/fatigue/get_patient_messages()
	var/static/list/L = list(
		"You feel inexplicably tired.",
		"It's getting hard to stay alert.",
	)
	return L


/datum/medical_symptom/numbness_arm
	name = "numb arm"
	category = "Subjective"
	clinical_description = "Loss of sensation in the affected arm and hand; reduced fine-motor function."
	audiences = SYMPTOM_AUDIENCE_PATIENT

/datum/medical_symptom/numbness_arm/get_patient_messages()
	var/static/list/L = list(
		"Your arm feels numb and useless.",
		"You can barely feel your fingers.",
	)
	return L


/datum/medical_symptom/numbness_leg
	name = "numb leg"
	category = "Subjective"
	clinical_description = "Loss of sensation in the affected leg and foot; reduced proprioception."
	audiences = SYMPTOM_AUDIENCE_PATIENT

/datum/medical_symptom/numbness_leg/get_patient_messages()
	var/static/list/L = list(
		"Your leg feels numb and dead.",
		"You can barely feel where your foot ends.",
	)
	return L


/datum/medical_symptom/burning_limb
	name = "burning limb"
	category = "Subjective"
	clinical_description = "Deep, persistent burning sensation in the affected limb without visible cause."
	audiences = SYMPTOM_AUDIENCE_PATIENT
	patient_message_chance = 6

/datum/medical_symptom/burning_limb/get_patient_messages()
	var/static/list/L = list(
		"Your limb feels like it's on fire from the inside.",
		"There's an unbearable burning sensation deep in the tissue.",
	)
	return L

// Symptom library — starter set for trauma / burn / infection conditions.
// New symptoms live alongside these; one symptom per stanza for grep-ability.
//
// The `patient_messages` and `public_emotes` lists live in per-subtype
// procs rather than instance vars. Each returns a `var/static/list/`
// local, so the message data is allocated exactly once per subtype on
// first read and shared across every active instance. The base class
// returns null for both, so a symptom that never speaks to the patient
// or public allocates no list at all. See _symptom.dm.

// --- Pain ---

/datum/medical_symptom/sharp_pain
	name = "sharp pain"
	category = "Observable"
	clinical_description = "Sudden, localized pain at the site of injury; intensifies with motion."
	examine_line = "They wince whenever they shift their weight."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	patient_message_chance = 7
	public_emote_chance = 4

/datum/medical_symptom/sharp_pain/get_patient_messages()
	var/static/list/L = list(
		"A sharp pain stabs through your body.",
		"Your injury flares with pain.",
	)
	return L

/datum/medical_symptom/sharp_pain/get_public_emotes()
	var/static/list/L = list("winces in pain", "grimaces")
	return L


/datum/medical_symptom/throbbing_pain
	name = "throbbing pain"
	category = "Subjective"
	clinical_description = "Deep, rhythmic pain synchronised with the cardiac cycle."
	audiences = SYMPTOM_AUDIENCE_PATIENT
	patient_message_chance = 5

/datum/medical_symptom/throbbing_pain/get_patient_messages()
	var/static/list/L = list(
		"A deep, throbbing pain pulses inside you.",
		"Your injury throbs with each heartbeat.",
	)
	return L


/datum/medical_symptom/chest_pain_crushing
	name = "crushing chest pain"
	category = "Observable"
	clinical_description = "Severe substernal pressure, often radiating; a hallmark of cardiac distress."
	examine_line = "They are clutching their chest in obvious distress."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	patient_message_chance = 8
	public_emote_chance = 5

/datum/medical_symptom/chest_pain_crushing/get_patient_messages()
	var/static/list/L = list(
		"A crushing pressure builds in your chest.",
		"Your chest feels like it's being squeezed in a vice.",
	)
	return L

/datum/medical_symptom/chest_pain_crushing/get_public_emotes()
	var/static/list/L = list("clutches their chest", "grimaces and clutches at their chest")
	return L


/datum/medical_symptom/sharp_chest_pain
	name = "sharp chest pain"
	category = "Observable"
	clinical_description = "Pleuritic chest pain worsened by inspiration; suggestive of pneumothorax or rib fracture."
	examine_line = "They wince sharply each time they inhale."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	patient_message_chance = 7
	public_emote_chance = 3

/datum/medical_symptom/sharp_chest_pain/get_patient_messages()
	var/static/list/L = list(
		"A sharp pain shoots through your chest with each breath.",
		"Your chest feels like it's being stabbed.",
	)
	return L

/datum/medical_symptom/sharp_chest_pain/get_public_emotes()
	var/static/list/L = list("winces while breathing")
	return L

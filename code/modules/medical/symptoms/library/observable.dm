// Symptom library — starter set for trauma / burn / infection conditions.
// New symptoms live alongside these; one symptom per stanza for grep-ability.
//
// The `patient_messages` and `public_emotes` lists live in per-subtype
// procs rather than instance vars. Each returns a `var/static/list/`
// local, so the message data is allocated exactly once per subtype on
// first read and shared across every active instance. The base class
// returns null for both, so a symptom that never speaks to the patient
// or public allocates no list at all. See _symptom.dm.

// --- Public + scanner (visible signs) ---

/datum/medical_symptom/pallor
	name = "pallor"
	category = "Observable"
	clinical_description = "Pale complexion from reduced peripheral perfusion; visible in mucous membranes."
	examine_line = "They look unnaturally pale."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "abnormally pale skin"

/datum/medical_symptom/pallor/get_public_emotes()
	var/static/list/L = list("looks pale")
	return L


/datum/medical_symptom/cyanosis
	name = "cyanosis"
	category = "Observable"
	clinical_description = "Bluish discolouration of the lips and extremities indicating impaired oxygenation."
	examine_line = "Their lips and fingertips have a bluish tinge."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "cyanosis of the lips and extremities"

/datum/medical_symptom/cyanosis/get_public_emotes()
	var/static/list/L = list("has a faint blue tinge to their lips")
	return L


/datum/medical_symptom/bleeding_visible
	name = "external bleeding"
	category = "Observable"
	clinical_description = "Active blood loss from an external wound; the rate indicates vessel involvement."
	examine_line = "They are bleeding heavily."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 3
	scanner_phrase = "active external blood loss"

/datum/medical_symptom/bleeding_visible/get_public_emotes()
	var/static/list/L = list("bleeds heavily")
	return L


/datum/medical_symptom/jaundice
	name = "jaundice"
	category = "Observable"
	clinical_description = "Yellow tinge to the skin and the whites of the eyes from accumulated metabolic byproducts the liver can no longer clear."
	examine_line = "There's a faint yellow cast to their skin."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "icterus on inspection"

/datum/medical_symptom/jaundice/get_public_emotes()
	var/static/list/L = list("looks faintly yellow")
	return L


/datum/medical_symptom/chills
	name = "chills"
	category = "Observable"
	clinical_description = "Involuntary shivering and a subjective sensation of cold."
	examine_line = "They are visibly shivering."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	public_emote_chance = 3

/datum/medical_symptom/chills/get_patient_messages()
	var/static/list/L = list(
		"A cold shiver runs through you.",
		"You feel a sudden chill.",
	)
	return L

/datum/medical_symptom/chills/get_public_emotes()
	var/static/list/L = list("shivers")
	return L


/datum/medical_symptom/fever_sensation
	name = "feverish sensation"
	category = "Observable"
	clinical_description = "Warmth across the body and flushed skin, often without measurable core temperature change."
	examine_line = "Their face is flushed and beaded with sweat."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	public_emote_chance = 2

/datum/medical_symptom/fever_sensation/get_patient_messages()
	var/static/list/L = list(
		"You feel uncomfortably warm.",
		"Your skin feels flushed.",
	)
	return L

/datum/medical_symptom/fever_sensation/get_public_emotes()
	var/static/list/L = list("looks flushed", "wipes their brow")
	return L


/datum/medical_symptom/cold_mottled_skin
	name = "cold, mottled skin"
	category = "Observable"
	clinical_description = "Patches of grey-purple discoloration over the affected tissue, cold to the touch. The tissue underneath has died."
	examine_line = "Their skin is patchy and grey in places, cool to the touch."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "discoloured, devitalised tissue; necrosis confirmed"

/datum/medical_symptom/cold_mottled_skin/get_public_emotes()
	var/static/list/L = list("has a patch of skin that looks grey and lifeless")
	return L


/datum/medical_symptom/unsteady_gait
	name = "unsteady gait"
	category = "Observable"
	clinical_description = "The patient sways or stumbles when standing or walking; balance and proprioception are impaired."
	examine_line = "They look unsteady on their feet."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 3
	scanner_phrase = "ataxia on motor examination"

/datum/medical_symptom/unsteady_gait/get_public_emotes()
	var/static/list/L = list("sways unsteadily", "stumbles slightly")
	return L


/datum/medical_symptom/pupillary_asymmetry
	name = "uneven pupils"
	category = "Observable"
	clinical_description = "The patient's pupils are unequal in size. A reliable sign of raised intracranial pressure or focal brain injury."
	examine_line = "Their pupils don't look quite the same size."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 1
	scanner_phrase = "anisocoria; suspected intracranial pathology"

/datum/medical_symptom/pupillary_asymmetry/get_public_emotes()
	var/static/list/L = list("blinks slowly, one pupil noticeably larger than the other")
	return L


/datum/medical_symptom/cloudy_eye
	name = "cloudy eye"
	category = "Observable"
	clinical_description = "The lens or retina is visibly damaged; the eye looks dull and unresponsive to light."
	examine_line = "Their eye looks oddly cloudy."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "loss of retinal definition; vision compromised"

/datum/medical_symptom/cloudy_eye/get_public_emotes()
	var/static/list/L = list("squints, one eye unfocused")
	return L


/datum/medical_symptom/limb_weakness
	name = "limb weakness"
	category = "Observable"
	clinical_description = "The patient can't fully extend or grip with the affected limb; motor control on one side is reduced."
	examine_line = "Their limb hangs limply."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 3
	scanner_phrase = "motor weakness in affected limb"

/datum/medical_symptom/limb_weakness/get_public_emotes()
	var/static/list/L = list("can't quite grip with their affected hand", "drags their leg slightly")
	return L


/datum/medical_symptom/skin_burns_minor
	name = "early radiation burns"
	category = "Observable"
	clinical_description = "Patchy erythema and skin breakdown — an early dermal sign of radiation exposure that precedes overt sickness."
	examine_line = "Their skin shows red, raw patches in places."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "dermal radiation injury; early burns visible"

/datum/medical_symptom/skin_burns_minor/get_public_emotes()
	var/static/list/L = list("has red, raw patches of skin")
	return L


// --- Chem side-effect symptoms ----------------------------------------
// Drip when a chem above its threshold spawns a side condition.

/datum/medical_symptom/drowsy
	name = "drowsiness"
	category = "Observable"
	clinical_description = "Slowed responses and a tendency to drift off — typical of opioid analgesia."
	examine_line = "Their eyelids droop and their head bobs slightly."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 4
	scanner_phrase = "diminished arousal; opioid-class CNS depression suspected"

/datum/medical_symptom/drowsy/get_patient_messages()
	var/static/list/L = list(
		"Your eyelids feel heavy.",
		"It's hard to keep your head up.",
	)
	return L

/datum/medical_symptom/drowsy/get_public_emotes()
	var/static/list/L = list("yawns deeply", "nods off for a moment")
	return L


/datum/medical_symptom/jittery
	name = "jitteriness"
	category = "Observable"
	clinical_description = "Restless small movements and an unsettled affect — typical of stimulant or neuro-activating chems."
	examine_line = "They keep fidgeting and shifting in place."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	public_emote_chance = 3

/datum/medical_symptom/jittery/get_patient_messages()
	var/static/list/L = list(
		"You feel restless, can't quite sit still.",
		"There's a buzzing energy under your skin.",
	)
	return L

/datum/medical_symptom/jittery/get_public_emotes()
	var/static/list/L = list("fidgets restlessly", "shifts from foot to foot")
	return L


// Nausea is primarily a subjective sensation, but severe enough nausea
// makes the patient vomit — which is visible. Modelled as PATIENT for
// the steady queasy drip and PUBLIC for the occasional retching/heaving
// event a medic can see across the room. Public chance is intentionally
// low: vomiting is the punctuation, not the constant.
/datum/medical_symptom/nausea
	name = "nausea"
	category = "Observable"
	clinical_description = "Urge to vomit; frequently autonomic rather than gastric in origin. Severe enough nausea produces intermittent vomiting that's visible to bystanders."
	examine_line = "They look queasy, swallowing hard."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	public_emote_chance = 2

/datum/medical_symptom/nausea/get_patient_messages()
	var/static/list/L = list(
		"You feel queasy.",
		"Your stomach turns.",
		"A wave of nausea rolls through you.",
	)
	return L

/datum/medical_symptom/nausea/get_public_emotes()
	var/static/list/L = list(
		"retches",
		"heaves and vomits",
		"clutches their stomach and gags",
	)
	return L

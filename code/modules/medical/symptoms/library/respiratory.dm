// Symptom library — starter set for trauma / burn / infection conditions.
// New symptoms live alongside these; one symptom per stanza for grep-ability.
//
// The `patient_messages` and `public_emotes` lists live in per-subtype
// procs rather than instance vars. Each returns a `var/static/list/`
// local, so the message data is allocated exactly once per subtype on
// first read and shared across every active instance. The base class
// returns null for both, so a symptom that never speaks to the patient
// or public allocates no list at all. See _symptom.dm.

// --- Respiratory ---

/datum/medical_symptom/short_breath
	name = "shortness of breath"
	category = "Observable"
	clinical_description = "Subjective sense of inadequate ventilation accompanied by tachypnea."
	examine_line = "Their breathing is quick and shallow."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 4
	scanner_phrase = "elevated respiratory rate"

/datum/medical_symptom/short_breath/get_patient_messages()
	var/static/list/L = list(
		"You're having trouble catching your breath.",
		"Each breath feels harder than the last.",
	)
	return L

/datum/medical_symptom/short_breath/get_public_emotes()
	var/static/list/L = list("breathes heavily")
	return L


/datum/medical_symptom/wet_cough
	name = "wet cough"
	category = "Observable"
	clinical_description = "Productive cough with audible fluid; suggests pulmonary contusion or fluid accumulation."
	examine_line = "They cough wetly into their hand, leaving a damp smear."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 5
	scanner_phrase = "productive cough with fluid"

/datum/medical_symptom/wet_cough/get_patient_messages()
	var/static/list/L = list(
		"You cough up something wet.",
		"You taste copper in your mouth.",
	)
	return L

/datum/medical_symptom/wet_cough/get_public_emotes()
	var/static/list/L = list("coughs wetly")
	return L


/datum/medical_symptom/wheeze
	name = "wheezing"
	category = "Observable"
	clinical_description = "High-pitched musical sound on expiration from narrowed airways."
	examine_line = "Every breath comes with a faint whistle."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 4
	scanner_phrase = "audible wheeze on auscultation"

/datum/medical_symptom/wheeze/get_patient_messages()
	var/static/list/L = list(
		"Each breath comes with a whistling sound.",
	)
	return L

/datum/medical_symptom/wheeze/get_public_emotes()
	var/static/list/L = list("wheezes")
	return L


/datum/medical_symptom/labored_breathing
	name = "labored breathing"
	category = "Observable"
	clinical_description = "Visible use of accessory respiratory muscles; each breath requires conscious effort."
	examine_line = "They are visibly struggling for each breath."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 5
	scanner_phrase = "severely labored respiration"

/datum/medical_symptom/labored_breathing/get_patient_messages()
	var/static/list/L = list(
		"You're working hard for every breath.",
		"Each inhale takes effort.",
	)
	return L

/datum/medical_symptom/labored_breathing/get_public_emotes()
	var/static/list/L = list("gasps", "struggles to breathe")
	return L

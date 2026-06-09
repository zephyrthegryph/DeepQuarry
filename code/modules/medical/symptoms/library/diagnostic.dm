// Symptom library — starter set for trauma / burn / infection conditions.
// New symptoms live alongside these; one symptom per stanza for grep-ability.
//
// The `patient_messages` and `public_emotes` lists live in per-subtype
// procs rather than instance vars. Each returns a `var/static/list/`
// local, so the message data is allocated exactly once per subtype on
// first read and shared across every active instance. The base class
// returns null for both, so a symptom that never speaks to the patient
// or public allocates no list at all. See _symptom.dm.

// --- Diagnostic markers --- scanner-visible findings for conditions
// whose subjective symptoms would otherwise be invisible to medics.

/datum/medical_symptom/confusion
	name = "confusion"
	category = "Observable"
	clinical_description = "Disorientation, slowed cognition, and impaired short-term memory."
	examine_line = "They look disoriented, their gaze unfocused."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC
	public_emote_chance = 2

/datum/medical_symptom/confusion/get_patient_messages()
	var/static/list/L = list(
		"You can't remember what you were just doing.",
		"Your thoughts feel scattered.",
	)
	return L

/datum/medical_symptom/confusion/get_public_emotes()
	var/static/list/L = list("looks confused", "stares blankly")
	return L


/datum/medical_symptom/palpitations
	name = "palpitations"
	category = "Diagnosable"
	clinical_description = "Awareness of irregular or forceful cardiac contractions."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "irregular cardiac rhythm"

/datum/medical_symptom/palpitations/get_patient_messages()
	var/static/list/L = list(
		"Your heart skips a beat.",
		"Your chest flutters strangely.",
	)
	return L


/datum/medical_symptom/abdominal_tenderness
	name = "abdominal tenderness"
	category = "Diagnosable"
	clinical_description = "Pain on palpation of the abdomen; suggests inflammation or internal hemorrhage."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_SCANNER
	patient_message_chance = 3
	scanner_phrase = "abdominal tenderness on palpation"

/datum/medical_symptom/abdominal_tenderness/get_patient_messages()
	var/static/list/L = list(
		"Your belly feels tender when you move.",
	)
	return L


/datum/medical_symptom/absent_reflex
	name = "absent reflex"
	category = "Diagnosable"
	clinical_description = "The limb fails to respond to reflex testing; the affected peripheral nerve is no longer conducting normally."
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "no reflex response in affected limb; suspected peripheral nerve damage"


/datum/medical_symptom/radiation_reading
	name = "elevated radiation reading"
	category = "Diagnosable"
	clinical_description = "The patient's body is registering above-background ionising radiation. Tissue damage will follow if exposure continues."
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "elevated radiation signature in patient tissue"


/datum/medical_symptom/genetic_instability
	name = "genetic instability"
	category = "Diagnosable"
	clinical_description = "The patient's chromosomes are fragmenting. The genome is no longer transcribing cleanly; mitotically active tissues will degrade first."
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "chromosomal damage detected in nucleated cells"

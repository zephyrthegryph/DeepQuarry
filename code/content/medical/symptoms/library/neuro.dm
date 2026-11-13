// Symptom library: seizure and bone presentations (see conditions/seizure.dm and conditions/malunion.dm).
// Same conventions as the rest of the library (observable.dm): message tables per subtype, one symptom per stanza.

// --- Seizure ---

/// The patient shakes and falls: while the condition runs, every tick keeps them jittering and floored.
/datum/affliction_symptom/convulsions
	name = "convulsions"
	category = "Observable"
	clinical_description = "Rhythmic, uncontrolled jerking of the whole body; the patient cannot stand or act until it passes."
	examine_line = "They are convulsing uncontrollably."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	patient_message_chance = 20
	public_emote_chance = 10
	scanner_phrase = "convulsions"

TYPE_TABLE(/datum/affliction_symptom/convulsions, get_patient_messages, list( \
		"Your muscles lock and jerk out of your control.", \
		"Your limbs thrash on their own.", \
	))

TYPE_TABLE(/datum/affliction_symptom/convulsions, get_public_emotes, list("convulses", "thrashes uncontrollably"))

/datum/affliction_symptom/convulsions/tick(mob/living/M, datum/affliction/source)
	. = ..()
	if(!M || !source)
		return
	M.status_at_least(STAT_JITTERY, 100)
	M.status_at_least(STAT_WEAKENED, 3)


/// Nobody home: the seizure has taken the patient's awareness.
/datum/affliction_symptom/unresponsive
	name = "unresponsive"
	category = "Observable"
	clinical_description = "No purposeful response to voice or touch; the eyes are open but unfocused."
	examine_line = "They stare blankly and do not respond."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 0
	scanner_phrase = "unresponsive to stimuli"


// --- Bone ---

/// The dull ache of a bone that healed crooked, or of a drug that forces bone growth. Masked by HIDE_PAIN like every pain sign.
/datum/affliction_symptom/bone_ache
	name = "bone ache"
	category = "Subjective"
	subcategory = SYMPTOM_SUBCATEGORY_PAIN
	clinical_description = "A deep, dull ache in the long bones, worse with weight and weather."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_SCANNER
	patient_message_chance = 4
	scanner_phrase = "deep bone ache"

TYPE_TABLE(/datum/affliction_symptom/bone_ache, get_patient_messages, list( \
		"Your bones ache deep inside.", \
		"A dull ache settles into the bone.", \
	))

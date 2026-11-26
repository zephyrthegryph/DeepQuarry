// Symptom library: speech presentations. Same conventions as the rest of the library (observable.dm): message tables per subtype, one symptom per stanza.

/// The patient's words run together while the condition runs: every tick keeps a little slurring on them.
/datum/affliction_symptom/slurred_speech
	name = "slurred speech"
	category = "Observable"
	clinical_description = "Words run together and consonants blur; the patient is hard to understand."
	examine_line = "Their speech is slurred."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	patient_message_chance = 3
	scanner_phrase = "slurred speech"

TYPE_TABLE(/datum/affliction_symptom/slurred_speech, get_patient_messages, list( \
		"Your tongue feels thick and clumsy.", \
		"Your words come out all run together.", \
	))

/datum/affliction_symptom/slurred_speech/tick(mob/living/M, datum/affliction/source)
	. = ..()
	if(!M || !source)
		return
	M.status_at_least(STAT_SLURRING, 10)

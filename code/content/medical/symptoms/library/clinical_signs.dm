// Symptom library: scanner-visible signs for conditions that had none (untreated fracture, cellulitis, profane corruption,
// neurotoxic envenomation). A basic analyzer reads these phrases as signs, a bystander sees the examine line.

/datum/affliction_symptom/bone_crepitus
	name = "bone crepitus"
	category = "Diagnosable"
	clinical_description = "A grating sensation and abnormal movement at the break; the limb is guarded and tender over the fracture."
	examine_line = "They are guarding an injured limb, holding it carefully still."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "bony crepitus and abnormal movement; suspected fracture"

TYPE_TABLE(/datum/affliction_symptom/bone_crepitus, get_public_emotes, list("holds an injured limb still"))


/datum/affliction_symptom/localised_inflammation
	name = "localised inflammation"
	category = "Observable"
	clinical_description = "A hot, red, swollen and tender patch of skin over the infected tissue."
	examine_line = "There is an angry, red, swollen patch on their skin."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 2
	scanner_phrase = "localised warmth, erythema and swelling; soft-tissue infection"

TYPE_TABLE(/datum/affliction_symptom/localised_inflammation, get_public_emotes, list("rubs a hot, swollen patch of skin"))


/datum/affliction_symptom/tainted_blood
	name = "tainted blood"
	category = "Diagnosable"
	clinical_description = "An unidentifiable contaminant in the blood and nervous system, with whispers and dread the patient cannot place."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_SCANNER
	patient_message_chance = 5
	scanner_phrase = "unidentified contaminant in the blood and nervous system"

TYPE_TABLE(/datum/affliction_symptom/tainted_blood, get_patient_messages, list( \
		"You hear whispers just out of reach.", \
		"A creeping dread settles over you.", \
		"Something is wrong in your blood.", \
	))


/datum/affliction_symptom/neurotoxic_tremor
	name = "neurotoxic tremor"
	category = "Observable"
	clinical_description = "Fine tremor and burning hypersensitivity along the nerves from a neurotoxic sting."
	examine_line = "A fine tremor runs through their hands."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	patient_message_chance = 5
	public_emote_chance = 2
	scanner_phrase = "peripheral neurotoxic effect: tremor and hypersensitivity"

TYPE_TABLE(/datum/affliction_symptom/neurotoxic_tremor, get_patient_messages, list( \
		"Your skin burns where the venom spread.", \
		"Your hands will not stop trembling.", \
	))

TYPE_TABLE(/datum/affliction_symptom/neurotoxic_tremor, get_public_emotes, list("trembles", "flinches at nothing"))

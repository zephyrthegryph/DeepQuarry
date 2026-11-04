// --- Arachnid envenomation (giant spider toxins) ----------------------------------------------------
// A liquefying venom injected by giant spiders: painful and systemic.
/datum/affliction/venom/arachnid
	name = "arachnid envenomation"
	clinical_description = "Giant-spider venom beginning to liquefy tissue around the bite and spreading systemically. Burning pain, weakness, nausea. Antitoxin neutralises the venom; analgesics control the pain."
	progression_rate = 0
	pain_at_max = 60
	treated_by = list(TREAT_ANTITOXIN = 1.3, TREAT_ANALGESIC = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/sharp_pain     = 80,
		/datum/affliction_symptom/throbbing_pain = 60,
		/datum/affliction_symptom/limb_weakness  = 50,
		/datum/affliction_symptom/nausea         = 40,
	)
	min_symptoms = 1
	max_symptoms = 3

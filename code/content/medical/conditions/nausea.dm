// Nausea: a treatable condition of its own, not only a symptom of something else.
//
// It sits on the stomach, grows milder by itself, and makes the patient vomit now and then at a rate that follows its severity (do_vomit(), which
// already respects STAT_ANTIEMETIC). Calcium carbonate treats it (TREAT_ANTIEMETIC) and, through the same stat, stops the vomiting outright.
// It presents with the nausea symptom (observable.dm); the lesion and organ conditions that list that symptom are unaffected.
//
// Drugs that cause nausea subtype it the way overdoses and side effects are written:
//   /datum/affliction/nausea/<drug>
//       name = "<drug> nausea"
//       caused_by_chems = list(REAGENT_ID_X = 5)
//       progression_rate = 0   (a chem-caused one is held by the chem, and cleared when it leaves)
// The base type has no caused_by_chems, so nothing spawns it on its own; a subtype may add symptoms to the pool or change the organ.

/datum/affliction/nausea
	name = "nausea"
	category = "Gastrointestinal"
	subcategory = "Nausea"
	clinical_description = "A queasy, unsettled stomach with the urge to vomit. Severe nausea brings on bouts of vomiting. It settles by itself, and antiemetics (calcium carbonate) settle it sooner."
	biology = BIOLOGY_ORGANIC
	// Fades by itself unless something holds it (a chem-caused subtype sets this to 0).
	progression_rate = -0.5
	initial_severity = 60
	treated_by = list(TREAT_ANTIEMETIC = 2)
	symptom_pool = list(
		/datum/affliction_symptom/nausea   = 100,
		/datum/affliction_symptom/dizziness = 30,
		/datum/affliction_symptom/pallor    = 20,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems_organ = O_STOMACH

/datum/affliction/nausea/tick()
	. = ..()
	if(QDELETED(src) || !owner || owner.stat == DEAD || severity < NAUSEA_VOMIT_MIN_SEVERITY)
		return
	if(prob(severity * NAUSEA_VOMIT_CHANCE_PER_SEVERITY))
		if(GLOB.chem_trace)
			log_world("CHEM: nausea ([type], severity [severity]) makes [owner] vomit")
		owner.do_vomit(5, FALSE, 2)

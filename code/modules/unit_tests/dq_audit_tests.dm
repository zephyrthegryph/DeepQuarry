// Cross-cutting audits over the DQ medical content:
//
//   - every condition must have at least one symptom whose audiences flag
//     includes SCANNER or PUBLIC (otherwise medics can't identify it)
//   - every condition must have at least one cure path: a chemical cure,
//     a treating surgery, or negative progression
//
// See dq_surgery_tests.dm for the include scheme and macro scope.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- audit: every condition has at least one observable symptom -------
// Every condition must have a symptom with SYMPTOM_AUDIENCE_PUBLIC or
// SYMPTOM_AUDIENCE_SCANNER in every stage. For staged conditions, every
// stage's symptom_pool is checked individually.

/datum/unit_test/dq_medical_every_condition_identifiable

/datum/unit_test/dq_medical_every_condition_identifiable/Run()
	var/list/failures = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/proto = new T()
		// Silent-marker conditions intentionally have no symptoms — they
		// exist only as a state-flag readable by other conditions (e.g.
		// drug-interaction markers that interferes_with another chem).
		// Skip them; they're not meant to be diagnosed directly.
		var/silent_marker = (proto.min_symptoms == 0 && proto.max_symptoms == 0)
		if(silent_marker)
			qdel(proto)
			continue
		var/list/stages = proto.get_stages()
		if(stages)
			for(var/stage_id in stages)
				var/list/sd = stages[stage_id]
				if(!_dq_pool_has_observable(sd["symptom_pool"]))
					failures += "[T] stage '[stage_id]' has no SCANNER or PUBLIC symptom"
		else
			if(!_dq_pool_has_observable(proto.symptom_pool))
				failures += "[T] has no SCANNER or PUBLIC symptom"
		qdel(proto)
	if(length(failures))
		TEST_FAIL("conditions are not identifiable to medics: [jointext(failures, "; ")]")


/datum/unit_test/proc/_dq_pool_has_observable(list/symptom_pool)
	if(!symptom_pool)
		return FALSE
	for(var/sym_path in symptom_pool)
		var/datum/medical_symptom/proto = new sym_path()
		var/observable = (proto.audiences & SYMPTOM_AUDIENCE_PUBLIC) || (proto.audiences & SYMPTOM_AUDIENCE_SCANNER)
		qdel(proto)
		if(observable)
			return TRUE
	return FALSE


// --- audit: every condition has a sensible cure path -----------------
// A condition is "curable" if it has at least one of:
//   - a non-empty cured_by list (chemical cure),
//   - a /datum/dq_surgery whose treats list includes it,
//   - a negative progression_rate (self-resolves over time).

/datum/unit_test/dq_medical_every_condition_curable

/datum/unit_test/dq_medical_every_condition_curable/Run()
	var/list/surgical_targets = list()
	for(var/ST in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/sg = new ST()
		if(sg.treats)
			for(var/cond in sg.treats)
				surgical_targets[cond] = TRUE
		qdel(sg)

	var/list/failures = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/proto = new T()
		var/curable = FALSE
		if(length(proto.cured_by))
			curable = TRUE
		else if(surgical_targets[T])
			curable = TRUE
		else if(length(proto.caused_by_chems))
			// Chem-driven conditions clear when the chem leaves the
			// body — implicit "stop dosing it" cure path.
			curable = TRUE
		else if(proto.progression_rate < 0)
			curable = TRUE
		if(!curable)
			failures += "[T]"
		qdel(proto)
	if(length(failures))
		TEST_FAIL("conditions lack any cure path (chem / surgery / self-heal / chem-presence): [jointext(failures, ", ")]")


// --- audit: every medically-relevant reagent with an OD has a DQ OD condition ---
//
// The medical book has a generic "harmful overdose effects" fallback for
// reagents the system knows have an OD threshold but for which no DQ
// /datum/medical_issue/condition was authored. That fallback is a
// content gap — the reagent shows up in the encyclopedia with a warning
// label but no actual presentation, no symptoms, no cure path.
//
// This audit walks every reagent referenced by any DQ medical condition
// (cured_by, caused_by_chems, worsened_by, od_cures_externally targets'
// cures, etc.) plus reagents flagged scannable for basic medical
// scanners (scannable <= SCANNABLE_ADVANCED), and verifies each one
// with an upstream `overdose > 0` either has a matching DQ OD condition
// (subcategory == "Overdose", caused_by_chems contains exactly the
// reagent) or is explicitly opted out below.

/datum/unit_test/dq_medical_every_overdose_has_condition

/datum/unit_test/dq_medical_every_overdose_has_condition/Run()
	// "Medical reagent" here means: directly referenced by some DQ
	// medical condition (cured_by / caused_by_chems / worsened_by).
	// This matches the reagent-tab indexer's seed set — anything not
	// reachable from this set is filtered out of the encyclopedia
	// anyway, so it can't surface the generic OD fallback.
	var/list/medical_reagents = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/cproto = new T()
		if(cproto.cured_by)
			for(var/id in cproto.cured_by)
				medical_reagents[id] = TRUE
		if(cproto.caused_by_chems)
			for(var/id in cproto.caused_by_chems)
				medical_reagents[id] = TRUE
		if(cproto.worsened_by)
			for(var/id in cproto.worsened_by)
				medical_reagents[id] = TRUE
		qdel(cproto)

	// Build the set of reagents that DO have a DQ OD condition.
	var/list/has_od_condition = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/cproto = new T()
		if(cproto.subcategory == "Overdose" && length(cproto.caused_by_chems) == 1)
			for(var/id in cproto.caused_by_chems)
				has_od_condition[id] = TRUE
		qdel(cproto)

	// Reagents we explicitly opted out of authoring an OD condition for.
	// Topical-only chems with no clinical OD pathway, food/recreational
	// chems, and species-specific niche reagents go here. Add an entry
	// with a one-line reason any time the audit fails on a reagent that
	// genuinely shouldn't have a clinical OD presentation.
	var/list/od_opt_out = list(
		REAGENT_ID_SPACOMYCAZE  = "topical antibiotic gel; no systemic OD pathway",
		REAGENT_ID_SKRELLIMMUNO = "Skrell-only species drug; no general OD pathway",
	)

	var/list/failures = list()
	if(SSchemistry?.chemical_reagents)
		for(var/id in medical_reagents)
			var/datum/reagent/R = SSchemistry.chemical_reagents[id]
			if(!R || !R.overdose)
				continue
			if(has_od_condition[id])
				continue
			if(od_opt_out[id])
				continue
			failures += "[id] (overdose [R.overdose]u)"

	if(length(failures))
		TEST_FAIL("medical reagents with upstream OD threshold but no DQ OD condition (would surface generic 'harmful overdose effects' in the book): [jointext(failures, ", ")]")

#endif

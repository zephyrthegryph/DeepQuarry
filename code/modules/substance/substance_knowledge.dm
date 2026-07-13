// Inference & mastery (design doc §8) — knowledge is learned, never scanned.
//
// Profiles are hidden. The only way to learn them is to combine and observe, then
// triangulate across several combinations. This module records what the crew's
// combinations have *revealed* about each source archetype this round, as a shared
// lab record surfaced in the combiner UI. It auto-logs observations from real
// combinations — it does NOT scan a substance to hand you its profile.
//
// What a combination reveals (and how this recorder reads it):
//   * Combining a source with ITSELF lands MATCHING (identical resonance), which
//     cleanly probes its four linear axes: magnitude -> energy, control ->
//     volatility, yield -> affinity, purity -> purity. Purity wobble means the
//     scalar reads are approximate, so repeated probes form a narrowing range.
//   * Combining two DIFFERENT sources reveals their resonance RELATIONSHIP
//     (matching / adjacent / opposing) — the map you triangulate resonance from.
// Resonance has no absolute reveal: you reason it out from the relationship map.

/datum/substance_knowledge
	var/id
	var/family
	var/trigger
	// Running estimate ranges per scalar axis (lo/hi), and a sample count. n == 0
	// means "not yet probed" and shows as unknown.
	var/e_lo = 0; var/e_hi = 0; var/e_n = 0
	var/v_lo = 0; var/v_hi = 0; var/v_n = 0
	var/a_lo = 0; var/a_hi = 0; var/a_n = 0
	var/p_lo = 0; var/p_hi = 0; var/p_n = 0
	// archetype id -> relationship int (latest observed), the resonance map.
	var/list/relationships

/datum/substance_knowledge/New(_id)
	id = _id
	relationships = list()

// Per-round registry (globals reset each round, so knowledge is per-round, as the
// profiles it describes are).
/proc/substance_knowledge_registry()
	var/static/list/registry
	if(!registry)
		registry = list()
	return registry

/proc/substance_knowledge(id)
	if(!id)
		return null
	var/list/reg = substance_knowledge_registry()
	var/datum/substance_knowledge/K = reg[id]
	if(!K)
		K = new(id)
		var/datum/substance_archetype/A = substance_archetype(id)
		if(A)
			K.family = A.family
			K.trigger = A.trigger
		reg[id] = K
	return K

// Narrow a (lo, hi, n) range with a fresh sample. Returns nothing; mutates via the
// caller since DM can't return multiples cleanly — handled inline in the recorder.

// Record what a single combination revealed about its inputs.
/proc/substance_record_observation(datum/substance/A, datum/substance/B, datum/substance_reaction/R)
	if(!istype(A) || !istype(B) || !istype(R))
		return

	if(A.archetype == B.archetype && A.archetype)
		// Self-probe: MATCHING reveals the four scalar axes of this one source.
		var/datum/substance_knowledge/K = substance_knowledge(A.archetype)
		var/imp_e = round(R.magnitude / SUB_EMOD_MATCH)
		_substance_narrow(K, "e", imp_e)
		_substance_narrow(K, "v", R.control)
		_substance_narrow(K, "a", round(R.yield * SUBSTANCE_ATTR_MAX))
		_substance_narrow(K, "p", R.purity)
		return

	// Cross-probe: record the resonance relationship both ways.
	if(A.archetype)
		var/datum/substance_knowledge/KA = substance_knowledge(A.archetype)
		if(B.archetype)
			KA.relationships[B.archetype] = R.relationship
	if(B.archetype)
		var/datum/substance_knowledge/KB = substance_knowledge(B.archetype)
		if(A.archetype)
			KB.relationships[A.archetype] = R.relationship

// Fold a sample into the named axis's running range. After the first sample the
// range is a point; later samples widen it to bracket the true (wobbling) value.
/proc/_substance_narrow(datum/substance_knowledge/K, axis, val)
	switch(axis)
		if("e")
			K.e_lo = K.e_n ? min(K.e_lo, val) : val
			K.e_hi = K.e_n ? max(K.e_hi, val) : val
			K.e_n++
		if("v")
			K.v_lo = K.v_n ? min(K.v_lo, val) : val
			K.v_hi = K.v_n ? max(K.v_hi, val) : val
			K.v_n++
		if("a")
			K.a_lo = K.a_n ? min(K.a_lo, val) : val
			K.a_hi = K.a_n ? max(K.a_hi, val) : val
			K.a_n++
		if("p")
			K.p_lo = K.p_n ? min(K.p_lo, val) : val
			K.p_hi = K.p_n ? max(K.p_hi, val) : val
			K.p_n++

// ---- UI summary ------------------------------------------------------------

// A compact "≈lo–hi" string for a probed axis, or "?" if never probed.
/proc/_substance_axis_str(lo, hi, n)
	if(!n)
		return "?"
	if(lo == hi)
		return "[lo]"
	return "[lo]–[hi]"

// Build the field-notes table for the combiner UI: only archetypes the crew has
// actually touched this round appear.
/proc/substance_knowledge_summary()
	var/list/out = list()
	var/list/reg = substance_knowledge_registry()
	for(var/id in reg)
		var/datum/substance_knowledge/K = reg[id]
		var/datum/substance_archetype/AR = substance_archetype(id)
		var/list/rels = list()
		for(var/other_id in K.relationships)
			var/datum/substance_archetype/OR = substance_archetype(other_id)
			rels += "[OR ? OR.name : other_id]: [substance_relationship_short(K.relationships[other_id])]"
		out += list(list(
			"name" = AR ? AR.name : id,
			"family" = substance_family_name(K.family),
			"energy" = _substance_axis_str(K.e_lo, K.e_hi, K.e_n),
			"volatility" = _substance_axis_str(K.v_lo, K.v_hi, K.v_n),
			"affinity" = _substance_axis_str(K.a_lo, K.a_hi, K.a_n),
			"purity" = _substance_axis_str(K.p_lo, K.p_hi, K.p_n),
			"relationships" = length(rels) ? jointext(rels, ", ") : "—",
		))
	return out

/proc/substance_relationship_short(rel)
	switch(rel)
		if(SUB_REL_MATCHING) return "matching"
		if(SUB_REL_ADJACENT) return "adjacent"
		if(SUB_REL_OPPOSING) return "opposing"
	return "?"

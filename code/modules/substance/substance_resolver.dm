// The combination resolver — the engine the whole system runs on.
//
// substance_combine(A, B) -> /datum/substance_reaction, holding:
//   * output    : the produced substance (may be null on a pure conflict),
//   * byproducts: 0+ spawned substances that re-enter the loop,
//   * hazard    : a /datum/substance_hazard if the mix erupted (else null),
//   * a human-readable breakdown log (for debug + inference feedback).
//
// The math is faithful to the design doc §4: resonance decides the relationship
// (reinforce / transform / conflict); energy sets magnitude; volatility sets
// control; affinity sets yield and the dampening lever; purity sets byproducts
// and reliability. Nothing here touches the world — it is pure data, so it can be
// validated in isolation (and that is exactly what Phase 1 demands).

/datum/substance_reaction
	var/relationship = SUB_REL_MATCHING
	var/res_delta = 0
	/// Derived magnitude (M) and control (V) of the reaction.
	var/magnitude = 0
	var/control = 0
	/// Bond yield 0..1 (how much of the output actually holds).
	var/yield = 0
	/// Resulting purity 0..100.
	var/purity = 0
	/// The produced substance, or null.
	var/datum/substance/output = null
	/// Spawned byproduct substances.
	var/list/byproducts = list()
	/// A hazard event, or null.
	var/datum/substance_hazard/hazard = null
	/// Ordered human-readable breakdown lines.
	var/list/log_lines = list()

/datum/substance_reaction/Destroy()
	// Datums in these lists are handed back to the caller normally; only clear refs.
	byproducts = null
	output = null
	hazard = null
	return ..()

/datum/substance_hazard
	/// 1..100, scales with the reaction magnitude.
	var/severity = 0
	/// The family the hazard is themed to.
	var/family = SUBFAM_DISCHARGE
	var/desc = "an unstable discharge"

// Where the combination happens shapes its outcome — this is how OTHER departments
// (design doc §7) feed the chemistry as inputs, not cleanup. The combiner builds a
// context from its surroundings and equipment and passes it to the resolver:
//   * volatility_mod  — ATMOSPHERICS' axis: ambient temperature/pressure raise or
//     lower the reaction's effective control. Run a volatile mix cold to tame it;
//     heat it to weaponise.
//   * energy_ceiling  — ENGINEERING's axis: the rig's safe magnitude rating.
//     Exceed it and containment fails (a hazard) regardless of the relationship.
//     A better/upgraded rig raises the ceiling, allowing more powerful attempts.
/datum/substance_context
	var/volatility_mod = 0
	var/energy_ceiling = 0 // 0 == no ceiling

// ---- Shared environment sampling -------------------------------------------
// ATMOSPHERICS' axis, read straight off a machine's turf. Hot / high-pressure
// surroundings destabilise a reaction (positive shift), cold / low-pressure calm
// it (negative). Every substance machine (bench combiner/refiner, the particle
// accelerator refine path, and the fusion-core combine path) samples the room the
// same way through this one helper, so "run it cold to tame it" holds everywhere.
/proc/substance_ambient_volatility_mod(atom/A)
	var/turf/T = get_turf(A)
	if(!T)
		return 0
	var/datum/gas_mixture/env = T.return_air()
	if(!env)
		return 0
	var/temp_mod = clamp(round((env.return_temperature() - T20C) / 20), -15, 20)
	var/pres_mod = clamp(round((env.return_pressure() - ONE_ATMOSPHERE) / 30), -10, 15)
	return clamp(temp_mod + pres_mod, -25, 30)

/proc/substance_ambient_readout(atom/A)
	var/turf/T = get_turf(A)
	if(!T)
		return "—"
	var/datum/gas_mixture/env = T.return_air()
	if(!env)
		return "vacuum"
	return "[round(env.return_temperature() - T0C)]°C / [round(env.return_pressure())] kPa"

// Build a resolver context for a machine: its surroundings (atmos) plus an
// engineering containment ceiling (0 == unrated). extra_volatility folds in any
// machine-internal heat source (e.g. a reactor's plasma temperature) on top of the
// room reading.
/proc/substance_env_context(atom/A, energy_ceiling = 0, extra_volatility = 0)
	var/datum/substance_context/ctx = new()
	ctx.energy_ceiling = energy_ceiling
	ctx.volatility_mod = substance_ambient_volatility_mod(A) + extra_volatility
	return ctx

// ---- The resolver ----------------------------------------------------------

/proc/substance_combine(datum/substance/A, datum/substance/B, datum/substance_context/ctx = null)
	if(!istype(A) || !istype(B))
		return null
	var/datum/substance_reaction/R = new()

	// 1. Resonance -> relationship (the character of the result).
	R.res_delta = substance_resonance_distance(A.resonance, B.resonance)
	R.relationship = substance_relationship(R.res_delta)
	R.log_lines += "Resonance delta [R.res_delta] -> [substance_relationship_name(R.relationship)]."

	// 2. Energy -> magnitude.
	var/energy_mod = substance_energy_mod(R.relationship)
	R.magnitude = ((A.energy + B.energy) / 2) * energy_mod

	// 3. Volatility -> control / threshold sharpness.
	R.control = max(A.volatility, B.volatility)
	if(R.relationship == SUB_REL_OPPOSING)
		R.control += SUB_OPPOSING_VOLATILITY_PENALTY
	// Atmospherics' axis: the ambient environment nudges effective control.
	if(ctx)
		R.control += ctx.volatility_mod
		if(ctx.volatility_mod)
			R.log_lines += "Environment shifts control by [ctx.volatility_mod > 0 ? "+" : ""][ctx.volatility_mod]."

	// 4. Affinity -> yield + the dampening lever.
	R.yield = (A.affinity + B.affinity) / (2 * SUBSTANCE_ATTR_MAX) // 0..1
	var/aff_lo = min(A.affinity, B.affinity)
	var/aff_hi = max(A.affinity, B.affinity)
	if((aff_hi - aff_lo) > SUB_AFFINITY_ASYMMETRY)
		// The low-affinity partner tames the mix: scale magnitude + volatility down.
		var/damp = 0.5 + (aff_lo / (2 * SUBSTANCE_ATTR_MAX)) // 0.5..1.0
		R.magnitude *= damp
		R.control *= damp
		R.log_lines += "Asymmetric affinity ([aff_lo] vs [aff_hi]) dampens the mix (x[round(damp, 0.01)])."

	// 5. Purity -> byproducts + reliability wobble.
	R.purity = (A.purity + B.purity) / 2
	if(R.relationship == SUB_REL_OPPOSING)
		R.purity *= SUB_OPPOSING_PURITY_FACTOR
	// Low purity wobbles the effective magnitude/control (same mix, different attempt).
	var/wobble = (SUBSTANCE_ATTR_MAX - R.purity) / SUBSTANCE_ATTR_MAX // 0..1
	if(wobble > 0)
		R.magnitude += rand(-1, 1) * wobble * 12
		R.control   += rand(-1, 1) * wobble * 12

	R.magnitude = clamp(round(R.magnitude), 0, SUBSTANCE_ATTR_MAX)
	R.control   = clamp(round(R.control), 0, SUBSTANCE_ATTR_MAX)
	R.purity    = clamp(round(R.purity), 0, SUBSTANCE_ATTR_MAX)
	R.log_lines += "Magnitude [R.magnitude], control [R.control], yield [round(R.yield * 100)]%, purity [R.purity]."

	// 6. Derive the output substance (per §4.6) unless the conflict consumed it.
	R.output = substance_derive_output(A, B, R)

	// 7. Byproducts + hazard.
	substance_roll_byproducts(A, B, R)
	substance_roll_hazard(A, B, R)

	// Engineering's axis: exceeding the rig's energy ceiling fails containment,
	// erupting regardless of the relationship (and overriding a milder hazard).
	if(ctx && ctx.energy_ceiling && R.magnitude > ctx.energy_ceiling)
		var/datum/substance_hazard/H = R.hazard || new()
		H.severity = clamp(max(H.severity, round(R.magnitude)), 1, 100)
		H.family = (A.energy >= B.energy) ? A.family : B.family
		H.desc = "a containment breach ([substance_hazard_word(H.severity)] [lowertext(substance_family_name(H.family))])"
		R.hazard = H
		R.log_lines += "CONTAINMENT FAILURE: magnitude [R.magnitude] exceeded the rig ceiling [ctx.energy_ceiling]."

	return R

// ---- Step helpers ----------------------------------------------------------

/proc/substance_relationship(res_delta)
	if(res_delta <= SUB_MATCH_BAND)
		return SUB_REL_MATCHING
	if(res_delta <= SUB_ADJ_BAND)
		return SUB_REL_ADJACENT
	return SUB_REL_OPPOSING

/proc/substance_relationship_name(rel)
	switch(rel)
		if(SUB_REL_MATCHING) return "MATCHING (reinforce)"
		if(SUB_REL_ADJACENT) return "ADJACENT (transform)"
		if(SUB_REL_OPPOSING) return "OPPOSING (conflict)"
	return "unknown"

/proc/substance_energy_mod(rel)
	switch(rel)
		if(SUB_REL_MATCHING) return SUB_EMOD_MATCH
		if(SUB_REL_ADJACENT) return SUB_EMOD_ADJ
		if(SUB_REL_OPPOSING) return SUB_EMOD_OPPOSING
	return 1

// Produce the output substance and write its derived profile.
/proc/substance_derive_output(datum/substance/A, datum/substance/B, datum/substance_reaction/R)
	// A pure low-yield conflict can fail to hold any product at all.
	if(R.relationship == SUB_REL_OPPOSING && R.yield < 0.25)
		R.log_lines += "The substances refuse to bond — no product held."
		return null

	var/datum/substance/dominant = (A.energy >= B.energy) ? A : B
	var/out_family
	switch(R.relationship)
		if(SUB_REL_MATCHING)
			out_family = dominant.family // same family, intensified
		if(SUB_REL_ADJACENT)
			out_family = substance_family_transform(A.family, B.family) // a NEW family
		if(SUB_REL_OPPOSING)
			out_family = dominant.family // an unstable remnant of the stronger one

	var/datum/substance/out = new()
	out.family = out_family
	out.energy = R.magnitude
	out.volatility = R.control
	// Affinity of the product trends toward the bond quality.
	out.affinity = clamp(round((A.affinity + B.affinity) / 2 * (0.6 + R.yield * 0.4)), 0, SUBSTANCE_ATTR_MAX)
	out.purity = R.purity
	// Resonance carries the chaos forward per relationship.
	switch(R.relationship)
		if(SUB_REL_MATCHING)
			out.resonance = (round((A.resonance + B.resonance) / 2) + rand(-10, 10) + SUBSTANCE_RES_MAX) % SUBSTANCE_RES_MAX
		if(SUB_REL_ADJACENT)
			out.resonance = (round((A.resonance + B.resonance) / 2) + rand(-40, 40) + SUBSTANCE_RES_MAX) % SUBSTANCE_RES_MAX
		if(SUB_REL_OPPOSING)
			out.resonance = rand(0, SUBSTANCE_RES_MAX - 1) // scattered
	// Trigger: matching keeps the dominant's; transform takes the new family's natural one.
	out.trigger = (R.relationship == SUB_REL_ADJACENT) ? substance_family_default_trigger(out_family) : dominant.trigger
	out.quantity = max(1, round(min(A.quantity, B.quantity) * (0.5 + R.yield * 0.5)))
	out.name = substance_output_name(out, R.relationship)
	return out

/proc/substance_output_name(datum/substance/out, rel)
	var/fam = lowertext(substance_family_name(out.family))
	switch(rel)
		if(SUB_REL_MATCHING) return "concentrated [fam] compound"
		if(SUB_REL_ADJACENT) return "synthesized [fam] compound"
		if(SUB_REL_OPPOSING) return "unstable [fam] remnant"
	return "[fam] compound"

// Spawn 0+ byproducts. Each is a fresh substance with a seeded-but-rerolled-feel
// profile, re-entering the loop as a new input (sometimes useful, often nasty).
/proc/substance_roll_byproducts(datum/substance/A, datum/substance/B, datum/substance_reaction/R)
	var/bymod = SUB_BYMOD_MATCH
	switch(R.relationship)
		if(SUB_REL_ADJACENT) bymod = SUB_BYMOD_ADJ
		if(SUB_REL_OPPOSING) bymod = SUB_BYMOD_OPPOSING
	var/chance = ((SUBSTANCE_ATTR_MAX - R.purity) / SUBSTANCE_ATTR_MAX) * bymod * 100
	// Up to two byproducts; the second is rarer.
	var/count = 0
	if(prob(clamp(chance, 0, 95)))
		count++
		if(prob(clamp(chance, 0, 95) * 0.5))
			count++
	for(var/i in 1 to count)
		var/datum/substance/bp = new()
		// Byproducts drift toward the corrosive/void "waste" end and run hot+dirty.
		bp.family = pick(A.family, B.family, SUBFAM_CORROSIVE, SUBFAM_VOID)
		bp.energy = clamp(round(R.magnitude * rand(40, 90) / 100), 0, SUBSTANCE_ATTR_MAX)
		bp.volatility = clamp(round(R.control * rand(60, 120) / 100), 0, SUBSTANCE_ATTR_MAX)
		bp.affinity = rand(10, 60)
		bp.purity = clamp(round(R.purity * rand(40, 90) / 100), 0, SUBSTANCE_ATTR_MAX)
		bp.resonance = rand(0, SUBSTANCE_RES_MAX - 1)
		bp.trigger = substance_family_default_trigger(bp.family)
		bp.name = "[lowertext(substance_family_name(bp.family))] byproduct"
		R.byproducts += bp
	if(count)
		R.log_lines += "Threw [count] byproduct\s."

// A conflict erupts into a hazard when magnitude AND control both run high.
/proc/substance_roll_hazard(datum/substance/A, datum/substance/B, datum/substance_reaction/R)
	if(R.relationship != SUB_REL_OPPOSING)
		return
	if(R.magnitude < SUB_HAZARD_M_THRESHOLD || R.control < SUB_HAZARD_V_THRESHOLD)
		return
	var/datum/substance_hazard/H = new()
	// Severity scales with magnitude, nudged by how far past the volatility line we are.
	H.severity = clamp(round(R.magnitude * (0.7 + (R.control - SUB_HAZARD_V_THRESHOLD) / 100)), 1, 100)
	H.family = (A.energy >= B.energy) ? A.family : B.family
	H.desc = "a [substance_hazard_word(H.severity)] [lowertext(substance_family_name(H.family))] eruption"
	R.hazard = H
	R.log_lines += "HAZARD: [H.desc] (severity [H.severity])."

/proc/substance_hazard_word(severity)
	if(severity >= 80) return "catastrophic"
	if(severity >= 55) return "violent"
	if(severity >= 30) return "sharp"
	return "minor"

// ---- The transform map (ADJACENT relationships) ----------------------------
// Maps a pair of effect families to a derived family. Symmetric, deterministic,
// and lawful (patterns are learnable: VOID tends to dominate, FIELD stabilizes).
// Implemented as a switch on the sorted pair to avoid numeric-keyed assoc lists.
/proc/substance_family_transform(fam_a, fam_b)
	if(fam_a == fam_b)
		return fam_a // same family evolves into itself, intensified
	var/lo = min(fam_a, fam_b)
	var/hi = max(fam_a, fam_b)
	switch(lo)
		if(SUBFAM_DISCHARGE)
			switch(hi)
				if(SUBFAM_THERMAL)   return SUBFAM_RADIANT
				if(SUBFAM_FORCE)     return SUBFAM_FIELD
				if(SUBFAM_FIELD)     return SUBFAM_DISCHARGE
				if(SUBFAM_SPORE)     return SUBFAM_CORROSIVE
				if(SUBFAM_CORROSIVE) return SUBFAM_THERMAL
				if(SUBFAM_RADIANT)   return SUBFAM_VOID
				if(SUBFAM_VOID)      return SUBFAM_FORCE
		if(SUBFAM_THERMAL)
			switch(hi)
				if(SUBFAM_FORCE)     return SUBFAM_CORROSIVE
				if(SUBFAM_FIELD)     return SUBFAM_RADIANT
				if(SUBFAM_SPORE)     return SUBFAM_SPORE
				if(SUBFAM_CORROSIVE) return SUBFAM_CORROSIVE
				if(SUBFAM_RADIANT)   return SUBFAM_RADIANT
				if(SUBFAM_VOID)      return SUBFAM_FIELD
		if(SUBFAM_FORCE)
			switch(hi)
				if(SUBFAM_FIELD)     return SUBFAM_FORCE
				if(SUBFAM_SPORE)     return SUBFAM_FORCE
				if(SUBFAM_CORROSIVE) return SUBFAM_DISCHARGE
				if(SUBFAM_RADIANT)   return SUBFAM_THERMAL
				if(SUBFAM_VOID)      return SUBFAM_VOID
		if(SUBFAM_FIELD)
			switch(hi)
				if(SUBFAM_SPORE)     return SUBFAM_SPORE
				if(SUBFAM_CORROSIVE) return SUBFAM_FIELD
				if(SUBFAM_RADIANT)   return SUBFAM_FIELD
				if(SUBFAM_VOID)      return SUBFAM_VOID
		if(SUBFAM_SPORE)
			switch(hi)
				if(SUBFAM_CORROSIVE) return SUBFAM_CORROSIVE
				if(SUBFAM_RADIANT)   return SUBFAM_SPORE
				if(SUBFAM_VOID)      return SUBFAM_SPORE
		if(SUBFAM_CORROSIVE)
			switch(hi)
				if(SUBFAM_RADIANT)   return SUBFAM_DISCHARGE
				if(SUBFAM_VOID)      return SUBFAM_CORROSIVE
		if(SUBFAM_RADIANT)
			switch(hi)
				if(SUBFAM_VOID)      return SUBFAM_VOID
	// Defensive fallback (should be unreachable): blend toward the higher family.
	return hi

// The substance datum — the universal unit of the chemistry system.
//
// Everything is a substance: a field-found material, a bio extract, a plant
// compound, a combination output, a byproduct. A substance carries:
//   * a VISIBLE surface behavior (effect family + trigger) known on acquisition,
//   * a HIDDEN five-axis attribute profile learned only through combination,
//   * a quantity (it is a finite material resource).
//
// Source substances are seeded from an archetype id + the per-round salt, so the
// surface behavior is stable but the hidden profile rerolls every round. Outputs
// of the resolver carry a concrete, derived profile (no archetype) so they can be
// re-combined and chained.

/datum/substance
	/// Player-facing name (surface behavior usually drives this).
	var/name = "unknown substance"
	/// Source archetype id, if this came from a source (null for resolver outputs).
	var/archetype = null

	// ---- Visible surface behavior (known on acquisition) ----
	/// Effect family (SUBFAM_*) — the kind of thing this does.
	var/family = SUBFAM_DISCHARGE
	/// Trigger (SUB_TRIG_*) — when it fires in its final form.
	var/trigger = SUB_TRIG_IMPACT

	// ---- Hidden attribute profile (learned through interaction) ----
	/// Magnitude axis (0..100): how big the result/hazard is.
	var/energy = 50
	/// Control axis (0..100): whether the reaction stays controlled or cascades.
	var/volatility = 50
	/// Bonding axis (0..100): yield/stability; low affinity dampens partners.
	var/affinity = 50
	/// Character axis (0..360, cyclic): the relational chaos engine.
	var/resonance = 0
	/// Cleanliness axis (0..100): byproducts and reliability.
	var/purity = 50

	/// How much of it there is.
	var/quantity = 1

	// ---- Inference scaffolding (Phase 2) ----
	// Which hidden axes the crew has pinned down for THIS substance, by inference.
	// The surface behavior is always known; the profile starts fully hidden.
	var/revealed_energy = FALSE
	var/revealed_volatility = FALSE
	var/revealed_affinity = FALSE
	var/revealed_resonance = FALSE
	var/revealed_purity = FALSE

/datum/substance/New(_archetype = null)
	if(_archetype)
		archetype = _archetype

// Build a source substance from a registered archetype, seeding the hidden
// profile from this round's salt. Returns null on an unknown archetype.
/proc/substance_from_archetype(archetype_id, qty = 1)
	var/datum/substance_archetype/A = substance_archetype(archetype_id)
	if(!A)
		return null
	var/datum/substance/S = new(archetype_id)
	S.name = A.name
	S.family = A.family
	S.trigger = A.trigger
	S.quantity = qty
	S.seed_profile()
	return S

// (Re)seed the hidden profile deterministically from the archetype + round salt.
// Tendencies come from the archetype so a "found material" reads volatile/exotic
// while a "clean reagent" reads pure — but the exact values reroll each round.
/datum/substance/proc/seed_profile()
	if(!archetype)
		return
	var/datum/substance_archetype/A = substance_archetype(archetype)
	if(!A)
		return
	energy     = substance_hash_range(archetype, "energy",     A.energy_lo,     A.energy_hi)
	volatility = substance_hash_range(archetype, "volatility", A.volatility_lo, A.volatility_hi)
	affinity   = substance_hash_range(archetype, "affinity",   A.affinity_lo,   A.affinity_hi)
	purity     = substance_hash_range(archetype, "purity",     A.purity_lo,     A.purity_hi)
	resonance  = substance_hash_range(archetype, "resonance",  0,               SUBSTANCE_RES_MAX) % SUBSTANCE_RES_MAX

// A detached copy (used by the resolver when an output inherits from a parent).
/datum/substance/proc/Clone()
	var/datum/substance/S = new()
	S.name = name
	S.archetype = archetype
	S.family = family
	S.trigger = trigger
	S.energy = energy
	S.volatility = volatility
	S.affinity = affinity
	S.resonance = resonance
	S.purity = purity
	S.quantity = quantity
	return S

// ---- Helpers ---------------------------------------------------------------

// Cyclic distance between two resonance values, 0..180. The core of relationship.
/proc/substance_resonance_distance(a, b)
	var/d = abs(a - b) % SUBSTANCE_RES_MAX
	return min(d, SUBSTANCE_RES_MAX - d)

// Visible one-liner: what the crew sees without any inference.
/datum/substance/proc/describe_surface()
	return "[name] ([substance_family_name(family)] / [substance_trigger_name(trigger)])"

// Full readout for debug/inference tools — hidden axes shown raw.
/datum/substance/proc/describe_full()
	return "[describe_surface()] | E[energy] V[volatility] A[affinity] R[resonance] P[purity] x[quantity]"

// ---- Display tables (plain indexed lists, never numeric-keyed assoc) -------

/proc/substance_family_name(fam)
	var/static/list/names = list(
		"Discharge", "Thermal", "Force", "Field",
		"Spore", "Corrosive", "Radiant", "Void",
	)
	if(fam >= 1 && fam <= length(names))
		return names[fam]
	return "Unknown"

/proc/substance_trigger_name(trig)
	var/static/list/names = list(
		"on impact", "on heat", "on pressure", "on energy", "on contact",
	)
	if(trig >= 1 && trig <= length(names))
		return names[trig]
	return "unknown"

// Each family's natural firing trigger — used when a transform has to pick one.
/proc/substance_family_default_trigger(fam)
	switch(fam)
		if(SUBFAM_DISCHARGE) return SUB_TRIG_ENERGY
		if(SUBFAM_THERMAL)   return SUB_TRIG_HEAT
		if(SUBFAM_FORCE)     return SUB_TRIG_IMPACT
		if(SUBFAM_FIELD)     return SUB_TRIG_PRESSURE
		if(SUBFAM_SPORE)     return SUB_TRIG_CONTACT
		if(SUBFAM_CORROSIVE) return SUB_TRIG_CONTACT
		if(SUBFAM_RADIANT)   return SUB_TRIG_ENERGY
		if(SUBFAM_VOID)      return SUB_TRIG_PRESSURE
	return SUB_TRIG_IMPACT

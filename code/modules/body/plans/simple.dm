// Simple body plan: creatures that don't need diagnosis — simple mobs, bots,
// pAIs, larvae, brainmobs. Injuries become whole-body LOAD afflictions measured
// in points; the mob dies when its total load reaches its endurance.

/datum/body/simple
	/// Cached sum of every load affliction, in points.
	var/total_load = 0

/// A hit always lands as immediate load. A named affliction additionally
/// takes hold (if it can exist on this plan) and harms over time through its
/// simple_load_rate — a spider bite hurts now AND the venom keeps working.
/datum/body/simple/receive_injury(kind, amount, target, atom/source, affliction_type, flags)
	if(affliction_type)
		afflict(affliction_type)?.receive_injury(amount, kind, source)
	var/load_type = simple_load_type_for(kind, owner.biology)
	if(!load_type)
		return 0
	var/datum/affliction/load/L = afflict(load_type)
	return L ? L.receive_injury(amount, kind, source) : 0

/// Tick afflictions, then convert non-load afflictions' ongoing harm into
/// load (the only thing that kills a simple body).
/datum/body/simple/life_tick()
	if(!LAZYLEN(afflictions) && !(dirty & BODY_DIRTY_VITALS))
		return
	// A cycle the stasis clock paused: afflictions hold still (advance_stasis()).
	if(stasis_paused)
		return
	invalidate(BODY_DIRTY_TREATMENT)
	for(var/datum/affliction/A as anything in afflictions?.Copy())
		if(A.body != src)
			continue
		A.tick()
		if(QDELETED(A) || istype(A, /datum/affliction/load) || !A.simple_load_rate)
			continue
		var/load_type = simple_load_type_for_category(A.injury_category, owner.biology)
		if(load_type)
			afflict(load_type)?.receive_injury(A.simple_load_rate * A.severity / AFFLICTION_SEVERITY_TERMINAL)
	recompute_vitals()
	evaluate_status()

/// Load afflictions carry the injury; other afflictions only describe it.
/datum/body/simple/injury_load(category)
	. = 0
	for(var/datum/affliction/load/L in afflictions)
		if(L.injury_category == category)
			. += L.load


/// Load affliction for an injury category (for afflictions harming over time).
/proc/simple_load_type_for_category(category, biology)
	switch(category)
		if(INJURY_CATEGORY_PHYSICAL, INJURY_CATEGORY_NEURAL)
			return simple_load_type_for(INJURY_BLUNT, biology)
		if(INJURY_CATEGORY_THERMAL)
			return simple_load_type_for(INJURY_BURN, biology)
		if(INJURY_CATEGORY_TOXIC)
			return simple_load_type_for(INJURY_TOXIN, biology)
		if(INJURY_CATEGORY_GENETIC)
			return simple_load_type_for(INJURY_CELLULAR, biology)
	return null

/// Which load affliction an injury kind feeds, or null if this biology is
/// immune to it.
/proc/simple_load_type_for(kind, biology)
	var/synthetic = (biology & (BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM)) && !(biology & BIOLOGY_ORGANIC)
	switch(kind)
		if(INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE, INJURY_NEURAL, INJURY_DIGESTION)
			return /datum/affliction/load/trauma
		if(INJURY_BURN, INJURY_FROSTBITE, INJURY_CORROSIVE, INJURY_ELECTRIC)
			return /datum/affliction/load/burn
		if(INJURY_RADIATION)
			return synthetic ? null : /datum/affliction/load/burn
		if(INJURY_TOXIN, INJURY_CELLULAR)
			return synthetic ? null : /datum/affliction/load/toxin
	// Pain: simple creatures fight through it.
	return null

/datum/body/simple/recompute_vitals()
	dirty &= ~BODY_DIRTY_VITALS
	total_load = 0
	for(var/datum/affliction/load/L in afflictions)
		total_load += L.load
	var/max_load = owner.get_endurance()
	vitality = max_load > 0 ? clamp(1 - total_load / max_load, 0, 1) : 0
	pain = 0
	consciousness = 100

/datum/body/simple/is_dead()
	ensure_vitals()
	return total_load >= owner.get_endurance()

/// Simple creatures don't pass out from injury.
/datum/body/simple/update_consciousness()
	return

/// Simple bodies have nothing to restore beyond clearing afflictions.
/datum/body/proc/restore()
	return


// --- Load afflictions ---------------------------------------------------------------
// Whole-body injury measured in points (the simple plan's successor to the
// brute/burn/tox/oxy pools). Treatable by the matching organic mechanism or
// its synthetic repair equivalent, so a medkit heals an animal and a welder
// repairs a bot through the same mend() call.

/datum/affliction/load
	name = "injury"
	biology = BIOLOGY_ALL
	body_plans = BODY_PLAN_ALL
	progression_rate = 0
	restoration_rate = 1
	min_symptoms = 0
	max_symptoms = 0
	/// Accumulated injury in points.
	var/load = 0

/datum/affliction/load/load_value()
	return load

/datum/affliction/load/receive_injury(amount, kind, atom/source)
	load += amount
	sync_severity()
	return amount

/datum/affliction/load/receive_treatment(amount)
	var/treated = min(amount, load)
	load -= treated
	if(load <= 0)
		cure()
	else
		sync_severity()
	return treated

/// Severity is a display-only percentage of the owner's endurance.
/datum/affliction/load/proc/sync_severity()
	var/max_load = owner?.get_endurance()
	set_severity(max_load ? load / max_load * 100 : 0)
	if(body)
		body.invalidate(BODY_DIRTY_VITALS)

/// Load is the state: every treatment, continuous (reagents in a creature's
/// holder) or instant (mend), comes straight off it.
/datum/affliction/load/receive_tagged_treatment(tag, amount, continuous = FALSE)
	return receive_treatment(amount)

/// Load afflictions don't progress on their own.
/datum/affliction/load/progress()
	return

/datum/affliction/load/trauma
	name = "trauma"
	injury_category = INJURY_CATEGORY_PHYSICAL
	treated_by = list(TREAT_TISSUE_REPAIR = 1, TREAT_PLATING_REPAIR = 1)

/datum/affliction/load/burn
	name = "burns"
	injury_category = INJURY_CATEGORY_THERMAL
	treated_by = list(TREAT_BURN_CARE = 1, TREAT_WIRING_REPAIR = 1)

/datum/affliction/load/toxin
	name = "poisoning"
	injury_category = INJURY_CATEGORY_TOXIC
	treated_by = list(TREAT_ANTITOXIN = 1, TREAT_GENETIC_REPAIR = 1)

/// A simple body's oxygen debt, as load: suffocating creatures (fish out of
/// water, bad air) die of it like any other load. Not an injury category.
/datum/affliction/load/hypoxia
	name = "hypoxia"
	treated_by = list(TREAT_OXYGENATION = 1)


// --- Oxygen debt ----------------------------------------------------------------------
// Simple creatures have no respiration model (their physiology queries return
// null): unsuitable air and suffocation arrive as explicit debt, carried as load.

/datum/body/simple/add_oxygen_debt(amount, source)
	if(amount <= 0 || !(owner.biology & BIOLOGY_ORGANIC))
		return 0
	var/datum/affliction/load/L = afflict(/datum/affliction/load/hypoxia)
	return L ? L.receive_injury(amount * get_factor(BF_DEMAND), null, source) : 0

/datum/body/simple/oxygen_debt()
	if(!(owner.biology & BIOLOGY_ORGANIC))
		return null
	var/datum/affliction/load/L = find_affliction(/datum/affliction/load/hypoxia)
	return L ? L.load : 0

/datum/body/simple/pay_oxygen_debt(amount)
	var/datum/affliction/load/L = find_affliction(/datum/affliction/load/hypoxia)
	return L ? L.receive_treatment(amount) : 0

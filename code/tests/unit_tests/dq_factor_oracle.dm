// The factor oracle (doc/rewrite/proposals/stat_layer.md, sections 3.6 and 4.2): the OLD fold of body factors, kept as test code, so the composition
// the stat engine does can be proved equal to it. It builds the vector of a mob's factors from its sources the way recompute_factors() did
// (afflictions, body effects, stasis, reagents, species, traits, form, worn items; per-rule accumulate; clamp), and compares it with what the stat
// vars hold now.
//
// The oracle reads only the sources' data and each stat's rule, base and bounds, never the stat store, so it is independent of the engine under
// test. Its vector is an alist keyed by stat id, over the body factors (the keys of body_factor_defs).

/// The ids of the body factor stats, in a fixed order.
/proc/oracle_ids()
	var/static/list/ids
	if(!ids)
		ids = list()
		var/alist/defs = GLOBAL_TABLE_GET(body_factor_defs)
		for(var/id in defs)
			ids += id
	return ids

/// The baseline of a factor, for a mob whose sources contribute nothing.
/proc/oracle_baseline(id)
	return stat_def_of(id)?.base

/// The old body_factor_accumulate(): folds one table into `acc` (seeded with the baselines on the first contribution) at `scale`.
/proc/oracle_accumulate(alist/acc, alist/table, scale = 1)
	if(!length(table) || scale <= 0)
		return acc
	if(!acc)
		acc = alist()
		for(var/id in oracle_ids())
			acc[id] = oracle_baseline(id)
	for(var/id in table)
		var/datum/stat_def/def = stat_def_of(id)
		if(!def || isnull(acc[id]))
			continue
		var/value = table[id]
		switch(def.rule)
			if(STAT_RULE_PRODUCT)
				acc[id] *= max(0, 1 - (1 - value) * scale)
			if(STAT_RULE_SUM)
				acc[id] += value * scale
			if(STAT_RULE_MAX)
				acc[id] = max(acc[id], value * scale)
			if(STAT_RULE_MIN)
				acc[id] = min(acc[id], value * scale)
			if(STAT_RULE_MASK_OR)
				acc[id] |= value
	return acc

/// The old body_factor_finalize(): clamps every factor to its bounds. Null when nothing was folded.
/proc/oracle_finalize(alist/acc)
	if(!acc)
		return null
	for(var/id in oracle_ids())
		var/datum/stat_def/def = stat_def_of(id)
		if(def.clamps)
			acc[id] = stat_clamp(def, acc[id])
	return acc

// --- The sources, folded as recompute_factors() folded them ---------------------------------------------------------------------

/// What this affliction folds in now (the old accumulate_factors()).
/datum/affliction/proc/oracle_factors(alist/acc)
	if(stage)
		var/list/stages = TYPE_TABLE_GET(src, affliction_stages)
		var/list/entry = stages?[stage]
		if(entry)
			return oracle_accumulate(acc, entry["factors"], 1)
	return oracle_accumulate(acc, factors, severity / AFFLICTION_SEVERITY_TERMINAL)

/datum/affliction/airway/oracle_factors(alist/acc)
	acc = ..()
	return oracle_accumulate(acc, alist(STAT_AIRWAY = patency()), 1)

/datum/affliction/respiratory_arrest/oracle_factors(alist/acc)
	acc = ..()
	return oracle_accumulate(acc, alist(STAT_RESP_DRIVE = is_apneic() ? 0 : 1 - severity / AFFLICTION_SEVERITY_TERMINAL), 1)

/datum/affliction/hypovolemic_shock/oracle_factors(alist/acc)
	acc = oracle_accumulate(acc, factors, severity / AFFLICTION_SEVERITY_TERMINAL)
	return oracle_accumulate(acc, band_factors, 1)

/datum/affliction/tissue_hypoxia/oracle_factors(alist/acc)
	acc = ..()
	if(severity <= PHYSIOLOGY_HYPOXIA_ARRHYTHMIA_THRESHOLD)
		return acc
	var/depth = clamp((severity - PHYSIOLOGY_HYPOXIA_ARRHYTHMIA_THRESHOLD) / (AFFLICTION_SEVERITY_TERMINAL - PHYSIOLOGY_HYPOXIA_ARRHYTHMIA_THRESHOLD), 0, 1)
	return oracle_accumulate(acc, alist(STAT_CARDIAC_IRRITABILITY = 1 + depth * (PHYSIOLOGY_HYPOXIA_IRRITABILITY_MAX - 1)), 1)

/// Every body effect's table, once per stack (the old accumulate_body_effect_factors()).
/mob/living/proc/oracle_effect_factors(alist/acc)
	var/list/active = body_effects()
	for(var/path in active)
		var/alist/table
		var/datum/body_effect_origin/application = body_effect_origins?[path]
		if(application && !isnull(application.table_override))
			table = application.table_override
		else
			table = body_effect_def(path).factors
		if(!table)
			continue
		for(var/i in 1 to active[path])
			acc = oracle_accumulate(acc, table)
	return acc

/// Every stasis level held by a source (the old accumulate_stasis_factors()).
/mob/living/proc/oracle_stasis_factors(alist/acc)
	for(var/key in stasis_sources)
		acc = oracle_accumulate(acc, body_effect_def(stasis_type_at(key)).factors)
	return acc

/// Patient-side contributions of a reagent (the old accumulate_special_factors()).
/datum/reagent/proc/oracle_special_factors(alist/acc, mob/living/L, volume)
	if(!ishuman(L) || volume <= 0)
		return acc
	var/mob/living/carbon/human/H = L
	var/scale = dq_chem_dose_scale(volume)
	if((H.species.allergens & allergen_type) || (H.species.medallergens & medallergen_type))
		acc = oracle_accumulate(acc, alist(STAT_ALLERGY = REM), allergen_factor * scale)
	if(id == H.species.blood_reagents)
		acc = oracle_accumulate(acc, alist(STAT_BLOOD_REGEN = 1.6), scale)
	return acc

/datum/reagent/ethanol/oracle_special_factors(alist/acc, mob/living/L, volume)
	acc = ..()
	if(!ishuman(L) || volume <= 0)
		return acc
	var/mob/living/carbon/human/H = L
	if(HAS_SYNTHETIC_BIOLOGY(H) && !H.species.robo_ethanol_drunk)
		return acc
	acc = oracle_accumulate(acc, alist(STAT_INTOXICATION = 1), dq_chem_dose_scale(volume))
	if(strength && volume >= strength * H.species.chem_strength_alcohol * 6)
		acc = oracle_accumulate(acc, alist(STAT_HEPATOTOXICITY = 1), toxicity)
	return acc

/// Every reagent in the body at its dose (the old accumulate_reagent_factors()).
/datum/body/proc/oracle_reagent_factors(alist/acc)
	if(dirty & BODY_DIRTY_TREATMENT)
		build_treatment_snapshot()
	var/list/volumes = reagent_volumes
	for(var/reagent_id in volumes)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
		if(!R)
			continue
		var/alist/table = R.get_factors(owner)
		var/scale = dq_chem_dose_scale(volumes[reagent_id])
		if(length(table) && scale > 0 && R.acts_on_body(owner))
			acc = oracle_scaled_reagent(acc, table, scale)
		acc = R.oracle_special_factors(acc, owner, volumes[reagent_id])
	return acc

/// One reagent table; the humanoid plan scales analgesia by the species' analgesic sensitivity.
/datum/body/proc/oracle_scaled_reagent(alist/acc, alist/table, scale)
	return oracle_accumulate(acc, table, scale)

/datum/body/humanoid/oracle_scaled_reagent(alist/acc, alist/table, scale)
	acc = ..()
	var/mob/living/carbon/human/H = owner
	var/strength = H.species?.chem_strength_pain
	var/analgesia = table[STAT_ANALGESIA]
	if(acc && analgesia && !isnull(strength) && strength != 1)
		acc[STAT_ANALGESIA] += analgesia * scale * (strength - 1)
	return acc

/// Species and trait baselines, the form and the worn items (the old accumulate_plan_factors()).
/datum/body/proc/oracle_plan_factors(alist/acc)
	return acc

/datum/body/humanoid/oracle_plan_factors(alist/acc)
	var/mob/living/carbon/human/H = owner
	if(H.species)
		acc = oracle_accumulate(acc, H.species.factor_baseline)
		for(var/alist/table as anything in H.species.granted_factors)
			acc = oracle_accumulate(acc, table)
		if(H.species.flags & NO_PAIN)
			acc = oracle_accumulate(acc, alist(STAT_PAIN_IMMUNITY = 1))
	var/datum/form/F = H.current_form()
	if(F)
		acc = oracle_accumulate(acc, F.factors)
	for(var/obj/item/I as anything in H.body_slot_items(BODY_SLOT_WORN))
		if(I.worn_factors)
			var/alist/table = alist()
			for(var/stat in I.worn_factors)
				if(stat != STAT_ITEM_ENCUMBRANCE)
					table[stat] = I.worn_factors[stat]
			acc = oracle_accumulate(acc, table)
	var/encumbrance = oracle_item_encumbrance(H)
	if(encumbrance)
		acc = oracle_accumulate(acc, alist(STAT_ITEM_ENCUMBRANCE = encumbrance))
	return acc

/// What the equipment a human carries adds to its movement delay, folded the way the old calculate_item_encumbrance() did: the worn slots (not suit
/// storage or pockets) scale a slowdown by the species' item_slowdown_mod and leave a speed-up alone, a held item counts only when it slows.
/proc/oracle_item_encumbrance(mob/living/carbon/human/H)
	var/mod = H.species?.item_slowdown_mod
	if(isnull(mod))
		mod = 1
	var/total = 0
	for(var/slot in list(SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_EAR_L, SLOT_ID_EAR_R, SLOT_ID_EYES, SLOT_ID_GLOVES, SLOT_ID_HEAD, SLOT_ID_SHOES, SLOT_ID_ID, SLOT_ID_MASK, SLOT_ID_SUIT, SLOT_ID_UNIFORM))
		var/obj/item/I = H.get_equipped_item(slot)
		if(!istype(I))
			continue
		var/v = I.worn_factor(STAT_ITEM_ENCUMBRANCE)
		if(v > 0 && mod > 0)
			v *= mod
		else if(mod < 0 && v < 0)
			v = -(v * mod)
		else if(mod < 0 && v > 0)
			v += mod
		total += v
	for(var/hand in list(SLOT_ID_HAND_L, SLOT_ID_HAND_R))
		var/obj/item/held = H.get_equipped_item(hand)
		if(istype(held) && held.worn_factor(STAT_ITEM_ENCUMBRANCE) > 0)
			total += held.worn_factor(STAT_ITEM_ENCUMBRANCE) * mod
	return total

/// The vector the old fold gives this body now, keyed by stat id; null when no source contributes.
/datum/body/proc/oracle_fold()
	var/alist/acc = null
	for(var/datum/affliction/A as anything in afflictions)
		acc = A.oracle_factors(acc)
	acc = owner.oracle_effect_factors(acc)
	acc = owner.oracle_stasis_factors(acc)
	acc = oracle_reagent_factors(acc)
	acc = oracle_plan_factors(acc)
	return oracle_finalize(acc)

/// The oracle's value of the factor stat `id` for `L` now, as the stat reads: evasion is the mob's own base evasion (the type's constant) and the factor.
/proc/factor_oracle_value(mob/living/L, id, alist/vector = null)
	if(isnull(vector))
		vector = L.body?.oracle_fold()
	. = vector ? vector[id] : oracle_baseline(id)
	if(id == STAT_EVASION)
		. += initial(L.evasion)

// --- Comparison with the stat vars ----------------------------------------------------------------------------------------------

/// TRUE for a factor whose value is a bit field or a flag (compared exactly).
/proc/factor_oracle_exact(id)
	return id == STAT_SIGHT_FLAGS || id == STAT_ACTION_BLOCKS

/// The factors on which the stat vars of `L` and the oracle disagree: a list of "name: stat value, oracle value" lines, empty when they agree
/// (relative 1e-5 for numbers, exact for bit fields).
/proc/factor_oracle_diff(mob/living/L)
	. = list()
	if(!L?.body || QDELETED(L))
		return
	var/alist/vector = L.body.oracle_fold()
	for(var/id in oracle_ids())
		var/expected = factor_oracle_value(L, id, vector)
		var/actual = stat_value(L, id)
		var/ok
		if(factor_oracle_exact(id))
			ok = (actual == expected)
		else
			ok = (abs(actual - expected) <= 0.00001 * max(1, abs(expected)))
		if(!ok)
			. += "[stat_label(id)]: stat [actual], oracle [expected]"

/// The end of a unit test (RunWrapped): every living mob the test allocated, or that stands in its block, reads what the oracle folds from its
/// sources. A disagreement fails the test that left the mob in that state.
/proc/factor_oracle_audit(datum/unit_test/test)
	var/list/mobs = list()
	for(var/datum/thing as anything in test.allocated)
		if(isliving(thing) && !QDELETED(thing))
			mobs |= thing
	if(test.test_block)
		for(var/turf/T as anything in block_turfs(test.test_block))
			for(var/mob/living/L in T)
				if(!QDELETED(L))
					mobs |= L
	for(var/mob/living/L as anything in mobs)
		if(!L.body)
			continue
		// Every source has its own trigger (an affliction's severity, a reagent's dose, an effect's stacks, the species, a form, an item, stasis), so a body
		// is compared as it stands: a missed trigger shows.
		var/list/diff = factor_oracle_diff(L)
		if(length(diff))
			test.Fail("factor oracle: [L.type] reads differently from the old fold: [jointext(diff, "; ")]", __FILE__, __LINE__)

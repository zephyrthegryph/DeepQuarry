/datum/reagent
	var/name = REAGENT_DEVELOPER_WARNING
	var/id = REAGENT_ID_DEVELOPER_WARNING
	var/description = REAGENT_DESC_DEVELOPER_WARNING
	var/taste_description = "bitterness"
	var/taste_mult = 1 //how this taste compares to others. Higher values means it is more noticable
	var/tmp/datum/reagents/holder = null
	var/reagent_state = SOLID
	var/list/data = null
	var/volume = 0
	/// Heat capacity per unit, J/K (holders sum it: /datum/reagents/proc/heat_capacity()).
	var/specific_heat = REAGENT_SPECIFIC_HEAT_DEFAULT
	var/metabolism = REM // This would be 0.2 normally
	var/list/filtered_organs	// Organs that will slow the processing of this chemical.
	var/mrate_static = FALSE	//If the reagent should always process at the same speed, regardless of species, make this TRUE
	var/ingest_met = 0
	var/touch_met = 0
	var/dose = 0
	var/max_dose = 0
	var/overdose = 0		//Amount at which overdose starts
	var/overdose_mod = 1	//Modifier to overdose damage
	var/can_overdose_touch = FALSE	// Can the chemical OD when processing on touch?
	var/scannable = SCANNABLE_SECRETIVE // Shows up on health analyzers.

	var/affects_dead = 0	// Does this chem process inside a corpse without outside intervention required?
	var/affects_robots = 0	// Does this chem process inside a Synth?

	var/allergen_type		// What potential allergens does this contain?
	var/medallergen_type	// What potential medical allergens does this contain?
	var/allergen_factor = 2	// If the potential allergens are mixed and low-volume, they're a bit less dangerous. Needed for drinks because they're a single reagent compared to food which contains multiple seperate reagents.

	var/cup_icon_state = null
	var/cup_name = null
	var/cup_desc = null
	var/cup_center_of_mass_x = 0
	var/cup_center_of_mass_y = 0
	var/cup_prefix = null

	var/color = "#000000"
	var/color_weight = 1

	var/glass_icon = DRINK_ICON_DEFAULT
	var/glass_name = "something"
	var/glass_desc = "It's a glass of... what, exactly?"
	var/list/glass_special = null // null equivalent to list()

	var/from_belly = FALSE
	var/dialysis_returnable = TRUE
	var/wiki_flag = 0 // Bitflags for secret/food/drink reagent sorting
	var/supply_conversion_value = null
	var/industrial_use = null // unique description for export off station
	/// A list of traits to apply while the reagent is being metabolized.
	var/list/metabolized_traits

	/// This cycle's base overdose injury, set by on_mob_life() around its overdose() call (Rust worked it out with the cycle).
	var/tmp/overdose_injury

	var/coolant_modifier = -0.5 // this is multiplied by the volume of the reagent. Most things are not good coolant. EX: Water is 1, coolant is 2. -1 would be a bad reagent for cooling.

	var/glass_icon_file = null
	var/glass_icon_state = null
	var/glass_center_of_mass_x = 0
	var/glass_center_of_mass_y = 0

	///How much (if any) of this reagent penetrates through skin and into the bloodstream. Ranges from 0 (none at all) to 1 (100% transfer from skin to blood).
	///This is for chemicals that don't have any special touch effects.
	var/dermal_absorption = 0

	// P2-S13: species gates as data. SPECIES_TAG_BIT(IS_*) masks of species this
	// reagent does nothing to by that route (the affect_* proc is not called).
	// Numbers, not lists: reagent datums are instanced per holder.
	var/immune_species_blood = 0
	var/immune_species_ingest = 0
	var/immune_species_touch = 0
	/// SPECIES_TAG_BIT mask of species for which this type's own extra effects are
	/// inert (read with `inert_for()`): parent-type effects a proc chains to still
	/// run, only the extras it gates are skipped. Also gates the base overdose and
	/// withdrawal. Default: diona, who ignore most drugs.
	var/inert_species = SPECIES_TAG_BIT(IS_DIONA)
	/// Per-species multiplier on this reagent's own effect strength: IS_* -> mult.
	/// Read with `species_mult()`; unlisted species get 1.
	var/alist/species_strength
	/// Species reactions by route: IS_* -> alist(INJURY_* = amount per unit
	/// metabolised). Applied by `on_mob_life` every tick that route metabolises,
	/// even when the species is immune to the route's own effects (so an immune
	/// mask plus a table expresses "this species reacts instead").
	var/alist/species_injuries_blood
	var/alist/species_injuries_ingest
	var/alist/species_injuries_touch
	/// SPECIES_TAG_BIT mask of species a sugary reagent sedates (see `sugar_sedation()`).
	var/sugar_sedated_species = SPECIES_TAG_BIT(IS_UNATHI)

/// Is `owner`'s species in the SPECIES_TAG_BIT mask `mask`?
/datum/reagent/proc/species_in(mob/living/owner, mask)
	var/tag = owner?.reagent_tag()
	if(isnull(tag))
		return FALSE
	return (mask & SPECIES_TAG_BIT(tag)) ? TRUE : FALSE

/// Are this reagent's type-specific extras inert for `owner`'s species (`inert_species`)?
/datum/reagent/proc/inert_for(mob/living/owner)
	return species_in(owner, inert_species)

/// The multiplier `owner`'s species applies to this reagent's own effect strength.
/datum/reagent/proc/species_mult(mob/living/owner)
	if(!species_strength)
		return 1
	var/tag = owner?.reagent_tag()
	if(isnull(tag))
		return 1
	var/mult = species_strength[tag]
	return isnull(mult) ? 1 : mult

/// The sugar crash: species in `sugar_sedated_species` grow drowsy, then weak (or,
/// with `deep_sleep`, asleep) as `effective_dose` of a sugary reagent builds.
/datum/reagent/proc/sugar_sedation(mob/living/carbon/M, effective_dose, deep_sleep = FALSE)
	if(!species_in(M, sugar_sedated_species))
		return
	if(effective_dose < 2)
		if(effective_dose == metabolism * 2 || prob(5))
			M.emote("yawn")
	else if(effective_dose < 5)
		M.status_at_least(STAT_BLURRY, 10)
	else if(effective_dose < 20)
		if(prob(50))
			M.status_at_least(STAT_WEAKENED, 2)
		M.status_at_least(STAT_DROWSY, 20)
	else
		if(deep_sleep)
			M.status_at_least(STAT_SLEEPING, 20)
		else
			M.status_at_least(STAT_WEAKENED, 10)
		M.status_at_least(STAT_DROWSY, 60)

/// Deal `owner`'s species' entry in a `species_injuries_*` table for `amount` units.
/datum/reagent/proc/apply_species_injuries(mob/living/owner, alist/table, amount)
	if(!table || !owner || amount <= 0)
		return
	var/tag = owner.reagent_tag()
	if(isnull(tag))
		return
	var/alist/injuries = table[tag]
	for(var/kind in injuries)
		owner.injure(kind, injuries[kind] * amount, source = src)

/// Does `owner`'s species ignore this reagent by metabolism route `route_class`
/// (CHEM_*)? Null route: every route.
/datum/reagent/proc/species_immune(mob/living/owner, route_class = null)
	var/tag = owner?.reagent_tag()
	if(isnull(tag))
		return FALSE
	var/mask
	switch(route_class)
		if(CHEM_BLOOD)
			mask = immune_species_blood
		if(CHEM_INGEST)
			mask = immune_species_ingest
		if(CHEM_TOUCH)
			mask = immune_species_touch
		else
			mask = immune_species_blood & immune_species_ingest & immune_species_touch
	return (mask & SPECIES_TAG_BIT(tag)) ? TRUE : FALSE

/// The one species/biology gate for a reagent's own effects: the amount that
/// acts on `owner` by `route_class`, 0 when the species ignores it.
/datum/reagent/proc/effective_dose(mob/living/owner, amount, route_class = null)
	if(!owner || amount <= 0)
		return 0
	return species_immune(owner, route_class) ? 0 : amount

/datum/reagent/proc/remove_self(amount) // Shortcut
	if(holder)
		holder.remove_reagent(id, amount)

// This doesn't apply to skin contact - this is for, e.g. extinguishers and sprays. The difference is that reagent is not directly on the mob's skin - it might just be on their clothing.
/datum/reagent/proc/touch_mob(mob/M, amount)
	return

/datum/reagent/proc/touch_obj(obj/O, amount, mob/user = null) // Acid melting, cleaner cleaning, etc
	if(notice_wanted(O, /datum/notice/reagent_expose_obj))
		var/datum/notice/reagent_expose_obj/N = notice_take(/datum/notice/reagent_expose_obj)
		N.reagent = src // ALLOW(ownership): a pooled notice holds its entities for one trigger and is reset on release
		N.amount = amount
		notice_publish(O, N)

/datum/reagent/proc/touch_turf(turf/T, amount) // Cleaner cleaning, lube lubbing, etc, all go here
	return

/// One Life cycle of this reagent in `location`, a mob's bloodstream, stomach or skin (Currently, on_mob_life is called on carbons. Any
/// interaction with non-carbon mobs (lube) will need to be done in touch_mob). The holder worked out this cycle's uptake for every reagent
/// at once (/datum/reagents/metabolism/proc/metabolize(): the rates in DM, the dose and overdose maths in Rust, vg_chem); this applies it:
/// the dose, the effects by route, the species' reactions, the overdose, and the units taken out of the holder.
/datum/reagent/proc/on_mob_life(mob/living/carbon/M, alien, datum/reagents/metabolism/location)
	if(!istype(M))
		return
	if(!metabolizes_in(M))
		return
	if(!istype(location))
		return

	var/datum/reagents/metabolism/active_metab = location
	var/list/taken = active_metab.cycle_taken(src)
	var/removed = taken[CHEM_TAKEN_REMOVED]
	var/ingest_abs_mult = taken[CHEM_TAKEN_ABSORBED]
	max_dose = taken[CHEM_TAKEN_MAX_DOSE]
	dose = taken[CHEM_TAKEN_DOSE]
	if(M.species.medallergens & medallergen_type) // Medical allergies don't gain ANY benefits (the reaction is a body factor)...
		remove_self(removed)
		return
	// P2-S13: the species gate is data (`species_immunity`), applied once here
	// instead of re-decided inside every affect_* proc.
	var/route_class = active_metab.metabolism_class
	if(effective_dose(M, removed, route_class) > 0)
		switch(route_class)
			if(CHEM_BLOOD)
				affect_blood(M, alien, removed)
			if(CHEM_INGEST)
				if(istype(src, /datum/reagent/toxin) && has_trait(M, INGESTED_TOXIN_IMMUNE))
					remove_self(removed)
					return
				affect_ingest(M, alien, removed * ingest_abs_mult)
			if(CHEM_TOUCH)
				affect_touch(M, alien, removed)
	switch(route_class)
		if(CHEM_BLOOD)
			apply_species_injuries(M, species_injuries_blood, removed)
		if(CHEM_INGEST)
			apply_species_injuries(M, species_injuries_ingest, removed * ingest_abs_mult)
		if(CHEM_TOUCH)
			apply_species_injuries(M, species_injuries_touch, removed)
	on_mob_metabolize(M, location)
	if(taken[CHEM_TAKEN_OVERDOSING])
		overdose_injury = taken[CHEM_TAKEN_OVERDOSE_INJURY]
		overdose(M, alien, removed)
		overdose_injury = null
	remove_self(removed)
	return

/// Whether this reagent does anything in `M` this cycle: a corpse only for what affects the dead (or a body kept pumping), a synthetic
/// only for what affects robots and when its chemistry runs.
/datum/reagent/proc/metabolizes_in(mob/living/carbon/M)
	if(!affects_dead && M.stat == DEAD && !M.has_body_effect(/datum/body_effect/bloodpump_corpse))
		return FALSE
	if(HAS_SYNTHETIC_BIOLOGY(M) && (!M.synth_reag_processing || !affects_robots))
		return FALSE
	return TRUE

/// The units `M` takes up of this reagent this cycle from `location`, at most: its metabolism times the body's (`location`'s
/// cycle_body(): species, traits, the heart's pulse, the stomach, a machine's pump), slowed by the organs that filter it; or its fixed
/// ingest_met / touch_met. `ingest_rem_mult` is the body's ingest rate (passed so a filter can slow it). Returns list(rate, absorbed share).
/datum/reagent/proc/cycle_rate(mob/living/carbon/M, datum/reagents/metabolism/location, list/body)
	var/removed = metabolism
	var/ingest_rem_mult = 1
	var/ingest_abs_mult = 1
	if(!mrate_static == TRUE)
		for(var/factor in body[CHEM_BODY_REMOVED])
			removed *= factor
		ingest_rem_mult = body[CHEM_BODY_INGEST_REMOVED]
		ingest_abs_mult = body[CHEM_BODY_INGEST_ABSORBED]
		if(ishuman(M) && filtered_organs && filtered_organs.len)
			var/mob/living/carbon/human/H = M
			for(var/organ_tag in filtered_organs)
				var/obj/item/organ/internal/O = H.organ_in(organ_tag)
				if(O && !O.is_broken() && prob(max(0, O.max_damage - O.damage)))
					removed *= 0.8
					if(location.metabolism_class == CHEM_INGEST)
						ingest_rem_mult *= 0.8
	if(ingest_met && (location.metabolism_class == CHEM_INGEST))
		removed = ingest_met * ingest_rem_mult
	if(touch_met && (location.metabolism_class == CHEM_TOUCH))
		removed = touch_met
	return list(removed, ingest_abs_mult)

/datum/reagent/proc/affect_blood(mob/living/carbon/M, alien, removed)
	return

/datum/reagent/proc/affect_ingest(mob/living/carbon/M, alien, removed)
	M.bloodstr.add_reagent(id, removed)
	return

/datum/reagent/proc/affect_touch(mob/living/carbon/M, alien, removed)
	M.bloodstr.add_reagent(id, removed * dermal_absorption)
	return

/datum/reagent/proc/overdose(mob/living/carbon/M, alien, removed) // Overdose effect.
	if(inert_for(M))
		return
	// B6: species scaling is applied per call, never written back onto the reagent.
	var/od_mod = overdose_mod
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		od_mod *= H.species.chemOD_mod
	// 6 damage per unit at minimum, scales with excessive reagents. Rounding should help keep damage consistent between ingest / inject, but isn't perfect.
	// Hardcapped at 3.6 damage per tick, or 18 damage per unit at 0.2 metabolic rate so that you can't instakill people with overdoses by feeding them infinite periadaxon.
	// Overall, max damage is slightly less effective than hydrophoron, and 1/5 as effective as cyanide.
	// The number is Rust's (vg_chem::metabolism): the holder's cycle worked it out; a call outside a cycle asks for this one reagent.
	var/injury = overdose_injury
	if(isnull(injury))
		injury = vg_chem_overdose_injury(removed, od_mod, volume, overdose)
	M.injure(INJURY_TOXIN, injury, source = src)

// --- Body heat (B15 / P2-S10) ---------------------------------------------------
// Reagents heat and cool through the mob's one temperature writer, scaled by the
// amount metabolised this tick: `kelvin_at_rem` is the shift for REM units, so a
// faster or slower metabolism (or a trickle at the end of a dose) moves the body
// in proportion instead of by a fixed step every tick.

/// Warm (positive) or cool (negative) the body by `kelvin_at_rem` per REM metabolised.
/datum/reagent/proc/warm_body(mob/living/M, kelvin_at_rem, removed, min_temp = 0, max_temp = INFINITY)
	if(!M || !kelvin_at_rem || removed <= 0)
		return 0
	return M.adjust_bodytemperature(kelvin_at_rem * removed / REM, min_temp, max_temp)

/// Move the body toward `target` K by up to `kelvin_at_rem` per REM metabolised,
/// never past it. `warm` / `cool` limit which directions this reagent pushes.
/datum/reagent/proc/drive_body_temperature(mob/living/M, target, kelvin_at_rem, removed, warm = TRUE, cool = TRUE)
	if(!M || kelvin_at_rem <= 0 || removed <= 0)
		return 0
	var/step = kelvin_at_rem * removed / REM
	var/current = M.body_temperature()
	if(cool && current > target)
		return M.adjust_bodytemperature(-min(step, current - target))
	if(warm && current < target)
		return M.adjust_bodytemperature(min(step, target - current))
	return 0

/datum/reagent/proc/initialize_data(newdata) // Called when the reagent is created.
	if(!isnull(newdata))
		data = newdata
	// Ensure data is a proper list instance for reagents that declare data = list(...).
	// If the type-default data is a list and we received no newdata, make a per-instance
	// shallow copy so subtypes do not share a single mutable list across all instances.
	else if(islist(data))
		data = data.Copy()
	return

/datum/reagent/proc/mix_data(newdata, newamount) // You have a reagent with data, and new reagent with its own data get added, how do you deal with that?
	return

/// The declared codec for `data` (doc/rewrite/ownership.md §6): the keys whose values are datums the
/// data owns (one, or a list of them). A copy of the data duplicates those instead of aliasing them,
/// so two holders never share a contagion; the serializer's reagent codec reads the same keys.
/// Every other value is plain data, or a relation (blood's "donor").
/datum/reagent/proc/reagent_data_codec()
	return TYPE_TABLE_GET(src, reagent_data_codec_keys)

TYPE_TABLE_DECLARE(/datum/reagent, reagent_data_codec_keys, null)

/// A copy of the data list `source` that shares no owned datum with it (reagent_data_codec() keys
/// get fresh copies through copy_data_value()).
/datum/reagent/proc/copy_data(list/source)
	if(!islist(source))
		return source
	var/list/copy = source.Copy()
	for(var/key in reagent_data_codec())
		var/value = copy[key]
		if(islist(value))
			var/list/fresh = list()
			for(var/datum/D in value)
				fresh += copy_data_value(key, D)
			copy[key] = fresh
		else if(isdatum(value))
			copy[key] = copy_data_value(key, value)
	return copy

/// The copy of one owned datum in `data[key]`.
/datum/reagent/proc/copy_data_value(key, datum/D)
	return D

/datum/reagent/proc/get_data() // Just in case you have a reagent that handles data differently.
	if(data && istype(data, /list))
		return copy_data(data)
	else if(data)
		return data
	return null

/// Returns a list of keys this reagent's data assoc list must always contain, or null if this
/// reagent uses no structured data. Subtypes override to document their schema.
/// Used by validate_data() to detect missing keys introduced by code changes.
TYPE_TABLE_DECLARE(/datum/reagent, get_data_schema, null)

/// Validates that the data assoc list contains all keys declared by get_data_schema().
/// Logs a stack trace for any missing key so issues surface during testing rather than
/// producing silent null reads at access time.
/datum/reagent/proc/validate_data()
	var/list/schema = TYPE_TABLE_GET(src, get_data_schema)
	if(!schema)
		return
	if(!islist(data))
		stack_trace("[type] ([id]) validate_data(): data is null or not a list, but get_data_schema() returned [schema.len] required keys.")
		return
	for(var/key in schema)
		if(!(key in data))
			stack_trace("[type] ([id]) validate_data(): data is missing required key '[key]'.")

/// Constant per-type tables, shared by every instance of a type. DM builds a
/// type-level list default per instance, and a holder instantiates one reagent
/// datum per reagent it contains, so without this each live reagent carries its
/// own copy. The shared tables are read-only: assign a new list, never edit.
/datum/reagent/New()
	var/static/list/shared_by_type = list()
	var/list/shared = shared_by_type[type]
	if(!shared)
		shared = list(treatment_tags, filtered_organs, factors, species_factors, species_strength, species_injuries_blood, species_injuries_ingest, species_injuries_touch)
		shared_by_type[type] = shared
	treatment_tags = shared[1]
	filtered_organs = shared[2]
	factors = shared[3]
	species_factors = shared[4]
	species_strength = shared[5]
	species_injuries_blood = shared[6]
	species_injuries_ingest = shared[7]
	species_injuries_touch = shared[8]
	return ..()


// `data` is plain data plus the owned datums reagent_data_codec() names (copied, never aliased);
// a live mob in it (blood's donor) is a reference the serializer saves as a relation.

/// Called by [/datum/reagents/proc/conditional_update]
/datum/reagent/proc/on_update(atom/A)
	return

/datum/reagent/proc/on_mob_metabolize(mob/living/affected_mob, datum/reagents/metabolism/location)
	SHOULD_CALL_PARENT(TRUE)
	if(metabolized_traits)
		affected_mob.add_traits(metabolized_traits, "metabolize_location:[location]reagent:[type]")

/// Called when this reagent stops being metabolized (due to running out)
/// Has the args 'affected_mob' and 'location' which allows us to remove any traits that is only being added by that reagent holder location. I.e stomach, bloodstream, dermal, etc.
/datum/reagent/proc/on_mob_end_metabolize(mob/living/affected_mob, datum/reagents/location)
	SHOULD_CALL_PARENT(TRUE)
	remove_traits_in(affected_mob, "metabolize_location:[location]reagent:[type]")

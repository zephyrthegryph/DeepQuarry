/// Distilling holders run the distilling regime.
/datum/reagents/distilling/xform_regime()
	return REGIME_DISTILLING

/// Distilling holders do not track belly-reagent state.
/datum/reagents/distilling/supports_belly_reagents()
	return FALSE

/// Distilling holders do not emit reagents_holder_reacted.
/datum/reagents/distilling/on_reactions_handled(list/effect_reactions)
	return

// handle_reactions() is fully inherited from /datum/reagents via the three hook overrides above.
// No logic is duplicated here — xform_regime(), supports_belly_reagents(), and
// on_reactions_handled() together select the distilling regime and suppress the signal.

// ---- Temperature-gated reactions (H3) ----
// A distilling holder's reactions need a temperature. The holder senses its
// atom's heat body against the increasing bounds of every candidate
// reaction's temp_range, and reacts when the temperature crosses one.

/datum/reagents/distilling
	/// The sensing of my_atom's temperature against the reaction bounds, or null.
	var/tmp/datum/sense_sub/heat/heat_set_watch
	/// The bounds it senses.
	var/tmp/list/heat_set_levels

CAPABILITIES(/datum/reagents/distilling)
	owns_one(nameof(heat_set_watch), /datum/sense_sub/heat)


/datum/reagents/distilling/update_total()
	. = ..()
	watch_reaction_temperatures()

/// The temperature bounds of every distilling transformation the contents could run, increasing: the watch bands of their temperature_in() conditions.
/datum/reagents/distilling/proc/reaction_temperatures()
	var/list/levels = list()
	for(var/datum/reagent/R as anything in reagent_list)
		for(var/datum/xform/X as anything in xform_candidates(MEDIUM_REAGENTS, REGIME_DISTILLING, R.id))
			for(var/list/band as anything in X.bands)
				if(!isnull(band[1]))
					levels |= band[1]
				if(!isnull(band[2]))
					levels |= band[2]
	return sortTim(levels, GLOBAL_PROC_REF(cmp_numeric_asc))

/// (Re)builds the sensing when the candidate bounds change.
/datum/reagents/distilling/proc/watch_reaction_temperatures()
	if(QDELETED(my_atom) || isturf(my_atom))
		return
	var/list/levels = reaction_temperatures()
	if(!length(levels))
		unwatch_reaction_temperatures()
		return
	if(heat_set_levels ~= levels && !isnull(heat_set_watch))
		return
	rel_clear(src, nameof(heat_set_watch))
	rel_set(src, nameof(heat_set_watch), sense_heat(src, PROC_REF(on_reaction_bound), my_atom, levels))
	heat_set_levels = isnull(heat_set_watch) ? null : levels

/datum/reagents/distilling/proc/unwatch_reaction_temperatures()
	rel_clear(src, nameof(heat_set_watch))
	heat_set_levels = null

/// The holder's temperature crossed a reaction bound: react now.
/datum/reagents/distilling/proc/on_reaction_bound(band, was)
	if(!QDELETED(my_atom))
		handle_reactions()

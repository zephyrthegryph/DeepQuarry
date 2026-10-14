/// Returns distilled_reactions_by_reagent so handle_reactions() uses the distilling reaction bucket.
/datum/reagents/distilling/get_reaction_lookup()
	return SSchemistry.ready().distilled_reactions_by_reagent

/// Distilling holders do not track belly-reagent state.
/datum/reagents/distilling/supports_belly_reagents()
	return FALSE

/// Distilling holders do not emit reagents_holder_reacted.
/datum/reagents/distilling/on_reactions_handled(list/effect_reactions)
	return

// handle_reactions() is fully inherited from /datum/reagents via the three hook overrides above.
// No logic is duplicated here — get_reaction_lookup(), supports_belly_reagents(), and
// on_reactions_handled() together select the distilling reaction bucket and suppress the signal.

// ---- Temperature-gated reactions (H3) ----
// A distilling holder's reactions need a temperature. The holder watches its
// atom's heat body with one ThresholdSet holding both ends of every candidate
// reaction's temp_range, and reacts when the temperature crosses one.

/datum/reagents/distilling
	/// The ThresholdSet on my_atom's heat body, or null.
	var/tmp/datum/native_watch/heat/heat_set_watch
	/// Levels in the set (payload = index).
	var/tmp/list/heat_set_levels

CAPABILITIES(/datum/reagents/distilling)
	owns_one(nameof(heat_set_watch), /datum/native_watch/heat)


/datum/reagents/distilling/update_total()
	. = ..()
	watch_reaction_temperatures()

/// The temperature bounds of every distilling reaction the contents could run.
/datum/reagents/distilling/proc/reaction_temperatures()
	var/list/levels = list()
	var/list/lookup = get_reaction_lookup()
	for(var/datum/reagent/R as anything in reagent_list)
		for(var/datum/decl/chemical_reaction/distilling/C in lookup[R.id])
			var/list/temp_range = TYPE_TABLE_GET(C, distilling_temp_range)
			levels |= temp_range[1]
			levels |= temp_range[2]
	return levels

/// (Re)builds the ThresholdSet when the candidate bounds change.
/datum/reagents/distilling/proc/watch_reaction_temperatures()
	if(QDELETED(my_atom) || isturf(my_atom))
		return
	var/list/levels = reaction_temperatures()
	if(!length(levels))
		unwatch_reaction_temperatures()
		return
	if(heat_set_levels ~= levels && !isnull(heat_set_watch))
		return
	if(isnull(heat_set_watch))
		rel_set(src, nameof(heat_set_watch), heat_watch_set(src, my_atom, PROC_REF(on_reaction_bound)))
		if(isnull(heat_set_watch))
			return
	for(var/i in 1 to length(levels))
		heat_set_watch.add_entry(i, 1, levels[i], TRUE, TRUE)
	for(var/i in length(levels) + 1 to length(heat_set_levels))
		heat_set_watch.remove_entry(i)
	heat_set_levels = levels

/datum/reagents/distilling/proc/unwatch_reaction_temperatures()
	rel_clear(src, nameof(heat_set_watch))
	heat_set_levels = null

/// The holder's temperature crossed a reaction bound: react now.
/datum/reagents/distilling/proc/on_reaction_bound(datum/native_watch/heat/watch, payload, entered, generation)
	if(!QDELETED(my_atom))
		handle_reactions()

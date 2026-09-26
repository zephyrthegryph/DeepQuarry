/// Returns distilled_reactions_by_reagent so handle_reactions() uses the distilling reaction bucket.
/datum/reagents/distilling/get_reaction_lookup()
	return SSchemistry.distilled_reactions_by_reagent

/// Distilling holders do not track belly-reagent state.
/datum/reagents/distilling/supports_belly_reagents()
	return FALSE

/// Distilling holders do not send COMSIG_REAGENTS_HOLDER_REACTED.
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
	var/tmp/heat_set_watch
	/// Levels in the set (payload = index).
	var/tmp/list/heat_set_levels

/datum/reagents/distilling/Destroy()
	unwatch_reaction_temperatures()
	return ..()

/datum/reagents/distilling/update_total()
	. = ..()
	watch_reaction_temperatures()

/// The temperature bounds of every distilling reaction the contents could run.
/datum/reagents/distilling/proc/reaction_temperatures()
	var/list/levels = list()
	var/list/lookup = get_reaction_lookup()
	for(var/datum/reagent/R as anything in reagent_list)
		for(var/datum/decl/chemical_reaction/distilling/C in lookup[R.id])
			levels |= C.temp_range[1]
			levels |= C.temp_range[2]
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
		heat_set_watch = heat_watch_set(my_atom)
		if(isnull(heat_set_watch))
			return
	for(var/i in 1 to length(levels))
		heat_watch_set_add(heat_set_watch, i, 1, levels[i], TRUE, TRUE)
	for(var/i in length(levels) + 1 to length(heat_set_levels))
		vg_heat_watch_set_remove(heat_set_watch[1], heat_set_watch[2], heat_set_watch[3], i)
	heat_set_levels = levels

/datum/reagents/distilling/proc/unwatch_reaction_temperatures()
	if(!isnull(heat_set_watch))
		heat_unwatch(heat_set_watch)
		heat_set_watch = null
	heat_set_levels = null
	heat_unsubscribe()

/// The holder's temperature crossed a reaction bound: react now.
/datum/reagents/distilling/on_heat_crossing(watch, payload, entered, generation)
	if(watch == heat_set_watch && !QDELETED(my_atom))
		handle_reactions()

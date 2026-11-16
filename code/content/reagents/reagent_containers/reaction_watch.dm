// A loose reagent container follows its own temperature (the heat system, not whatever heated it): while it has a heat body (it was warmed or cooled away from the
// room) it senses its temperature against the edges of the temperature bands of the recipes its contents could take part in
// (code/domains/world_model/reagents/chem_temperature.dm), and when it crosses one its contents react at once. A beaker taken off a hot plate keeps cooling on its
// body's coupling to the room and keeps reacting as it passes through each band. The sensing is not made until the container has a body, so a container at room
// temperature costs nothing.

/// The container got its heat body (it left the temperature of its surroundings): follow the temperature.
/obj/item/reagent_containers/heat_body_created()
	. = ..()
	watch_reaction_bands()

/// (Re)builds the sensing when the edges its contents care about change.
/obj/item/reagent_containers/proc/watch_reaction_bands()
	if(QDELETED(src) || !reagents)
		return
	var/list/levels = reagents.reaction_band_edges()
	if(length(levels) > REACTION_WATCH_MAX_LEVELS)
		// Too many to sense at once: the window of them around the temperature now; the watch moves when the temperature crosses one.
		var/temperature = get_temperature()
		var/above = 1
		while(above <= length(levels) && levels[above] <= temperature)
			above++
		var/first = clamp(above - REACTION_WATCH_MAX_LEVELS / 2, 1, length(levels) - REACTION_WATCH_MAX_LEVELS + 1)
		levels = levels.Copy(first, first + REACTION_WATCH_MAX_LEVELS)
	if(!length(levels))
		rel_clear(src, nameof(reaction_watch))
		reaction_watch_levels = null
		return
	if(reaction_watch_levels ~= levels && !isnull(reaction_watch))
		return
	rel_clear(src, nameof(reaction_watch))
	rel_set(src, nameof(reaction_watch), sense_heat(src, PROC_REF(on_reaction_band), src, levels, keep_body = FALSE))
	reaction_watch_levels = isnull(reaction_watch) ? null : levels

/// The temperature crossed an edge of a recipe's band: react now.
/obj/item/reagent_containers/proc/on_reaction_band(band, was)
	if(QDELETED(src) || !reagents)
		return
	if(GLOB.chem_trace)
		log_world("CHEM: [src] crossed a reaction band edge at [round(get_temperature() - T0C, 0.1)] C (band [was] -> [band]): its contents react")
	reagents.handle_reactions()
	watch_reaction_bands() // the window of edges moves with the temperature

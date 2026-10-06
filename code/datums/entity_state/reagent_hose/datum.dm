/obj/effect/ebeam/hose
	plane = OBJ_PLANE
	layer = STAIRS_LAYER

/datum/hose
	VAR_PRIVATE/name = "hose"

	VAR_PRIVATE/datum/hose_connector/node1 = null
	VAR_PRIVATE/datum/hose_connector/node2 = null

	VAR_PRIVATE/hose_color = "#ffffff"

	VAR_PRIVATE/initial_distance = HOSE_MAX_DISTANCE
	VAR_PRIVATE/datum/beam/current_beam = null

CAPABILITIES(/datum/hose)
	owns_one(nameof(current_beam), /datum/beam)

/// Set once both ends are attached and the hose formed; periodic_step() moves reagents while it is (DECLARE_PERIODIC_WHILE).
OM_FIELD_TYPED(/datum/hose, tmp, hose_formed, FALSE, CHANGE_DATUM_A)
DECLARE_PERIODIC_WHILE(/datum/hose, PERIODIC_FAST, "hose_formed")

/datum/hose/New()
	..()
	lifecycle_decls_init(src) // starts the declaration (a non-atom has no materialize)

/datum/hose/proc/get_pairing(datum/hose_connector/target)
	RETURN_TYPE(/datum/hose_connector)
	if(target)
		if(target == node1)
			return node2
		else if(target == node2)
			return node1
	return null

// a hose disconnects both ends.
/datum/hose/on_destroy(force)
	disconnect()
	..()

/datum/hose/proc/has_pairing()
	return (node1 && node2)

/datum/hose/proc/disconnect(mob/user = null)
	// Stop processing, we're disconnecting anyway
	set_hose_formed(FALSE)
	var/list/drop_locs = list()
	if(node1)
		var/atom/A = node1.get_carrier()
		if(A)
			drop_locs.Add(get_turf(node1.get_carrier()))
			A.visible_message("The hose detatches from \the [A]")
			play_sfx(A, SFX_EFFECTS_CRATE_CLOSE)
			play_sfx(A, SFX_EFFECTS_PLOP)
		node1.remove_hose()
		rel_clear(src, nameof(node1))
	if(node2)
		var/atom/A = node2.get_carrier()
		if(A)
			drop_locs.Add(get_turf(node2.get_carrier()))
			A.visible_message("The hose detatches from \the [A]")
			play_sfx(A, SFX_EFFECTS_CRATE_CLOSE)
			play_sfx(A, SFX_EFFECTS_PLOP)
		node2.remove_hose()
		rel_clear(src, nameof(node2))
	// Drop hose at one of the locations if no user is specified
	if((user || drop_locs.len) && initial_distance)
		new /obj/item/stack/hose(user ? get_turf(user) : pick(drop_locs), initial_distance)
		initial_distance = 0
	update_beam()

/datum/hose/proc/set_hose(datum/hose_connector/target1, datum/hose_connector/target2, distancetonode)
	if(target1 && target2)
		rel_set(src, nameof(node1), target1)
		rel_set(src, nameof(node2), target2)

	node1.connect(src)
	node2.connect(src)
	name = "[name] ([node1],[node2])"

	initial_distance = distancetonode
	if(update_beam()) // Somehow you screwed this up from the start?
		set_hose_formed(TRUE)

		// Poip!~
		var/atom/A = node1.get_carrier()
		A.visible_message("The hose attaches to \the [A]")
		play_sfx(A, SFX_EFFECTS_CRATE_OPEN)
		play_sfx(A, SFX_EFFECTS_POP, 1.3)

		A = node2.get_carrier()
		A.visible_message("The hose attaches to \the [A]")
		play_sfx(A, SFX_EFFECTS_CRATE_OPEN)
		play_sfx(A, SFX_EFFECTS_POP, 1.3)

/// Updates the beam visual effect for the hose. Returns if the hose is still has a valid connection or not.
/datum/hose/proc/update_beam()
	if(!node1 && !node2) // We've already disconnected, clear beam
		if(current_beam)
			own_clear(src, nameof(current_beam), OWN_DELETE)
		return FALSE
	if(get_dist(get_turf(node1.get_carrier()), get_turf(node2.get_carrier())) > initial_distance)	// The hose didn't form. Something's fucky.
		spent(src)
		return FALSE

	var/turf/A = get_turf(node1.get_carrier())
	var/turf/B = get_turf(node2.get_carrier())
	if(get_dist(A,B) > 0)
		// Colors!
		var/new_col = hose_color
		var/datum/reagents/reagent_node1 = node1.reagents
		var/datum/reagents/reagent_node2 = node2.reagents
		if(reagent_node1.total_volume > reagent_node2.total_volume)
			new_col = reagent_node1.get_color()
		else if(reagent_node2.total_volume > 0)
			new_col = reagent_node2.get_color()

		// We are in the beam!
		rel_set(src, nameof(current_beam), A.Beam(B, icon_state = "hose", beam_color = new_col, maxdistance = (HOSE_MAX_DISTANCE + 1), beam_type = /obj/effect/ebeam/hose))

	return TRUE

/datum/hose/periodic_step()
	if(node1 && node2)
		if(!update_beam())
			return

		var/datum/reagents/reagent_node1 = node1.reagents
		var/datum/reagents/reagent_node2 = node2.reagents

		switch(node1.get_flow_direction())	// Node 1 is the default 'master', interactions are considered in all current possible states in regards to it, however.
			if(HOSE_INPUT)
				if(node2.get_flow_direction() == HOSE_NEUTRAL)	// We're input, they're neutral. Take half of our volume.
					reagent_node2.trans_to_holder(reagent_node1, reagent_node1.maximum_volume / 2)
				else if(node2.get_flow_direction() == HOSE_OUTPUT)	// We're input, they're output. Take all of our volume.
					reagent_node2.trans_to_holder(reagent_node1, reagent_node1.maximum_volume)

			if(HOSE_OUTPUT)	// We're output, give all of their maximum volume.
				reagent_node1.trans_to_holder(reagent_node2, reagent_node2.maximum_volume)

			if(HOSE_NEUTRAL)
				switch(node2.get_flow_direction())
					if(HOSE_INPUT)	// We're neutral, they're input. Give them half of their volume.
						reagent_node1.trans_to_holder(reagent_node2, reagent_node2.maximum_volume / 2)

					if(HOSE_NEUTRAL)	// We're neutral, they're neutral. Balance our values.
						var/volume_difference_perc = (reagent_node1.total_volume / reagent_node1.maximum_volume) - (reagent_node2.total_volume / reagent_node2.maximum_volume)
						var/volume_difference = 0

						var/pulling = FALSE
						if(volume_difference_perc > 0)	// They are smaller, so they determine the transfer amount. Half of the difference will equalize.
							volume_difference = reagent_node2.maximum_volume * volume_difference_perc / 2

						else if(volume_difference_perc < 0)	// We're smaller, so we determine the transfer amount. Half of the difference will equalize.
							volume_difference_perc *= -1

							pulling = TRUE

							volume_difference = reagent_node1.maximum_volume * volume_difference_perc / 2

						if(volume_difference)
							if(pulling)
								reagent_node2.trans_to_holder(reagent_node1, volume_difference)
							else
								reagent_node1.trans_to_holder(reagent_node2, volume_difference)

					if(HOSE_OUTPUT)
						reagent_node2.trans_to_holder(reagent_node1, reagent_node2.maximum_volume)

	else
		spent(src)

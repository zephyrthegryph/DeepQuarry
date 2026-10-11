/datum/planet/sif
	expected_z_levels = list(
		Z_NAME_ALIAS_SURFACE,
		Z_NAME_ALIAS_SURFACE_MINES,
		Z_NAME_ALIAS_SURFACE_WILDS,
		//Z_LEVEL_SURFACE_SKYLANDS, //Sky islands removal due to lack of use
		//Z_LEVEL_SURFACE_VALLEY //Replaced with Tyr
	)
// Z_LEVEL_SURFACE_CASINO // KSC = So there is weather on the Casino. //Move this into /datum/planet/sif and remember to add a coma for the new entry, for when you need the casino again

// Shared only between SC and SN
/obj/effect/map_effect/portal/master/side_a/wilderness_to_valley
	portal_id = "wilderness_valley"

/obj/effect/map_effect/portal/master/side_b/wilderness_to_valley
	portal_id = "wilderness_valley"

// Shared between SC, SN, RB
/obj/effect/map_effect/portal/master/side_a/plains_to_caves
	portal_id = "plains_caves-normal"

/obj/effect/map_effect/portal/master/side_b/caves_to_plains
	portal_id = "plains_caves-normal"

/obj/effect/map_effect/portal/master/side_a/plains_to_caves/river
	portal_id = "plains_caves-river"

/obj/effect/map_effect/portal/master/side_b/caves_to_plains/river
	portal_id = "plains_caves-river"

/obj/effect/map_effect/portal/master/side_a/caves_to_wilderness
	portal_id = "caves_wilderness-normal"

/obj/effect/map_effect/portal/master/side_b/wilderness_to_caves
	portal_id = "caves_wilderness-normal"

/obj/effect/map_effect/portal/master/side_a/caves_to_wilderness/river
	portal_id = "caves_wilderness-river"

/obj/effect/map_effect/portal/master/side_b/wilderness_to_caves/river
	portal_id = "caves_wilderness-river"

// Bridge teleporters: a step moves you across the bridge, by the shift from where the trigger is placed.
/obj/effect/step_trigger/teleporter/bridge
	var/shift_x = 0
	var/shift_y = 0

/obj/effect/step_trigger/teleporter/bridge/Trigger(atom/movable/AM)
	move_object(AM, locate(x + shift_x, y + shift_y, z))

/obj/effect/step_trigger/teleporter/bridge/east_to_west
	shift_x = -4

/obj/effect/step_trigger/teleporter/bridge/east_to_west/small
	shift_x = -3

/obj/effect/step_trigger/teleporter/bridge/west_to_east
	shift_x = 4

/obj/effect/step_trigger/teleporter/bridge/west_to_east/small
	shift_x = 3

/obj/effect/step_trigger/teleporter/bridge/north_to_south
	shift_y = -4

/obj/effect/step_trigger/teleporter/bridge/south_to_north
	shift_y = 4

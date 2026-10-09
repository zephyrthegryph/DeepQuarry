/// Sprays the gibs of pattern `gibber_type` (an /obj/effect/gibspawner type) at `location`.
/proc/gibs(atom/location, datum/dna/MobDNA, gibber_type = /obj/effect/gibspawner/generic, fleshcolor, bloodcolor)
	var/obj/effect/gibspawner/P = gibber_type
	if(!fleshcolor)
		fleshcolor = initial(P.fleshcolor)
	if(!bloodcolor)
		bloodcolor = initial(P.bloodcolor)
	if(initial(P.sparks))
		fx_sparks(get_turf(location), 2)
	for(var/list/row as anything in gib_pattern(gibber_type))
		var/gib_type = row[1]
		var/amount = row[2]
		if(amount < 0) // 0 to 2
			amount = rand(0, 2)
		var/list/directions = row[3]
		for(var/j in 1 to amount)
			var/obj/effect/decal/cleanable/blood/gibs/gib = new gib_type(location)
			// Apply human species colouration to masks.
			if(fleshcolor)
				gib.set_fleshcolor(fleshcolor)
			if(bloodcolor)
				gib.set_basecolor(bloodcolor)
			gib.init_forensic_data()
			gib.add_blooddna(MobDNA, null)
			if(isturf(location) && length(directions))
				gib.streak(directions)

/// Gib patterns: rows of list(gib type, amount (-1: 0 to 2), streak directions).
GLOBAL_LIST_INIT(gib_pattern_generic, list( \
	list(/obj/effect/decal/cleanable/blood/gibs, 2, list(WEST, NORTHWEST, SOUTHWEST, NORTH)), \
	list(/obj/effect/decal/cleanable/blood/gibs, 2, list(EAST, NORTHEAST, SOUTHEAST, SOUTH)), \
	list(/obj/effect/decal/cleanable/blood/gibs/core, 1, list()) \
))
GLOBAL_LIST_INIT(gib_pattern_human, list( \
	list(/obj/effect/decal/cleanable/blood/gibs, 1, list(NORTH, NORTHEAST, NORTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/down, 1, list(SOUTH, SOUTHEAST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs, 1, list(WEST, NORTHWEST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs, 1, list(EAST, NORTHEAST, SOUTHEAST)), \
	list(/obj/effect/decal/cleanable/blood/gibs, 1, list(NORTH, SOUTH, EAST, WEST, NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs, -1, list(NORTH, SOUTH, EAST, WEST, NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/core, 1, list()) \
))
GLOBAL_LIST_INIT(gib_pattern_robot, list( \
	list(/obj/effect/decal/cleanable/blood/gibs/robot/up, 1, list(NORTH, NORTHEAST, NORTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/robot/down, 1, list(SOUTH, SOUTHEAST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/robot, 1, list(WEST, NORTHWEST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/robot, 1, list(EAST, NORTHEAST, SOUTHEAST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/robot, 1, list(NORTH, SOUTH, EAST, WEST, NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST)), \
	list(/obj/effect/decal/cleanable/blood/gibs/robot/limb, -1, list(NORTH, SOUTH, EAST, WEST, NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST)) \
))

/// The gib pattern of an /obj/effect/gibspawner type (a shared GLOB list; don't modify it).
/proc/gib_pattern(gibber_type)
	if(ispath(gibber_type, /obj/effect/gibspawner/robot))
		return GLOB.gib_pattern_robot
	if(ispath(gibber_type, /obj/effect/gibspawner/human))
		return GLOB.gib_pattern_human
	return GLOB.gib_pattern_generic

/// A mapped gib spray: resolved at map time into its gibs.
/obj/effect/gibspawner
	var/sparks = 0 //whether sparks spread
	var/fleshcolor //Used for gibbed humans.
	var/bloodcolor //Used for gibbed humans.
	invisibility = INVISIBILITY_BADMIN // So a badmin can go view these by changing their see_invisible.
	icon = 'icons/effects/map_effects.dmi'
	icon_state = "gibspawn"

CAPABILITIES(/obj/effect/gibspawner)
	map_resolver(GLOBAL_PROC_REF(resolve_gibspawner), vars = list("bloodcolor", "fleshcolor"))

/proc/resolve_gibspawner(atom/loc, path, list/varedits)
	var/obj/effect/gibspawner/P = path
	gibs(loc, null, path, MAP_VAR(P, varedits, fleshcolor), MAP_VAR(P, varedits, bloodcolor))
	return TRUE

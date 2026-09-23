/turf/simulated/wall/r_wall
	icon_state = "rgeneric"
	rad_insulation = RAD_HEAVY_INSULATION
/turf/simulated/wall/r_wall/Initialize(mapload)
	. = ..(mapload, MAT_PLASTEEL,MAT_PLASTEEL) //3strong

/turf/simulated/wall/shull
	icon_state = "hull-steel"
/turf/simulated/wall/shull/Initialize(mapload) //Spaaaace ship.
	. = ..(mapload,  MAT_STEELHULL, null, MAT_STEELHULL)
/turf/simulated/wall/rshull
	icon_state = "hull-r_steel"
	rad_insulation = RAD_HEAVY_INSULATION
/turf/simulated/wall/rshull/Initialize(mapload)
	. = ..(mapload,  MAT_STEELHULL, MAT_STEELHULL, MAT_STEELHULL)
/turf/simulated/wall/rpshull
	icon_state = "hull-r_plasteel"
/turf/simulated/wall/rpshull/Initialize(mapload)
	. = ..(mapload,  MAT_PLASTEELHULL, MAT_PLASTEELHULL, MAT_PLASTEELHULL)


/turf/simulated/wall/thull
	icon_state = "hull-titanium"
	rad_insulation = RAD_HEAVY_INSULATION

/turf/simulated/wall/thull/Initialize(mapload)
	. = ..(mapload,  MAT_TITANIUMHULL, null, MAT_TITANIUMHULL)


/turf/simulated/wall/cult
	icon_state = "cult"
/turf/simulated/wall/cult/Initialize(mapload)
	. = ..(mapload, MAT_CULT,MAT_CULT2,MAT_CULT)
/turf/unsimulated/wall/cult
	name = "cult wall"
	desc = "Hideous images dance beneath the surface."
	icon = 'icons/turf/wall_masks.dmi'
	icon_state = "cult"

/turf/simulated/wall/iron/Initialize(mapload)
	. = ..(mapload, MAT_IRON)
/turf/simulated/wall/diamond/Initialize(mapload)
	. = ..(mapload, MAT_DIAMOND)
/turf/simulated/wall/gold/Initialize(mapload)
	. = ..(mapload, MAT_GOLD)


/turf/simulated/wall/r_lead
	rad_insulation = RAD_EXTREME_INSULATION

/turf/simulated/wall/r_lead/Initialize(mapload)
	. = ..(mapload, MAT_LEAD, MAT_LEAD)
/turf/simulated/wall/phoron/Initialize(mapload)
	. = ..(mapload, MAT_PHORON)
/turf/simulated/wall/sandstone/Initialize(mapload)
	. = ..(mapload, MAT_SANDSTONE)
/turf/simulated/wall/golddiamond/Initialize(mapload)
	. = ..(mapload, MAT_GOLD,MAT_DIAMOND)
/turf/simulated/wall/snowbrick/Initialize(mapload)
	. = ..(mapload, MAT_SNOWBRICK)


/turf/simulated/wall/concrete
	icon_state = "brick"
	rad_insulation = RAD_HEAVY_INSULATION

/turf/simulated/wall/concrete/Initialize(mapload)
	. = ..(mapload, MAT_CONCRETE) //3strong


// Kind of wondering if this is going to bite me in the butt.
/turf/simulated/wall/skipjack/Initialize(mapload)
	. = ..(mapload, MAT_ALIENALLOY)
/turf/simulated/wall/skipjack/attackby()
	return
/turf/simulated/wall/titanium/Initialize(mapload)
	. = ..(mapload, MAT_TITANIUM)

/turf/simulated/wall/durasteel
	rad_insulation = RAD_HEAVY_INSULATION

/turf/simulated/wall/durasteel/Initialize(mapload)
	. = ..(mapload, MAT_DURASTEEL, MAT_DURASTEEL)


// ENd

/turf/simulated/wall/wood/Initialize(mapload)
	. = ..(mapload,  MAT_WOOD)


/turf/simulated/wall/log_sif/Initialize(mapload)
	. = ..(mapload,  MAT_SIFLOG)


// Shuttle Walls
/turf/simulated/shuttle/wall
	name = "autojoin wall"
	icon_state = "light"
	opacity = 1
	density = TRUE
	blocks_air = 1

	var/base_state = "light" //The base iconstate to base sprites on
	var/hard_corner = 0 //Forces hard corners (as opposed to diagonals)
	var/true_name = "wall" //What to rename this to on init

	//Extra things this will try to locate and act like we're joining to. You can put doors, or whatever.
	//Carefully means only if it's on a /turf/simulated/shuttle subtype turf.
	var/static/list/join_carefully = list(
	/obj/structure/grille,
	/obj/machinery/door/blast/regular
	)
	var/static/list/join_always = list(
	/obj/structure/shuttle/engine,
	/obj/structure/shuttle/window,
	/obj/machinery/door/airlock/voidcraft
	)

/turf/simulated/shuttle/wall/hard_corner
	name = "hardcorner wall"
	icon_state = "light-hc"
	hard_corner = 1

/turf/simulated/shuttle/wall/no_join
	icon_state = "light-nj"
	join_group = null

/turf/simulated/shuttle/wall/dark
	icon = 'icons/turf/shuttle_dark.dmi'
	icon_state = "dark"
	base_state = "dark"

/turf/simulated/shuttle/wall/dark/hard_corner
	name = "hardcorner wall"
	icon_state = "dark-hc"
	hard_corner = 1

/turf/simulated/shuttle/wall/dark/no_join
	name = "nojoin wall"
	icon_state = "dark-nj"
	join_group = null

/turf/simulated/shuttle/wall/alien
	icon = 'icons/turf/shuttle_alien.dmi'
	icon_state = "alien"
	base_state = "alien"
	light_range = 3
	light_power = 0.75
	light_color = "#ff0066" // Pink-ish
	light_on = TRUE
	block_tele = TRUE // Will be used for dungeons so this is needed to stop cheesing with handteles.

/turf/simulated/shuttle/wall/alien/Initialize(mapload)
	. = ..()
	update_light()


/turf/simulated/shuttle/wall/Initialize(mapload)
	. = ..()

	//To allow mappers to rename shuttle walls to like "redfloor interior" or whatever for ease of use.
	name = true_name

	if(join_group)
		auto_join()
	else
		icon_state = base_state

	if(takes_underlays)
		underlay_update()

/turf/simulated/shuttle/wall/proc/auto_join()
	match_turf(NORTH, NORTH)
	match_turf(EAST, EAST)
	match_turf(SOUTH, SOUTH)
	match_turf(WEST, WEST)

	icon_state = "[base_state][join_flags]"
	if(isDiagonal(join_flags))
		if(hard_corner) //You are using 'hard' (aka full-tile) corners.
			icon_state += "h" //Hard corners have 'h' at the end of the state
		else //Diagonals need an underlay to not look ugly.
			takes_underlays = 1
	else //Everything else doesn't deserve our time!
		takes_underlays = initial(takes_underlays)

	return join_flags

/turf/simulated/shuttle/wall/proc/match_turf(direction, flag, mask=0)
	if((join_flags & mask) == mask)
		var/turf/simulated/shuttle/wall/adj = get_step(src, direction)
		if(istype(adj, /turf/simulated/shuttle/wall) && adj.join_group == src.join_group)
			join_flags |= flag      // turn on the bit flag
			return

		else if(istype(adj, /turf/simulated/shuttle))
			var/turf/simulated/shuttle/adj_cast = adj
			if(adj_cast.join_group == src.join_group)
				var/found
				for(var/E in join_carefully)
					found = locate(E) in adj
					if(found) break
				if(found)
					join_flags |= flag      // turn on the bit flag
					return

		var/always_found
		for(var/E in join_always)
			always_found = locate(E) in adj
			if(always_found) break
		if(always_found)
			join_flags |= flag      // turn on the bit flag
		else
			join_flags &= ~flag     // turn off the bit flag

/turf/simulated/shuttle/wall/voidcraft
	name = "voidcraft wall"
	icon = 'icons/turf/shuttle_void.dmi'
	icon_state = "void"
	base_state = "void"
	var/stripe_color = null // If set, generates a colored stripe overlay.  Accepts #XXXXXX as input.

/turf/simulated/shuttle/wall/voidcraft/hard_corner
	name = "hardcorner wall"
	icon_state = "void-hc"
	hard_corner = 1

/turf/simulated/shuttle/wall/voidcraft/hard_corner/blue
	name = "hardcorner wall"
	icon_state = "void-hc"
	hard_corner = 1
	stripe_color = "#0000FF"


/turf/simulated/shuttle/wall/voidcraft/no_join
	name = "nojoin wall"
	icon_state = "void-nj"
	join_group = null

/turf/simulated/shuttle/wall/voidcraft/red
	stripe_color = "#FF0000"

/turf/simulated/shuttle/wall/voidcraft/blue
	stripe_color = "#0000FF"

/turf/simulated/shuttle/wall/voidcraft/lightblue
	stripe_color = "#33ccff"

/turf/simulated/shuttle/wall/voidcraft/orange
	stripe_color = "#cc3300"

/turf/simulated/shuttle/wall/voidcraft/green
	stripe_color = "#00FF00"

/turf/simulated/shuttle/wall/voidcraft/Initialize(mapload)
	. = ..()
	update_icon()

/turf/simulated/shuttle/wall/voidcraft/update_icon()
	if(stripe_color)
		cut_overlays()
		var/image/I = image(icon = src.icon, icon_state = "o_[icon_state]")
		I.color = stripe_color
		add_overlay(I)

// Fake corners for making hulls look pretty
/obj/structure/hull_corner
	name = "hull corner"
	plane = OBJ_PLANE - 1
	icon = 'icons/turf/wall_masks.dmi'
	icon_state = "hull_corner"

	anchored = TRUE
	density = TRUE
	breakable = TRUE

/obj/structure/hull_corner/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/structure/hull_corner/LateInitialize()
	update_look()

/obj/structure/hull_corner/proc/get_dirs_to_test()
	return list(dir, turn(dir,90))

/obj/structure/hull_corner/proc/update_look()
	cut_overlays()
	var/turf/simulated/wall/T
	for(var/direction in get_dirs_to_test())
		T = get_step(src, direction)
		if(!istype(T))
			continue

		name = T.name
		desc = T.desc

		var/datum/material/B = T.material
		var/datum/material/R = T.reinf_material

		if(B?.icon_colour)
			color = B.icon_colour
		if(R?.icon_colour)
			var/image/I = image(icon, icon_state+"_reinf", dir=dir)
			I.color = R.icon_colour
			add_overlay(I)
		break

	if(!T)
		WARNING("Hull corner at [x],[y] not placed adjacent to a hull it can find.")

/obj/structure/hull_corner/long_vert
	icon = 'icons/turf/wall_masks32x64.dmi'
	bound_height = 64

/obj/structure/hull_corner/long_vert/get_dirs_to_test()
	return list(dir, turn(dir,90), turn(dir,-90))

/obj/structure/hull_corner/long_horiz
	icon = 'icons/turf/wall_masks64x32.dmi'
	bound_width = 64

/obj/structure/hull_corner/long_horiz/get_dirs_to_test()
	return list(dir, turn(dir,90), turn(dir,-90))


// Eris walls
/turf/simulated/wall/eris
	icon = 'icons/turf/wall_masks_eris.dmi'
	icon_state = "generic"
	wall_masks = 'icons/turf/wall_masks_eris.dmi'
	var/static/list/blend_objects = list(/obj/machinery/door) // convert to static list
	var/static/list/noblend_objects = list(/obj/machinery/door/window, /obj/machinery/door/firedoor) // convert to static list

/turf/simulated/wall/eris/can_join_with_low_wall(obj/structure/low_wall/WF)
	return istype(WF, /obj/structure/low_wall/eris)

/turf/simulated/wall/eris/special_wall_connections(list/dirs, list/inrange)
	..()
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		var/decided_to_blend = FALSE
		blend_obj_loop:
			for(var/obj/O in T)
				for(var/b_type in blend_objects)
					if(istype(O, b_type))
						decided_to_blend = TRUE
						for(var/obj/structure/S in T)
							if(istype(S, src))
								decided_to_blend = FALSE
						for(var/nb_type in noblend_objects)
							if(istype(O, nb_type))
								decided_to_blend = FALSE

					if(decided_to_blend)
						dirs += direction
						break blend_obj_loop // breaks outer loop


// Bay walls
/turf/simulated/wall/bay
	icon = 'icons/turf/wall_masks_bay.dmi'
	icon_state = "generic"
	wall_masks = 'icons/turf/wall_masks_bay.dmi'
	var/static/list/blend_objects = list(/obj/machinery/door) // convert to static list
	var/static/list/noblend_objects = list(/obj/machinery/door/window, /obj/machinery/door/firedoor) // convert to static list

	var/stripe_color // Adds a colored stripe to the walls

/turf/simulated/wall/bay/can_join_with_low_wall(obj/structure/low_wall/WF)
	return istype(WF, /obj/structure/low_wall/bay)

/turf/simulated/wall/bay/update_icon()
	. = ..()
	if(stripe_color)
		var/image/I
		var/list/connections = get_wall_connections()
		for(var/i = 1 to 4)
			I = image(wall_masks, "stripe[connections[i]]", dir = 1<<(i-1))
			I.color = stripe_color
			add_overlay(I)

/turf/simulated/wall/bay/special_wall_connections(list/dirs, list/inrange)
	..()
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		var/decided_to_blend = FALSE
		blend_obj_loop:
			for(var/obj/O in T)
				for(var/b_type in blend_objects)
					if(istype(O, b_type))
						decided_to_blend = TRUE
						for(var/obj/structure/S in T)
							if(istype(S, src))
								decided_to_blend = FALSE
						for(var/nb_type in noblend_objects)
							if(istype(O, nb_type))
								decided_to_blend = FALSE

					if(decided_to_blend)
						dirs += direction
						break blend_obj_loop // breaks outer loop


/turf/simulated/wall/tgmc
	icon = 'icons/turf/wall_masks_tgmc.dmi'
	wall_masks = 'icons/turf/wall_masks_tgmc.dmi' // not really a MASK per-se, I guess
	icon_state = "metal0"

	var/static/list/blend_objects = list(/obj/machinery/door) // convert to static list
	var/static/list/noblend_objects = list(/obj/machinery/door/window, /obj/machinery/door/firedoor) // convert to static list

	var/wall_base_state = "metal"
	var/wall_blend_category = "metal"
	var/force_icon
	var/list/blend_log = list()
	var/strict_blending = FALSE
	var/diagonal_blending = FALSE

// *INHALE
/turf/simulated/wall/tgmc/update_icon()
	if(!damage_overlays[1]) //list hasn't been populated
		generate_overlays()

	cut_overlays()

	if(force_icon)
		icon_state = "[wall_base_state][force_icon]"
	else
		icon_state = "[wall_base_state][wall_connections]"

	var/damage_fraction = wall_damage_fraction()
	if(damage_fraction > 0)
		var/overlay = round(damage_fraction * damage_overlays.len) + 1
		if(overlay > damage_overlays.len)
			overlay = damage_overlays.len

		add_overlay(damage_overlays[overlay])

/turf/simulated/wall/tgmc/update_connections(propagate)
	if(!material)
		return
	var/dirs = 0
	var/list_to_use = diagonal_blending ? GLOB.alldirs : GLOB.cardinal
	main_direction_loop:
		for(var/direction in list_to_use)
			var/turf/simulated/wall/tgmc/W = get_step(src, direction)
			if(strict_blending)
				if(istype(W, src))
					dirs |= direction
				continue main_direction_loop

			var/decided_to_blend = FALSE
			for(var/obj/O in W)
				for(var/b_type in blend_objects)
					if(istype(O, b_type))
						decided_to_blend = TRUE
						for(var/obj/structure/S in W)
							if(istype(S, src))
								decided_to_blend = FALSE
						for(var/nb_type in noblend_objects)
							if(istype(O, nb_type))
								decided_to_blend = FALSE

					if(decided_to_blend)
						blend_log += "Blending with [O] at [direction] because special said to"
						dirs |= direction
						continue main_direction_loop

			for(var/obj/structure/low_wall/WF in W)
				if(can_join_with_low_wall(WF))
					dirs |= direction
					blend_log += "Blending with [WF] at [get_dir(src, WF)] because can join with that low wall"
					continue main_direction_loop

			// Needs to be our type of wall to blend from this point
			if(!istype(W))
				continue
			if(propagate)
				W.update_connections()
				W.update_icon()
			if(W.wall_blend_category == wall_blend_category)
				dirs |= direction
				blend_log += "Blending with [W] at [get_dir(src, W)] because blend category is the same"

	wall_connections = dirs

/turf/simulated/wall/tgmc/can_join_with_low_wall(obj/structure/low_wall/WF)
	return istype(WF, /obj/structure/low_wall)


#define WINDOW_GLASS 0x1
#define WINDOW_RGLASS 0x2


#undef WINDOW_GLASS
#undef WINDOW_RGLASS


/turf/simulated/shuttle/wall/alien/blue
	name = "hybrid wall"
	desc = "Seems slightly more friendly than if the wall were ominous purple."
	icon = 'icons/turf/shuttle_alien_blue.dmi'
	light_color = "#1fdbf4" // Cyan-ish

/turf/simulated/shuttle/wall/alien/blue/hard_corner
	name = "hybrid wall"
	icon_state = "alien-hc"
	hard_corner = 1

/turf/simulated/shuttle/wall/alien/blue/no_join
	name = "hybrid wall"
	icon_state = "alien-nj"
	join_group = null

/turf/simulated/flesh
	name = "flesh wall"
	desc = "The fleshy surface of this wall squishes nicely under your touch but looks and feels extremly strong"
	icon = 'icons/turf/stomach_vr.dmi'
	icon_state = "flesh"
	opacity = 1
	density = TRUE
	blocks_air = 1


/turf/simulated/flesh/attackby()
	return

/turf/simulated/flesh/Initialize(mapload)
	. = ..()
	update_icon(1)

GLOBAL_LIST_EMPTY(flesh_overlay_cache)

/turf/simulated/flesh/update_icon(update_neighbors)
	cut_overlays()

	if(density)
		icon = 'icons/turf/stomach_vr.dmi'
		icon_state = "flesh"
		for(var/direction in GLOB.cardinal)
			var/turf/T = get_step(src,direction)
			if(istype(T) && !T.density)
				var/place_dir = turn(direction, 180)
				if(!GLOB.flesh_overlay_cache["flesh_side_[place_dir]"])
					GLOB.flesh_overlay_cache["flesh_side_[place_dir]"] = image('icons/turf/stomach_vr.dmi', "flesh_side", dir = place_dir)
				add_overlay(GLOB.flesh_overlay_cache["flesh_side_[place_dir]"])

	if(update_neighbors)
		for(var/direction in GLOB.alldirs)
			if(istype(get_step(src, direction), /turf/simulated/flesh))
				var/turf/simulated/flesh/F = get_step(src, direction)
				F.update_icon()

/turf/simulated/gore
	name = "wall of viscera"
	desc = "Its veins pulse in a sickeningly rapid fashion, while certain spots of the wall rise and fall gently, much like slow, deliberate breathing."
	icon = 'icons/goonstation/turf/meatland.dmi'
	icon_state = "bloodwall_2"
	opacity = 1
	density = TRUE
	blocks_air = 1

/turf/simulated/goreeyes
	name = "wall of viscera"
	desc = "Strangely observant eyes dot the wall. Getting too close has the eyes fixate on you, while their pupils shake violently. Each socket is connected by a series of winding, writhing veins."
	icon = 'icons/goonstation/turf/meatland.dmi'
	icon_state = "bloodwall_4"
	opacity = 1
	density = TRUE
	blocks_air = 1


/turf/simulated/wall/rplastihull
	icon_state = "rhull-plastitanium"
	icon = 'icons/turf/wall_masks_vr.dmi'
/turf/simulated/wall/rplastihull/Initialize(mapload)
	. = ..(mapload, MAT_PLASTITANIUMHULL,MAT_PLASTITANIUMHULL,MAT_PLASTITANIUMHULL)


/turf/simulated/wall/diamond
	icon_state = "diamond"
	icon = 'icons/turf/wall_masks_vr.dmi'


/turf/simulated/wall/durasteel
	icon_state = "durasteel"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/elevator
	icon_state = "elevator"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/gold
	icon_state = "gold"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/golddiamond
	icon_state = "golddiamond"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/iron
	icon_state = "iron"
	icon = 'icons/turf/wall_masks_vr.dmi'


/turf/simulated/wall/log_sif
	icon_state = "log_sif"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/phoron
	icon_state = "phoron"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/r_lead
	icon_state = "lead"
	icon = 'icons/turf/wall_masks_vr.dmi'


/turf/simulated/wall/sandstone
	icon_state = "sandstone"
	icon = 'icons/turf/wall_masks_vr.dmi'


/turf/simulated/wall/skipjack
	icon_state = "skipjack"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/snowbrick
	icon_state = "snowbrick"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/solidrock
	icon_state = "solidrock"
	icon = 'icons/turf/wall_masks_vr.dmi'
	climbable = TRUE

/turf/simulated/wall/titanium
	icon_state = "titanium"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/uranium
	icon_state = "uranium"
	icon = 'icons/turf/wall_masks_vr.dmi'
	var/last_event = 0

/turf/simulated/wall/uranium/Initialize(mapload)
	. = ..(mapload, MAT_URANIUM)
	RegisterSignal(src, COMSIG_ATOM_PROPAGATE_RAD_PULSE, PROC_REF(radiate))

/turf/simulated/wall/uranium/Destroy()
	UnregisterSignal(src, COMSIG_ATOM_PROPAGATE_RAD_PULSE)
	. = ..()

/turf/simulated/wall/uranium/radiate()
	// SIGNAL_HANDLER is declared on /turf/simulated/wall/radiate(); this override
	// inherits the contract and must not re-set the should_not_sleep pragma.
	if(active)
		return
	if(world.time <= last_event + 1.5 SECONDS)
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = 3,
		threshold = RAD_LIGHT_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = 5
	)
	propagate_radiation_pulse()
	last_event = world.time
	active = FALSE


/turf/simulated/wall/wood
	icon_state = "wood"
	icon = 'icons/turf/wall_masks_vr.dmi'


/turf/simulated/wall/stonelogs
	icon_state = "stonelogs"
	icon = 'icons/turf/wall_masks_vr.dmi'

/turf/simulated/wall/stonelogs/Initialize(mapload)
			. = ..(mapload, MAT_CONCRETE,MAT_LOG)

/turf/simulated/wall/glass
	icon = 'icons/obj/structures_vr.dmi'
	icon_state = "window-full"
	opacity = 0

/turf/simulated/wall/glass/Initialize(mapload)
	. = ..(mapload, MAT_GLASS)

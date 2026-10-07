/datum/sun_holder
	var/atom/movable/sun_visuals/sun
	var/tmp/datum/planet/our_planet_static

	var/our_color = "#FFFFFF"
	var/our_brightness = 1.0

CAPABILITIES(/datum/sun_holder)
	owns_one(nameof(sun), /atom/movable/sun_visuals)

/// world.time the running rainbow() ends; rainbow_step() runs every 0.3 s while set (the every() below).
OM_FIELD_TYPED(/datum/sun_holder, tmp, rainbow_ends_at, 0, CHANGE_DATUM_A)

/datum/sun_holder/reactions()
	. = ..()
	. += every(0.3 SECONDS, PROC_REF(rainbow_step), when = nameof(rainbow_ends_at))

/// The running rainbow's next colour, and the light to restore when it ends.
/datum/sun_holder/var/tmp/rainbow_index = 1
/datum/sun_holder/var/tmp/rainbow_original_brightness
/datum/sun_holder/var/tmp/rainbow_original_color

/datum/sun_holder/New(source)
	..()
	lifecycle_decls_init(src) // starts the declaration (a non-atom has no materialize)
	rel_set(src, nameof(sun), new /atom/movable/sun_visuals(null))
	our_planet_static = source

/datum/sun_holder/proc/update_color(new_color)
	// Doesn't save much work, but might save a smidge of client work
	if(our_color == new_color)
		return

	// Visible change
	our_color = new_color
	sun.set_color(new_color)

/datum/sun_holder/proc/update_brightness(new_brightness, list/turfs)
	// Doesn't save much work, but might save a smidge of client work
	if(our_brightness == new_brightness)
		return

	// Store the old for math
	. = our_brightness
	our_brightness = new_brightness

	// Visible change
	sun.set_alpha(round(CLAMP01(our_brightness)*255,1))

	// Update dynamic lumcount so darksight and stuff works
	var/difference = . - our_brightness
	for(var/turf/T as anything in turfs)
		T.dynamic_lumcount -= difference

/datum/sun_holder/proc/apply_to_turf(turf/T)
	if(sun in T.vis_contents)
		WARNING("Was asked to add fake sun to [T.x], [T.y], [T.z] despite already having us in it's vis contents")
		return
	sun.apply_to_turf(T)

/datum/sun_holder/proc/remove_from_turf(turf/T)
	if(!(sun in T.vis_contents))
		// warning("Was asked to remove fake sun from [T.x], [T.y], [T.z] despite it not having us in it's vis contents") // Disable the warning
		return
	sun.remove_from_turf(T)

/datum/sun_holder/proc/rainbow()
	if(!rainbow_ends_at)
		rainbow_original_brightness = sun.alpha/255
		rainbow_original_color = sun.color
		rainbow_index = 1
	update_brightness(0.8)
	set_rainbow_ends_at(world.time + 30 SECONDS)

/// One colour of the rainbow every 0.3 s until `rainbow_ends_at`, then the original light.
/datum/sun_holder/proc/rainbow_step(dt)
	var/static/list/colors = list("#ff5d5d","#ffd17b","#ffff5e","#7eff7e","#6868ff","#b753ff","#d08fff","#ffffff")
	if(!BEFORE(src, rainbow_ends_at, CLOCK_WORLD))
		set_rainbow_ends_at(0)
		update_brightness(rainbow_original_brightness)
		update_color(rainbow_original_color)
		return
	update_color(colors[rainbow_index])
	if(++rainbow_index > colors.len)
		rainbow_index = 1

// Holds a full white icon that can be mutated to make sun on the O_LIGHTING plane
/atom/movable/sun_visuals
	icon = 'icons/effects/effects.dmi'
	icon_state = "white"
	plane = PLANE_O_LIGHTING_VISUAL
	mouse_opacity = 0
	alpha = 0
	color = "#FFFFFF"

	var/turfs_providing_spreads
	var/spreads

/atom/movable/sun_visuals/Initialize(mapload)
	. = ..()
	LAZYINITLIST(spreads)
	spreads["1"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = NORTH, icon_state = "white_gradient")
	spreads["2"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = SOUTH, icon_state = "white_gradient")
	spreads["4"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = EAST, icon_state = "white_gradient")
	spreads["8"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = WEST, icon_state = "white_gradient")

	spreads["i5"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = NORTHEAST, icon_state = "white_inner")
	spreads["i6"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = SOUTHEAST, icon_state = "white_inner")
	spreads["i9"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = NORTHWEST, icon_state = "white_inner")
	spreads["i10"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = SOUTHWEST, icon_state = "white_inner")

	spreads["o5"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = NORTHEAST, icon_state = "white_outer")
	spreads["o6"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = SOUTHEAST, icon_state = "white_outer")
	spreads["o9"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = NORTHWEST, icon_state = "white_outer")
	spreads["o10"] = make(/atom/movable/sun_visuals_overlap, at = src, dir = SOUTHWEST, icon_state = "white_outer")

/atom/movable/sun_visuals/proc/set_color(new_color)
	src.color = new_color
	for(var/key in spreads)
		var/atom/movable/sun_visuals_overlap/SVO = spreads[key]
		SVO.color = new_color

/atom/movable/sun_visuals/proc/set_alpha(new_alpha)
	src.alpha = new_alpha
	for(var/key in spreads)
		var/atom/movable/sun_visuals_overlap/SVO = spreads[key]
		SVO.alpha = new_alpha

/atom/movable/sun_visuals/proc/apply_to_turf(turf/T)
	T.vis_contents += src
	T.dynamic_lumcount += 0.5
	T.set_luminosity(1, TRUE)

	var/list/localspreads
	// Test for corners
	for(var/direction in GLOB.cornerdirs)
		var/turf/dirturf = get_step(T, direction)
		if(dirturf && !dirturf.is_outdoors())
			var/turf/TL = get_step(T, turn(direction, -45))
			var/turf/TR = get_step(T, turn(direction, 45))

			// If outdoors at 45 degrees are the same, then this is a corner
			if(TL && TR && TL.is_outdoors() == TR.is_outdoors())
				var/atom/movable/sun_visuals_overlap/OL
				// Outer corner
				if(TL.is_outdoors())
					OL = spreads["o[direction]"]
				// Inner corner
				else
					OL = spreads["i[direction]"]
				dirturf.vis_contents += OL
				dirturf.set_luminosity(1)
				dirturf.outdoors_adjacent = TRUE
				LAZYINITLIST(localspreads)
				LAZYINITLIST(localspreads[dirturf])
				LAZYADD(localspreads[dirturf], OL)

	// Take all orthagonals
	for(var/direction in GLOB.cardinal)
		var/turf/dirturf = get_step(T, direction)
		if(dirturf && !dirturf.is_outdoors())
			var/turf/TL = get_step(T, turn(direction, -45))
			var/turf/TR = get_step(T, turn(direction, 45))
			// End of a wall, the corner will handle it
			if(TL && TR && TL.is_outdoors() != TR.is_outdoors())
				continue
			var/atom/movable/sun_visuals_overlap/OL = spreads["[direction]"]
			dirturf.vis_contents += OL
			dirturf.set_luminosity(1)
			dirturf.outdoors_adjacent = TRUE
			LAZYINITLIST(localspreads)
			LAZYINITLIST(localspreads[dirturf])
			LAZYADD(localspreads[dirturf], OL)

	if(LAZYLEN(localspreads))
		LAZYSET(turfs_providing_spreads, T, localspreads)

/atom/movable/sun_visuals/proc/remove_from_turf(turf/T)
	T.vis_contents -= src
	T.dynamic_lumcount -= 0.5
	T.set_luminosity(0, TRUE)
	var/list/applied = LAZYACCESS(turfs_providing_spreads, T)
	if(LAZYLEN(applied))
		for(var/turf/old as anything in applied)
			old.vis_contents -= applied[old]
			var/old_lit = FALSE
			for(var/direction in GLOB.alldirs)
				var/turf/CT = get_step(old, direction)
				if(CT && CT.is_outdoors())
					old_lit = TRUE
				if(!old_lit)
					old.outdoors_adjacent = TRUE
					old.set_luminosity(0)
			applied -= old
		LAZYREMOVE(turfs_providing_spreads, T)
		applied.Cut()

/atom/movable/sun_visuals_overlap
	icon = 'icons/effects/effects.dmi'
	icon_state = null
	plane = PLANE_O_LIGHTING_VISUAL
	mouse_opacity = 0
	alpha = 0
	color = "#FFFFFF"

CAPABILITIES(/atom/movable/sun_visuals_overlap)
	param(nameof(dir), pos = 1)
	param(nameof(icon_state), pos = 2)

/// Accessor for a shared definition.
/datum/sun_holder/proc/our_planet() as /datum/planet
	return our_planet_static

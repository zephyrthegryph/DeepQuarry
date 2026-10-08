
/obj/vehicle/train/engine/quadbike //It's a train engine, so it can tow trailers.
	name = "electric all terrain vehicle"
	desc = "A ridable electric ATV designed for all terrain. Except space."
	icon = 'icons/obj/vehicles_64x64.dmi'
	icon_state = "quad"
	on = 0
	powered = 1
	locked = 0

	load_item_visible = 1
	load_offset_x = 0
	mob_offset_y = 5

	pixel_x = -16
	speed_mod = 0.45
	car_limit = 1	//It gets a trailer. That's about it.
	active_engines = 1
	key_type = /obj/item/key/quadbike

	var/frame_state = "quad" //Custom-item proofing!
	var/paint_base = 'icons/obj/vehicles_64x64.dmi'
	var/custom_frame = FALSE
	//var/datum/looping_sound/vehicle_engine/soundloop //Chomp REMOVE

	paint_color = "#ffffff"

	var/outdoors_speed_mod = 0.7 //The general 'outdoors' speed. I.E., the general difference you'll be at when driving outside.

/obj/vehicle/train/engine/quadbike/ownership()
	. = ..()
	. += owns(nameof(key), policy = OWN_CONTAINED, starts = nameof(key_type))

CAPABILITIES(/obj/vehicle/train/engine/quadbike)
	param(nameof(built_from_assembly), pos = 1)
	op("vehicle_paint", tool(TOOL_MULTITOOL), when(req_is(nameof(open), TRUE)), priority(OP_PRIORITY_DEFAULT - 1), label("Paint"), wait(0), asks(/datum/prompt/color/vehicle_paint, fields = list("default" = nameof(paint_color)), step = "colour"), then(PROC_REF(vehicle_paint_picked)))

/// Whether the bike was built from an assembly (its constructor param): it then brings no cell of its own.
/obj/vehicle/train/engine/quadbike/var/built_from_assembly = FALSE

// ALLOW(init/INSTANCE_STATE): a quad bike not built from an assembly comes with a cell and an engine sound, and starts switched off
/obj/vehicle/train/engine/quadbike/Initialize(mapload)
	. = ..()
	if(!built_from_assembly)
		rel_set(src, nameof(cell), new /obj/item/cell/high(src))
		rel_set(src, nameof(soundloop), new /datum/looping_sound/idle_carengine(list(src), FALSE))
	turn_off()

/obj/vehicle/train/engine/quadbike/built
	built_from_assembly = TRUE

CAPABILITIES(/obj/vehicle/train/engine/quadbike/random)
	rolls(nameof(paint_color), PROC_REF(roll_paint_color))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/vehicle/train/engine/quadbike/random/proc/roll_paint_color(datum/roller/R)
	return rgb(R.number(1, 255),R.number(1, 255),R.number(1, 255))

/obj/item/key/quadbike
	name = "key"
	desc = "A keyring with a small steel key, and a blue fob reading \"ZOOM!\"."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "quad_keys"
	w_class = ITEMSIZE_TINY

/obj/vehicle/train/engine/quadbike/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..() //Move it move it, so we can test it test it.
	get_turf_speeds(old_loc)
	handle_vehicle_icon()

/obj/vehicle/train/engine/quadbike/proc/get_turf_speeds(atom/prev_loc)
	// Same speed if turf type doesn't change
	if(istype(loc, prev_loc.type) || istype(prev_loc, loc.type))
		return
	if(istype(loc, /turf/simulated/floor/water))
		speed_mod = outdoors_speed_mod * 4 //It kind of floats due to its tires, but it is slow.
	else if(istype(loc, /turf/simulated/floor/outdoors/rocks))
		speed_mod = initial(speed_mod) //Rocks are good, rocks are solid.
	else if(istype(loc, /turf/simulated/floor/outdoors/dirt) || istype(loc, /turf/simulated/floor/outdoors/grass) || istype(loc, /turf/simulated/floor/outdoors/newdirt) || istype(loc, /turf/simulated/floor/outdoors/newdirt_nograss))
		speed_mod = outdoors_speed_mod //Dirt and grass are the outdoors bench mark.
	else if(istype(loc, /turf/simulated/floor/outdoors/mud))
		speed_mod = outdoors_speed_mod * 1.5 //Gets us roughly 1. Mud may be fun, but it's not the best.
	else if(istype(loc, /turf/simulated/floor/outdoors/snow))
		speed_mod = outdoors_speed_mod * 1.7 //Roughly a 1.25. Snow is coarse and wet and gets everywhere, especially your electric motors.
	else
		speed_mod = initial(speed_mod)
	update_car(train_length, active_engines)

/obj/vehicle/train/engine/quadbike/proc/handle_vehicle_icon()
	switch(dir) //Due to being a Big Boy sprite, it has to have special pixel shifting to look 'normal' when being driven.
		if(1)
			pixel_y = -6
		if(2)
			pixel_y = -6
		if(4)
			pixel_y = 0
		if(8)
			pixel_y = 0

/obj/vehicle/train/engine/quadbike/draw(datum/look/look)
	..()
	var/paint_icon = custom_frame ? 'icons/obj/custom_items_vehicle.dmi' : paint_base
	look.overlay(look_overlay_image(paint_icon, "[frame_state]_a", layer = layer, color = paint_color))
	look.overlay(look_overlay_image(paint_icon, "[frame_state]_overlay", layer = layer + 0.2, plane = MOB_PLANE))
	look.overlay(look_overlay_image(paint_icon, "[frame_state]_overlay_a", layer = layer + 0.2, plane = MOB_PLANE, color = paint_color))

/obj/vehicle/train/engine/quadbike/Bump(atom/Obstacle)
	if(!istype(Obstacle, /atom/movable))
		return
	var/atom/movable/A = Obstacle

	if(!A.anchored)
		var/turf/T = get_step(A, dir)
		if(isturf(T))
			A.Move(T)	//bump things away when hit

	if(isliving(A))
		var/mob/living/M = A
		visible_message(span_danger("[src] knocks over [M]!"))
		M.apply_effects(2, 2)				// Knock people down for a short moment
		M.injure(INJURY_BLUNT, 8 / move_delay, null, src)		// Smaller amount of damage than a tug, since this will always be possible because Quads don't have safeties.
		var/list/throw_dirs = list(1, 2, 4, 8, 5, 6, 9, 10)
		if(!emagged)						// By the power of Bumpers TM, it won't throw them ahead of the quad's path unless it's emagged or the person turns.
			take_damage(round(M.mob_size / 2), BRUTE)
			throw_dirs -= dir
			throw_dirs -= get_dir(M, src) //Don't throw it AT the quad either.
		else
			take_damage(round(M.mob_size / 4), BRUTE) // Less damage if they actually put the point in to emag it.
		var/turf/T2 = get_step(A, pick(throw_dirs))
		M.throw_at(T2, 1, 1, src)
		if(ishuman(load))
			var/mob/living/D = load
			to_chat(D, span_danger("You hit [M]!"))
			add_attack_logs(D,M,"Ran over with [src.name]")

/obj/vehicle/train/engine/quadbike/RunOver(mob/living/M)
	..()
	var/list/throw_dirs = list(1, 2, 4, 8, 5, 6, 9, 10)
	if(!emagged)
		throw_dirs -= dir
		if(tow())
			throw_dirs -= get_dir(M, tow()) //Don't throw it at the trailer either.
	var/turf/T = get_step(M, pick(throw_dirs))
	M.throw_at(T, 1, 1, src)

/obj/vehicle/train/engine/quadbike/turn_on()
	..()
	if(on)
		src.visible_message("\The [src] rumbles to life.", "You hear something rumble deeply.")
		soundloop.start()

/obj/vehicle/train/engine/quadbike/turn_off()
	if(on)
		src.visible_message("\The [src] putters before turning off.", "You hear something putter slowly.")
		soundloop.stop()
	..()

/*
 * Trailer bits and bobs.
 */

/obj/vehicle/train/trolley/trailer
	name = "all terrain trailer"
	icon = 'icons/obj/vehicles_64x64.dmi'
	icon_state = "quadtrailer"
	anchored = FALSE
	passenger_allowed = 1
	buckle_lying = 1
	locked = 0

	load_item_visible = 1
	load_offset_x = 0
	load_offset_y = 13
	mob_offset_y = 16

	pixel_x = -16

	paint_color = "#ffffff"

CAPABILITIES(/obj/vehicle/train/trolley/trailer/random)
	rolls(nameof(paint_color), PROC_REF(roll_paint_color))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/vehicle/train/trolley/trailer/random/proc/roll_paint_color(datum/roller/R)
	return rgb(R.number(1, 255),R.number(1, 255),R.number(1, 255))

/obj/vehicle/train/trolley/trailer/proc/update_load()
	if(load)
		var/y_offset = load_offset_y
		if(isliving(load))
			y_offset = mob_offset_y
		load.pixel_x = (initial(load.pixel_x) + 16 + load_offset_x + pixel_x) //Base location for the sprite, plus 16 to center it on the 'base' sprite of the trailer, plus the x shift of the trailer, then shift it by the same pixel_x as the trailer to track it.
		load.pixel_y = (initial(load.pixel_y) + y_offset + pixel_y) //Same as the above.
		return 1
	return 0

/obj/vehicle/train/trolley/trailer/Initialize(mapload)
	. = ..()

/obj/vehicle/train/trolley/trailer/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(lead())
		switch(dir) //Due to being a Big Boy sprite, it has to have special pixel shifting to look 'normal'.
			if(1)
				pixel_y = -10
				pixel_x = -16
			if(2)
				pixel_y = 0
				pixel_x = -16
			if(4)
				pixel_y = 0
				pixel_x = -25
			if(8)
				pixel_y = 0
				pixel_x = -5
	else
		pixel_x = initial(pixel_x)
		pixel_y = initial(pixel_y)
	update_load()

/obj/vehicle/train/trolley/trailer/Bump(atom/Obstacle)
	if(!istype(Obstacle, /atom/movable))
		return
	var/atom/movable/A = Obstacle

	if(!A.anchored)
		var/turf/T = get_step(A, dir)
		if(isturf(T))
			A.Move(T)	//bump things away when hit

	if(isliving(A))
		var/mob/living/M = A
		visible_message(span_danger("[src] knocks over [M]!"))
		M.apply_effects(1, 1)
		M.injure(INJURY_BLUNT, 8 / move_delay, null, src)
		if(load)
			M.injure(INJURY_BLUNT, 4 / move_delay, null, src)
		var/list/throw_dirs = list(1, 2, 4, 8, 5, 6, 9, 10)
		if(!emagged)
			throw_dirs -= dir
		var/turf/T2 = get_step(A, pick(throw_dirs))
		M.throw_at(T2, 1, 1, src)
		if(ishuman(load))
			var/mob/living/D = load
			to_chat(D, span_danger("You hit [M]!"))
			add_attack_logs(D,M,"Ran over with [src.name]")

/obj/vehicle/train/trolley/trailer/draw(datum/look/look)
	..()

	look.overlay(look_overlay_image('icons/obj/vehicles_64x64.dmi', "[initial(icon_state)]_a", layer = layer, color = paint_color))

CAPABILITIES(/obj/vehicle/train/trolley/trailer)
	op("vehicle_paint", tool(TOOL_MULTITOOL), when(req_is(nameof(open), TRUE)), priority(OP_PRIORITY_DEFAULT - 1), label("Paint"), wait(0), asks(/datum/prompt/color/vehicle_paint, fields = list("default" = nameof(paint_color)), step = "colour"), then(PROC_REF(vehicle_paint_picked)))

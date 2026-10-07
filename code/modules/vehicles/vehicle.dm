//Dummy object for holding items in vehicles.
//Prevents items from being interacted with.
/datum/vehicle_dummy_load
	var/name = "dummy load"
	var/actual_load

/obj/vehicle
	name = "vehicle"
	icon = 'icons/obj/vehicles.dmi'
	layer = MOB_LAYER + 0.1 //so it sits above objects including mobs
	density = TRUE
	anchored = TRUE
	animate_movement=1
	light_range = 3

	can_buckle = TRUE
	buckle_movable = 1
	buckle_lying = 0

	var/mechanical = TRUE // If false, doesn't care for things like cells, engines, EMP, keys, etc.
	var/attack_log = null
	var/on = 0
	max_integrity = 100	//do not forget to set max_integrity for your vehicle!
	var/fire_dam_coeff = 1.0
	var/brute_dam_coeff = 1.0
	var/open = 0	//Maint panel
	var/locked = 1
	var/emagged = 0
	var/powered = 0		//set if vehicle is powered and should use fuel when moving
	var/move_delay = 1	//set this to limit the speed of the vehicle
	/// Blocks the next flat move until move_delay after the last move (inclusive: moving is allowed on the tick it ends).
	COOLDOWN_DECLARE(move_cooldown)

	var/obj/item/cell/cell
	var/charge_use = 5	//set this to adjust the amount of power the vehicle uses per move

	var/paint_color = "#666666" //For vehicles with special paint overlays.

	var/atom/movable/load		//all vehicles can take a load, since they should all be a least drivable
	var/load_item_visible = 1	//set if the loaded item should be overlayed on the vehicle sprite
	var/load_offset_x = 0		//pixel_x offset for item overlay
	var/load_offset_y = 0		//pixel_y offset for item overlay
	var/mob_offset_y = 0		//pixel_y offset for mob overlay

	var/datum/looping_sound/idle_carengine/soundloop // Looping engine audio.

	/// Whether it was running when the EMP took it down (it restarts when the outage lapses).
	var/emp_was_on = FALSE

/// A vehicle runs unless a pulse knocked its engine out (emp_disable() holds it down).
STAT(/obj/vehicle, operable, ALL, virtual = TRUE)

CAPABILITIES(/obj/vehicle)
	owns_one(nameof(soundloop), /datum/looping_sound/idle_carengine)
	op("vehicle_item", item(/obj/item), then(PROC_REF(interaction_vehicle_item)))
	emp_disable(PROC_REF(emp_outage))
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(emp_state_changed)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

//-------------------------------------------
// Standard procs
//-------------------------------------------
/obj/vehicle/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(soundloop), new /datum/looping_sound/idle_carengine(list(src), FALSE))

///obj/vehicle/New()
//	..()
// //spawn the cell you want in each vehicle // Commented out in favour of initialize.


//BUCKLE HOOKS

/obj/vehicle/buckle_mob(mob/living/M, forced = FALSE, check_loc = TRUE)
	. = ..()
	M.update_water()
	if(riding_datum)
		rel_set(riding_datum, nameof(riding_datum.ridden), src)
		riding_datum.handle_vehicle_offsets()

/obj/vehicle/unbuckle_mob(mob/living/buckled_mob, force = FALSE)
	. = ..(buckled_mob, force)
	buckled_mob?.update_water()
	if(riding_datum)
		riding_datum.restore_position(buckled_mob)
		riding_datum.handle_vehicle_offsets() // So the person in back goes to the front.

/obj/vehicle/Move(atom/newloc, direct = 0, movetime)
	var/turf/newturf = newloc
	var/zmove = (newturf && z != newturf.z)

	if(!zmove && COOLDOWN_TIMELEFT(src, move_cooldown) > 0) //This AND the riding datum move speed limit?
		return FALSE

	if(!zmove && mechanical && on && powered && cell.charge < charge_use)
		turn_off()
		return FALSE

	. = ..()
	if(.)
		COOLDOWN_START(src, move_cooldown, move_delay)

	if(!zmove && mechanical && on && powered)
		cell.use(charge_use)

	//Dummy loads do not have to be moved as they are just an overlay
	//See load_object() proc in cargo_trains.dm for an example
	//Also mobs are BUCKLED(src) to the vehicle and get moved in atom/movable/Move's call to take care of that
	if(load && !(load in src?.buckled_mob_list()) && !istype(load, /datum/vehicle_dummy_load))
		load.forceMove(loc)

/// Old attackby: mechanical vehicles take cells (and swallow every other item); others take weapon hits.
/obj/vehicle/proc/interaction_vehicle_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/hand_labeler))
		return TRUE
	if(mechanical)
		if(istype(W, /obj/item/cell) && !cell && open)
			insert_cell(W, user)
		return TRUE
	if(W.force && W.obj_damage_type())
		user.setClickCooldown(user.get_attack_speed(W))
		switch(W.obj_damage_type())
			if(BURN)
				receive_weapon_hit(W, user, W.force * fire_dam_coeff, INJURY_BURN, silent = FALSE)
			if(BRUTE)
				receive_weapon_hit(W, user, W.force * brute_dam_coeff, silent = FALSE)
		return OP_PASS
	return OP_DECLINE

/obj/vehicle/screwdriver_act(mob/user, obj/item/tool)
	if(!mechanical)
		return ..()
	if(locked)
		return ITEM_INTERACT_BLOCKING
	open = !open
	update_icon()
	to_chat(user, span_notice("Maintenance panel is now [open ? "opened" : "closed"]."))
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/vehicle/crowbar_act(mob/user, obj/item/tool)
	if(!mechanical)
		return ..()
	if(!cell || !open)
		return ITEM_INTERACT_BLOCKING
	remove_cell(user)
	return ITEM_INTERACT_SUCCESS

/obj/vehicle/welder_act(mob/user, obj/item/tool)
	if(!mechanical)
		return ..()
	if(!open || get_integrity() >= max_integrity)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder?.remove_fuel(0, user))
		return ITEM_INTERACT_BLOCKING
	repair_damage(10)
	user.setClickCooldown(user.get_attack_speed(tool))
	playsound(src, welder.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF(span_blue("You repair %T%!")), MSG_OTHERS(span_red("%U% repairs %T%!")))
	return ITEM_INTERACT_SUCCESS

/obj/vehicle/proc/adjust_health(amount)
	if(amount < 0)
		take_damage(-amount, BRUTE, MELEE)
	else
		repair_damage(amount)

/// emp_disable()'s outage: 30 s over the severity, for a mechanical vehicle only.
/obj/vehicle/proc/emp_outage(severity)
	return mechanical ? 30 SECONDS / max(severity, 1) : 0

/// Down: sparks and the engine dies. Back: it restarts if it was running.
/obj/vehicle/proc/emp_state_changed(datum/act/A)
	if(!emp_disabled(src))
		stat_remove(EMPED)
		if(emp_was_on)
			turn_on()
		emp_was_on = FALSE
		return
	emp_was_on = on
	stat_add(EMPED)
	var/obj/effect/overlay/pulse2 = new /obj/effect/overlay(src.loc)
	pulse2.icon = 'icons/effects/effects.dmi'
	pulse2.icon_state = "empdisable"
	pulse2.name = "emp sparks"
	pulse2.set_anchored(TRUE)
	pulse2.set_dir(pick(GLOB.cardinal))

	pulse2.expire(1 SECOND)
	if(on)
		turn_off()

// For downstream compatibility (in particular Paradise)
/obj/vehicle/proc/handle_rotation()
	return

//-------------------------------------------
// Vehicle procs
//-------------------------------------------
/obj/vehicle/proc/turn_on()
	if(!mechanical || has_stat(MACHINE_STAT_ANY))
		return FALSE
	if(!cell)
		return FALSE
	if(powered && cell.charge < charge_use)
		return FALSE
	if(on)
		return FALSE
	on = 1
	play_sfx(src, SFX_EFFECTS_VEHICLE_IGNITION_CAR) // New sound effects.
	soundloop.start()
	set_light(initial(light_range))
	update_icon()
	return TRUE

/obj/vehicle/proc/turn_off()
	if(!on)
		return FALSE
	if(!mechanical)
		return FALSE
	on = 0
	play_sfx(src, SFX_EFFECTS_VEHICLE_ENGINE_OFF) // New sound effects.
	soundloop.stop()
	set_light(0)
	update_icon()

/obj/vehicle/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!mechanical)
		return OP_DECLINE

	if(!emagged)
		emagged = 1
		if(locked)
			locked = 0
			to_chat(user, span_warning("You bypass [src]'s controls."))
		return OP_OK
	return OP_DECLINE

/obj/vehicle/proc/explode()
	src.visible_message(span_bolddanger("[src] blows apart!"), 1)
	play_sfx(src, SFX_EFFECTS_EXPLOSIONS_VEHICLEEXPLOSION) // New sound effects.
	var/turf/Tsec = get_turf(src)

	//stuns people who are thrown off a train that has been blown up
	if(isliving(load))
		var/mob/living/M = load
		M.apply_effects(5, 5)

	unload()

	if(mechanical)
		new /obj/item/stack/rods(Tsec)
		new /obj/item/stack/rods(Tsec)
		new /obj/item/stack/cable_coil/cut(Tsec)
		gibs(Tsec, null, /obj/effect/gibspawner/robot)
		new /obj/effect/decal/cleanable/blood/oil(src.loc)

		if(cell)
			cell.forceMove(Tsec)
			cell.update_icon()
			rel_take(src, nameof(cell))

	destroyed(src, null, "explosion")

/obj/vehicle/atom_destruction(damage_flag)
	. = ..()
	explode()

/obj/vehicle/proc/powercheck()
	if(!mechanical)
		return

	if(!cell && !powered)
		return

	if(!cell && powered)
		turn_off()
		return

	if(cell.charge < charge_use)
		turn_off()
		return

	if(cell && powered)
		turn_on()
		return

/obj/vehicle/proc/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	if(!mechanical)
		return
	if(cell)
		return
	if(!istype(C))
		return

	if(!move_into(src, nameof(src.cell), C, H))
		return
	powercheck()
	to_chat(H, span_notice("You install [C] in [src]."))

/obj/vehicle/proc/remove_cell(mob/living/carbon/human/H)
	if(!mechanical)
		return
	if(!cell)
		return

	to_chat(H, span_notice("You remove [cell] from [src]."))
	cell.forceMove(get_turf(H))
	H.put_in_hands(cell)
	rel_take(src, nameof(cell))
	powercheck()

/obj/vehicle/proc/RunOver(mob/living/M)
	return		//write specifics for different vehicles

//-------------------------------------------
// Loading/unloading procs
//
// Set specific item restriction checks in
// the vehicle load() definition before
// calling this parent proc.
//-------------------------------------------
/obj/vehicle/proc/load(atom/movable/C, mob/living/user)
	//This loads objects onto the vehicle so they can still be interacted with.
	//Define allowed items for loading in specific vehicle definitions.
	if(!isturf(C.loc)) //To prevent loading things from someone's inventory, which wouldn't get handled properly.
		return 0
	if(load || C.anchored)
		return 0

	// if a create/closet, close before loading
	var/obj/structure/closet/crate = C
	if(istype(crate))
		crate.close()

	C.forceMove(loc)
	C.set_dir(dir)
	C.set_anchored(TRUE)

	rel_set(src, nameof(load), C)

	if(load_item_visible)
		C.pixel_x += load_offset_x
		if(ismob(C))
			C.pixel_y += mob_offset_y
		else
			C.pixel_y += load_offset_y
		C.layer = layer + 0.1

	if(ismob(C) && user)
		user_buckle_mob(C, user)

	return 1

/obj/vehicle/proc/unload(mob/user, direction)
	if(!load)
		return

	var/turf/dest = null

	//find a turf to unload to
	if(direction)	//if direction specified, unload in that direction
		dest = get_step(src, direction)
	else if(user)	//if a user has unloaded the vehicle, unload at their feet
		dest = get_turf(user)

	if(!dest)
		dest = get_step_to(src, get_step(src, turn(dir, 90))) //try unloading to the side of the vehicle first if neither of the above are present

	//if these all result in the same turf as the vehicle or nullspace, pick a new turf with open space
	if(!dest || dest == get_turf(src))
		var/list/options = new()
		for(var/test_dir in GLOB.alldirs)
			var/new_dir = get_step_to(src, get_step(src, test_dir))
			if(new_dir && load.Adjacent(new_dir))
				options += new_dir
		if(options.len)
			dest = pick(options)
		else
			dest = get_turf(src)	//otherwise just dump it on the same turf as the vehicle

	if(!isturf(dest))	//if there still is nowhere to unload, cancel out since the vehicle is probably in nullspace
		return 0

	load.forceMove(dest)
	load.set_dir(get_dir(loc, dest))
	load.set_anchored(FALSE) //we can only load non-anchored items, so it makes sense to set this to false
	if(ismob(load))
		var/mob/L = load
		L.pixel_x = L.default_pixel_x
		L.pixel_y = L.default_pixel_y
	else
		load.pixel_x = initial(load.pixel_x)
		load.pixel_y = initial(load.pixel_y)
	load.layer = initial(load.layer)

	if(ismob(load))
		unbuckle_mob(load)

	rel_clear(src, nameof(load))

	return 1

//-------------------------------------------------------
// Stat update procs
//-------------------------------------------------------
/obj/vehicle/proc/update_stats()
	return

/obj/vehicle/attack_generic(mob/user, damage, attack_message)
	if(!damage)
		return
	act_message(user, src, others = span_danger("%U% [attack_message] %T%!"))
	add_attack_logs(user, src, "attacked")
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)
	return 1

// Thin override so any damage source leaks a little oil on mechanical vehicles.
/obj/vehicle/take_damage(damage_amount, damage_type = BRUTE, damage_flag = "", sound_effect = TRUE, attack_dir, armour_penetration = 0)
	. = ..()
	if(. && mechanical && prob(10))
		new /obj/effect/decal/cleanable/blood/oil(src.loc)

//----------------------------
// Engine sounds datum
//----------------------------

/datum/looping_sound/idle_carengine
	mid_sounds = 'sound/effects/vehicle/engine_loop.ogg'
	mid_length = 2.60 SECONDS
	chance = 100
	volume = 10
	exclusive = TRUE
	volume_chan = VOLUME_CHANNEL_AMBIENCE


/obj/vehicle/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED)

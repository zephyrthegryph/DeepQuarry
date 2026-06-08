// Contains the rapid construction device.
/obj/item/rcd
	name = "rapid construction device"
	desc = "A device used to rapidly build and deconstruct. Reload with compressed matter cartridges."
	icon = 'icons/obj/tools.dmi'
	icon_state = "rcd"
	item_state = "rcd"
	drop_sound = 'sound/items/drop/gun.ogg'
	pickup_sound = 'sound/items/pickup/gun.ogg'
	flags = NOBLUDGEON
	force = 10
	throwforce = 10
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	matter = list(DEFAULT_WALL_MATERIAL = 50000)
	preserve_item = TRUE // RCDs are pretty important.
	var/datum/effect/effect/system/spark_spread/spark_system
	var/stored_matter = 0
	var/max_stored_matter = RCD_MAX_CAPACITY
	var/ranged = FALSE
	var/busy = FALSE
	var/allow_concurrent_building = FALSE // If true, allows for multiple RCD builds at the same time.
	var/mode_index = 1
	var/list/modes = list(RCD_FLOORWALL, RCD_AIRLOCK, RCD_WINDOWGRILLE, RCD_DECONSTRUCT)
	var/can_remove_rwalls = FALSE
	var/airlock_type = /obj/machinery/door/airlock
	var/window_type = /obj/structure/window/reinforced/full
	var/material_to_use = DEFAULT_WALL_MATERIAL // So badmins can make RCDs that print diamond walls.
	var/make_rwalls = FALSE // If true, when building walls, they will be reinforced.
/* Unused
/obj/item/rcd/Initialize(mapload)

	src.spark_system = new /datum/effect/effect/system/spark_spread
	spark_system.set_up(5, 0, src)
	spark_system.attach(src)
	return ..()
*/
/obj/item/rcd/Destroy()
	QDEL_NULL(spark_system)
	spark_system = null
	return ..()

/obj/item/rcd/examine(mob/user)
	. = ..()
	. += display_resources()

// Used to show how much stuff (matter units, cell charge, etc) is left inside.
/obj/item/rcd/proc/display_resources()
	return "It currently holds [stored_matter]/[max_stored_matter] matter-units."

// Used to add new cartridges.
/* VOREStation Tweak - Wow this is annoying, moved to _vr file for overhaul
/obj/item/rcd/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/rcd_ammo))
		var/obj/item/rcd_ammo/cartridge = W
		if((stored_matter + cartridge.remaining) > max_stored_matter)
			to_chat(user, span_warning("The RCD can't hold that many additional matter-units."))
			return FALSE
		stored_matter += cartridge.remaining
		user.drop_from_inventory(W)
		qdel(W)
		playsound(src, 'sound/machines/click.ogg', 50, 1)
		to_chat(user, span_notice("The RCD now holds [stored_matter]/[max_stored_matter] matter-units."))
		return TRUE
	return ..()
*/
// Changes which mode it is on.
/*/obj/item/rcd/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	// Removal - Moved to VR
	if(mode_index >= modes.len) // Shouldn't overflow unless someone messes with it in VV poorly but better safe than sorry.
		mode_index = 1
	else
		mode_index++

	to_chat(user, span_notice("Changed mode to '[modes[mode_index]]'."))
	playsound(src, 'sound/effects/pop.ogg', 50, 0)

	if(prob(20))
		src.spark_system.start()
*/
// Removes resources if the RCD can afford it.
/obj/item/rcd/proc/consume_resources(amount)
	if(!can_afford(amount))
		return FALSE
	stored_matter -= amount
	return TRUE

// Useful for testing before actually paying (e.g. before a do_after() ).
/obj/item/rcd/proc/can_afford(amount)
	return stored_matter >= amount

/obj/item/rcd/afterattack(atom/A, mob/living/user, proximity)
	if(!ranged && !proximity)
		return FALSE
	use_rcd(A, user)

// Used to call rcd_act() on the atom hit.
/obj/item/rcd/proc/use_rcd(atom/A, mob/living/user)
	if(busy && !allow_concurrent_building)
		to_chat(user, span_warning("\The [src] is busy finishing its current operation, be patient."))
		return FALSE

	var/list/rcd_results = A.rcd_values(user, src, modes[mode_index])
	// start
	if(rcd_results == 1)
		return FALSE
	// end
	if(!rcd_results)
		to_chat(user, span_warning("\The [src] blinks a red light as you point it towards \the [A], indicating \
		that it won't work. Try changing the mode, or use it on something else."))
		return FALSE
	if(!can_afford(rcd_results[RCD_VALUE_COST]))
		to_chat(user, span_warning("\The [src] lacks the required material to start."))
		return FALSE

	playsound(src, 'sound/machines/click.ogg', 50, 1)

	var/true_delay = rcd_results[RCD_VALUE_DELAY] * toolspeed

	var/datum/beam/rcd_beam = null
	if(ranged)
		var/atom/movable/beam_origin = user // This is needed because mecha pilots are inside an object and the beam won't be made if it tries to attach to them..
		if(!isturf(beam_origin.loc))
			beam_origin = user.loc
		rcd_beam = beam_origin.Beam(A, icon_state = "rped_upgrade", time = max(true_delay, 5))
	busy = TRUE

	perform_effect(A, true_delay)
	if(do_after(user, true_delay, target = A))
		busy = FALSE
		// Doing another check in case we lost matter during the delay for whatever reason.
		if(!can_afford(rcd_results[RCD_VALUE_COST]))
			to_chat(user, span_warning("\The [src] lacks the required material to finish the operation."))
			return FALSE
		if(A.rcd_act(user, src, rcd_results[RCD_VALUE_MODE]))
			consume_resources(rcd_results[RCD_VALUE_COST])
			playsound(A, 'sound/items/deconstruct.ogg', 50, 1)
			return TRUE

	// If they moved, kill the beam immediately.
	qdel(rcd_beam)
	busy = FALSE
	return FALSE

// RCD variants.

// This one starts full.
/obj/item/rcd/loaded/Initialize(mapload)
	stored_matter = max_stored_matter
	return ..()

// This one makes cooler walls by using an alternative material.
/obj/item/rcd/shipwright
	name = "shipwright's rapid construction device"
	desc = "A device used to rapidly build and deconstruct. This version creates a stronger variant of wall, often \
	used in the construction of hulls for starships. Reload with compressed matter cartridges."
	material_to_use = MAT_STEELHULL

/obj/item/rcd/shipwright/loaded/Initialize(mapload)
	stored_matter = max_stored_matter
	return ..()


/obj/item/rcd/advanced
	name = "advanced rapid construction device"
	desc = "A device used to rapidly build and deconstruct. This version works at a range, builds faster, and has a much larger capacity. \
	Reload with compressed matter cartridges."
	icon_state = "adv_rcd"
	ranged = TRUE
	toolspeed = 0.5 // Twice as fast.
	max_stored_matter = RCD_MAX_CAPACITY * 3 // Three times capacity.

/obj/item/rcd/advanced/loaded/Initialize(mapload)
	stored_matter = max_stored_matter
	return ..()


// Electric RCDs.
// Currently just a base for the mounted RCDs.
// Currently there isn't a way to swap out the cells.
// One could be added if there is demand to do so.
/obj/item/rcd/electric
	name = "electric rapid construction device"
	desc = "A device used to rapidly build and deconstruct. It runs directly off of electricity, no matter cartridges needed."
	icon_state = "electric_rcd"
	var/obj/item/cell/cell = null
	var/make_cell = TRUE // If false, initialize() won't spawn a cell for this.
	var/electric_cost_coefficent = 83.33 // Higher numbers make it less efficent. 86.3... means it should matche the standard RCD capacity on a 10k cell.

/obj/item/rcd/electric/Initialize(mapload)
	if(make_cell)
		cell = new /obj/item/cell/high(src)
	return ..()

/obj/item/rcd/electric/Destroy()
	if(cell)
		QDEL_NULL(cell)
	return ..()

/obj/item/rcd/electric/get_cell()
	return cell

/obj/item/rcd/electric/can_afford(amount) // This makes it so borgs won't drain their last sliver of charge by mistake, as a bonus.
	var/obj/item/cell/cell = get_cell()
	if(cell)
		return cell.check_charge(amount * electric_cost_coefficent)
	return FALSE

/obj/item/rcd/electric/consume_resources(amount)
	if(!can_afford(amount))
		return FALSE
	var/obj/item/cell/cell = get_cell()
	return cell.checked_use(amount * electric_cost_coefficent)

/obj/item/rcd/electric/display_resources()
	var/obj/item/cell/cell = get_cell()
	if(cell)
		return "The power source connected to \the [src] has a charge of [cell.percent()]%."
	return "It lacks a source of power, and cannot function."



// 'Mounted' RCDs, used for borgs/RIGs/Mechas, all of which use their cells to drive the RCD.
/obj/item/rcd/electric/mounted
	name = "mounted electric rapid construction device"
	desc = "A device used to rapidly build and deconstruct. It runs directly off of electricity from an external power source."
	make_cell = FALSE

/obj/item/rcd/electric/mounted/get_cell()
	return get_external_power_supply()

/obj/item/rcd/electric/mounted/proc/get_external_power_supply()
	if(isrobot(loc)) // In a borg.
		var/mob/living/silicon/robot/R = loc
		return R.cell
	if(istype(loc, /obj/item/rig_module)) // In a RIG.
		var/obj/item/rig_module/module = loc
		if(module.holder) // Is it attached to a RIG?
			return module.holder.cell
	if(istype(loc, /obj/item/mecha_parts/mecha_equipment)) // In a mech.
		var/obj/item/mecha_parts/mecha_equipment/ME = loc
		if(ME.chassis) // Is the part attached to a mech?
			return ME.chassis.cell
	return null


// RCDs for borgs.
/obj/item/rcd/electric/mounted/borg
	can_remove_rwalls = TRUE
	desc = "A device used to rapidly build and deconstruct. It runs directly off of electricity, drawing directly from your cell."
	electric_cost_coefficent = 41.66 // Twice as efficent, out of pity.
	toolspeed = 0.5 // Twice as fast, since borg versions typically have this.

/obj/item/rcd/electric/mounted/borg/swarm
	can_remove_rwalls = FALSE
	name = "Rapid Assimilation Device"
	ranged = TRUE
	toolspeed = 0.7
	material_to_use = MAT_STEELHULL

/obj/item/rcd/electric/mounted/borg/lesser
	can_remove_rwalls = FALSE


// RCDs for RIGs.
/obj/item/rcd/electric/mounted/rig


// RCDs for Mechs.
/obj/item/rcd/electric/mounted/mecha
	ranged = TRUE
	toolspeed = 0.5


// Infinite use RCD for debugging/adminbuse.
/obj/item/rcd/debug
	name = "self-repleshing rapid construction device"
	desc = "An RCD that appears to be plated with gold. For some reason it also seems to just \
	be vastly superior to all other RCDs ever created, possibly due to it being colored gold."
	icon_state = "debug_rcd"
	ranged = TRUE
	can_remove_rwalls = TRUE
	allow_concurrent_building = TRUE
	toolspeed = 0.25 // Four times as fast.

/obj/item/rcd/debug/can_afford(amount)
	return TRUE

/obj/item/rcd/debug/consume_resources(amount)
	return TRUE

/obj/item/rcd/debug/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/rcd_ammo))
		to_chat(user, span_notice("\The [src] makes its own material, no need to add more."))
		return FALSE
	return ..()

/obj/item/rcd/debug/display_resources()
	return "It has UNLIMITED POWER!"



// Ammo for the (non-electric) RCDs.
/obj/item/rcd_ammo
	name = "compressed matter cartridge"
	desc = "Highly compressed matter for the RCD."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "rcd"
	item_state = "rcdammo"
	w_class = ITEMSIZE_SMALL
	matter = list(DEFAULT_WALL_MATERIAL = 30000,MAT_GLASS = 15000)
	var/remaining = RCD_MAX_CAPACITY / 0.75

/obj/item/rcd_ammo/large
	name = "high-capacity matter cartridge"
	desc = "Do not ingest."
	matter = list(DEFAULT_WALL_MATERIAL = 45000,MAT_GLASS = 22500)
	remaining = RCD_MAX_CAPACITY * 2


// === merged from RCD_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/rcd
	icon = 'icons/obj/tools_vr.dmi'
	icon_state = "rcd"
	item_state = "rcd"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
	)
	var/ammostate
	var/list/effects = list()

	var/static/image/radial_image_airlock = image(icon = 'icons/mob/radial.dmi', icon_state = "airlock")
	var/static/image/radial_image_decon = image(icon= 'icons/mob/radial.dmi', icon_state = "delete")
	var/static/image/radial_image_grillewind = image(icon = 'icons/mob/radial.dmi', icon_state = "grillewindow")
	var/static/image/radial_image_floorwall = image(icon = 'icons/mob/radial.dmi', icon_state = "wallfloor")

// Ammo for the (non-electric) RCDs.
/obj/item/rcd_ammo
	name = "compressed matter cartridge"
	desc = "Highly compressed matter for the RCD."
	icon = 'icons/obj/tools_vr.dmi'
	icon_state = "rcdammo"
	item_state = "rcdammo"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
	)

/obj/item/rcd/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/rcd/consume_resources(amount)
	. = ..()
	update_icon()

/obj/item/rcd/update_icon()
	var/nearest_ten = round((stored_matter/max_stored_matter)*10, 1)

	//Just to prevent updates every use
	if(ammostate == nearest_ten)
		return //No change
	ammostate = nearest_ten

	cut_overlays()

	//Main sprite update
	if(!nearest_ten)
		icon_state = "[initial(icon_state)]_empty"
	else
		icon_state = "[initial(icon_state)]"

	add_overlay("[initial(icon_state)]_charge[nearest_ten]")

/obj/item/rcd/proc/perform_effect(atom/A, time_taken)
	effects[A] = new /obj/effect/constructing_effect(get_turf(A), time_taken, modes[mode_index])

/obj/item/rcd/use_rcd(atom/A, mob/living/user)
	. = ..()
	cleanup_effect(A)

/obj/item/rcd/proc/cleanup_effect(atom/A)
	if(A in effects)
		qdel(effects[A])
		effects -= A

/* moved this block to modular_chomp\code\game\objects\items\weapons\rcd.dm
/obj/item/rcd/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/rcd_ammo))
		var/obj/item/rcd_ammo/cartridge = W
		var/can_store = min(max_stored_matter - stored_matter, cartridge.remaining)
		if(can_store <= 0)
			to_chat(user, span_warning("There's either no space or \the [cartridge] is empty!"))
			return FALSE
		stored_matter += can_store
		cartridge.remaining -= can_store
		if(!cartridge.remaining)
			to_chat(user, span_warning("\The [cartridge] dissolves as it empties of compressed matter."))
			user.drop_from_inventory(W)
			qdel(W)
		playsound(src, 'sound/machines/click.ogg', 50, 1)
		to_chat(user, span_notice("The RCD now holds [stored_matter]/[max_stored_matter] matter-units."))
		update_icon()
		return TRUE
	return ..()
*/

/obj/item/rcd/proc/check_menu(mob/living/user)
	if(!istype(user))
		return FALSE
	if(user.incapacitated() || !user.Adjacent(src))
		return FALSE
	return TRUE

// Mounted one is more complex
/obj/item/rcd/electric/mounted/rig/check_menu(mob/living/user)
	if(!istype(user))
		world.log << "One"
		return FALSE
	if(user.incapacitated())
		world.log << "Two"
		return FALSE

	var/obj/item/rig_module/device/D = loc
	if(!istype(D) || !D?.holder?.wearer == user)
		world.log << "Three"
		return FALSE

	return TRUE

/* moved this block to modular_chomp\code\game\objects\items\weapons\rcd.dm
/obj/item/rcd/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/choices = list(
		"Airlock" = radial_image_airlock,
		"Deconstruct" = radial_image_decon,
		"Grilles & Windows" = radial_image_grillewind,
		"Floors & Walls" = radial_image_floorwall
	)
	/* We don't have these features yet
	if(upgrade & RCD_UPGRADE_FRAMES)
		choices += list(
		"Machine Frames" = image(icon = 'icons/mob/radial.dmi', icon_state = "machine"),
		"Computer Frames" = image(icon = 'icons/mob/radial.dmi', icon_state = "computer_dir"),
		)
	if(upgrade & RCD_UPGRADE_SILO_LINK)
		choices += list(
		"Silo Link" = image(icon = 'icons/obj/mining.dmi', icon_state = "silo"),
		)
	if(mode == RCD_AIRLOCK)
		choices += list(
		"Change Access" = image(icon = 'icons/mob/radial.dmi', icon_state = "access"),
		"Change Airlock Type" = image(icon = 'icons/mob/radial.dmi', icon_state = "airlocktype")
		)
	else if(mode == RCD_WINDOWGRILLE)
		choices += list(
			"Change Window Type" = image(icon = 'icons/mob/radial.dmi', icon_state = "windowtype")
		)
	*/
	var/choice = show_radial_menu(user, user, choices, custom_check = CALLBACK(src, PROC_REF(check_menu), user), tooltips = TRUE)
	if(!check_menu(user))
		return
	switch(choice)
		if("Floors & Walls")
			mode_index = modes.Find(RCD_FLOORWALL)
		if("Airlock")
			mode_index = modes.Find(RCD_AIRLOCK)
		if("Deconstruct")
			mode_index = modes.Find(RCD_DECONSTRUCT)
		if("Grilles & Windows")
			mode_index = modes.Find(RCD_WINDOWGRILLE)
		/* We don't have these features yet
		if("Machine Frames")
			mode = RCD_MACHINE
		if("Computer Frames")
			mode = RCD_COMPUTER
			change_computer_dir(user)
			return
		if("Change Access")
			change_airlock_access(user)
			return
		if("Change Airlock Type")
			change_airlock_setting(user)
			return
		if("Change Window Type")
			toggle_window_type(user)
			return
		if("Silo Link")
			toggle_silo_link(user)
			return
		*/
		else
			return
	playsound(src, 'sound/effects/pop.ogg', 50, FALSE)
	to_chat(user, span_notice("You change RCD's mode to '[choice]'."))
*/

//////////////////
/obj/item/rcd/electric/update_icon()
	return

/obj/item/rcd/shipwright
	icon_state = "swrcd"
	item_state = "ircd"
	can_remove_rwalls = TRUE
	make_rwalls = TRUE

//////////////////
/obj/item/rcd_ammo/examine(mob/user)
	. = ..()
	. += display_resources()

// Used to show how much stuff (matter units, cell charge, etc) is left inside.
/obj/item/rcd_ammo/proc/display_resources()
	return "It currently holds [remaining]/[initial(remaining)] matter-units."

//////////////////
// start
/obj/effect/constructing_effect
	icon = 'icons/effects/effects_rcd.dmi'
	icon_state = ""
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/effect/constructing_effect/Initialize(mapload, rcd_delay, rcd_status)
	. = ..()
	update_icon(rcd_delay, rcd_status)

/obj/effect/constructing_effect/update_icon(delay = 30, status)
	icon_state = "rcd"
	if (delay < 10)
		icon_state += "_shortest"
	else if (delay < 20)
		icon_state += "_shorter"
	else if (delay < 37)
		icon_state += "_short"
	if (status == RCD_DECONSTRUCT)
		icon_state += "_reverse"
	addtimer(CALLBACK(src, PROC_REF(end_animation), status), delay)

/obj/effect/constructing_effect/proc/end_animation(status)
	if (status == RCD_DECONSTRUCT)
		icon_state = "rcd_end_reverse"
	else
		icon_state = "rcd_end"
	addtimer(CALLBACK(src, PROC_REF(end)), 15)

/obj/effect/constructing_effect/proc/end()
	qdel(src)
// end

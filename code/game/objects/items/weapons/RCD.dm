// Contains the rapid construction device.
/obj/item/rcd
	name = "rapid construction device"
	desc = "A device used to rapidly build and deconstruct. Reload with compressed matter cartridges."
	icon = 'icons/obj/tools.dmi'
	icon_state = "rcd"
	item_state = "rcd"
	drop_sound = SFX_ITEMS_DROP_GUN
	pickup_sound = SFX_ITEMS_PICKUP_GUN
	flags = NOBLUDGEON
	force = 10
	throwforce = 10
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 50000)
	preserve_item = TRUE // RCDs are pretty important.
	var/stored_matter = 0
	var/max_stored_matter = RCD_MAX_CAPACITY
	var/ranged = FALSE
	var/allow_concurrent_building = FALSE // If true, allows for multiple RCD builds at the same time.
	var/mode_index = 1
	var/can_remove_rwalls = FALSE
	var/airlock_type = /obj/machinery/door/airlock
	var/window_type = /obj/structure/window/reinforced/full
	var/material_to_use = DEFAULT_WALL_MATERIAL // So badmins can make RCDs that print diamond walls.
	var/make_rwalls = FALSE // If true, when building walls, they will be reinforced.

TYPE_TABLE_DECLARE(/obj/item/rcd, rcd_modes, list(RCD_FLOORWALL, RCD_AIRLOCK, RCD_WINDOWGRILLE, RCD_DECONSTRUCT, RCD_WINDOOR, RCD_FIRELOCK, RCD_FRAME, RCD_WALLFRAME, RCD_CONVEYOR, RCD_TURRET))

/obj/item/rcd/examine(mob/user)
	. = ..()
	. += display_resources()

// Used to show how much stuff (matter units, cell charge, etc) is left inside.
/obj/item/rcd/proc/display_resources()
	return "It currently holds [stored_matter]/[max_stored_matter] matter-units."

// Removes resources if the RCD can afford it.
/obj/item/rcd/proc/consume_resources(amount)
	if(!can_afford(amount))
		return FALSE
	stored_matter -= amount
	update_icon()
	return TRUE

// Useful for testing before actually paying (e.g. before a timed action).
/obj/item/rcd/proc/can_afford(amount)
	return stored_matter >= amount

/obj/item/rcd/proc/power_output_envelope(amount)
	return 1

/obj/item/rcd/proc/record_enhanced_output(amount, output_envelope)
	return

/obj/item/rcd/afterattack(atom/A, mob/living/user, proximity)
	if(!ranged && !proximity)
		return FALSE
	use_rcd(A, user)

// Used to call rcd_act() on the atom hit.
/obj/item/rcd/proc/use_rcd(atom/A, mob/living/user)
	if(!allow_concurrent_building && task_busy(src)) // an operation in progress claims the RCD
		to_chat(user, span_warning("\The [src] is busy finishing its current operation, be patient."))
		return FALSE

	var/list/rcd_results = A.rcd_values(user, src, TYPE_TABLE_GET(src, rcd_modes)[mode_index])
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

	play_sfx(src, SFX_MACHINES_CLICK)

	var/output_envelope = power_output_envelope(rcd_results[RCD_VALUE_COST])
	var/true_delay = rcd_results[RCD_VALUE_DELAY] * toolspeed / output_envelope

	var/datum/beam/rcd_beam = null
	if(ranged)
		var/atom/movable/beam_origin = user // This is needed because mecha pilots are inside an object and the beam won't be made if it tries to attach to them..
		if(!isturf(beam_origin.loc))
			beam_origin = user.loc
		rcd_beam = beam_origin.Beam(A, icon_state = "rped_upgrade", time = max(true_delay, 5))

	perform_effect(A, true_delay)
	var/started = task_start(/datum/task/timed/rcd_build, user, A, duration = true_delay, receiver = src, rcd_results = rcd_results, output_envelope = output_envelope, beam = rcd_beam, busy = (allow_concurrent_building ? null : src))
	if(istext(started))
		use_rcd_interrupted(A, rcd_beam)
	return FALSE

/// An RCD operation on the target: its beam shows while it runs.
/datum/task/timed/rcd_build
	complete_proc = /obj/item/rcd/proc/use_rcd_timed_done
	cancel_proc = /obj/item/rcd/proc/use_rcd_cancelled
	unheld = list("beam")
	var/list/rcd_results
	var/output_envelope
	/// Ends itself.
	var/datum/beam/beam

/obj/item/rcd/proc/use_rcd_cancelled(datum/task/timed/rcd_build/task)
	use_rcd_interrupted(task.target, task.beam)

/// The operation stopped (they moved, or it never started): kill the beam and the effect.
/obj/item/rcd/proc/use_rcd_interrupted(atom/A, datum/beam/rcd_beam)
	if(!QDELETED(rcd_beam))
		rcd_beam.End()
	if(A)
		cleanup_effect(A)

/obj/item/rcd/proc/use_rcd_timed_done(datum/task/timed/rcd_build/task)
	var/atom/A = task.target
	var/mob/living/user = task.actor
	var/list/rcd_results = task.rcd_results
	var/output_envelope = task.output_envelope
	var/datum/beam/rcd_beam = task.beam
	if(!QDELETED(rcd_beam))
		rcd_beam.End()
	// Doing another check in case we lost matter during the delay for whatever reason.
	if(!can_afford(rcd_results[RCD_VALUE_COST] * output_envelope))
		to_chat(user, span_warning("\The [src] lacks the required material to finish the operation."))
		cleanup_effect(A)
		return FALSE
	if(A.rcd_act(user, src, rcd_results[RCD_VALUE_MODE]))
		consume_resources(rcd_results[RCD_VALUE_COST] * output_envelope)
		record_enhanced_output(rcd_results[RCD_VALUE_COST], output_envelope)
		play_sfx(A, SFX_ITEMS_DECONSTRUCT)
		cleanup_effect(A)
		return TRUE

// RCD variants.

// This one starts full.
TYPE_TABLE(/obj/item/rcd/loaded, rcd_start_loaded, TRUE)

// This one makes cooler walls by using an alternative material.
/obj/item/rcd/shipwright
	name = "shipwright's rapid construction device"
	desc = "A device used to rapidly build and deconstruct. This version creates a stronger variant of wall, often \
	used in the construction of hulls for starships. Reload with compressed matter cartridges."
	material_to_use = MAT_STEELHULL

TYPE_TABLE(/obj/item/rcd/shipwright/loaded, rcd_start_loaded, TRUE)

/obj/item/rcd/advanced
	name = "advanced rapid construction device"
	desc = "A device used to rapidly build and deconstruct. This version works at a range, builds faster, and has a much larger capacity. \
	Reload with compressed matter cartridges."
	icon_state = "adv_rcd"
	ranged = TRUE
	toolspeed = 0.5 // Twice as fast.
	max_stored_matter = RCD_MAX_CAPACITY * 3 // Three times capacity.

TYPE_TABLE(/obj/item/rcd/advanced/loaded, rcd_start_loaded, TRUE)

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

CAPABILITIES(/obj/item/rcd/electric)
	owns_one(nameof(cell), /obj/item/cell)

/obj/item/rcd/electric/Initialize(mapload)
	if(make_cell)
		rel_set(src, nameof(cell), new /obj/item/cell/high(src)) // ALLOW(decl): the cell is made only when make_cell is set, which a declaration cannot condition
	return ..()


/obj/item/rcd/electric/get_cell()
	RETURN_TYPE(/obj/item/cell)
	return cell

/obj/item/rcd/electric/power_output_envelope(amount)
	var/obj/item/cell/power_cell = get_cell()
	return power_cell ? power_cell.material_output_envelope(amount * electric_cost_coefficent, 1.4) : 1

/obj/item/rcd/electric/record_enhanced_output(amount, output_envelope)
	get_cell()?.material_record_enhanced_output(amount * electric_cost_coefficent, output_envelope)

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

CAPABILITIES(/obj/item/rcd/debug)
	op("debug_rcd_refuse_ammo", item(/obj/item/rcd_ammo), label("Load"), then(PROC_REF(debug_rcd_refuse_ammo)))

/// Old attackby: refuses cartridges; anything else falls through to the RCD's loading.
/obj/item/rcd/debug/proc/debug_rcd_refuse_ammo(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("\The [src] makes its own material, no need to add more."))
	return OP_PASS

/obj/item/rcd/debug/display_resources()
	return "It has UNLIMITED POWER!"

MATERIAL_MIX(/obj/item/rcd_ammo, list(DEFAULT_WALL_MATERIAL = 30000,MAT_GLASS = 15000))
// Ammo for the (non-electric) RCDs.
/obj/item/rcd_ammo
	name = "compressed matter cartridge"
	desc = "Highly compressed matter for the RCD."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "rcd"
	item_state = "rcdammo"
	w_class = ITEMSIZE_SMALL
	var/remaining = RCD_MAX_CAPACITY / 0.75

MATERIAL_MIX(/obj/item/rcd_ammo/large, list(DEFAULT_WALL_MATERIAL = 45000,MAT_GLASS = 22500))
/obj/item/rcd_ammo/large
	name = "high-capacity matter cartridge"
	desc = "Do not ingest."
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
	var/list/effects

	var/static/image/radial_image_airlock = image(icon = 'icons/mob/radial.dmi', icon_state = "airlock")
	var/static/image/radial_image_decon = image(icon= 'icons/mob/radial.dmi', icon_state = "delete")
	var/static/image/radial_image_grillewind = image(icon = 'icons/mob/radial.dmi', icon_state = "grillewindow")
	var/static/image/radial_image_floorwall = image(icon = 'icons/mob/radial.dmi', icon_state = "wallfloor")

CAPABILITIES(/obj/item/rcd)
	emag(then(PROC_REF(on_emag)), powered = FALSE)
	owns_many(nameof(effects))
	op("rcd_item", item(/obj/item), label("Load"), then(PROC_REF(rcd_item)))
	op("rcd_self", in_hand(), label("Select mode"), then(PROC_REF(rcd_self)))

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

TYPE_TABLE_DECLARE(/obj/item/rcd, rcd_start_loaded, FALSE)

/obj/item/rcd/Initialize(mapload)
	if(TYPE_TABLE_GET(src, rcd_start_loaded))
		stored_matter = max_stored_matter
	. = ..()
	update_icon()

/// Stored matter as a percentage of capacity (the charge overlay level).
/obj/item/rcd/proc/appearance_matter_percent()
	return max_stored_matter ? (stored_matter / max_stored_matter) * 100 : 0

/obj/item/rcd/proc/appearance_matter_empty()
	return !round((stored_matter / max_stored_matter) * 10, 1)

APPEARANCE_TEMPLATE(/obj/item/rcd, "{initial(icon_state)}{appearance_matter_empty?_empty:}")
APPEARANCE_LEVEL(/obj/item/rcd, "appearance_matter_percent", 10, "{initial(icon_state)}_charge%d")

/obj/item/rcd/proc/perform_effect(atom/A, time_taken)
	rel_add(src, nameof(effects), new /obj/effect/constructing_effect(get_turf(A), time_taken, TYPE_TABLE_GET(src, rcd_modes)[mode_index]), A)

/obj/item/rcd/proc/cleanup_effect(atom/A)
	if(A in effects)
		rel_add(src, nameof(effects), null, A) // drops the key and disposes of (deletes) the owned effect

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
	if(!istype(D) || !D?.holder?.wearer() == user)
		world.log << "Three"
		return FALSE

	return TRUE

//////////////////
APPEARANCE_NONE(/obj/item/rcd/electric)

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

CAPABILITIES(/obj/effect/constructing_effect)
	param(nameof(rcd_delay), pos = 1)
	param(nameof(rcd_status), pos = 2, apply = PROC_REF(animate_build))

/// The build's delay and status (its constructor params).
/obj/effect/constructing_effect/var/rcd_delay
/obj/effect/constructing_effect/var/rcd_status

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/constructing_effect/proc/animate_build(status)
	start_animation(rcd_delay, status)

/// Plays the construction animation for `delay` (shorter states for faster work), then the end animation.
/obj/effect/constructing_effect/proc/start_animation(delay, status)
	icon_state = "rcd"
	if (delay < 1 SECOND)
		icon_state += "_shortest"
	else if (delay < 2 SECONDS)
		icon_state += "_shorter"
	else if (delay < 3.7 SECONDS)
		icon_state += "_short"
	if (status == RCD_DECONSTRUCT)
		icon_state += "_reverse"
	after(src, delay, PROC_REF(end_animation), with = list(status))

/obj/effect/constructing_effect/proc/end_animation(status)
	if (status == RCD_DECONSTRUCT)
		icon_state = "rcd_end_reverse"
	else
		icon_state = "rcd_end"
	after(src, 1.5 SECONDS, PROC_REF(end))

/obj/effect/constructing_effect/proc/end()
	consume(src)
// end

/// The index of `mode` in this RCD's modes, or 0 when it has no such mode.
/obj/item/rcd/proc/rcd_mode_index(mode)
	var/list/modes = TYPE_TABLE_GET(src, rcd_modes)
	return modes.Find(mode)

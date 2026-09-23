/obj/machinery/door
	name = "Door"
	desc = "It opens and closes."
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door1"
	anchored = TRUE
	opacity = 1
	density = TRUE
	can_atmos_pass = ATMOS_PASS_PROC
	layer = DOOR_OPEN_LAYER
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE
	var/open_layer = DOOR_OPEN_LAYER
	var/closed_layer = DOOR_CLOSED_LAYER

	var/visible = 1
	var/p_open = 0
	var/operating = 0
	var/autoclose = 0
	var/glass = 0
	var/normalspeed = 1
	var/heat_proof = FALSE // For glass airlocks/opacity firedoors
	var/air_properties_vary_with_direction = 0
	max_integrity = 300
	integrity_failure = 0.25
	var/min_force = 10 //minimum amount of force needed to damage the door with a melee weapon
	var/hitsound = 'sound/weapons/smash.ogg' //sound door makes when hit with a weapon
	//var/repairing = 0 //VOREstation Edit: We're not using materials anymore
	var/block_air_zones = 1 //If set, air zones cannot merge across the door even when it is opened.
	var/close_door_at = 0 //When to automatically close the door, if possible
	/// The REACT_AT token for next_door_deadline(), and the deadline it was set for.
	var/tmp/door_timer_token
	var/tmp/door_timer_at = 0
	var/list/autoclose_blockers

	var/anim_length_before_density = 0.3 SECONDS
	var/anim_length_before_finalize = 0.7 SECONDS

	//Multi-tile doors
	dir = EAST
	var/width = 1

	// turf animation
	var/atom/movable/overlay/c_animation = null

	var/reinforcing = 0
	var/tintable = 0
	var/icon_tinted
	var/id_tint

	var/update_adjacent_tiles = TRUE

/obj/machinery/door/attack_generic(mob/user, damage)
	if(isanimal(user))
		var/mob/living/simple_mob/S = user
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			visible_message(span_danger("\The [user] smashes into [src]!"))
			playsound(src, S.attack_sound, 75, 1)
			receive_generic_attack(user, damage)
		else
			visible_message(span_infoplain(span_bold("\The [user]") + " bonks \the [src] harmlessly."))
	user.do_attack_animation(src)

/obj/machinery/door/Initialize(mapload)
	. = ..()
	if(density)
		layer = closed_layer
		explosion_resistance = initial(explosion_resistance)
		update_heat_protection(get_turf(src))
	else
		layer = open_layer
		explosion_resistance = 0


	if(width > 1)
		if(dir in list(EAST, WEST))
			bound_width = width * world.icon_size
			bound_height = world.icon_size
		else
			bound_width = world.icon_size
			bound_height = width * world.icon_size

	update_icon()

	update_nearby_tiles(need_rebuild=1)

/obj/machinery/door/Destroy()
	clear_autoclose_blockers()
	density = FALSE
	update_nearby_tiles()
	. = ..()
	/*
	var/obj/effect/step_trigger/claymore_laser/las = locate() in loc
	if(las)
		las.Trigger(src)
	*/

// Door deadlines (autoclose here; power and electrification on airlocks) are one REACT_AT on
// the earliest of them (reactor.md §3), never a process() poll.

/// The earliest pending deadline (world.time), or 0 for none. Subtypes add theirs.
/obj/machinery/door/proc/next_door_deadline()
	return close_door_at > 0 ? close_door_at : 0

/// Keeps one REACT_AT on next_door_deadline(). Call after changing any deadline.
/obj/machinery/door/proc/schedule_door_timer()
	var/deadline = next_door_deadline()
	if(deadline == door_timer_at && (!isnull(door_timer_token) || !deadline))
		return
	if(!isnull(door_timer_token))
		REACT_CANCEL(src, door_timer_token)
		door_timer_token = null
	door_timer_at = deadline
	if(deadline)
		door_timer_token = REACT_AT(src, deadline)

/obj/machinery/door/on_react(reason, source, source_kind)
	. = ..()
	if(reason & REACT_REASON_TIMER)
		door_timer_token = null
		door_timer_at = 0
		door_deadlines_due()
		schedule_door_timer()

/// Runs every deadline that has passed. Called from the door's timer wake.
/obj/machinery/door/proc/door_deadlines_due()
	if(close_door_at && world.time >= close_door_at)
		if(density && !operating)
			close_door_at = 0
		else if(autoclose)
			close_door_at = world.time + next_close_wait()
			close()
		else
			close_door_at = 0

/obj/machinery/door/react_sleep_violation()
	var/deadline = next_door_deadline()
	if(!deadline)
		return null
	if(isnull(door_timer_token) || door_timer_at > deadline)
		return "deadline [deadline] (now [world.time]) has no timer (timer at [door_timer_at])"
	return null

/obj/machinery/door/proc/autoclose_in(wait)
	clear_autoclose_blockers()
	close_door_at = world.time + wait
	schedule_door_timer()

/obj/machinery/door/proc/sleep_until_autoclose_blocker_moves(atom/movable/blocker)
	if(!blocker)
		return
	LAZYADD(autoclose_blockers, blocker)
	RegisterSignal(blocker, COMSIG_MOVABLE_MOVED, PROC_REF(on_autoclose_blocker_changed))
	RegisterSignal(blocker, COMSIG_QDELETING, PROC_REF(on_autoclose_blocker_changed))
	close_door_at = 0
	schedule_door_timer()

/obj/machinery/door/proc/clear_autoclose_blockers()
	for(var/atom/movable/blocker as anything in autoclose_blockers)
		UnregisterSignal(blocker, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING))
	LAZYCLEARLIST(autoclose_blockers)

/obj/machinery/door/proc/on_autoclose_blocker_changed(datum/source)
	SIGNAL_HANDLER
	clear_autoclose_blockers()
	autoclose_in(0)

/obj/machinery/door/proc/can_open()
	if(!density || operating || !SSticker)
		return FALSE
	return TRUE

/obj/machinery/door/proc/can_close()
	if(density || operating || !SSticker)
		return FALSE
	return TRUE

/obj/machinery/door/Bumped(atom/AM)
	. = ..()
	if(p_open || operating)
		return

	if(ismob(AM))
		var/mob/M = AM
		if(world.time - M.last_bumped <= 10)
			return	//Can bump-open one airlock per second. This is to prevent shock spam.
		M.last_bumped = world.time
		if(M.restrained() && !check_access(null))
			return
		else if(HAS_TRAIT(M, TRAIT_AMBIENT_PEST_MOB) && !(M.ckey))
			return
		else
			bumpopen(M)
		return

	if(istype(AM, /obj/item/uav))
		if(check_access(null))
			open()
		else
			do_animate("deny")
		return

	if(isbot(AM))
		var/mob/living/bot/bot = AM
		if(check_access(bot.botcard))
			if(density)
				open()
		return

	if(istype(AM, /obj/mecha))
		var/obj/mecha/mecha = AM
		if(density)
			if(mecha.occupant && (allowed(mecha.occupant) || check_access_list(mecha.operation_req_access)))
				open()
			else
				do_animate("deny")
		return

	if(istype(AM, /obj/structure/bed/chair/wheelchair))
		var/obj/structure/bed/chair/wheelchair/wheel = AM
		if(density)
			if(wheel.pulling && (allowed(wheel.pulling)))
				open()
			else
				do_animate("deny")
		return

/obj/machinery/door/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return !opacity
	return !density

// CanZASPass was a ZAS zone-graph hook that controlled whether the door
// allowed adjacent zones to merge. LINDA tracks adjacency via /turf flags and
// SSair.add_to_active, not through this hook. The override is dead under LINDA;
// stub returns the old block-zones semantics so any callers from CHOMP machinery
// still get a meaningful answer (matters until they're migrated to LINDA APIs).
// was `proc/CanZASPass` declaration; the parent proc lives on /atom in
// code/atmospherics/tg_infra_stubs.dm. This is the door override.
/obj/machinery/door/CanZASPass(turf/T, is_zone)
	if(is_zone)
		return !block_air_zones
	return !density // Block airflow unless density = FALSE

/obj/machinery/door/proc/bumpopen(mob/user)
	if(!user)
		return
	if(operating)
		return
	// ZAS airflow was deleted with the atmos migration; the old guard
	// suppressed bumpopen briefly after a mob got shoved by an airflow pulse so
	// they didn't open the door they were tumbling through. LINDA has no airflow
	// pulses, so the guard is unconditionally pass-through.
	// if(user.last_airflow > world.time - GLOB.vsc.airflow_delay) return
	add_fingerprint(user)
	if(density)
		if(allowed(user))
			open()
		else
			do_animate("deny")
	return

/obj/machinery/door/bullet_act(obj/item/projectile/Proj)
	var/damage = Proj.get_structure_damage()
	. = ..()
	if(damage && !QDELETED(src))
		update_icon()



/obj/machinery/door/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	..()
	visible_message(span_danger("[name] was hit by [source]."))
	playsound(src, hitsound, 100, 1)

/obj/machinery/door/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	try_to_activate_door(user)

/obj/machinery/door/attack_tk(mob/user)
	if(requiresID() && !allowed(null))
		return
	..()

/obj/machinery/door/attackby(obj/item/I, mob/user)
	add_fingerprint(user)

	if(istype(I, /obj/item/stack/material) && I.get_material_name() == MAT_PLASTEEL)
		if(heat_proof)
			to_chat(user, span_warning("\The [src] is already reinforced."))
			return
		if((stat & BROKEN) || (get_integrity() < max_integrity))
			to_chat(user, span_notice("It looks like \the [src] broken. Repair it before reinforcing it."))
			return
		if(!density)
			to_chat(user, span_warning("\The [src] must be closed before you can reinforce it."))
			return

		var/amount_needed = 2

		var/obj/item/stack/stack = I
		var/amount_given = amount_needed - reinforcing
		var/mats_given = stack.get_amount()
		var/singular_name = stack.singular_name
		if(reinforcing && amount_given <= 0)
			to_chat(user, span_warning("You must weld or remove \the plasteel from \the [src] before you can add anything else."))
		else
			if(mats_given >= amount_given)
				if(stack.use(amount_given))
					reinforcing += amount_given
			else
				if(stack.use(mats_given))
					reinforcing += mats_given
					amount_given = mats_given
		if(amount_given)
			to_chat(user, span_notice("You fit [amount_given] [singular_name]\s on \the [src]."))
		return

	// Handle signals
	if(..())
		return

	//psa to whoever coded this, there are plenty of objects that need to call attack() on doors without bludgeoning them.
	if(density && istype(I, /obj/item) && IS_HARMING(user) && !istype(I, /obj/item/card))
		var/obj/item/W = I
		user.setClickCooldown(user.get_attack_speed(W))
		if(W.obj_damage_type())
			user.do_attack_animation(src)
			if(W.force < min_force)
				user.visible_message(span_danger("\The [user] hits \the [src] with \the [W] with no visible effect."))
			else
				user.visible_message(span_danger("\The [user] forcefully strikes \the [src] with \the [W]!"))
				playsound(src, hitsound, 100, 1)
				receive_weapon_hit(W, user, silent = FALSE)
		return

	try_to_activate_door(user)

/obj/machinery/door/crowbar_act(mob/user, obj/item/tool)
	if(!reinforcing)
		return NONE
	var/obj/item/stack/material/plasteel/reinforcing_sheet = new /obj/item/stack/material/plasteel(get_turf(src), reinforcing)
	reinforcing = 0
	to_chat(user, span_notice("You remove \the [reinforcing_sheet]."))
	playsound(src, tool.usesound, 100, 1)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/door/welder_act(mob/user, obj/item/tool)
	if(reinforcing)
		if(!density)
			to_chat(user, span_warning("\The [src] must be closed before you can reinforce it."))
			return ITEM_INTERACT_BLOCKING

		if(reinforcing < 2)
			to_chat(user, span_warning("You will need more plasteel to reinforce \the [src]."))
			return ITEM_INTERACT_BLOCKING

		var/obj/item/weldingtool/welder = tool.get_welder()
		if(welder.remove_fuel(0,user))
			to_chat(user, span_notice("You start welding the plasteel into place."))
			playsound(src, welder.usesound, 50, 1)
			if(do_after(user, 1 SECOND * welder.toolspeed, target = src) && welder && welder.isOn())
				to_chat(user, span_notice("You finish reinforcing \the [src]."))
				heat_proof = TRUE
				update_icon()
				reinforcing = 0
		return ITEM_INTERACT_SUCCESS

	if(get_integrity() < max_integrity)
		if(!density)
			to_chat(user, span_warning("\The [src] must be closed before you can repair it."))
			return ITEM_INTERACT_BLOCKING

		var/obj/item/weldingtool/welder = tool.get_welder()
		if(welder.remove_fuel(0,user))
			to_chat(user, span_notice("You start to fix dents and repair \the [src]."))
			playsound(src, welder.usesound, 50, 1)
			var/repairtime = max_integrity - get_integrity()
			if(do_after(user, repairtime * welder.toolspeed, target = src) && welder && welder.isOn())
				to_chat(user, span_notice("You finish repairing the damage to \the [src]."))
				repair_damage(max_integrity)
				atom_fix()
		return ITEM_INTERACT_SUCCESS
	return NONE

/obj/machinery/door/proc/try_to_activate_door(mob/user)
	add_fingerprint(user)
	if(operating || isrobot(user))
		return FALSE //borgs can't attack doors open because it conflicts with their AI-like interaction with them.
	if(allowed(user) && operable())
		if(density)
			open()
		else
			close()
		return TRUE
	if(density)
		do_animate("deny")

	return FALSE

/obj/machinery/door/emag_act(remaining_charges)
	if(density && operable())
		do_animate("spark")
		addtimer(CALLBACK(src, PROC_REF(trigger_emag)), 0.6 SECONDS)
		return TRUE

/obj/machinery/door/proc/trigger_emag()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	open()
	operating = -1

// Damage-state flavour text as integrity drops.
/obj/machinery/door/on_update_integrity(old_value, new_value)
	. = ..()
	if(new_value > 0)
		if(new_value < max_integrity / 4 && old_value >= max_integrity / 4)
			visible_message("\The [src] looks like it's about to break!" )
		else if(new_value < max_integrity / 2 && old_value >= max_integrity / 2)
			visible_message("\The [src] looks seriously damaged!" )
		else if(new_value < max_integrity * 3/4 && old_value >= max_integrity * 3/4)
			visible_message("\The [src] shows signs of damage!" )
	update_icon()

/obj/machinery/door/atom_break(damage_flag)
	. = ..()
	if(.)
		on_broken()


/obj/machinery/door/examine(mob/user)
	. = ..()
	if(stat & BROKEN)
		. += "It is broken!"


/// What a door does when it breaks, after the base machinery break.
/obj/machinery/door/proc/on_broken()
	for (var/mob/O in viewers(src, null))
		if ((O.client && !( O.blinded )))
			O.show_message("[name] breaks!" )


/obj/machinery/door/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(prob(20/severity) && (istype(src,/obj/machinery/door/airlock) || istype(src,/obj/machinery/door/window)) )
		open()

/obj/machinery/door/blob_act(obj/structure/blob/B)
	if(density) // If it's closed.
		if(stat & BROKEN)
			open(1)
		else
			receive_blob(B)

/obj/machinery/door/update_icon()
	if(density)
		icon_state = "door1"
	else
		icon_state = "door0"
	return


/obj/machinery/door/proc/do_animate(animation)
	switch(animation)
		if("opening")
			if(p_open)
				flick("o_doorc0", src)
			else
				flick("doorc0", src)
		if("closing")
			if(p_open)
				flick("o_doorc1", src)
			else
				flick("doorc1", src)
		if("spark")
			if(density)
				flick("door_spark", src)
		if("deny")
			if(density && !(stat & (NOPOWER|BROKEN)))
				flick("door_deny", src)
				playsound(src, 'sound/machines/buzz-two.ogg', 50, 0)
	return

/obj/machinery/door/proc/open(forced = 0)
	if(!can_open(forced))
		return
	operating = 1

	SSai?.publish_navigation_change()

	do_animate("opening")
	icon_state = "door0"
	set_opacity(0)
	addtimer(CALLBACK(src, PROC_REF(open_internalsetdensity),forced), anim_length_before_density)

/obj/machinery/door/proc/open_internalsetdensity(forced = 0)
	PRIVATE_PROC(TRUE) //do not touch this or BYOND will devour you
	SHOULD_NOT_OVERRIDE(TRUE)
	density = FALSE
	update_nearby_tiles()
	addtimer(CALLBACK(src, PROC_REF(open_internalfinish),forced), anim_length_before_finalize)

/obj/machinery/door/proc/open_internalfinish(forced = 0)
	PRIVATE_PROC(TRUE) //do not touch this or BYOND will devour you
	SHOULD_NOT_OVERRIDE(TRUE)
	layer = open_layer
	explosion_resistance = 0
	update_icon()
	set_opacity(0)
	operating = 0

	/*
	var/obj/effect/step_trigger/claymore_laser/las = locate() in loc
	if(las)
		addtimer(CALLBACK(las, TYPE_PROC_REF(/obj/effect/step_trigger/claymore_laser,Trigger), src), 5)
	*/

	if(autoclose)
		autoclose_in(next_close_wait())
	return TRUE

/obj/machinery/door/proc/next_close_wait()
	var/lowest_temp = T20C
	var/highest_temp = T0C
	for(var/D in GLOB.cardinal)
		var/turf/target = get_step(loc, D)
		if(target && !target.density)
			var/datum/gas_mixture/airmix = target.return_air()
			if(!airmix)
				continue
			var/airmix_temp = airmix.return_temperature()
			if(airmix_temp < lowest_temp)
				lowest_temp = airmix_temp
			if(airmix_temp > highest_temp)
				highest_temp = airmix_temp
	// Fast close to keep in the heat
	var/open_speed = 150
	if(abs(highest_temp - lowest_temp) >= 5)
		open_speed = 15
	return (normalspeed ? open_speed : 5)

/obj/machinery/door/proc/close(forced = 0, ignore_safties = FALSE, crush_damage = DOOR_CRUSH_DAMAGE)
	if(!can_close(forced))
		return
	clear_autoclose_blockers()
	operating = 1

	SSai?.publish_navigation_change()

	close_door_at = 0
	do_animate("closing")
	addtimer(CALLBACK(src, PROC_REF(close_internalsetdensity),forced), anim_length_before_density)

/obj/machinery/door/proc/close_internalsetdensity(forced = 0)
	PRIVATE_PROC(TRUE) //do not touch this or BYOND will devour you
	SHOULD_NOT_OVERRIDE(TRUE)
	density = TRUE
	explosion_resistance = initial(explosion_resistance)
	layer = closed_layer
	update_nearby_tiles()
	addtimer(CALLBACK(src, PROC_REF(close_internalfinish),forced), anim_length_before_finalize)

/obj/machinery/door/proc/close_internalfinish(forced = 0)
	PROTECTED_PROC(TRUE) //do not touch this or BYOND will devour you
	update_icon()
	if(visible && !glass)
		set_opacity(1)	//caaaaarn!
	operating = 0

	// /obj/fire was a ZAS hotspot type, deleted with the LINDA migration.
	// LINDA tracks hotspots via /obj/effect/hotspot (vendored under
	// code/atmospherics/environmental/LINDA_fire.dm). Switch to the
	// LINDA type so doors still extinguish fire underneath when they close.
	var/obj/effect/hotspot/hotspot = locate() in loc
	if(hotspot)
		qdel(hotspot)

	/*
	var/obj/effect/step_trigger/claymore_laser/las = locate() in loc
	if(las)
		addtimer(CALLBACK(las, TYPE_PROC_REF(/obj/effect/step_trigger/claymore_laser,Trigger), src), 1)
	*/

	return TRUE

/obj/machinery/door/proc/requiresID()
	return TRUE

/obj/machinery/door/allowed(mob/M)
	if(!requiresID())
		return ..(null) //don't care who they are or what they have, act as if they're NOTHING
	. = ..()

/obj/machinery/door/update_nearby_tiles(need_rebuild)
	if(!SSair)
		return FALSE

	for(var/turf/simulated/turf in locs)
		update_heat_protection(turf)
		SSair.mark_for_update(turf)

	return TRUE

/obj/machinery/door/proc/update_heat_protection(turf/simulated/source)
	if(istype(source))
		if(density && (opacity || heat_proof))
			source.thermal_conductivity = DOOR_HEAT_TRANSFER_COEFFICIENT
		else
			source.thermal_conductivity = initial(source.thermal_conductivity)

/obj/machinery/door/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(width > 1)
		if(dir in list(EAST, WEST))
			bound_width = width * world.icon_size
			bound_height = world.icon_size
		else
			bound_width = world.icon_size
			bound_height = width * world.icon_size

	if(update_adjacent_tiles)
		update_nearby_tiles()

/obj/machinery/door/morgue
	icon = 'icons/obj/doors/doormorgue.dmi'


/obj/machinery/door/fire_act(exposed_temperature, exposed_volume)
	for(var/obj/machinery/door/blast/B in loc.contents)
		if(B.density)
			return

	var/maxtemperature = 1800 //same as a normal steel wall
	if(heat_proof)
		maxtemperature = 6000 //same as a plasteel rwall

	if(exposed_temperature > maxtemperature)
		var/burndamage = log(RAND_F(0.9, 1.1) * (exposed_temperature - maxtemperature))
		if(burndamage)
			deal_damage(DAMAGE_THERMAL, burndamage, FIRE)

	return ..()

/obj/machinery/door/proc/toggle()
	if(glass)
		icon = icon_tinted
		glass = 0
		if(!operating && density)
			set_opacity(1)
	else
		icon = initial(icon)
		glass = 1
		if(!operating)
			set_opacity(0)

/obj/machinery/button/windowtint/doortint
	name = "door tint control"
	desc = "A remote control switch for polarized glass doors."

/obj/machinery/button/windowtint/doortint/toggle_tint()
	use_power(5)
	active = !active
	update_icon()

	for(var/obj/machinery/door/D in range(src,range))
		if(D.icon_tinted && (D.id_tint == src.id || !D.id_tint))
			D.toggle()

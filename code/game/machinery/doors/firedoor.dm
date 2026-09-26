#define FIREDOOR_MAX_PRESSURE_DIFF 25 // kPa
#define FIREDOOR_MAX_TEMP 50 // °C
#define FIREDOOR_MIN_TEMP 0
// Bitflags
#define FIREDOOR_ALERT_HOT		1
#define FIREDOOR_ALERT_COLD		2
// Not used #define FIREDOOR_ALERT_LOWPRESS 4

/obj/machinery/door/firedoor
	/// Optional generated-turbolift owner; ordinary mapped firedoors leave null.
	var/datum/turbolift_floor/turbolift_floor
	name = "\improper Emergency Shutter"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas."
	icon = 'icons/obj/doors/DoorHazard.dmi'
	icon_state = "door_open"
	req_one_access = list(ACCESS_EVA)	//ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
	opacity = 0
	density = FALSE
	layer = DOOR_OPEN_LAYER - 0.01
	open_layer = DOOR_OPEN_LAYER - 0.01 // Just below doors when open
	closed_layer = DOOR_CLOSED_LAYER + 0.01 // Just above doors when closed

	//These are frequenly used with windows, so make sure zones can pass.
	//Generally if a firedoor is at a place where there should be a zone boundery then there will be a regular door underneath it.
	block_air_zones = 0
	heat_proof = 1

	var/blocked = 0
	var/prying = 0
	var/lockdown = 0 // When the door has detected a problem, it locks.
	var/pdiff_alert = 0
	var/pdiff = 0
	var/nextstate = null
	var/net_id
	var/list/areas_added
	/// Lazy list of names who opened this door during an alert.
	var/list/users_to_open
	var/list/sleeping_mixture_ids

	var/hatch_open = 0

	power_channel = ENVIRON
	use_power = USE_POWER_IDLE
	idle_power_usage = 5

	/// Lazy: 4 cardinal dirs of FIREDOOR_ALERT_* bitflags, null while no direction alerts.
	var/list/dir_alerts

	// MUST be in same order as FIREDOOR_ALERT_*
	var/static/list/ALERT_STATES=list(
		"hot",
		"cold"
	)
	var/open_sound = 'sound/machines/firelockopen.ogg' // firedoor sound variable.
	var/close_sound = 'sound/machines/firelockclose.ogg' // firedoor sound variable.

/obj/machinery/door/firedoor/Initialize(mapload)
	. = ..()
	//Delete ourselves if we find extra mapped in firedoors
	for(var/obj/machinery/door/firedoor/F in loc)
		if(F != src)
			log_mapping("Duplicate firedoors at [x],[y],[z]")
			return INITIALIZE_HINT_QDEL

	var/area/A = get_area(src)
	ASSERT(istype(A))

	LAZYADD(A.all_doors, src)
	areas_added = list(A)

	for(var/direction in GLOB.cardinal)
		A = get_area(get_step(src,direction))
		if(istype(A) && !(A in areas_added))
			LAZYADD(A.all_doors, src)
			areas_added += A

/obj/machinery/door/firedoor/Destroy()
	if(turbolift_floor)
		turbolift_floor.doors -= src
		turbolift_floor = null
	clear_gas_dependencies()
	for(var/area/A in areas_added)
		LAZYREMOVE(A.all_doors, src)
	. = ..()

/obj/machinery/door/firedoor/get_material()
	return get_material_by_name(MAT_STEEL)

/obj/machinery/door/firedoor/examine(mob/user)
	. = ..()

	if(!Adjacent(user))
		return .

	if(pdiff >= FIREDOOR_MAX_PRESSURE_DIFF)
		. += span_warning("WARNING: Current pressure differential is [pdiff]kPa! Opening door may result in injury!")

	. += span_bold("Sensor readings:")
	var/list/tile_info = getCardinalAirInfo(src.loc, list("temperature", "pressure"))
	for(var/index = 1; index <= tile_info.len; index++)
		var/o = "&nbsp;&nbsp;"
		switch(index)
			if(1)
				o += "NORTH: "
			if(2)
				o += "SOUTH: "
			if(3)
				o += "EAST: "
			if(4)
				o += "WEST: "
		if(tile_info[index] == null)
			o += span_warning("DATA UNAVAILABLE")
			. += o
			continue
		var/celsius = convert_k2c(tile_info[index][1])
		var/pressure = tile_info[index][2]
		var/temperature_string = "[celsius]&deg;C "
		o += ((LAZYACCESS(dir_alerts, index) & (FIREDOOR_ALERT_HOT|FIREDOOR_ALERT_COLD)) ? span_warning(temperature_string) : span_blue(temperature_string))
		o += span_blue("[pressure]kPa")
		o += "</li>"
		. += o

	if(islist(users_to_open) && users_to_open.len)
		var/users_to_open_string = users_to_open[1]
		if(users_to_open.len >= 2)
			for(var/i = 2 to users_to_open.len)
				users_to_open_string += ", [users_to_open[i]]"
		. += "These people have opened \the [src] during an alert: [users_to_open_string]."

/obj/machinery/door/firedoor/Bumped(atom/AM)
	if(p_open || operating)
		return
	if(!density)
		return ..()
	if(istype(AM, /obj/mecha))
		var/obj/mecha/mecha = AM
		if(mecha.occupant)
			var/mob/M = mecha.occupant
			if(world.time - M.last_bumped <= 10) return //Can bump-open one airlock per second. This is to prevent popup message spam.
			M.last_bumped = world.time
			attack_hand(M)
	return 0

/obj/machinery/door/firedoor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/firedoor_use,
	)
	..()

/// The old attack_hand: never called ..(), prompted to open/close the firedoor.
/datum/interaction/machine_hand/ungated/firedoor_use
	id = "firedoor_use"
	name = "Use"
	effect = /obj/machinery/door/firedoor/proc/interaction_use

/obj/machinery/door/firedoor/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(operating)
		return TRUE//Already doing something.

	if(ishuman(user))
		var/mob/living/carbon/human/X = user
		if(istype(X.species, /datum/species/xenos))
			src.attack_alien(user)
			return TRUE

	if(blocked)
		to_chat(user, span_warning("\The [src] is welded solid!"))
		return TRUE

	var/alarmed = lockdown
	for(var/area/A in areas_added)		//Checks if there are fire alarms in any areas associated with that firedoor
		if(A.firedoors_closed)
			alarmed = 1

	var/answer = tgui_alert(user, "Would you like to [density ? "open" : "close"] this [src.name]?[ alarmed && density ? "\nNote that by doing so, you acknowledge any damages from opening this\n[src.name] as being your own fault, and you will be held accountable under the law." : ""]",\
	"\The [src]", list("Yes, [density ? "open" : "close"]", "No"))
	if(!answer || answer == "No")
		return TRUE
	if(user.incapacitated() || (get_dist(src, user) > 1 && !issilicon(user)))
		to_chat(user, "Sorry, you must remain able bodied and close to \the [src] in order to use it.")
		return TRUE
	if(density && (stat & (BROKEN|NOPOWER))) //can still close without power
		to_chat(user, "\The [src] is not functioning, you'll have to force it open manually.")
		return TRUE

	if(alarmed && density && lockdown && !allowed(user))
		to_chat(user, span_warning("Access denied. Please wait for authorities to arrive, or for the alert to clear."))
		return TRUE
	else
		user.visible_message(span_notice("\The [src] [density ? "open" : "close"]s for \the [user]."),\
		"\The [src] [density ? "open" : "close"]s.",\
		"You hear a beep, and a door opening.")

	var/needs_to_close = 0
	if(density)
		if(alarmed)
			// Accountability!
			LAZYOR(users_to_open, user.name)
			needs_to_close = !issilicon(user)
		spawn()
			open()
	else
		spawn()
			close()

	if(needs_to_close)
		spawn(50)
			alarmed = 0
			for(var/area/A in areas_added)		//Just in case a fire alarm is turned off while the firedoor is going through an autoclose cycle
				if(A.firedoors_closed)
					alarmed = 1
			if(alarmed)
				nextstate = FIREDOOR_CLOSED
				close()
	return TRUE

/obj/machinery/door/firedoor/attack_alien(mob/user) //Familiar, right? Doors.
	if(ishuman(user))
		var/mob/living/carbon/human/X = user
		if(istype(X.species, /datum/species/xenos))
			if(src.blocked)
				visible_message(span_alium("\The [user] begins digging into \the [src] internals!"))
				if(do_after(user, 5 SECONDS, target = src))
					playsound(src, 'sound/machines/door/airlock_creaking.ogg', 100, 1)
					src.blocked = 0
					update_icon()
					open(1)
			else if(src.density)
				visible_message(span_alium("\The [user] begins forcing \the [src] open!"))
				if(do_after(user, 2 SECONDS, target = src))
					playsound(src, 'sound/machines/door/airlock_creaking.ogg', 100, 1)
					visible_message(span_danger("\The [user] forces \the [src] open!"))
					open(1)
			else
				visible_message(span_danger("\The [user] forces \the [src] closed!"))
				close(1)
		else
			visible_message(span_notice("\The [user] strains fruitlessly to force \the [src] [density ? "open" : "closed"]."))
			return
	..()

/obj/machinery/door/firedoor/attack_generic(mob/living/user, damage)
	if(stat & (BROKEN|NOPOWER))
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			var/time_to_force = (2 + (2 * blocked)) * 5
			if(src.density)
				visible_message(span_danger("\The [user] starts forcing \the [src] open!"))
				if(user.ai_brain) user.ai_brain.busy = TRUE // If the mob doesn't have an AI attached, this won't do anything.
				if(do_after(user, time_to_force, target = src))
					visible_message(span_danger("\The [user] forces \the [src] open!"))
					src.blocked = 0
					open(1)
				if(user.ai_brain) user.ai_brain.busy = FALSE
			else
				time_to_force = (time_to_force / 2)
				visible_message(span_danger("\The [user] starts forcing \the [src] closed!"))
				if(user.ai_brain) user.ai_brain.busy = TRUE // If the mob doesn't have an AI attached, this won't do anything.
				if(do_after(user, time_to_force, target = src))
					visible_message(span_danger("\The [user] forces \the [src] closed!"))
					close(1)
				if(user.ai_brain) user.ai_brain.busy = FALSE
		else
			visible_message(span_notice("\The [user] strains fruitlessly to force \the [src] [density ? "open" : "closed"]."))
		return
	..()

/obj/machinery/door/firedoor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/firedoor_use_item,
	)
	..()

/// The old attackby: unwelds/tape/pry handling, then fell through to ..().
/datum/interaction/machine_item/firedoor_use_item
	id = "firedoor_use_item"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/door/firedoor/proc/interaction_use_item

/obj/machinery/door/firedoor/proc/interaction_use_item(mob/user, obj/item/C, datum/interaction/interaction)
	add_fingerprint(user)
	if(istype(C, /obj/item/taperoll))
		return TRUE //Don't open the door if we're putting tape on it to tell people 'don't open the door'.
	if(operating)
		return TRUE//Already doing something.
	if(blocked)
		to_chat(user, span_danger("\The [src] is welded shut!"))
		return TRUE

	if(C.pry == 1)
		if(operating)
			return TRUE

		if(istype(C,/obj/item/material/twohanded/fireaxe))
			var/obj/item/material/twohanded/fireaxe/F = C
			if(!F.wielded)
				return TRUE

		if(prying)
			to_chat(user, span_notice("Someone's already prying that [density ? "open" : "closed"]."))
			return TRUE

		prying = 1
		update_icon()
		if(use_tool(user, C, src, delay = 3 SECONDS, volume = 100,
				message_self = "You start forcing \the [src] [density ? "open" : "closed"] with \the [C]!",
				message_others = "\The [user] starts to force \the [src] [density ? "open" : "closed"] with \a [C]!"))
			user.visible_message(span_danger("\The [user] forces \the [ blocked ? "welded" : "" ] [src] [density ? "open" : "closed"] with \a [C]!"),\
					"You force \the [ blocked ? "welded" : "" ] [src] [density ? "open" : "closed"] with \the [C]!",\
					"You hear metal strain and groan, and a door [density ? "opening" : "closing"].")
			if(density)
				spawn(0)
					open(1)
			else
				spawn(0)
					close()
		prying = 0
		update_icon()
		return TRUE

	return FALSE

/obj/machinery/door/firedoor/welder_act(mob/user, obj/item/tool)
	if(operating)
		return TRUE
	if(get_integrity() < max_integrity)
		return ..()
	if(prying)
		to_chat(user, span_notice("Someone's busy prying that [density ? "open" : "closed"]!"))
		return TRUE
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(welder.remove_fuel(0, user))
		blocked = !blocked
		user.visible_message(span_danger("\The [user] [blocked ? "welds" : "unwelds"] \the [src] with \a [welder]."), "You [blocked ? "weld" : "unweld"] \the [src] with \the [welder].", "You hear something being welded.")
		playsound(src, welder.usesound, 100, TRUE)
		update_icon()
	return TRUE

/obj/machinery/door/firedoor/screwdriver_act(mob/user, obj/item/tool)
	if(operating || !density)
		return FALSE
	hatch_open = !hatch_open
	playsound(src, tool.usesound, 50, TRUE)
	user.visible_message(span_danger("[user] has [hatch_open ? "opened" : "closed"] \the [src] maintenance hatch."), "You have [hatch_open ? "opened" : "closed"] the [src] maintenance hatch.")
	update_icon()
	return TRUE

/obj/machinery/door/firedoor/crowbar_act(mob/user, obj/item/tool)
	if(operating)
		return TRUE
	if(blocked)
		if(!hatch_open)
			to_chat(user, span_danger("You must open the maintenance hatch first!"))
			return TRUE
		user.visible_message(span_danger("[user] is removing the electronics from \the [src]."), "You start to remove the electronics from [src].")
		if(do_after(user, 3 SECONDS, target = src) && blocked && density && hatch_open)
			playsound(src, tool.usesound, 50, TRUE)
			user.visible_message(span_danger("[user] has removed the electronics from \the [src]."), "You have removed the electronics from [src].")
			if(stat & BROKEN)
				new /obj/item/circuitboard/broken(loc)
			else
				new /obj/item/circuitboard/airalarm(loc)
			var/obj/structure/firedoor_assembly/assembly = new(loc)
			assembly.anchored = TRUE
			assembly.density = TRUE
			assembly.wired = TRUE
			assembly.glass = glass
			assembly.update_icon()
			qdel(src)
		return TRUE
	if(prying)
		to_chat(user, span_notice("Someone's already prying that [density ? "open" : "closed"]."))
		return TRUE
	prying = TRUE
	update_icon()
	if(use_tool(user, tool, src, delay = 3 SECONDS, quality = TOOL_CROWBAR, volume = 100,
			message_self = "You start forcing \the [src] [density ? "open" : "closed"] with \the [tool]!",
			message_others = "\The [user] starts to force \the [src] [density ? "open" : "closed"] with \a [tool]!") \
			&& (stat & (BROKEN|NOPOWER) || !density))
		user.visible_message(span_danger("\The [user] forces \the [src] [density ? "open" : "closed"] with \a [tool]!"), "You force \the [src] [density ? "open" : "closed"] with \the [tool]!", "You hear metal strain, and a door [density ? "open" : "close"].")
		if(density)
			open(TRUE)
		else
			close()
	prying = FALSE
	update_icon()
	return TRUE

// CHECK PRESSURE
/obj/machinery/door/firedoor/process()
	..()

	if(!density)
		return PROCESS_KILL
	var/changed = FALSE
	lockdown = FALSE
	pdiff = getOPressureDifferential(src.loc)
	var/new_pdiff_alert = pdiff >= FIREDOOR_MAX_PRESSURE_DIFF
	lockdown ||= new_pdiff_alert
	if(pdiff_alert != new_pdiff_alert)
		pdiff_alert = new_pdiff_alert
		changed = TRUE
	var/list/tile_info = getCardinalAirInfo(src.loc, list("temperature", "pressure"))
	var/any_alerts = FALSE
	for(var/index = 1; index <= 4; index++)
		var/list/tileinfo = tile_info[index]
		var/alerts = tileinfo ? firedoor_temperature_band(tileinfo[1]) : 0
		if((LAZYACCESS(dir_alerts, index) || 0) != alerts)
			changed = TRUE
			if(!dir_alerts)
				dir_alerts = new /list(4)
			dir_alerts[index] = alerts
		any_alerts ||= alerts
		lockdown ||= alerts
	if(!any_alerts)
		dir_alerts = null
	if(changed)
		update_icon()
	hibernate_until_air_changes()
	return PROCESS_KILL

/// Arms one om_watch value watch (code/datums/om/watch.dm) per dependency turf (the door's own
/// plus its four cardinal neighbours), all sharing firedoor_atmos_signature() as their getter:
/// whichever one notices a change first recomputes the full signature and wakes the door if it
/// actually crossed a pressure/temperature-band edge, not on every harmless diffusion tick.
/obj/machinery/door/firedoor/proc/hibernate_until_air_changes()
	clear_gas_dependencies()
	var/list/dependency_turfs = list(get_turf(src))
	for(var/direction in GLOB.cardinal)
		dependency_turfs += get_step(src, direction)
	var/datum/callback/getter = CALLBACK(src, PROC_REF(firedoor_atmos_signature))
	var/datum/callback/wake = CALLBACK(src, PROC_REF(wake_from_air))
	for(var/index in 1 to length(dependency_turfs))
		var/turf/T = dependency_turfs[index]
		var/datum/gas_mixture/air = T?.return_air()
		var/mixture_id = air?.arena_id()
		if(isnull(mixture_id))
			continue
		LAZYSET(sleeping_mixture_ids, "turf[index]", mixture_id)
		om_watch_arm_value(src, "turf[index]", mixture_id, GAS_DEPENDENCY_PRESSURE | GAS_DEPENDENCY_TEMPERATURE, getter, wake_callback = wake)
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/door/firedoor/proc/clear_gas_dependencies()
	for(var/key in sleeping_mixture_ids)
		om_watch_disarm(src, key)
	sleeping_mixture_ids = null

/obj/machinery/door/firedoor/proc/wake_from_air()
	clear_gas_dependencies()
	START_MACHINE_PROCESSING(src)

/obj/machinery/door/firedoor/proc/firedoor_atmos_signature()
	var/signature = getOPressureDifferential(src.loc) >= FIREDOOR_MAX_PRESSURE_DIFF
	var/datum/gas_mixture/local_air = loc?.return_air()
	signature = (signature << 2) | (local_air ? firedoor_temperature_band(local_air.return_temperature()) : 0)
	var/list/cardinal_air = getCardinalAirInfo(src.loc, list("temperature", "pressure"))
	for(var/index = 1; index <= 4; index++)
		var/list/tileinfo = cardinal_air[index]
		signature = (signature << 2) | (tileinfo ? firedoor_temperature_band(tileinfo[1]) : 0)
	return signature

/obj/machinery/door/firedoor/proc/firedoor_temperature_band(temperature)
	// Auxmos publishes temperatures as 32-bit floats. Allow a tiny boundary
	// tolerance so an exact configured threshold survives the FFI round trip.
	var/celsius = convert_k2c(temperature)
	if(celsius >= FIREDOOR_MAX_TEMP - 0.01)
		return FIREDOOR_ALERT_HOT
	if(celsius <= FIREDOOR_MIN_TEMP + 0.01)
		return FIREDOOR_ALERT_COLD
	return 0

/obj/machinery/door/firedoor/proc/latetoggle()
	if(operating || !nextstate)
		return
	switch(nextstate)
		if(FIREDOOR_OPEN)
			nextstate = null

			open()
		if(FIREDOOR_CLOSED)
			nextstate = null
			close()
	return

/obj/machinery/door/firedoor/close()
	latetoggle()
	. = ..()

/obj/machinery/door/firedoor/close_internalfinish(forced = 0)
	// Queue us for processing when we are closed!
	..()
	if(density)
		clear_gas_dependencies()
		START_MACHINE_PROCESSING(src)

/obj/machinery/door/firedoor/open(forced = 0)
	clear_gas_dependencies()
	if(hatch_open)
		hatch_open = 0
		visible_message("The maintenance hatch of \the [src] closes.")
		update_icon()

	if(!forced)
		if(stat & (BROKEN|NOPOWER))
			return //needs power to open unless it was forced
		else
			use_power(360)
	else
		if(usr && usr.ckey)
			log_admin("[usr]([usr.ckey]) has forced open an emergency shutter.")
			message_admins("[usr]([usr.ckey]) has forced open an emergency shutter.")
	latetoggle()
	return ..()

/obj/machinery/door/firedoor/do_animate(animation)
	switch(animation)
		if("opening")
			flick("door_opening", src)
			playsound(src, open_sound, 37, 1) // var
		if("closing")
			playsound(src, close_sound, 37, 1) // var
			flick("door_closing", src)
	return


/obj/machinery/door/firedoor/update_icon()
	cut_overlays()
	if(density)
		icon_state = "door_closed"
		if(prying)
			icon_state = "prying_closed"
		if(hatch_open)
			add_overlay("hatch")
		if(blocked)
			add_overlay("welded")
		if(pdiff_alert)
			add_overlay("palert")
		if(dir_alerts)
			for(var/d=1;d<=4;d++)
				var/cdir = GLOB.cardinal[d]
				for(var/i=1;i<=ALERT_STATES.len;i++)
					if(dir_alerts[d] & (1<<(i-1)))
						add_overlay(new/icon(icon,"alert_[ALERT_STATES[i]]", dir=cdir))
	else
		icon_state = "door_open"
		if(prying)
			icon_state = "prying_open"
		if(blocked)
			add_overlay("welded_open")
	return

//These are playing merry hell on ZAS.  Sorry fellas :(

/obj/machinery/door/firedoor/border_only
/*
	icon = 'icons/obj/doors/edge_Doorfire.dmi'
	glass = 1 //There is a glass window so you can see through the door
			  //This is needed due to BYOND limitations in controlling visibility
	heat_proof = 1
	air_properties_vary_with_direction = 1

	CanPass(atom/movable/mover, turf/target)
		if(istype(mover) && mover.checkpass(PASSGLASS))
			return 1
		if(get_dir(loc, target) == dir) //Make sure looking at appropriate border
			return !density
		else
			return 1

	CheckExit(atom/movable/mover as mob|obj, turf/target as turf)
		if(istype(mover) && mover.checkpass(PASSGLASS))
			return 1
		if(get_dir(loc, target) == dir)
			return !density
		else
			return 1


	update_nearby_tiles(need_rebuild)
		if(!SSair) return 0

		var/turf/simulated/source = loc
		var/turf/simulated/destination = get_step(source,dir)

		update_heat_protection(loc)

		if(istype(source)) SSair.tiles_to_update += source
		if(istype(destination)) SSair.tiles_to_update += destination
		return 1
*/

/obj/machinery/door/firedoor/multi_tile
	icon = 'icons/obj/doors/DoorHazard2x1.dmi'
	width = 2
	open_sound = 'sound/machines/firewide1o.ogg'
	close_sound = 'sound/machines/firewide1c.ogg'

/obj/machinery/door/firedoor/glass
	name = "\improper Emergency Glass Shutter"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas. This one has a resilient glass window, allowing you to see the danger."
	icon = 'icons/obj/doors/DoorHazardGlass.dmi'
	icon_state = "door_open"
	glass = 1

#undef FIREDOOR_MAX_PRESSURE_DIFF
#undef FIREDOOR_MAX_TEMP
#undef FIREDOOR_MIN_TEMP

#undef FIREDOOR_ALERT_HOT
#undef FIREDOOR_ALERT_COLD
// Not used #undef FIREDOOR_ALERT_LOWPRESS


//Glass variation of the 2x1 firedoor
/obj/machinery/door/firedoor/multi_tile/glass
	icon = 'icons/obj/doors/DoorHazardGlass2x1.dmi'
	width = 2
	glass = 1
	open_sound = 'sound/machines/firewide1o.ogg'
	close_sound = 'sound/machines/firewide1c.ogg'

/obj/machinery/door/firedoor/border_only/can_pathfinding_exit(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir) || ..()

/obj/machinery/door/firedoor/border_only/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir) || ..()


/obj/machinery/door/firedoor/glass/hidden
	name = "\improper Emergency Shutter System"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas. This model fits flush with the walls, and has a panel in the floor for maintenance."
	icon = 'icons/obj/doors/DoorHazardHidden.dmi'
	plane = TURF_PLANE

/obj/machinery/door/firedoor/glass/hidden/open()
	. = ..()
	plane = TURF_PLANE

/obj/machinery/door/firedoor/glass/hidden/close()
	. = ..()
	plane = OBJ_PLANE

/obj/machinery/door/firedoor/glass/hidden/steel
	name = "\improper Emergency Shutter System"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas. This model fits flush with the walls, and has a panel in the floor for maintenance."
	icon = 'icons/obj/doors/DoorHazardHidden_steel.dmi'

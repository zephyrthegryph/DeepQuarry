// Updated version of old powerswitch by Atlantis
// Has better texture, and is now considered electronic device
// AI has ability to toggle it in 5 seconds
// Humans need 30 seconds (AI is faster when it comes to complex electronics)
// Used for advanced grid control (read: Substations)

/obj/machinery/power/breakerbox
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "Breaker Box"
	desc = "Large machine with heavy duty switching circuits used for advanced grid control."
	icon = 'icons/obj/power.dmi'
	icon_state = "bbox_off"
	//directwired = 0
	var/icon_state_on = "bbox_on"
	var/icon_state_off = "bbox_off"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	circuit = /obj/item/circuitboard/breakerbox
	var/on = 0
	var/busy = 0
	var/directions = list(1,2,4,8,5,6,9,10)
	var/RCon_tag = "NO_TAG"
	var/update_locked = 0

/obj/machinery/power/breakerbox/Destroy()
	for(var/obj/structure/cable/C in src.loc)
		C.breaker_box = null
		qdel(C)
	. = ..()
	for(var/datum/tgui_module/rcon/R in SStgui.all_uis)
		R.FindDevices()

/obj/machinery/power/breakerbox/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/power/breakerbox/activated
	icon_state = "bbox_on"

// Enabled on server startup. Used in substations to keep them in bypass mode.
/obj/machinery/power/breakerbox/activated/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/breakerbox/activated/LateInitialize()
	set_state(1)

/obj/machinery/power/breakerbox/examine(mob/user)
	. = ..()
	if(on)
		. += span_notice("It seems to be online.")
	else
		. += span_warning("It seems to be offline.")

/obj/machinery/power/breakerbox/attack_ai(mob/user)
	if(update_locked)
		to_chat(user, span_red("System locked. Please try again later."))
		return

	if(busy)
		to_chat(user, span_red("System is busy. Please wait until current operation is finished before changing power settings."))
		return

	busy = 1
	to_chat(user, span_green("Updating power settings..."))
	if(do_after(user, 5 SECONDS, target = src))
		set_state(!on)
		to_chat(user, span_green("Update Completed. New setting:[on ? "on": "off"]"))
		update_locked = 1
		spawn(600)
			update_locked = 0
	busy = 0


/obj/machinery/power/breakerbox/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/breakerbox_toggle,
		/datum/interaction/machine_item/breakerbox_use,
	)
	..()

/// Old attack_hand (never called ..()): reprogram the breaker box, gated on lock/busy state.
/datum/interaction/machine_hand/ungated/breakerbox_toggle
	id = "breakerbox_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_INTERACTION_REACH, \
		REQ_ON(PRED_TARGET, /obj/machinery/power/breakerbox/proc/breakerbox_not_locked, "system locked. please try again later"), \
		REQ_ON(PRED_TARGET, /obj/machinery/power/breakerbox/proc/breakerbox_not_busy, "system is busy. please wait until current operation is finished before changing power settings"))
	effect = /obj/machinery/power/breakerbox/proc/interaction_toggle

/obj/machinery/power/breakerbox/proc/breakerbox_not_locked(mob/actor, atom/target, obj/item/held)
	return !update_locked

/obj/machinery/power/breakerbox/proc/breakerbox_not_busy(mob/actor, atom/target, obj/item/held)
	return !busy

/obj/machinery/power/breakerbox/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	busy = 1
	for(var/mob/O in viewers(user))
		O.show_message(span_red(text("[user] started reprogramming [src]!")), 1)

	if(do_after(user, 5 SECONDS, target = src))
		set_state(!on)
		user.visible_message(\
		span_notice("[user.name] [on ? "enabled" : "disabled"] the breaker box!"),\
		span_notice("You [on ? "enabled" : "disabled"] the breaker box!"))
		update_locked = 1
		spawn(600)
			update_locked = 0
	busy = 0
	return TRUE

/**
 * Old attackby: a multitool renames the RCON tag, then regardless of item type the box
 * refuses maintenance while on, else tries a part replacement. Kept as one interaction
 * with the whole old body since the multitool branch isn't exclusive of the rest.
 */
/datum/interaction/machine_item/breakerbox_use
	id = "breakerbox_use"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/power/breakerbox/proc/interaction_use

/obj/machinery/power/breakerbox/proc/interaction_use(mob/user, obj/item/W, datum/interaction/interaction)
	if(W.has_tool_quality(TOOL_MULTITOOL))
		var/newtag = tgui_input_text(user, "Enter new RCON tag. Use \"NO_TAG\" to disable RCON or leave empty to cancel.", "SMES RCON system", "", MAX_NAME_LEN)
		if(newtag)
			RCon_tag = newtag
			to_chat(user, span_notice("You changed the RCON tag to: [newtag]"))
	if(on)
		to_chat(user, span_red("Disable the breaker before performing maintenance."))
		return TRUE
	default_part_replacement(user, W)
	return TRUE

/obj/machinery/power/breakerbox/proc/set_state(state)
	on = state
	if(on)
		icon_state = icon_state_on
		var/list/connection_dirs = list()
		for(var/direction in directions)
			for(var/obj/structure/cable/C in get_step(src,direction))
				if(C.d1 == turn(direction, 180) || C.d2 == turn(direction, 180))
					connection_dirs += direction
					break

		for(var/direction in connection_dirs)
			var/obj/structure/cable/C = new/obj/structure/cable(src.loc)
			C.d1 = 0
			C.d2 = direction
			C.icon_state = "[C.d1]-[C.d2]"
			C.breaker_box = src
			C.power_register()

	else
		icon_state = icon_state_off
		for(var/obj/structure/cable/C in src.loc)
			C.breaker_box = null
			qdel(C)

// Used by RCON to toggle the breaker box.
/obj/machinery/power/breakerbox/proc/auto_toggle()
	if(!update_locked)
		set_state(!on)
		update_locked = 1
		spawn(600)
			update_locked = 0

/obj/machinery/power/breakerbox/process()
	return PROCESS_KILL

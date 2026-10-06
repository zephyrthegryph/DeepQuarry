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
	var/icon_state_on = "bbox_on"
	var/icon_state_off = "bbox_off"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	circuit = /obj/item/circuitboard/breakerbox
	on = 0
	var/directions = list(1,2,4,8,5,6,9,10)
	var/RCon_tag = "NO_TAG"
	var/update_locked = 0

// the cables it switched go with it (an RCON console reads its breakers live, so it needs no rescan).
/obj/machinery/power/breakerbox/on_destroy(force)
	for(var/obj/structure/cable/C in src.loc)
		destroyed(C)
	..()

/obj/machinery/power/breakerbox/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/power/breakerbox/activated
	icon_state = "bbox_on"

CAPABILITIES(/obj/machinery/power/breakerbox/activated)
	after_init(0, then(PROC_REF(switch_on)))

// Enabled on server startup. Used in substations to keep them in bypass mode.
/// Switched on once the cables around it exist (substations start in bypass).
/obj/machinery/power/breakerbox/activated/proc/switch_on(datum/act/timer/A)
	set_breaker_on(1)

/obj/machinery/power/breakerbox/examine(mob/user)
	. = ..()
	if(on)
		. += span_notice("It seems to be online.")
	else
		. += span_warning("It seems to be offline.")

/// Old attack_ai: toggle the breaker remotely.
/obj/machinery/power/breakerbox/proc/breakerbox_silicon_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(update_locked)
		to_chat(user, span_red("System locked. Please try again later."))
		return TRUE

	if(task_busy(src))
		to_chat(user, span_red("System is busy. Please wait until current operation is finished before changing power settings."))
		return TRUE

	to_chat(user, span_green("Updating power settings..."))
	task_timed(user, 5 SECONDS, src, src, PROC_REF(toggle_done), list(user, FALSE), claims = TRUE)
	return TRUE

/obj/machinery/power/breakerbox/proc/unlock_updates()
	update_locked = 0

/obj/machinery/power/breakerbox/proc/toggle_done(mob/user, by_hand)
	set_breaker_on(!on)
	if(by_hand)
		act_message(user, null, MSG_SELF(span_notice("You [on ? "enabled" : "disabled"] the breaker box!")), \
			MSG_OTHERS(span_notice("[user.name] [on ? "enabled" : "disabled"] the breaker box!")))
	else
		to_chat(user, span_green("Update Completed. New setting:[on ? "on": "off"]"))
	update_locked = 1
	after(src, 60 SECONDS, PROC_REF(unlock_updates))

/obj/machinery/power/breakerbox/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_SILICON("Toggle", PROC_REF(breakerbox_silicon_toggle)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
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
	return !task_busy(src)

/obj/machinery/power/breakerbox/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	for(var/mob/O in viewers(user))
		O.show_message(span_red(text("[user] started reprogramming [src]!")), 1)

	task_timed(user, 5 SECONDS, src, src, PROC_REF(toggle_done), list(user, TRUE), claims = TRUE)
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
		var/newtag = rerun_ask(user, "k125", PROC_REF(interaction_use), args, /datum/om/prompt/text, message = "Enter new RCON tag. Use \"NO_TAG\" to disable RCON or leave empty to cancel.", title = "SMES RCON system", max_length = MAX_NAME_LEN)
		if(isnull(newtag))
			return
		if(newtag)
			RCon_tag = newtag
			to_chat(user, span_notice("You changed the RCON tag to: [newtag]"))
	if(on)
		to_chat(user, span_red("Disable the breaker before performing maintenance."))
		return TRUE
	default_part_replacement(user, W)
	return TRUE

/obj/machinery/power/breakerbox/proc/set_breaker_on(state)
	set_on(state)
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
			rel_set(C, nameof(C.breaker_box), src)
			C.power_register()

	else
		icon_state = icon_state_off
		for(var/obj/structure/cable/C in src.loc)
			rel_clear(C, nameof(C.breaker_box))
			destroyed(C)

// Used by RCON to toggle the breaker box.
/obj/machinery/power/breakerbox/proc/auto_toggle()
	if(!update_locked)
		set_breaker_on(!on)
		update_locked = 1
		after(src, 1 MINUTE, PROC_REF(unlock_updates))


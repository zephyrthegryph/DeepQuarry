TRACKED(/obj/machinery/power/breakerbox, update_locked)

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

MSG_DEF_SELF(breakerbox/locked, "system locked. please try again later")
MSG_DEF_SELF(breakerbox/busy, "system is busy. please wait until current operation is finished before changing power settings")

MSG_DEF_SELF(breakerbox/needs_item, "needs an item")

CAPABILITIES(/obj/machinery/power/breakerbox)
	op("breakerbox_toggle", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Toggle"), needs(req(PROC_REF(breakerbox_unlocked), because = MSG(breakerbox/locked))), claims(), starts(PROC_REF(hand_toggle_started)), wait(5 SECONDS), then(PROC_REF(interaction_toggle)))
	op("breakerbox_silicon_toggle", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), needs(req(PROC_REF(breakerbox_unlocked), because = MSG(breakerbox/locked))), claims(), starts(PROC_REF(remote_toggle_started)), wait(5 SECONDS), then(PROC_REF(breakerbox_silicon_toggle)))
	op("breakerbox_use", inputs(item(/obj/item), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(/obj/item, because = MSG(breakerbox/needs_item)), req_adjacent(), req_capable()), asks(/datum/prompt/text, fields = list("question" = "Enter new RCON tag. Use \"NO_TAG\" to disable RCON or leave empty to cancel.", "title" = "SMES RCON system", "max_len" = MAX_NAME_LEN, "name_text" = TRUE), when = PROC_REF(breakerbox_multitool)), then(PROC_REF(interaction_use)))
	default_parts()

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

/obj/machinery/power/breakerbox/proc/remote_toggle_started(datum/act/op/A)
	to_chat(A.actor, span_green("Updating power settings..."))
	return OP_OK

/obj/machinery/power/breakerbox/proc/breakerbox_silicon_toggle(datum/act/op/A)
	toggle_done(A.actor, FALSE)
	return OP_OK

/obj/machinery/power/breakerbox/proc/unlock_updates()
	set_update_locked(0)

/obj/machinery/power/breakerbox/proc/toggle_done(mob/user, by_hand)
	set_breaker_on(!on)
	if(by_hand)
		act_message(user, null, MSG_SELF(span_notice("You [on ? "enabled" : "disabled"] the breaker box!")), \
			MSG_OTHERS(span_notice("[user.name] [on ? "enabled" : "disabled"] the breaker box!")))
	else
		to_chat(user, span_green("Update Completed. New setting:[on ? "on": "off"]"))
	set_update_locked(1)
	after(src, 60 SECONDS, PROC_REF(unlock_updates))

/obj/machinery/power/breakerbox/proc/breakerbox_not_locked(mob/actor, atom/target, obj/item/held)
	return !update_locked

/obj/machinery/power/breakerbox/proc/hand_toggle_started(datum/act/op/A)
	for(var/mob/O in viewers(A.actor))
		O.show_message(span_red(text("[A.actor] started reprogramming [src]!")), 1)
	return OP_OK

/obj/machinery/power/breakerbox/proc/interaction_toggle(datum/act/op/A)
	toggle_done(A.actor, TRUE)
	return OP_OK

/**
 * Old attackby: a multitool renames the RCON tag, then regardless of item type the box
 * refuses maintenance while on, else tries a part replacement. Kept as one interaction
 * with the whole old body since the multitool branch isn't exclusive of the rest.
 */

/obj/machinery/power/breakerbox/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.has_tool_quality(TOOL_MULTITOOL))
		var/newtag = A.answer?.value
		if(isnull(newtag))
			return
		if(newtag)
			RCon_tag = newtag
			to_chat(user, span_notice("You changed the RCON tag to: [newtag]"))
	if(on)
		to_chat(user, span_red("Disable the breaker before performing maintenance."))
		return OP_OK
	default_part_replacement(user, W)
	return OP_OK

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
			C.set_d1(0)
			C.set_d2(direction)
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
		set_update_locked(1)
		after(src, 1 MINUTE, PROC_REF(unlock_updates))


/obj/machinery/power/breakerbox/proc/breakerbox_unlocked(datum/act/op/A)
	return !update_locked

/obj/machinery/power/breakerbox/proc/breakerbox_multitool(datum/act/op/A)
	return A.held?.has_tool_quality(TOOL_MULTITOOL)

/// A RIG's five wires, every suit its own colours.
/datum/wire_set/rig
	name = "Unknown"
	count = 5
	randomize = TRUE
	wires = list(WIRE_RIG_SECURITY, WIRE_RIG_AI_OVERRIDE, WIRE_RIG_SYSTEM_CONTROL, WIRE_RIG_INTERFACE_LOCK, WIRE_RIG_INTERFACE_SHOCK)
/*
 * Rig security can be snipped to disable ID access checks on rig.
 * Rig AI override can be pulsed to toggle whether or not the AI can take control of the suit.
 * System control can be pulsed to toggle some malfunctions.
 * Interface lock can be pulsed to toggle whether or not the interface can be accessed.
 */

/// The security wire mended puts the suit's access back as built.
/obj/item/rig/proc/security_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		req_access = initial(req_access)
		req_one_access = initial(req_one_access)

/obj/item/rig/proc/security_wire_pulsed(datum/act/A)
	security_check_enabled = !security_check_enabled
	visible_message("\The [src] twitches as several suit locks [security_check_enabled?"close":"open"].")

/obj/item/rig/proc/ai_override_wire_pulsed(datum/act/A)
	ai_override_enabled = !ai_override_enabled
	visible_message("A small red light on [src] [ai_override_enabled?"goes dead":"flickers on"].")

/obj/item/rig/proc/system_wire_pulsed(datum/act/A)
	var/datum/notice/wire_pulsed/N = A
	malfunctioning += 10
	if(malfunction_delay <= 0)
		malfunction_delay = 20
	shock(N.user, 100)

/obj/item/rig/proc/interface_lock_wire_pulsed(datum/act/A)
	interface_locked = !interface_locked
	visible_message("\The [src] clicks audibly as the software interface [interface_locked?"darkens":"brightens"].")

/// The shock wire cut electrifies the interface until mended; either way it may shock the hand.
/obj/item/rig/proc/shock_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	electrified = N.mended ? 0 : -1
	shock(N.user, 100)

/obj/item/rig/proc/shock_wire_pulsed(datum/act/A)
	var/datum/notice/wire_pulsed/N = A
	if(electrified != -1)
		electrified = 30
	shock(N.user, 100)

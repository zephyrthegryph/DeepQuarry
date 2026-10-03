/obj/machinery/computer
	name = "computer"
	icon = 'icons/obj/computer.dmi'
	icon_state = "computer"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 300
	active_power_usage = 300
	blocks_emissive = EMISSIVE_BLOCK_NONE
	var/processing = 0

	var/icon_keyboard = "generic_key"
	var/icon_screen = "generic"
	var/light_range_on = 2
	var/light_power_on = 1

	clicksound = SFX_KEYBOARD
	integrity_failure = 0.5

/// A console is a MEMBER relation of the area it stands in (role POWER_ROLE_COMPUTER): an APC overload reads them
/// through area_members(area, POWER_ROLE_COMPUTER). The membership follows the console into another area.
/obj/machinery/computer/capabilities()
	. = ..()
	. += legacy_powered_by(POWERED_BY_AREA, role = POWER_ROLE_COMPUTER)

CAPABILITIES(/obj/machinery/computer)
	climb()

/obj/machinery/computer/Initialize(mapload)
	. = ..()
	power_change()
	update_icon()

DAMAGE_REACTION(/obj/machinery/computer, DAMAGE_EMP, PROC_REF(computer_emp))
/// An EMP may break the computer.
/obj/machinery/computer/proc/computer_emp(datum/damage_packet/packet)
	if(prob(20/packet.severity))
		atom_break()

DAMAGE_REACTION(/obj/machinery/computer, DAMAGE_BLOB, PROC_REF(computer_blob))
/// A blob hits a computer like a medium blast.
/obj/machinery/computer/proc/computer_blob(datum/damage_packet/packet)
	ex_act(2)
	return DAMAGE_REACTION_BLOCK

DECLARE_APPEARANCE_PROC(/obj/machinery/computer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/computer/appearance_overlays()
	. = list()

	. = list()

	// Connecty
	if(initial(icon_state) == "computer")
		var/append_string = ""
		var/left = turn(dir, 90)
		var/right = turn(dir, -90)
		var/turf/L = get_step(src, left)
		var/turf/R = get_step(src, right)
		var/obj/machinery/computer/LC = locate_on(L, /obj/machinery/computer)
		var/obj/machinery/computer/RC = locate_on(R, /obj/machinery/computer)
		if(LC && LC.dir == dir && initial(LC.icon_state) == "computer")
			append_string += "_L"
		if(RC && RC.dir == dir && initial(RC.icon_state) == "computer")
			append_string += "_R"
		icon_state = "computer[append_string]"

	if(icon_keyboard)
		if(has_stat(NOPOWER))
			play_sfx(src, SFX_MACHINES_TERMINAL_OFF)
			. += "[icon_keyboard]_off"
			return .
		. += icon_keyboard

	// This whole block lets screens ignore lighting and be visible even in the darkest room
	var/overlay_state = icon_screen
	if(has_stat(BROKEN))
		overlay_state = "[icon_state]_broken"

	. += mutable_appearance(icon, overlay_state)
	. += emissive_appearance(icon, overlay_state)
	play_sfx(src, SFX_MACHINES_TERMINAL_ON)


/obj/machinery/computer/power_change()
	. = ..()
	if(has_stat(NOPOWER))
		set_light(0)
	else
		set_light(light_range_on, light_power_on)

/obj/machinery/computer/proc/decode(text)
	// Adds line breaks
	text = replacetext(text, "\n", "<BR>")
	return text

/obj/machinery/computer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/computer_gripper,
		/datum/interaction/machine_item/computer_use_item,
	)
	..()

/// Behold, Grippers and their horribleness.
/datum/interaction/machine_item/computer_gripper
	id = "computer_gripper"
	name = "Use with gripper"
	held_type = /obj/item/gripper
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/computer/proc/can_use_gripper))
	effect = /obj/machinery/computer/proc/interaction_gripper

/// Requirement: the gripper has to be holding something.
/obj/machinery/computer/proc/can_use_gripper(mob/user, atom/target, obj/item/gripper/B)
	if(istype(B) && !B.get_wrapped_item())
		return "[B] is not holding anything"
	return TRUE

/obj/machinery/computer/proc/interaction_gripper(mob/user, obj/item/gripper/B, datum/interaction/interaction)
	var/B_held = B.get_wrapped_item()
	to_chat(user, "You use \the [B] to use \the [B_held] with \the [src].")
	playsound(src, clicksound, 100, 1, 0)
	return TRUE

/// Old attackby's fallback: any other item just triggers the hand entry.
/datum/interaction/machine_item/computer_use_item
	id = "computer_use_item"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/computer/proc/interaction_use_item

/obj/machinery/computer/proc/interaction_use_item(mob/user, obj/item/held, datum/interaction/interaction)
	attack_hand(user)
	return TRUE

/obj/machinery/computer/screwdriver_act(mob/user, obj/item/tool)
	return deconstruct_display(user, tool)

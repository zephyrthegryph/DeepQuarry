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

	clicksound = "keyboard"
	integrity_failure = 0.5

/obj/machinery/computer/Initialize(mapload)
	. = ..()
	power_change()
	update_icon()
	AddElement(/datum/element/climbable)

/obj/machinery/computer/process()
	return PROCESS_KILL

/obj/machinery/computer/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(prob(20/severity))
		atom_break()

/obj/machinery/computer/blob_act()
	ex_act(2)

/obj/machinery/computer/update_icon()
	cut_overlays()

	. = list()

	// Connecty
	if(initial(icon_state) == "computer")
		var/append_string = ""
		var/left = turn(dir, 90)
		var/right = turn(dir, -90)
		var/turf/L = get_step(src, left)
		var/turf/R = get_step(src, right)
		var/obj/machinery/computer/LC = locate() in L
		var/obj/machinery/computer/RC = locate() in R
		if(LC && LC.dir == dir && initial(LC.icon_state) == "computer")
			append_string += "_L"
		if(RC && RC.dir == dir && initial(RC.icon_state) == "computer")
			append_string += "_R"
		icon_state = "computer[append_string]"

	if(icon_keyboard)
		if(stat & NOPOWER)
			playsound(src, 'sound/machines/terminal_off.ogg', 50, 1)
			return add_overlay("[icon_keyboard]_off")
		. += icon_keyboard

	// This whole block lets screens ignore lighting and be visible even in the darkest room
	var/overlay_state = icon_screen
	if(stat & BROKEN)
		overlay_state = "[icon_state]_broken"

	. += mutable_appearance(icon, overlay_state)
	. += emissive_appearance(icon, overlay_state)
	playsound(src, 'sound/machines/terminal_on.ogg', 50, 1)

	add_overlay(.)

/obj/machinery/computer/power_change()
	..()
	update_icon()
	if(stat & NOPOWER)
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
	effect = /obj/machinery/computer/proc/interaction_gripper

/obj/machinery/computer/proc/interaction_gripper(mob/user, obj/item/gripper/B, datum/interaction/interaction)
	var/obj/item/wrapped = B.get_wrapped_item()
	if(!wrapped)
		to_chat(user, "\The [B] is not holding anything.")
		return TRUE
	var/B_held = wrapped
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

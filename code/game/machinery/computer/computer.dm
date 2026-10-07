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
TRACKED(/obj/machinery/computer, icon_screen)

MSG_DEF(computer/gripper_use, "You use the gripper's tool with %T%.", "")
MSG_DEF_SELF(computer/gripper_empty, "The gripper is not holding anything.")

// A console (doc/rewrite/final_api.html, sections 5, 6, 11, 13): a member of the console registry (an APC's overload finds the consoles of
// its area there), drawn as its desk, keyboard and screen (the screen glows and lights the room while it has power), a pulse may break it
// (one time in five over severity), a blob hits it as a medium blast, a screwdriver disconnects the monitor into a frame with its board (a
// broken one drops its glass), and any other item is the hand's use of it.
CAPABILITIES(/obj/machinery/computer)
	membership(joins = REGISTRY_COMPUTERS)
	climb()
	on_notice(/datum/notice/hit/emp, then(PROC_REF(computer_emp)))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(computer_blob))))
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(screen_sound)))
	op("disconnect", tool(TOOL_SCREWDRIVER), when(nameof(circuit)), wait(2 SECONDS), then(PROC_REF(disconnected)))
	op("use_gripper", item(/obj/item/gripper), needs(req(PROC_REF(gripper_holds), because = MSG(computer/gripper_empty))), says(MSG(computer/gripper_use)), then(PROC_REF(gripper_used)))
	op("use_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT), then(PROC_REF(used_as_hand)))

/// The consoles standing in area `A` (an APC's overload): the registry's members there.
/proc/area_consoles(area/A)
	. = list()
	if(!A)
		return
	for(var/obj/machinery/computer/C as anything in REGISTRY_MEMBERS(REGISTRY_COMPUTERS))
		if(get_area(C) == A)
			. += C

/// A pulse may break the console: one time in five, over the pulse's severity.
/obj/machinery/computer/proc/computer_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	if(prob(20 / max(N.packet?.severity, 1)))
		atom_break()

/// A blob hits a console as a medium blast instead of a blunt blow.
/obj/machinery/computer/proc/computer_blob(datum/act/A)
	ex_act(2)
	return OP_OK

/// The terminal sounds as the console comes on or goes off.
/obj/machinery/computer/proc/screen_sound(datum/act/A)
	play_sfx(src, stat_value(src, STAT_OPERABLE) ? SFX_MACHINES_TERMINAL_ON : SFX_MACHINES_TERMINAL_OFF)

/// The desk (joined with a neighbour facing the same way), the keyboard, and the screen that glows and lights the room while it has power.
/obj/machinery/computer/draw(datum/look/look)
	..()
	if(initial(icon_state) == "computer")
		look.state("computer[desk_joins()]")
	if(icon_keyboard && power_lost())
		look.overlay("[icon_keyboard]_off")
		return
	look.overlay(icon_keyboard)
	look.glow(broken_now() ? "[initial(icon_state)]_broken" : screen_state())
	look.light(light_range_on, light_power_on)

/// The screen the console shows now (a type with screens of its own overrides it).
/obj/machinery/computer/proc/screen_state()
	return icon_screen

/// "_L", "_R" or both for a console with a plain desk on that side facing the same way.
/obj/machinery/computer/proc/desk_joins()
	. = ""
	var/obj/machinery/computer/LC = locate_on(get_step(src, turn(dir, 90)), /obj/machinery/computer)
	var/obj/machinery/computer/RC = locate_on(get_step(src, turn(dir, -90)), /obj/machinery/computer)
	if(LC && LC.dir == dir && initial(LC.icon_state) == "computer")
		. += "_L"
	if(RC && RC.dir == dir && initial(RC.icon_state) == "computer")
		. += "_R"

/// A question a console asked is still worth answering: the console stands and the person is next to it (a silicon works from anywhere).
/obj/machinery/computer/proc/request_usable(datum/request/R)
	var/mob/M = R.answerer
	return istype(M) && !QDELETED(src) && (issilicon(M) || in_range(src, M))

/// needs: the gripper holds something to use on the console.
/obj/machinery/computer/proc/gripper_holds(datum/act/op/A)
	var/obj/item/gripper/G = A.held
	return istype(G) && !!G.get_wrapped_item()

/obj/machinery/computer/proc/gripper_used(datum/act/op/A)
	playsound(src, clicksound, 100, 1, 0)
	return OP_OK

/// Any other item on the console is the hand's use of it.
/obj/machinery/computer/proc/used_as_hand(datum/act/op/A)
	attack_hand(A.actor)
	return OP_OK

/// The monitor disconnected: the console becomes a frame with its board (a broken one drops its glass).
/obj/machinery/computer/proc/disconnected(datum/act/op/A)
	if(broken_now())
		to_chat(A.actor, span_notice("The broken glass falls out."))
		new /obj/item/material/shard(loc)
	else
		to_chat(A.actor, span_notice("You disconnect the monitor."))
	dismantle()
	return OP_OK

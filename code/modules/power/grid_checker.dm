/obj/machinery/power/grid_checker
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "grid checker"
	desc = "A machine that reacts to unstable conditions in the powernet, by safely shutting everything down.  Probably better \
	than the alternative."
	icon_state = "gridchecker_on"
	circuit = /obj/item/circuitboard/grid_checker
	density = TRUE
	anchored = TRUE
	var/power_failing = FALSE // Turns to TRUE when the grid check event is fired by the Game Master, or perhaps a cheeky antag.
	// Wire stuff below.
	var/wire_locked_out = FALSE
	var/wire_allow_manual_1 = FALSE
	var/wire_allow_manual_2 = FALSE
	var/wire_allow_manual_3 = FALSE
	var/opened = FALSE

/obj/machinery/power/grid_checker/Initialize(mapload)
	. = ..()
	connect_to_network()
	update_icon()
	set_wires(new /datum/wires/grid_checker(src))
	default_apply_parts()

/obj/machinery/power/grid_checker/Destroy()
	qdel(wires)
	wires = null
	return ..()

/obj/machinery/power/grid_checker/update_icon()
	if(power_failing)
		icon_state = "gridchecker_off"
		set_light(2, 2, "#F86060")
	else
		icon_state = "gridchecker_on"
		set_light(2, 2, "#A8B0F8")

/obj/machinery/power/grid_checker/screwdriver_act(mob/user, obj/item/W)
	var/result = ..()
	if(ITEM_INTERACT_CONSUMED(result))
		opened = panel_open
	return result

/obj/machinery/power/grid_checker/crowbar_act(mob/user, obj/item/W)
	return ..()

/obj/machinery/power/grid_checker/multitool_act(mob/user, obj/item/W)
	attack_hand(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/grid_checker/wirecutter_act(mob/user, obj/item/W)
	attack_hand(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/grid_checker/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/grid_checker_use,
	)
	..()

/datum/interaction/machine_hand/ungated/grid_checker_use
	id = "grid_checker_use"
	name = "Use"
	effect = /obj/machinery/power/grid_checker/proc/interaction_grid_checker_use

/obj/machinery/power/grid_checker/proc/interaction_grid_checker_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user)
		return TRUE
	add_fingerprint(user)
	interact(user)
	return TRUE

/obj/machinery/power/grid_checker/interact(mob/user)
	if(!user)
		return

	if(opened)
		wires.Interact(user)

	return tgui_interact(user)

/obj/machinery/power/grid_checker/proc/power_failure(announce = TRUE)
	if(announce)
		GLOB.command_announcement.Announce("Abnormal activity detected in [station_name()]'s powernet. As a precautionary measure, \
		the station's power will be shut off for an indeterminate duration while the powernet monitor restarts automatically, or \
		when Engineering can manually resolve the issue.",
		"Critical Power Failure",
		new_sound = ANNOUNCER_MSG_POWER_OFF)
	power_failing = TRUE
	if(powernet)
		for(var/obj/machinery/power/terminal/T in powernet.nodes) // APCs that are "downstream" of the powernet.

			if(istype(T.master, /obj/machinery/power/apc))
				var/obj/machinery/power/apc/A = T.master
				if(A.is_critical)
					continue
				A.do_grid_check()

		for(var/obj/machinery/power/smes/smes in powernet.nodes) // These are "upstream"
			smes.do_grid_check()

	update_icon()

	spawn(rand(4 MINUTES, 10 MINUTES) )
		if(power_failing) // Check to see if engineering didn't beat us to it.
			end_power_failure(TRUE)

/obj/machinery/power/grid_checker/proc/end_power_failure(announce = TRUE)
	if(announce)
		GLOB.command_announcement.Announce("Power has been restored to [station_name()]. We apologize for the inconvenience.",
		"Power Systems Nominal",
		new_sound = ANNOUNCER_MSG_POWER_ON)
	power_failing = FALSE
	update_icon()

	for(var/obj/machinery/power/terminal/T in powernet.nodes)
		if(istype(T.master, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = T.master
			if(A.is_critical)
				continue
			A.grid_check = FALSE

	for(var/obj/machinery/power/smes/smes in powernet.nodes) // These are "upstream"
		smes.grid_check = FALSE

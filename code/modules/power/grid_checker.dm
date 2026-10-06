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
TRACKED(/obj/machinery/power/grid_checker, power_failing)

/obj/machinery/power/grid_checker/Initialize(mapload)
	. = ..()
	default_apply_parts()

/// `connect_to_network()` needs `vg_entity` bound, which only happens once
/// `on_materialize()`'s `vg_bind()` runs -- see the base class override's
/// docs (`code/modules/power/power.dm`).
/obj/machinery/power/grid_checker/on_materialize()
	. = ..()
	connect_to_network()

/obj/machinery/power/grid_checker/draw(datum/look/look)
	..()
	if(power_failing)
		look.state("gridchecker_off")
		look.light(2, 2, "#F86060")
	else
		look.state("gridchecker_on")
		look.light(2, 2, "#A8B0F8")

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
		wires_open(src, user)

	return tgui_interact(user)

/obj/machinery/power/grid_checker/proc/power_failure(announce = TRUE)
	if(announce)
		GLOB.command_announcement.Announce("Abnormal activity detected in [station_name()]'s powernet. As a precautionary measure, \
		the station's power will be shut off for an indeterminate duration while the powernet monitor restarts automatically, or \
		when Engineering can manually resolve the issue.",
		"Critical Power Failure",
		new_sound = ANNOUNCER_MSG_POWER_OFF)
	set_power_failing(TRUE)
	if(power_region)
		for(var/obj/machinery/power/terminal/T in power_grid_nodes(power_region)) // APCs that are "downstream" of the grid.

			if(istype(T.master(), /obj/machinery/power/apc))
				var/obj/machinery/power/apc/A = T.master()
				if(A.is_critical)
					continue
				A.do_grid_check()

		for(var/obj/machinery/power/smes/smes in power_grid_nodes(power_region)) // These are "upstream"
			smes.do_grid_check()


	after(src, rand(4 MINUTES, 10 MINUTES), PROC_REF(power_failure_times_out))

/obj/machinery/power/grid_checker/proc/end_power_failure(announce = TRUE)
	if(announce)
		GLOB.command_announcement.Announce("Power has been restored to [station_name()]. We apologize for the inconvenience.",
		"Power Systems Nominal",
		new_sound = ANNOUNCER_MSG_POWER_ON)
	set_power_failing(FALSE)

	for(var/obj/machinery/power/terminal/T in power_grid_nodes(power_region))
		if(istype(T.master(), /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = T.master()
			if(A.is_critical)
				continue
			A.set_grid_check(FALSE)

	for(var/obj/machinery/power/smes/smes in power_grid_nodes(power_region)) // These are "upstream"
		smes.set_grid_check(FALSE)

/obj/machinery/power/grid_checker/proc/power_failure_times_out()
	if(power_failing) // Check to see if engineering didn't beat us to it.
		end_power_failure(TRUE)

/// The lockout a pulsed wire imposed is over.
/obj/machinery/power/grid_checker/proc/end_wire_lockout()
	wire_locked_out = FALSE

// ---- the wires ----

CAPABILITIES(/obj/machinery/power/grid_checker)
	space(SPACE_PANEL, door = nameof(opened))
	wires(name = "Grid Checker", count = 8, tools = FALSE, status_lines = PROC_REF(wire_lights))
	on_wire(WIRE_REBOOT, pulse = PROC_REF(reboot_wire_pulsed))
	on_wire(WIRE_LOCKOUT, cut = PROC_REF(lockout_wire_cut), pulse = PROC_REF(lockout_wire_pulsed))
	on_wire(WIRE_ALLOW_MANUAL1, cut = PROC_REF(manual_wire_cut))
	on_wire(WIRE_ALLOW_MANUAL2, cut = PROC_REF(manual_wire_cut))
	on_wire(WIRE_ALLOW_MANUAL3, cut = PROC_REF(manual_wire_cut))
	on_wire(WIRE_ELECTRIFY, cut = PROC_REF(shock_wire_touched), pulse = PROC_REF(shock_wire_touched))


/obj/machinery/power/grid_checker/proc/wire_lights()
	return list(
		"The green light is [power_failing ? "off." : "on."]",
		"The red light is [wire_locked_out ? "on." : "off."]",
		"The blue light is [(wire_allow_manual_1 && wire_allow_manual_2 && wire_allow_manual_3) ? "on." : "off."]")

/// The reboot wire pulsed ends a power failure, when the three manual wires allow it and nothing locks it out.
/obj/machinery/power/grid_checker/proc/reboot_wire_pulsed(datum/act/A)
	if(wire_locked_out)
		return
	if(power_failing && wire_allow_manual_1 && wire_allow_manual_2 && wire_allow_manual_3)
		end_power_failure(TRUE)

/obj/machinery/power/grid_checker/proc/lockout_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	wire_locked_out = !N.mended

/// The lockout wire pulsed locks the checker out for thirty seconds.
/obj/machinery/power/grid_checker/proc/lockout_wire_pulsed(datum/act/A)
	if(wire_locked_out)
		return
	wire_locked_out = TRUE
	after(src, 30 SECONDS, PROC_REF(end_wire_lockout))

/// A manual wire cut allows a manual reboot; mended, it does not.
/obj/machinery/power/grid_checker/proc/manual_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	switch(N.wire)
		if(WIRE_ALLOW_MANUAL1)
			wire_allow_manual_1 = !N.mended
		if(WIRE_ALLOW_MANUAL2)
			wire_allow_manual_2 = !N.mended
		if(WIRE_ALLOW_MANUAL3)
			wire_allow_manual_3 = !N.mended

/// The shock wire, cut, mended or pulsed, may shock the hand on it (unless the checker is locked out).
/obj/machinery/power/grid_checker/proc/shock_wire_touched(datum/act/A)
	if(wire_locked_out)
		return
	var/datum/notice/wire_pulsed/P = A
	var/datum/notice/wire_cut/C = A
	shock(istype(P) ? P.user : C.user, 70)

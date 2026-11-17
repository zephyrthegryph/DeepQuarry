// The ice machine: a table-top chiller that turns the water in a container into ice (the ice reagent and the phase change: code/domains/world_model/reagents/freezing.dm).
//
// Stand a container of water in it and switch it on. While it runs it draws ICE_MACHINE_POWER watts and its coil takes ICE_MACHINE_COOLING watts of heat out of the container
// each second (never below ICE_MACHINE_TEMP): the water chills to 0 C and then, as heat keeps leaving, freezes unit by unit, each unit giving its latent heat to the container
// for the coil to take out again (the heat system, add_heat()). It switches itself off when the contents are ice at the setpoint and no water is left. Ice comes out of the
// machine in its container: put it in a bath (code/content/reagents/purification/nesting.dm) to chill a small container to 0 C and keep it there until the ice is gone.
// It chills nothing without power. Everything it does is written to the world log under GLOB.chem_trace.

/obj/machinery/chem_ice_machine
	name = "ice machine"
	desc = "A small bench-top chiller. Stand a container of water in it, switch it on and it makes ice."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "icecream_vat"
	density = FALSE
	anchored = FALSE
	layer = ABOVE_WINDOW_LAYER
	use_power = USE_POWER_IDLE
	circuit = VARIANT(/obj/item/circuitboard/chem_ice_machine)
	/// The coil is running.
	var/running = FALSE
	/// The container standing in the machine.
	var/obj/item/reagent_containers/glass/held_container

	var/static/radial_use = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_use")
	var/static/radial_remove = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject_input")

CAPABILITIES(/obj/machinery/chem_ice_machine)
	tabletop(carry = TRUE)
	configure(machine_rules(maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE))
	configure(movable_motion(unacidable = TRUE))
	configure(uses_power(idle = 5, active = ICE_MACHINE_POWER))
	owns_one(nameof(held_container), /obj/item/reagent_containers/glass)
	default_parts()
	started_work(step = PROC_REF(work_step), interval = 1 SECONDS, starts = TRUE, gate = PROC_REF(step_needed), wakes_on = list(nameof(running), nameof(held_container)), gate_waits = TRUE)
	op("place_container", item(/obj/item/reagent_containers/glass), label("Stand it in the machine"), needs(req(PROC_REF(machine_free))), then(PROC_REF(container_placed)))
	op("ice_machine_radial", hand(), ungated(), label("Use"),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(radial_choices)), "radial" = TRUE, "autopick_single_option" = FALSE, "timeout" = 0), step = "choice"),
		then(PROC_REF(radial_chosen)))

MSG_DEF_SELF(ice_machine/occupied, "There is a container in the machine already.")

/obj/machinery/chem_ice_machine/proc/machine_free(datum/act/op/A)
	return held_container ? MSG(ice_machine/occupied) : null

/obj/machinery/chem_ice_machine/proc/radial_choices(datum/act/op/A)
	var/list/options = list()
	options["switch"] = radial_use
	if(held_container)
		options["remove"] = radial_remove
	return options

/obj/machinery/chem_ice_machine/proc/container_placed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/C = A.held
	if(!move_into(src, nameof(src.held_container), C, user))
		return OP_OK
	update_readout()
	to_chat(user, span_notice("You stand \the [C] in \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] stood [C] ([C.reagents?.get_reagents()]) in [src] at [round(C.get_temperature() - T0C, 0.1)] C")
	return OP_OK

/obj/machinery/chem_ice_machine/proc/radial_chosen(datum/act/op/A)
	var/mob/user = A.actor
	switch(A.step_value("choice"))
		if("switch")
			switch_coil(user, !running)
		if("remove")
			remove_container(user)
	return OP_OK

/// Switches the coil on or off.
/obj/machinery/chem_ice_machine/proc/switch_coil(mob/user, on)
	if(on && !operable())
		to_chat(user, span_notice("Nothing happens."))
		return
	set_running(on)
	set_use_power(on ? USE_POWER_ACTIVE : USE_POWER_IDLE)
	if(user)
		to_chat(user, span_notice("You switch \the [src] [on ? "on" : "off"]."))
	update_readout()
	if(GLOB.chem_trace)
		log_world("CHEM: [src] switched [on ? "on" : "off"]")

/// The container comes out of the machine into the hand.
/obj/machinery/chem_ice_machine/proc/remove_container(mob/user)
	var/obj/item/reagent_containers/glass/C = held_container
	if(!C)
		return
	C.forceMove(get_turf(src))
	rel_take(src, nameof(held_container))
	update_readout()
	user?.put_in_hands(C)
	to_chat(user, span_notice("You take \the [C] out of \the [src]."))

/// One second of the coil (started_work): see chill_step().
/obj/machinery/chem_ice_machine/proc/work_step(datum/act/timer/A)
	chill_step(A.dt / (1 SECONDS))

/// The machine has something to do each second: the coil is running, or a container in it is away from room temperature and its readout is live.
/obj/machinery/chem_ice_machine/proc/step_needed()
	return running || container_off_room()

/obj/machinery/chem_ice_machine/proc/container_off_room()
	return !isnull(held_container) && abs(held_container.get_temperature() - get_temperature()) > HOT_PLATE_ROOM_TOLERANCE

/// The units of ice in the machine's container.
/obj/machinery/chem_ice_machine/proc/ice_made()
	return held_container?.reagents ? held_container.reagents.get_reagent_amount(REAGENT_ID_ICE) : 0

/// The live readout over the machine: the container's temperature and its ice, while the coil runs or the container is away from room temperature.
/obj/machinery/chem_ice_machine/proc/update_readout()
	var/text = ""
	if(running || container_off_room())
		var/shown = held_container ? "[round(held_container.get_temperature() - T0C)]C [round(ice_made())]u ice" : "--"
		text = "<span style='font-size:6px;color:[running ? "#80c0ff" : "#c0c0c0"];text-align:center;'>[shown]</span>"
	if(maptext != text)
		maptext = text
		maptext_width = 64
		maptext_x = -16
		maptext_y = 24

/// `seconds` of the coil: heat leaves the container at ICE_MACHINE_COOLING watts down to ICE_MACHINE_TEMP, the water in it freezes as the heat allows (its latent heat goes
/// back into the container and out through the coil again), and the machine stops by itself when the contents are ice at the setpoint. Chills nothing while it is off.
/obj/machinery/chem_ice_machine/proc/chill_step(seconds)
	update_readout()
	var/obj/item/reagent_containers/glass/C = held_container
	if(!running || !C)
		return
	var/current = C.get_temperature()
	if(current > ICE_MACHINE_TEMP + 0.25)
		var/list/properties = C.thermal_properties()
		var/joules = min(ICE_MACHINE_COOLING * seconds, (current - ICE_MACHINE_TEMP) * properties[THERMAL_CAPACITY])
		C.add_heat(-joules)
	if(C.reagents?.total_volume)
		C.reagents.handle_reactions() // the water below 0 C freezes (phase_step), and what reacts cold reacts
	update_readout()
	if(!C.reagents?.get_reagent_amount(REAGENT_ID_WATER) && C.get_temperature() <= ICE_MACHINE_TEMP + 0.5)
		if(GLOB.chem_trace)
			log_world("CHEM: [src] finished: [round(ice_made(), 0.001)]u of ice in [C] at [round(C.get_temperature() - T0C, 0.1)] C")
		switch_coil(null, FALSE)

/obj/machinery/chem_ice_machine/examine(mob/user)
	. = ..()
	. += span_notice("The coil is [running ? "running" : "off"].")
	if(held_container)
		. += span_notice("\A [held_container] stands in it, at [round(held_container.get_temperature() - T0C, 0.1)] C, with [round(ice_made(), 0.1)] units of ice.")

/// The machine and what stands in it.
/obj/machinery/chem_ice_machine/draw(datum/look/look)
	..()
	look.state(initial(icon_state))
	if(held_container)
		look.watch(held_container)
		look.watch(held_container.reagents)
		look.overlay(image("icon" = held_container))

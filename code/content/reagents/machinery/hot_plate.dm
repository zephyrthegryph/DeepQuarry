// The hot plate: a table-top element that heats the container standing on it toward a dial setting (code/content/reagents/reactions/reaction_temperatures.dm
// says what each recipe needs; code/domains/world_model/reagents/boiling.dm says what boils).
//
// Put a beaker on it, set the dial (Celsius), switch it on. Each second it feeds the container's heat body up to HOT_PLATE_POWER joules, never past the setting
// (the container warms over seconds and cools on its own when the plate is off), draws its active power while the element is on, lets the container's reagents react at the new
// temperature and boils off what is above its boiling point. The vapour is collected by a condenser next to the plate (code/content/reagents/machinery/condenser.dm)
// or deleted. It heats nothing without power. Everything it does is written to the world log under GLOB.chem_trace.

/obj/machinery/chem_hot_plate
	name = "hot plate"
	desc = "A small electric hot plate for the lab bench. Stand a beaker on it, set the dial and switch it on."
	icon = 'icons/obj/device.dmi'
	icon_state = "bunsen0"
	density = FALSE
	anchored = FALSE
	layer = ABOVE_WINDOW_LAYER
	use_power = USE_POWER_IDLE
	circuit = VARIANT(/obj/item/circuitboard/chem_hot_plate)
	/// The temperature the dial is set to, K.
	var/target_temp = T0C + 60
	/// The element is on.
	var/heating = FALSE
	/// The container standing on the plate.
	var/obj/item/reagent_containers/glass/held_container

	var/static/radial_use = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_use")
	var/static/radial_adjust_temp = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_temp")
	var/static/radial_remove = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject_input")

CAPABILITIES(/obj/machinery/chem_hot_plate)
	configure(machine_rules(maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE))
	configure(movable_motion(unacidable = TRUE))
	configure(uses_power(idle = 5, active = HOT_PLATE_POWER))
	owns_one(nameof(held_container), /obj/item/reagent_containers/glass)
	default_parts()
	started_work(step = PROC_REF(work_step), interval = 1 SECONDS, starts = TRUE, when = nameof(heating), wakes_on = list(nameof(heating)))
	op("place_container", item(/obj/item/reagent_containers/glass), label("Stand it on the plate"), needs(req(PROC_REF(plate_free))), then(PROC_REF(container_placed)))
	op("hot_plate_radial", hand(), ungated(), label("Use"),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(radial_choices)), "radial" = TRUE, "autopick_single_option" = FALSE, "timeout" = 0), step = "choice"),
		asks(/datum/prompt/number, fields = list("question" = "Set the dial (degrees Celsius).", "title" = "Temperature", "min_value" = 0, "max_value" = HOT_PLATE_MAX_TEMP - T0C, "default" = computed(PROC_REF(dial_celsius)), "timeout" = 0), step = "temp", when = PROC_REF(chose_set_temp)),
		then(PROC_REF(radial_chosen)))

MSG_DEF_SELF(hot_plate/occupied, "There is a container on the plate already.")

/obj/machinery/chem_hot_plate/proc/plate_free(datum/act/op/A)
	return held_container ? MSG(hot_plate/occupied) : null

/// The dial, in Celsius.
/obj/machinery/chem_hot_plate/proc/dial_celsius(datum/act/op/A)
	return round(target_temp - T0C)

/obj/machinery/chem_hot_plate/proc/radial_choices(datum/act/op/A)
	var/list/options = list()
	options["switch"] = radial_use
	options["dial"] = radial_adjust_temp
	if(held_container)
		options["remove"] = radial_remove
	return options

/// The dial question follows the radial when it was chosen.
/obj/machinery/chem_hot_plate/proc/chose_set_temp(datum/act/op/A)
	return A.step_value("choice") == "dial"

/obj/machinery/chem_hot_plate/proc/container_placed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/C = A.held
	if(!move_into(src, nameof(src.held_container), C, user))
		return OP_OK
	to_chat(user, span_notice("You stand \the [C] on \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] stood [C] ([C.reagents?.get_reagents()]) on [src] at [round(C.get_temperature() - T0C, 0.1)] C")
	return OP_OK

/obj/machinery/chem_hot_plate/proc/radial_chosen(datum/act/op/A)
	var/mob/user = A.actor
	switch(A.step_value("choice"))
		if("switch")
			switch_element(user, !heating)
		if("dial")
			var/celsius = A.step_value("temp")
			if(isnum(celsius))
				set_dial(clamp(celsius, 0, HOT_PLATE_MAX_TEMP - T0C) + T0C)
				to_chat(user, span_notice("You set the dial to [round(target_temp - T0C)] C."))
		if("remove")
			remove_container(user)
	return OP_OK

/// Sets the dial, K.
/obj/machinery/chem_hot_plate/proc/set_dial(kelvin)
	set_target_temp(clamp(kelvin, T0C, HOT_PLATE_MAX_TEMP))
	if(GLOB.chem_trace)
		log_world("CHEM: [src] dial set to [round(target_temp - T0C, 0.1)] C")

/// Switches the element on or off.
/obj/machinery/chem_hot_plate/proc/switch_element(mob/user, on)
	if(on && !operable())
		to_chat(user, span_notice("Nothing happens."))
		return
	set_heating(on)
	set_use_power(on ? USE_POWER_ACTIVE : USE_POWER_IDLE)
	if(user)
		to_chat(user, span_notice("You switch \the [src] [on ? "on" : "off"]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [src] switched [on ? "on" : "off"] (dial [round(target_temp - T0C, 0.1)] C)")

/// The container comes off the plate into the hand.
/obj/machinery/chem_hot_plate/proc/remove_container(mob/user)
	var/obj/item/reagent_containers/glass/C = held_container
	if(!C)
		return
	C.forceMove(get_turf(src))
	rel_take(src, nameof(held_container))
	user?.put_in_hands(C)
	to_chat(user, span_notice("You take \the [C] off \the [src]."))

/// One second of the element (started_work): see heat_step().
/obj/machinery/chem_hot_plate/proc/work_step(datum/act/timer/A)
	heat_step(A.dt / (1 SECONDS))

/// `seconds` of the element: heat the container up to the dial, let it react, boil it, hand the vapour on. Heats nothing while the element is off.
/obj/machinery/chem_hot_plate/proc/heat_step(seconds)
	var/obj/item/reagent_containers/glass/C = held_container
	if(!heating || !C)
		return
	var/current = C.get_temperature()
	var/target = clamp(target_temp, T0C, HOT_PLATE_MAX_TEMP)
	if(current < target - 0.25)
		var/list/properties = C.thermal_properties()
		var/joules = min(HOT_PLATE_POWER * seconds, (target - current) * properties[THERMAL_CAPACITY])
		C.add_heat(joules)
	if(!C.reagents?.total_volume)
		return
	C.reagents.handle_reactions() // the temperature moved: what could not react a second ago may now
	var/list/vapour = C.reagents.boil_step(seconds)
	if(length(vapour))
		vent_vapour(vapour)

/// The vapour of the boiling container: a condenser next to the plate collects what it can; the rest is gone (vapour is not simulated).
/obj/machinery/chem_hot_plate/proc/vent_vapour(list/vapour)
	for(var/direction in GLOB.alldirs + 0)
		var/turf/T = direction ? get_step(src, direction) : get_turf(src)
		if(!T)
			continue
		for(var/obj/machinery/chem_condenser/condenser in contents_of(T))
			if(condenser.collect(vapour))
				return
	if(GLOB.chem_trace)
		log_world("CHEM: [src] boiled off vapour with no condenser to catch it: it is deleted")

/obj/machinery/chem_hot_plate/examine(mob/user)
	. = ..()
	. += span_notice("The dial is set to [round(target_temp - T0C)] C and the element is [heating ? "on" : "off"].")
	if(held_container)
		. += span_notice("\A [held_container] stands on it, at [round(held_container.get_temperature() - T0C)] C.")

/// The plate, what stands on it, and the glow of the element while it is on.
/obj/machinery/chem_hot_plate/draw(datum/look/look)
	..()
	look.state("bunsen0")
	if(held_container)
		look.watch(held_container)
		look.watch(held_container.reagents)
		look.overlay(image("icon" = held_container))
	if(heating)
		look.overlay(image(icon, icon_state = "bunsen1", layer = initial(layer) + 0.1))

// A cooker is a heat source coupled to its contents (H3). Its temperature is
// its heat body's: heating_power watts while below optimal_temp (a
// thermostat), losing heat to the room through its casing. Its cooking
// containers and the food in them get heat bodies coupled to it, and the
// cooking rule (code/datums/rules/declarations.dm) decides when food is cooked.
/obj/machinery/appliance/cooker
	var/min_temp = 80 + T0C	//Minimum temperature to do any cooking
	var/optimal_temp = 200 + T0C	//Temperature at which we have 100% efficiency. efficiency is lowered on either side of this
	var/optimal_power = 0.6 //cooking power at 100% - This variable determines the MAXIMUM increase in do_cooking_ticks, once math goes through. If you want ticks of 0.5, set it to 0.5, etc.

	var/resistance = 1200	//Resistance to heating: with the process interval, the cooker's heat capacity (thermal_properties()).
	/// The heat source is on.
	var/tmp/heating = FALSE
	/// Heat watch that wakes a hibernating cooker when it cools.
	var/tmp/thermostat_watch

	var/light_x = 0
	var/light_y = 0
	cooking_coeff = 0
	cooking_power = 0
	mob_injury_kind = INJURY_BURN
	can_burn_food = TRUE

	tgui_id = "CookingAppliance"

/obj/machinery/appliance/cooker/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/temperature = get_temperature()
	data["temperature"] = round(temperature - T0C, 0.1)
	data["optimalTemp"] = round(optimal_temp - T0C, 0.1)
	data["temperatureEnough"] = temperature >= min_temp
	data["efficiency"] = round(get_efficiency(), 0.1)

	return data

/obj/machinery/appliance/cooker/examine(mob/user)
	. = ..()
	if(.)	//no need to duplicate adjacency check
		var/temperature = get_temperature()
		if(!stat)
			if (temperature < min_temp)
				. += span_warning("\The [src] is still heating up and is too cold to cook anything yet.")
			else
				. += span_notice("It is running at [round(get_efficiency(), 0.1)]% efficiency!")
			. += "Temperature: [round(temperature - T0C, 0.1)]C / [round(optimal_temp - T0C, 0.1)]C"
		else
			. += span_warning("It is switched off.")

/obj/machinery/appliance/cooker/list_contents(mob/user)
	if (cooking_objs.len)
		var/string = "Contains...</br>"
		var/num = 0
		for (var/a in cooking_objs)
			num++
			var/datum/cooking_item/CI = a
			if (CI && CI.container)
				string += "- [CI.container.label(num)], [report_progress(CI)]</br>"
		to_chat(user, string)
	else
		to_chat(user, span_notice("It's empty."))

/obj/machinery/appliance/cooker/proc/get_efficiency()
	// to_world("Our cooking_power is [cooking_power] and our efficiency is [(cooking_power / optimal_power) * 100].") // Debug lines, uncomment if you need to test.
	return (cooking_power / optimal_power) * 100

/obj/machinery/appliance/cooker/Initialize(mapload)
	. = ..()
	cooking_objs = list()
	for (var/i = 0, i < max_contents, i++)
		cooking_objs.Add(new /datum/cooking_item/(new container_type(src)))
	cooking = FALSE

	update_icon() // this probably won't cause issues, but Aurora used SSIcons and queue_icon_update() instead

/obj/machinery/appliance/cooker/update_icon()
	cut_overlays()
	var/image/light
	if(use_power == 1 && !stat)
		light = image(icon, "light_idle")
	else if(use_power == 2 && !stat)
		light = image(icon, "light_preheating")
	else
		light = image(icon, "light_off")
	light.pixel_x = light_x
	light.pixel_y = light_y
	add_overlay(light)

/obj/machinery/appliance/cooker/process()
	if (!stat)
		heat_up()
	else
		set_heating(FALSE)
		equalize_temperature()
	..()
	if(cooking)
		return
	if(!stat)
		// Idle at temperature: hibernate until it cools below the thermostat band.
		if(get_temperature() >= optimal_temp && arm_thermostat())
			return PROCESS_KILL
		return
	// Off and back at room temperature: its body has been released.
	if(isnull(heat_body))
		return PROCESS_KILL

/obj/machinery/appliance/cooker/power_change()
	. = ..()
	if(.)
		START_MACHINE_PROCESSING(src)
	update_icon() // this probably won't cause issues, but Aurora used SSIcons and queue_icon_update() instead

/obj/machinery/appliance/cooker/proc/update_cooking_power()
	var/temp_scale = 0
	var/temperature = get_temperature()
	if(temperature > min_temp)
		if(temperature >= optimal_temp) // If we're at or above optimal temp, then we're going to be at 1 for temp scale. No use penalizing you for the cookers increasing heat constantly (until we implement setting a temp on the oven via a menu.)
			temp_scale = 1
		else
			temp_scale = (temperature - min_temp) / (optimal_temp - min_temp) // If we're between min and optimal this will yield a value in the range 0-1

	cooking_coeff = optimal_power * temp_scale
	// to_world("Our cooking_power is [cooking_power] and our tempscale is [temp_scale], and our cooking_coeff is [cooking_coeff] before RefreshParts.") // Debug lines, uncomment if you need to test.
	RefreshParts()
	// to_world("Our cooking_power is [cooking_power] after RefreshParts.") // Debug lines, uncomment if you need to test.

/// Thermostat: the heat source runs below optimal_temp.
/obj/machinery/appliance/cooker/proc/heat_up()
	var/temperature = get_temperature()
	if(temperature < optimal_temp)
		if(use_power == 1 && ((optimal_temp - temperature) > 5))
			playsound(src, 'sound/machines/click.ogg', 20, 1)
			use_power = 2.//If we're heating we use the active power
			update_icon()
		set_heating(TRUE)
		update_cooking_power()
		return 1
	else
		if(use_power == 2)
			use_power = 1
			playsound(src, 'sound/machines/click.ogg', 20, 1)
			update_icon()
		//We're holding steady: the casing loses heat to the room.
		set_heating(FALSE)
		equalize_temperature()
		return -1

/// The cooker is losing heat to the room (its body's coupling does that): refresh the cooking power.
/obj/machinery/appliance/cooker/proc/equalize_temperature()
	update_cooking_power()
	return 1

/// Turns the heat source on or off. The body is kept while the cooker is on.
/obj/machinery/appliance/cooker/proc/set_heating(on)
	if(on == heating && (!on || !isnull(heat_body)))
		return
	heating = on
	if(on)
		if(!create_heat_body(TRUE))
			heating = FALSE
			return
		vg_heat_body_keep(heat_body, TRUE)
		vg_heat_body_power(heat_body, heating_power)
		warm_contents()
	else if(!isnull(heat_body))
		vg_heat_body_power(heat_body, 0)
		vg_heat_body_keep(heat_body, !stat)
		if(stat)
			release_contents_heat()

/// Wakes the cooker when its body cools below the thermostat band.
/obj/machinery/appliance/cooker/proc/arm_thermostat()
	if(!isnull(thermostat_watch))
		return TRUE
	thermostat_watch = heat_watch_threshold(src, optimal_temp - COOKER_THERMOSTAT_BAND, FALSE)
	return !isnull(thermostat_watch)

/obj/machinery/appliance/cooker/on_heat_wake(watch, reason, source)
	if(watch != thermostat_watch)
		return
	heat_unwatch(thermostat_watch)
	thermostat_watch = null
	START_MACHINE_PROCESSING(src)

/obj/machinery/appliance/cooker/Destroy()
	if(!isnull(thermostat_watch))
		heat_unwatch(thermostat_watch)
		thermostat_watch = null
	heat_unsubscribe()
	return ..()

/// Heat capacity from `resistance` (the old per-process heating step is
/// heating_power / resistance), and the casing's loss to the room.
/obj/machinery/appliance/cooker/thermal_properties()
	return list(resistance * COOKER_SECONDS_PER_PROCESS, cooker_conductance(), THERMAL_EMISSIVITY_DEFAULT)

/obj/machinery/appliance/cooker/proc/cooker_conductance()
	return COOKER_CONDUCTANCE

/// Couples the cooking containers, and the food in them, to the cooker's body.
/obj/machinery/appliance/cooker/proc/warm_contents()
	if(isnull(heat_body))
		return
	for(var/datum/cooking_item/CI as anything in cooking_objs)
		var/obj/item/container = CI?.container
		if(!container || container.loc != src)
			continue
		cooker_couple(container, heat_body)
		for(var/obj/item/food in container)
			cooker_couple(food, container.heat_body)

/// Couples `thing` to `holder_body`, kept while the cooker heats.
/obj/machinery/appliance/cooker/proc/cooker_couple(obj/item/thing, holder_body)
	if(isnull(holder_body) || !thing.create_heat_body(TRUE))
		return
	vg_heat_body_keep(thing.heat_body, TRUE)
	vg_heat_body_couple(thing.heat_body, 0, HEAT_TARGET_BODY, holder_body, COOKER_CONTENT_CONDUCTANCE)

/// The cooker stopped heating: its contents may be released at equilibrium again.
/obj/machinery/appliance/cooker/proc/release_contents_heat()
	for(var/datum/cooking_item/CI as anything in cooking_objs)
		var/obj/item/container = CI?.container
		if(!container)
			continue
		if(!isnull(container.heat_body))
			vg_heat_body_keep(container.heat_body, FALSE)
		for(var/obj/item/food in container)
			if(!isnull(food.heat_body))
				vg_heat_body_keep(food.heat_body, FALSE)

//Cookers do differently, they use containers
/obj/machinery/appliance/cooker/has_space(obj/item/I)
	if(istype(I, /obj/item/reagent_containers/cooking_container))
		//Containers can go into an empty slot
		if(cooking_objs.len < max_contents)
			return 1
	else
		//Any food items directly added need an empty container. A slot without a container cant hold food
		for (var/datum/cooking_item/CI in cooking_objs)
			if (CI.container.check_contents() == 0)
				return CI

	return 0

/obj/machinery/appliance/cooker/add_content(obj/item/I, mob/user)
	var/datum/cooking_item/CI = ..()
	if(heating)
		warm_contents()
	if(istype(CI) && CI.combine_target)
		to_chat(user, span_filter_notice("\The [I] will be used to make a [selected_option]. Output selection is returned to default for future items."))
		selected_option = null

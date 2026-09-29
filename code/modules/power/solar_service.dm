// The solar world service (fold wave F4; was SSsun + SSsolars). Every minute
// /datum/om/behaviour/world/solars (code/datums/om/world_lanes.dm) steps the sun and then updates
// every solar controller and its panels, yielding across ticks over budget.
GLOBAL_DATUM_INIT(sun, /datum/sun, new)
GLOBAL_DATUM_INIT(solar_service, /datum/world_service/solars, new)

/datum/world_service/solars
	name = "Solars"
	lane = /datum/om/behaviour/world/solars
	// List of solar controllers that need to be prepared for the second half of processing
	var/list/current_run

	// Relation list: controllers collected for the second half of this pass. Each controller
	// carries its own pending panels (solar_pending) and running sum (solar_pending_sum).
	var/list/controller_run

/datum/world_service/solars/service_step(resumed)
	if(!resumed)
		GLOB.sun.calc_position()
		// Get the list of controllers we need to process
		current_run = REGISTRY_COPY(REGISTRY_SOLAR_CONTROLS)
		// Clear secondary process lists so they're fresh for the impending run ahead
		for(var/obj/machinery/power/solar_control/old_SC as anything in controller_run)
			rel_clear(old_SC, nameof(old_SC.solar_pending))
		rel_clear(src, nameof(controller_run))

	////////////////////////////////////////////////////////////////////////////////
	// First processing cycle collects the controllers we'll be processing
	////////////////////////////////////////////////////////////////////////////////
	while(length(current_run))
		var/obj/machinery/power/solar_control/SC = current_run[length(current_run)]
		current_run.len--

		// Controllers with no network are ignored
		if(!SC.power_region)
			registry_leave(REGISTRY_SOLAR_CONTROLS, SC)
			if(TICK_CHECK)
				return FALSE
			continue

		// Update the controller and prepare each of the solar array lists it needs
		SC.update()
		rel_add(src, nameof(controller_run), SC) // this pass's work queue (like current_run); a deleted controller leaves it
		rel_clear(SC, nameof(SC.solar_pending))
		for(var/obj/machinery/power/solar/panel as anything in SC.get_connected_panels())
			rel_add(SC, nameof(SC.solar_pending), panel)
		SC.solar_pending_sum = 0

		if(TICK_CHECK)
			return FALSE

	////////////////////////////////////////////////////////////////////////////////
	// Second processing cycle handles all of the panels for each controller!
	////////////////////////////////////////////////////////////////////////////////
	while(length(controller_run))
		var/obj/machinery/power/solar_control/SC = controller_run[length(controller_run)]

		// Handle all solar panels for this controller.
		while(length(SC.solar_pending))
			var/obj/machinery/power/solar/S = SC.solar_pending[length(SC.solar_pending)]
			SC.solar_pending_sum += S.update_power_generation(SC)
			rel_remove(SC, nameof(SC.solar_pending), S)

			if(TICK_CHECK)
				return FALSE

		// Update the controller
		SC.connected_power = SC.solar_pending_sum
		SC.set_power_supply(SC.connected_power)
		SC.update_icon()
		rel_remove(src, nameof(controller_run), SC)

		if(TICK_CHECK)
			return FALSE
	return TRUE

/datum/world_service/solars/stat_line()
	return "Controllers: [length(controller_run)]"

/datum/world_service/solars/proc/get_solar_angle(turf/our_t)
	if(!our_t || our_t.z > length(GLOB.planet_service.z_to_planet) || !GLOB.planet_service.z_to_planet[our_t.z])
		return GLOB.sun.angle // standard in space solar panels use the global sun angle

	// On planets, use the daynight cycle
	var/datum/planet/our_planet = GLOB.planet_service.z_to_planet[our_t.z]
	return our_planet.get_sun_solar_position()

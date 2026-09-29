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

	// Each list has a key of its controller, for each subrun of the subsystem
	var/list/controller_run = list()
	var/list/panel_run = list()
	var/list/panel_sum = list()

/datum/world_service/solars/service_step(resumed)
	if(!resumed)
		GLOB.sun.calc_position()
		// Get the list of controllers we need to process
		current_run = REGISTRY_COPY(REGISTRY_SOLAR_CONTROLS)
		// Clear secondary process lists so they're fresh for the impending run ahead
		controller_run.Cut()
		panel_run.Cut()
		panel_sum.Cut()

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
		controller_run[REF(SC)] = SC // this pass's work queue (like current_run); a controller deleted mid-pass is skipped below
		panel_run[REF(SC)] = SC.get_connected_panels().Copy()
		panel_sum[REF(SC)] = 0

		if(TICK_CHECK)
			return FALSE

	////////////////////////////////////////////////////////////////////////////////
	// Second processing cycle handles all of the panels for each controller!
	////////////////////////////////////////////////////////////////////////////////
	while(length(controller_run))
		var/conkey = controller_run[length(controller_run)]
		// Check if the controller still exists
		var/obj/machinery/power/solar_control/SC = controller_run[conkey]
		if(QDELETED(SC))
			controller_run -= conkey
			if(TICK_CHECK)
				return FALSE
			continue

		// Handle all solar panels for this controller.
		var/list/handling_panels = panel_run[conkey]
		while(length(handling_panels))
			var/obj/machinery/power/solar/S = handling_panels[length(handling_panels)]
			panel_sum[conkey] += S.update_power_generation(SC)
			handling_panels.len--

			if(TICK_CHECK)
				return FALSE

		// Update the controller
		SC.connected_power = panel_sum[conkey]
		SC.set_power_supply(SC.connected_power)
		SC.update_icon()
		controller_run.len--

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

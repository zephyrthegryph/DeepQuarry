// The solar system (was SSsun + SSsolars). Every minute it steps the sun and then updates every solar controller
// and its panels, yielding across ticks over budget.
GLOBAL_DATUM_INIT(sun, /datum/sun, new)

SYSTEM_DEF(solars)
	name = "Solars"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	// List of solar controllers that need to be prepared for the second half of processing
	VAR_PRIVATE/list/current_run

	// Relation list: controllers collected for the second half of this pass. Each controller
	// carries its own pending panels (solar_pending) and running sum (solar_pending_sum).
	VAR_PRIVATE/list/controller_run
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE

/datum/system/solars/reactions()
	. = ..()
	. += every(1 MINUTE, PROC_REF(update_solars), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/solars/proc/update_solars(dt)
	var/resumed = resuming
	resuming = FALSE
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
			if(KERNEL_OVER_BUDGET)
				resuming = TRUE
				return STEP_YIELD
			continue

		// Update the controller and prepare each of the solar array lists it needs
		SC.update()
		rel_add(src, nameof(controller_run), SC) // this pass's work queue (like current_run); a deleted controller leaves it
		rel_clear(SC, nameof(SC.solar_pending))
		for(var/obj/machinery/power/solar/panel as anything in SC.get_connected_panels())
			rel_add(SC, nameof(SC.solar_pending), panel)
		SC.solar_pending_sum = 0

		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD

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

			if(KERNEL_OVER_BUDGET)
				resuming = TRUE
				return STEP_YIELD

		// Update the controller
		SC.connected_power = SC.solar_pending_sum
		SC.set_power_supply(SC.connected_power)
		rel_remove(src, nameof(controller_run), SC)

		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/solars/stat_entry(msg)
	return "[msg]Controllers: [length(controller_run)]"

/datum/system/solars/proc/get_solar_angle(turf/our_t)
	if(!our_t || our_t.z > length(SSplanets.z_to_planet) || !SSplanets.z_to_planet[our_t.z])
		return GLOB.sun.angle // standard in space solar panels use the global sun angle

	// On planets, use the daynight cycle
	var/datum/planet/our_planet = SSplanets.z_to_planet[our_t.z]
	return our_planet.get_sun_solar_position()

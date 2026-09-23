
/datum/pipeline
	var/datum/gas_mixture/air
	/// Physical volume contributed by this pipeline, retained while its air slot
	/// is rebound to the larger authoritative network mixture.
	var/volume

	var/list/obj/machinery/atmospherics/pipe/members
	var/list/obj/machinery/atmospherics/pipe/edges //Used for building networks

	// Nodes that are leaking. Used for A.S. Valves.
	var/list/leaks = list()

	var/datum/pipe_network/network
	var/list/datum/pipe_network/network_memberships
	var/alert_pressure = 0
	var/engineered_exposure_timer

/datum/pipeline/proc/register_network_membership(datum/pipe_network/new_network)
	LAZYOR(network_memberships, new_network)

/datum/pipeline/proc/unregister_network_membership(datum/pipe_network/old_network)
	LAZYREMOVE(network_memberships, old_network)

/datum/pipeline/proc/add_edge(obj/machinery/atmospherics/pipe/edge)
	if(!edge || QDELETED(edge))
		return FALSE
	LAZYOR(edges, edge)
	edge.register_edge_pipeline(src)
	return TRUE

/datum/pipeline/proc/remove_edge(obj/machinery/atmospherics/pipe/edge, clear_backlink = TRUE)
	if(edges)
		edges -= edge
	if(clear_backlink && edge)
		edge.unregister_edge_pipeline(src)

/datum/pipeline/Destroy()
	if(network?.rust_authoritative)
		return QDEL_HINT_LETMELIVE
	if(engineered_exposure_timer)
		deltimer(engineered_exposure_timer)
		engineered_exposure_timer = null
	// Drop our backlink before invalidating the shared topology.  The network's
	// Destroy() clears every other member and is deliberately re-entry safe.
	var/list/old_memberships = network_memberships
	network_memberships = null
	for(var/datum/pipe_network/membership as anything in old_memberships)
		if(membership?.line_members)
			membership.line_members -= src
	var/datum/pipe_network/old_network = network
	network = null
	qdel(old_network)

	if(air && air.return_volume())
		temporarily_store_air()
	QDEL_NULL(air)
	var/list/old_members = members
	var/list/old_edges = edges
	members = null
	edges = null
	leaks = null
	for(var/obj/machinery/atmospherics/pipe/P in old_members)
		if(P.parent == src)
			P.parent = null
	for(var/obj/machinery/atmospherics/pipe/edge in old_edges)
		edge.unregister_edge_pipeline(src)
	. = ..()

/datum/pipeline/process()//This use to be called called from the pipe networks

	//Check to see if pressure is within acceptable limits
	var/pressure = air.return_pressure()
	if(pressure > alert_pressure)
		for(var/obj/machinery/atmospherics/pipe/member in members)
			if(!member.check_pressure(pressure))
				break //Only delete 1 pipe per process

/// Engineered pipes are evaluated whenever their authoritative network gas is
/// mutated. Ordinary mapped pipes retain the old cheap path.
/datum/pipeline/proc/process_engineered_materials()
	if(!air || !length(members))
		return
	var/pressure = air.return_pressure()
	var/needs_followup = FALSE
	for(var/obj/machinery/atmospherics/pipe/member in members)
		if(member.process_engineered_material_exposure(air))
			needs_followup = TRUE
		if(!member.check_pressure(pressure))
			break
	if(needs_followup && !engineered_exposure_timer)
		engineered_exposure_timer = addtimer(CALLBACK(src, PROC_REF(wake_engineered_exposure)), 5 SECONDS, TIMER_STOPPABLE)

/datum/pipeline/proc/wake_engineered_exposure()
	engineered_exposure_timer = null
	network?.mark_dirty()

/datum/pipeline/proc/temporarily_store_air()
	//Update individual gas_mixtures by volume ratio

	for(var/obj/machinery/atmospherics/pipe/member in members)
		member.air_temporary = new
		member.air_temporary.copy_from(air)
		member.air_temporary.set_volume(member.volume)
		member.air_temporary.multiply(member.volume / air.return_volume())

/datum/pipeline/proc/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network == reference)
		air = network_air

/datum/pipeline/proc/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network == reference && air == network_air)
		air = detached_pipenet_air(network_air, volume, network_volume)

/datum/pipeline/proc/return_network(obj/machinery/atmospherics/reference)
	// Rust materializes this read-only compatibility wrapper.
	return network

// rewrote off ZAS zones. ZAS branch was `if(target.zone) … modify
// zone.air …`. Under LINDA, /turf.zone is always null, so we always take the
// non-zone path. Under the auxmos arena there is no share(); we do the mingle
// with arena ops: pull a sample of the pipe air, merge it into the turf mix so
// the combined contents fully equalise, then split the mingle share back out of
// the (now equalised) turf mix by volume ratio and merge it into the pipe.
/datum/pipeline/proc/mingle_with_turf(turf/target, mingle_volume)
	var/datum/gas_mixture/turf_air = target.return_air()
	if(!turf_air)
		return
	// Sample the pipe air proportional to the mingle volume.
	var/datum/gas_mixture/air_sample = air.remove_ratio(mingle_volume / air.return_volume())
	air_sample.set_volume(mingle_volume)

	// Merge the sample into the turf mix so both sets of contents fully mix,
	// then reclaim the pipe's share back out by volume ratio.
	turf_air.merge(air_sample)
	qdel(air_sample)
	var/turf_volume = turf_air.return_volume()
	if(turf_volume > 0)
		var/datum/gas_mixture/reclaimed = turf_air.remove_ratio(mingle_volume / (mingle_volume + turf_volume))
		if(reclaimed)
			air.merge(reclaimed)
			qdel(reclaimed)

	// Mark the turf so SSair re-equalises it with its neighbours next tick.
	if(SSair?.initialized)
		SSair.add_to_active(target)

	if(network)
		network.mark_dirty()

/datum/pipeline/proc/temperature_interact(turf/target, share_volume, thermal_conductivity)
	var/total_heat_capacity = air.heat_capacity()
	var/partial_heat_capacity = total_heat_capacity*(share_volume/air.return_volume())

	if(istype(target, /turf/simulated))
		var/turf/simulated/modeled_location = target

		if (modeled_location.special_temperature)
			var/new_temp = air.return_temperature() + thermal_conductivity * (modeled_location.special_temperature - air.return_temperature())
			if (new_temp < TCMB)
				new_temp = TCMB
			air.set_temperature(new_temp)
			if (network)
				network.mark_dirty()

		if(modeled_location.blocks_air)

			if((modeled_location.heat_capacity>0) && (partial_heat_capacity>0))
				// Read the wall turf's live (arena-authoritative) temperature, not the stale DM mirror.
				var/wall_temp = modeled_location.get_temperature()
				var/delta_temperature = air.return_temperature() - wall_temp

				var/heat = thermal_conductivity*delta_temperature* \
					(partial_heat_capacity*modeled_location.heat_capacity/(partial_heat_capacity+modeled_location.heat_capacity))

				air.set_temperature(air.return_temperature() - heat/total_heat_capacity)
				// The same joules into the wall's solid heat cell (a set would
				// overwrite whatever the field conducted since the read).
				modeled_location.add_heat(heat)

		else
			// collapsed ZAS zone branch. zone is always null under LINDA;
			// the air-bearing turf exposes its mixture directly via .air (set in
			// /turf/open/Initialize). Heat exchanges between the pipe and the turf
			// air using LINDA's heat_capacity() proc.
			var/datum/gas_mixture/sharer_air = modeled_location.air
			if(!sharer_air)
				return 1
			var/delta_temperature = air.return_temperature() - sharer_air.return_temperature()
			var/sharer_heat_capacity = sharer_air.heat_capacity()

			var/self_temperature_delta = 0
			var/sharer_temperature_delta = 0

			if((sharer_heat_capacity>0) && (partial_heat_capacity>0))
				var/heat = thermal_conductivity*delta_temperature* \
					(partial_heat_capacity*sharer_heat_capacity/(partial_heat_capacity+sharer_heat_capacity))

				self_temperature_delta = -heat/total_heat_capacity
				sharer_temperature_delta = heat/sharer_heat_capacity
			else
				return 1

			air.set_temperature(air.return_temperature() + self_temperature_delta)
			sharer_air.set_temperature(sharer_air.return_temperature() + sharer_temperature_delta)


	else
		if((target.heat_capacity>0) && (partial_heat_capacity>0))
			var/delta_temperature = air.return_temperature() - target.temperature

			var/heat = thermal_conductivity*delta_temperature* \
				(partial_heat_capacity*target.heat_capacity/(partial_heat_capacity+target.heat_capacity))

			air.set_temperature(air.return_temperature() - heat/total_heat_capacity)
	if(network)
		network.mark_dirty()

//surface must be the surface area in m^2
/datum/pipeline/proc/radiate_heat_to_space(surface, thermal_conductivity)
	var/gas_density = air.total_moles()/air.return_volume()
	thermal_conductivity *= min(gas_density / ( RADIATOR_OPTIMUM_PRESSURE/(R_IDEAL_GAS_EQUATION*GAS_CRITICAL_TEMPERATURE) ), 1) //mult by density ratio

	// We only get heat from the star on the exposed surface area.
	// If the HE pipes gain more energy from AVERAGE_SOLAR_RADIATION than they can radiate, then they have a net heat increase.
	var/heat_gain = AVERAGE_SOLAR_RADIATION * (RADIATOR_EXPOSED_SURFACE_AREA_RATIO * surface) * thermal_conductivity

	// Previously, the temperature would enter equilibrium at 26C or 294K.
	// Only would happen if both sides (all 2 square meters of surface area) were exposed to sunlight.  We now assume it aligned edge on.
	// It currently should stabilise at 129.6K or -143.6C
	heat_gain -= surface * STEFAN_BOLTZMANN_CONSTANT * thermal_conductivity * (air.return_temperature() - COSMIC_RADIATION_TEMPERATURE) ** 4

	air.add_thermal_energy(heat_gain)
	if(network)
		network.mark_dirty()

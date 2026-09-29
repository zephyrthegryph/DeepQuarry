
OWN_TIMER(/datum/pipeline, engineered_exposure_timer)

/datum/pipeline
	/// PROTO gas port: the pipe network's authoritative mixture (shared, the network owns it),
	/// or a private detached share this line owns. Written only by atmos_air_set().
	var/datum/gas_mixture/air
	/// Pipes in this line (two-sided with each pipe's `parent`).
	var/list/obj/machinery/atmospherics/pipe/members
	/// Pipes at this line's edges (two-sided with each pipe's `edge_pipelines`). Used for building networks.
	var/list/obj/machinery/atmospherics/pipe/edges

	// Nodes that are leaking. Used for A.S. Valves.
	var/list/leaks = list() // ALLOW(instance_list): atmos area (M1a): pipeline leaks; listed in memory_lists_audit.md, not edited here


	var/datum/pipe_network/network
	/// Every network whose line_members lists this line (two-sided).
	var/list/datum/pipe_network/network_memberships
	var/alert_pressure = 0

/datum/pipeline/proc/add_edge(obj/machinery/atmospherics/pipe/edge)
	if(!edge || QDELETED(edge))
		return FALSE
	rel_add(src, "edges", edge)
	return TRUE

/// Unlinks an edge pipe (both sides: `edges` is two-sided with the pipe's edge_pipelines).
/datum/pipeline/proc/remove_edge(obj/machinery/atmospherics/pipe/edge)
	rel_remove(src, "edges", edge)

// Rust-owned wrappers refuse deletion.
/datum/pipeline/lifecycle_keep(force)
	return network?.rust_authoritative

// A legacy line stores its gas back into its pipes and releases its network. The rosters,
// `network`, and the pipes' `parent`/`edge_pipelines` are relations (cleared in phase 4);
// `air` is PROTO (a private share is deleted at teardown, the network's is left to it).
/datum/pipeline/lifecycle_unbind()
	..()
	// Leave the network's roster before destroying it, so its unbind doesn't hand this
	// line a share of the gas it is about to store back into its pipes.
	for(var/datum/pipe_network/membership as anything in network_memberships?.Copy())
		rel_remove(src, "network_memberships", membership)
	qdel(network)

	if(air && air.return_volume())
		temporarily_store_air()
	rel_clear(src, "leaks")

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
	if(needs_followup && !om_timer_slot_pending(src, "engineered_exposure_timer"))
		om_after_slot(src, "engineered_exposure_timer", 5 SECONDS, PROC_REF(wake_engineered_exposure))

/datum/pipeline/proc/wake_engineered_exposure()
	network?.mark_dirty()

/datum/pipeline/proc/temporarily_store_air()
	//Update individual gas_mixtures by volume ratio

	for(var/obj/machinery/atmospherics/pipe/member in members)
		var/datum/gas_mixture/share = new
		share.copy_from(air)
		share.set_volume(member.volume)
		share.multiply(member.volume / air.return_volume())
		if(QDELETED(member))
			// A pipe being destroyed (its unbind destroys this line) can't adopt a new
			// mixture: its share goes straight back to the room.
			member.loc?.assume_air(share)
			qdel(share)
			continue
		own_set(member, "air_temporary", share)

/datum/pipeline/proc/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network == reference)
		atmos_air_set(src, "air", network_air)

/// Physical volume this line's pipes contribute: derived from the members, never stored.
/datum/pipeline/proc/physical_volume()
	var/total = 0
	for(var/obj/machinery/atmospherics/pipe/member as anything in members)
		total += member.volume
	return total

/datum/pipeline/proc/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network == reference && air == network_air)
		atmos_air_set(src, "air", detached_pipenet_air(network_air, physical_volume(), network_volume))

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
	heat_gain -= surface * STEFAN_BOLTZMANN_CONSTANT * thermal_conductivity * (air.return_temperature() - TCMB) ** 4

	air.add_thermal_energy(heat_gain)
	if(network)
		network.mark_dirty()

REL(/datum/pipeline, network)
REL_PAIR_LIST(/datum/pipeline, network_memberships, line_members)
REL_PAIR_LIST(/datum/pipeline, members, parent)
REL_PAIR_LIST(/datum/pipeline, edges, edge_pipelines)
PROTO(/datum/pipeline, air)

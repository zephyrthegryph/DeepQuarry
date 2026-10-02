
/datum/pipeline
	/// PROTO gas port: the pipe network's authoritative mixture (shared, the network owns it),
	/// or a private detached share this line owns. Written only by atmos_air_set().
	var/datum/gas_mixture/air
	/// Pipes in this line (two-sided with each pipe's `parent`).
	var/list/obj/machinery/atmospherics/pipe/members
	/// Pipes at this line's edges (two-sided with each pipe's `edge_pipelines`). Used for building networks.
	var/list/obj/machinery/atmospherics/pipe/edges

	// Nodes that are leaking. Used for A.S. Valves.
	var/list/leaks = list() // ALLOW(instance_list): the pipeline's leaking nodes: filled and cleared in place while the pipeline runs


	var/datum/pipe_network/network
	/// Every network whose line_members lists this line (two-sided).
	var/list/datum/pipe_network/network_memberships
	var/alert_pressure = 0

/datum/pipeline/proc/add_edge(obj/machinery/atmospherics/pipe/edge)
	if(!edge || QDELETED(edge))
		return FALSE
	rel_add(src, nameof(edges), edge)
	return TRUE

/// Unlinks an edge pipe (both sides: `edges` is two-sided with the pipe's edge_pipelines).
/datum/pipeline/proc/remove_edge(obj/machinery/atmospherics/pipe/edge)
	rel_remove(src, nameof(edges), edge)

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
		rel_remove(src, nameof(network_memberships), membership)
	qdel(network)

	if(air && air.return_volume())
		temporarily_store_air()
	rel_clear(src, nameof(leaks))

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
		after_slot(src, "engineered_exposure_timer", 5 SECONDS, PROC_REF(wake_engineered_exposure))

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
		own_set(member, nameof(member.air_temporary), share)

/datum/pipeline/proc/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network == reference)
		atmos_air_set(src, nameof(air), network_air)

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

/// A leaking pipe's face: the pipeline's air mingles with the turf's through one Rust batch mingle
/// (pipe -> turf sample, then the pipe's share reclaimed by volume ratio: verdigris/ffi/src/gas/binds.rs
/// auxmos_batch_mingle). Returns TRUE while the two still differ, so the leak needs to keep running.
/datum/pipeline/proc/leak_into(turf/target, share_volume)
	var/datum/gas_mixture/turf_air = target.return_air()
	if(!turf_air || !air)
		return FALSE
	var/list/residual = vg_batch_mingle_hook(list(air, turf_air, share_volume))
	// Mark the turf so SSair re-equalises it with its neighbours next tick.
	if(SSair?.initialized)
		SSair.add_to_active(target)
	if(network)
		network.mark_dirty()
	return length(residual) && residual[1]

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

/datum/pipeline/ownership()
	. = ..()
	. += rel_one(nameof(air), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)

/datum/pipeline/relations()
	. = ..()
	. += rel_one(nameof(network))
	. += rel_many(nameof(network_memberships), back = nameof(/datum/pipe_network::line_members))
	. += rel_many(nameof(members), back = nameof(/obj/machinery/atmospherics/pipe::parent))
	. += rel_many(nameof(edges), back = nameof(/obj/machinery/atmospherics/pipe::edge_pipelines))

/// Below this much spin a turbine has stopped and its motor has nothing to convert.
#define TURBINE_MIN_KIN_ENERGY 1

/obj/machinery/atmospherics/pipeturbine
	name = "turbine"
	desc = "A gas turbine. Converting pressure into energy since 1884."
	icon = 'icons/obj/pipeturbine.dmi'
	icon_state = "turbine"
	anchored = FALSE
	density = TRUE

	var/efficiency = 0.4
	var/kin_energy = 0
	/// PROTO gas ports (atmos_air_set()): private until bound to a pipe network's mixture.
	var/datum/gas_mixture/air_in
	var/datum/gas_mixture/air_out
	var/volume_ratio = 0.2
	var/kin_loss = 0.001

	var/dP = 0

	var/datum/pipe_network/network1
	var/datum/pipe_network/network2

/// Not BROKEN (the turbine needs no power, so operable() is too strict).
OM_DERIVE_FIELD(/obj/machinery/atmospherics/pipeturbine, unbroken, list("stat"))
/obj/machinery/atmospherics/pipeturbine/proc/unbroken()
	return !has_stat(BROKEN)

DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/atmospherics/pipeturbine, MACHINE_PIPELINE, list("anchored", "unbroken"))

CAPABILITIES(/obj/machinery/atmospherics/pipeturbine)
	climb()

/obj/machinery/atmospherics/pipeturbine/Initialize(mapload, newdir)
	. = ..()
	atmos_air_set(src, nameof(air_in), new /datum/gas_mixture(200))
	atmos_air_set(src, nameof(air_out), new /datum/gas_mixture(800))
	air_in.set_volume(200)
	air_out.set_volume(800)
	volume_ratio = air_in.return_volume() / (air_in.return_volume() + air_out.return_volume())
	switch(dir)
		if(NORTH)
			initialize_directions = EAST|WEST
		if(SOUTH)
			initialize_directions = EAST|WEST
		if(EAST)
			initialize_directions = NORTH|SOUTH
		if(WEST)
			initialize_directions = NORTH|SOUTH

	make_rotatable()

/obj/machinery/atmospherics/pipeturbine/machine_step()
	..()
	kin_energy *= 1 - kin_loss
	dP = max(air_in.return_pressure() - air_out.return_pressure(), 0)
	if(dP > 10)
		kin_energy += 1/ADIABATIC_EXPONENT * dP * air_in.return_volume() * (1 - volume_ratio**ADIABATIC_EXPONENT) * efficiency
		air_in.set_temperature(air_in.return_temperature() * volume_ratio**ADIABATIC_EXPONENT)

		var/datum/gas_mixture/air_all = new
		air_all.set_volume(air_in.return_volume() + air_out.return_volume())
		var/datum/gas_mixture/removed_in = air_in.remove_ratio(1)
		var/datum/gas_mixture/removed_out = air_out.remove_ratio(1)
		air_all.merge(removed_in)
		air_all.merge(removed_out)
		qdel(removed_in)
		qdel(removed_out)

		var/datum/gas_mixture/returned_in = air_all.remove(volume_ratio)
		air_in.merge(returned_in)
		qdel(returned_in)
		air_out.merge(air_all)
		qdel(air_all)

	update_icon()

	if (network1)
		network1.mark_dirty()
	if (network2)
		network2.mark_dirty()

	// Its motor draws the spin down; wake it while there is spin to draw.
	if(kin_energy >= TURBINE_MIN_KIN_ENERGY)
		var/obj/machinery/power/turbinemotor/motor = locate_within(get_step(src, dir), /obj/machinery/power/turbinemotor)
		if(motor)
			MACHINE_WAKE(motor)
		return
	// Spun down with no pressure head: park until the head returns (the test above).
	kin_energy = 0
	om_watch_arm_condition(src, "gas", list(air_in.arena_id(), air_out.arena_id()), GAS_DEPENDENCY_PRESSURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))
	return PROCESS_KILL

/obj/machinery/atmospherics/pipeturbine/proc/gas_wake_condition()
	return anchored && !has_stat(BROKEN) && air_in.return_pressure() - air_out.return_pressure() > 10

/obj/machinery/atmospherics/pipeturbine/proc/wake_from_gas()
	om_watch_disarm(src, "gas")
	MACHINE_WAKE(src)

DECLARE_APPEARANCE(/obj/machinery/atmospherics/pipeturbine, "appearance_moto", list("1" = list(APPEARANCE_OVERLAYS = list("moto-turb"))))
DECLARE_APPEARANCE(/obj/machinery/atmospherics/pipeturbine, "appearance_speed", list("1" = list(APPEARANCE_OVERLAYS = list("low-turb")), "2" = list(APPEARANCE_OVERLAYS = list("low-turb", "med-turb")), "3" = list(APPEARANCE_OVERLAYS = list("low-turb", "med-turb", "hi-turb"))))

/obj/machinery/atmospherics/pipeturbine/proc/appearance_moto()
	return dP > 10

/// Speed overlays: 1 above 100 kJ, 2 above 500 kJ, 3 above 1 MJ of kinetic energy.
/obj/machinery/atmospherics/pipeturbine/proc/appearance_speed()
	if(kin_energy > 1000000)
		return 3
	if(kin_energy > 500000)
		return 2
	return kin_energy > 100000 ? 1 : 0

/obj/machinery/atmospherics/pipeturbine/wrench_act(mob/user, obj/item/W)
	set_anchored(!anchored)
	playsound(src, W.usesound, 50, 1)
	to_chat(user, span_notice("You [anchored ? "secure" : "unsecure"] the bolts holding \the [src] to the floor."))

	if(anchored)
		if(dir & (NORTH|SOUTH))
			initialize_directions = EAST|WEST
		else if(dir & (EAST|WEST))
			initialize_directions = NORTH|SOUTH

		atmos_init()
		if (node1)
			node1.atmos_init()
		if (node2)
			node2.atmos_init()
		rust_register_pipe_topology()
	else
		rust_unregister_pipe_topology()
		if(node1)
			node1.disconnect(src)
			rust_release_network_wrapper(network1)
		if(node2)
			node2.disconnect(src)
			rust_release_network_wrapper(network2)

		rel_clear(src, nameof(node1))
		rel_clear(src, nameof(node2))

	return ITEM_INTERACT_SUCCESS

//Goddamn copypaste from binary base class because atmospherics machinery API is not damn flexible
/obj/machinery/atmospherics/pipeturbine/get_neighbor_nodes_for_init()
	return list(node1, node2)

/obj/machinery/atmospherics/pipeturbine/atmos_init()
	if(node1 && node2)
		return

	var/node2_connect = turn(dir, -90)
	var/node1_connect = turn(dir, 90)

	for(var/obj/machinery/atmospherics/target in get_step(src,node1_connect))
		if(target.initialize_directions & get_dir(target,src))
			rel_set(src, nameof(node1), target)
			break

	for(var/obj/machinery/atmospherics/target in get_step(src,node2_connect))
		if(target.initialize_directions & get_dir(target,src))
			rel_set(src, nameof(node2), target)
			break

/obj/machinery/atmospherics/pipeturbine/return_network(obj/machinery/atmospherics/reference)
	if(reference==node1)
		return network1

	if(reference==node2)
		return network2

	return null

/obj/machinery/atmospherics/pipeturbine/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network1 == old_network)
		rel_set(src, nameof(network1), new_network)
	if(network2 == old_network)
		rel_set(src, nameof(network2), new_network)

	return 1

/obj/machinery/atmospherics/pipeturbine/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	if(network1 == reference)
		results += air_in
	if(network2 == reference)
		results += air_out

	return results

/obj/machinery/atmospherics/pipeturbine/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network1 == reference)
		atmos_air_set(src, nameof(air_in), network_air)
	if(network2 == reference)
		atmos_air_set(src, nameof(air_out), network_air)

/obj/machinery/atmospherics/pipeturbine/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network1 == reference && air_in == network_air)
		atmos_air_set(src, nameof(air_in), detached_pipenet_air(network_air, 200, network_volume))
	if(network2 == reference && air_out == network_air)
		atmos_air_set(src, nameof(air_out), detached_pipenet_air(network_air, 800, network_volume))

/obj/machinery/atmospherics/pipeturbine/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network1)
		rel_clear(src, nameof(node1))

	else if(reference==node2)
		rust_release_network_wrapper(network2)
		rel_clear(src, nameof(node2))

	return null

/obj/machinery/power/turbinemotor
	name = "motor"
	desc = "Electrogenerator. Converts rotation into power."
	icon = 'icons/obj/pipeturbine.dmi'
	icon_state = "motor"
	anchored = FALSE
	density = TRUE

	var/kin_to_el_ratio = 0.1	//How much kinetic energy will be taken from turbine and converted into electricity
	var/obj/machinery/atmospherics/pipeturbine/turbine

/// Not BROKEN (the motor is a generator; operable() would also demand power).
OM_DERIVE_FIELD(/obj/machinery/power/turbinemotor, unbroken, list("stat"))
/obj/machinery/power/turbinemotor/proc/unbroken()
	return !has_stat(BROKEN)

DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/power/turbinemotor, MACHINE_PIPELINE, list("anchored", "unbroken"))

CAPABILITIES(/obj/machinery/power/turbinemotor)
	climb()

/obj/machinery/power/turbinemotor/Initialize(mapload)
	. = ..()
	updateConnection()
	make_rotatable()

/obj/machinery/power/turbinemotor/proc/updateConnection()
	rel_clear(src, nameof(turbine))
	if(src.loc && anchored)
		rel_set(src, nameof(turbine), locate_within(get_step(src,dir), /obj/machinery/atmospherics/pipeturbine))
		if(!turbine)
			return
		if (turbine.has_stat(BROKEN) || !turbine.anchored || turn(turbine.dir,180) != dir)
			rel_clear(src, nameof(turbine))

/// Converts its turbine's spin while there is any; parked otherwise, the turbine's own step wakes
/// it (pipeturbine machine_step()).
/obj/machinery/power/turbinemotor/machine_step()
	updateConnection()
	if(!turbine || turbine.kin_energy < TURBINE_MIN_KIN_ENERGY)
		return PROCESS_KILL

	var/power_generated = kin_to_el_ratio * turbine.kin_energy
	turbine.kin_energy -= power_generated
	add_avail(power_generated)

/obj/machinery/power/turbinemotor/wrench_act(mob/user, obj/item/W)
	set_anchored(!anchored)
	playsound(src, W.usesound, 50, 1)
	rel_clear(src, nameof(turbine))
	to_chat(user, span_notice("You [anchored ? "secure" : "unsecure"] the bolts holding \the [src] to the floor."))
	updateConnection()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/pipeturbine/step_has_work()
	return anchored && !has_stat(BROKEN) && (kin_energy >= TURBINE_MIN_KIN_ENERGY || gas_wake_condition())

/obj/machinery/power/turbinemotor/step_has_work()
	return turbine && anchored && !has_stat(BROKEN) && turbine.kin_energy >= TURBINE_MIN_KIN_ENERGY

#undef TURBINE_MIN_KIN_ENERGY

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/atmospherics/pipeturbine/arm_wakes()
	..()
	if(air_in && air_out)
		om_watch_arm_condition(src, "gas", list(air_in.arena_id(), air_out.arena_id()), GAS_DEPENDENCY_PRESSURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))

/obj/machinery/atmospherics/pipeturbine/ownership()
	. = ..()
	. += rel_one(nameof(air_in), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)
	. += rel_one(nameof(air_out), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)


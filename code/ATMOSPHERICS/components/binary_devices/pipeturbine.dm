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
	/// It has work each service interval: bolted, whole, and spinning or with a pressure head across it (reconsider()).
	var/spinning = FALSE
	/// What it shows: a pressure head across it (the motor overlay) and its speed band (0 to 3).
	var/driven = FALSE
	var/speed_band = 0
	/// The watches it sleeps on: its two sides' mixtures.
	var/list/datum/native_watch/gas/side_watches

TRACKED(/obj/machinery/atmospherics/pipeturbine, spinning)
TRACKED(/obj/machinery/atmospherics/pipeturbine, driven)
TRACKED(/obj/machinery/atmospherics/pipeturbine, speed_band)

MSG_DEF_SELF(turbine/secured, "You secure the bolts holding it to the floor.")
MSG_DEF_SELF(turbine/unsecured, "You unsecure the bolts holding it to the floor.")

CAPABILITIES(/obj/machinery/atmospherics/pipeturbine)
	climb()
	owns_one(nameof(air_in), on_destroy = ON_DESTROY_PRIVATE_COPY)
	owns_one(nameof(air_out), on_destroy = ON_DESTROY_PRIVATE_COPY)
	owns_many(nameof(side_watches), /datum/native_watch/gas)
	after_init(0, then(PROC_REF(reconsider)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(turbine_step)), when = nameof(spinning))
	on_change(nameof(stat), ANY, then(PROC_REF(reconsider)))
	op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(0), says(PROC_REF(anchor_message)), then(PROC_REF(anchor_toggled)))

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

/// Whether it has work: bolted, whole, and spinning or driven by a pressure head. Asleep, it watches its two sides.
/obj/machinery/atmospherics/pipeturbine/proc/reconsider(datum/act/A)
	if(anchored && !broken_now() && (kin_energy >= TURBINE_MIN_KIN_ENERGY || gas_wake_condition()))
		gas_watch_many_clear(src, nameof(side_watches))
		set_spinning(TRUE)
		return
	set_spinning(FALSE)
	if(anchored && !broken_now())
		gas_watch_many(src, nameof(side_watches), list(air_in, air_out), GAS_DEPENDENCY_PRESSURE, PROC_REF(side_heard))
	else
		gas_watch_many_clear(src, nameof(side_watches))

/obj/machinery/atmospherics/pipeturbine/proc/side_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	if(gas_wake_condition())
		reconsider()

/// One service interval of turning (its every()): the head across it spins the rotor, which equalizes the two sides; its motor draws the spin.
/obj/machinery/atmospherics/pipeturbine/proc/turbine_step(datum/act/A)
	kin_energy *= 1 - kin_loss
	dP = max(air_in.return_pressure() - air_out.return_pressure(), 0)
	if(dP > 10)
		kin_energy += 1/ADIABATIC_EXPONENT * dP * air_in.return_volume() * (1 - volume_ratio**ADIABATIC_EXPONENT) * efficiency
		heat_set(air_in, air_in.return_temperature() * volume_ratio**ADIABATIC_EXPONENT, HEAT_SOURCE_DEVICE) // adiabatic expansion: the drop is the work the rotor takes

		var/datum/gas_mixture/air_all = new
		air_all.set_volume(air_in.return_volume() + air_out.return_volume())
		var/datum/gas_mixture/removed_in = air_in.remove_ratio(1)
		var/datum/gas_mixture/removed_out = air_out.remove_ratio(1)
		air_all.merge(removed_in)
		air_all.merge(removed_out)
		spent(removed_in)
		spent(removed_out)

		var/datum/gas_mixture/returned_in = air_all.remove_ratio(volume_ratio)
		air_in.merge(returned_in)
		spent(returned_in)
		air_out.merge(air_all)
		spent(air_all)

	gas_touched(air_in)
	gas_touched(air_out)

	if(kin_energy < TURBINE_MIN_KIN_ENERGY)
		kin_energy = 0
	update_display()
	// Its motor draws the spin down while there is spin to draw.
	var/obj/machinery/power/turbinemotor/motor = locate_within(get_step(src, dir), /obj/machinery/power/turbinemotor)
	motor?.reconsider()
	reconsider()

/// A pressure head across it worth turning.
/obj/machinery/atmospherics/pipeturbine/proc/gas_wake_condition()
	return anchored && !broken_now() && air_in.return_pressure() - air_out.return_pressure() > 10

/// Speed bands: 1 above 100 kJ, 2 above 500 kJ, 3 above 1 MJ of kinetic energy.
/obj/machinery/atmospherics/pipeturbine/proc/update_display()
	set_driven(dP > 10)
	if(kin_energy > 1000000)
		set_speed_band(3)
	else if(kin_energy > 500000)
		set_speed_band(2)
	else
		set_speed_band(kin_energy > 100000 ? 1 : 0)

/obj/machinery/atmospherics/pipeturbine/draw(datum/look/look)
	..()
	look.overlay("moto-turb", when = driven)
	look.overlay("low-turb", when = speed_band >= 1)
	look.overlay("med-turb", when = speed_band >= 2)
	look.overlay("hi-turb", when = speed_band >= 3)

/obj/machinery/atmospherics/pipeturbine/derived()
	. = ..()
	. += drawn_from(nameof(driven), nameof(speed_band))

/obj/machinery/atmospherics/pipeturbine/proc/anchor_message(datum/act/A)
	return anchored ? /datum/msg/turbine/secured : /datum/msg/turbine/unsecured

/// The wrench bolts it onto its pipes, or frees it.
/obj/machinery/atmospherics/pipeturbine/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)

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
	reconsider()
	return OP_OK

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
	/// It has work each service interval: bolted, whole, on a turbine with spin to draw (reconsider(); the turbine's step asks it).
	var/converting = FALSE

TRACKED(/obj/machinery/power/turbinemotor, converting)

CAPABILITIES(/obj/machinery/power/turbinemotor)
	climb()
	after_init(0, then(PROC_REF(reconsider)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(motor_step)), when = nameof(converting))
	op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(0), says(PROC_REF(anchor_message)), then(PROC_REF(anchor_toggled)))

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
		if (turbine.broken_now() || !turbine.anchored || turn(turbine.dir,180) != dir)
			rel_clear(src, nameof(turbine))

/// Whether it has work: on a turbine with spin to draw.
/obj/machinery/power/turbinemotor/proc/reconsider(datum/act/A)
	updateConnection()
	set_converting(!!(anchored && !broken_now() && turbine && turbine.kin_energy >= TURBINE_MIN_KIN_ENERGY))

/// One service interval of converting its turbine's spin to power (its every(), while its turbine spins).
/obj/machinery/power/turbinemotor/proc/motor_step(datum/act/A)
	updateConnection()
	if(!turbine || turbine.kin_energy < TURBINE_MIN_KIN_ENERGY)
		reconsider()
		return
	var/power_generated = kin_to_el_ratio * turbine.kin_energy
	turbine.kin_energy -= power_generated
	add_avail(power_generated)

/obj/machinery/power/turbinemotor/proc/anchor_message(datum/act/A)
	return anchored ? /datum/msg/turbine/secured : /datum/msg/turbine/unsecured

/// The wrench bolts it beside its turbine, or frees it.
/obj/machinery/power/turbinemotor/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	rel_clear(src, nameof(turbine))
	reconsider()
	return OP_OK

#undef TURBINE_MIN_KIN_ENERGY

//
// Heat Exchanging Pipes - Behave like simple pipes
//
/obj/machinery/atmospherics/pipe/simple/heat_exchanging
	icon = 'icons/atmos/heat.dmi'
	icon_state = "intact"
	pipe_icon = "hepipe"
	color = "#404040"
	level = 2
	connect_types = CONNECT_TYPE_HE
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY
	construction_type = /obj/item/pipe/binary/bendable
	pipe_state = "he"

	layer = PIPES_HE_LAYER
	var/initialize_directions_he
	var/surface = 2	//surface area in m^2
	var/icon_temperature = T20C //stop small changes in temperature causing an icon refresh
	/// It has work each service interval: a body lies on it, or its glow is behind its gas (reconsider()).
	var/tending = FALSE
	/// The watch it sleeps on: its pipeline's gas (temperature), for the glow.
	var/list/datum/native_watch/gas/glow_watches
	/// It lies on space and radiates (set when it joins its pipeline: a pipe does not move).
	var/in_space = FALSE

	minimum_temperature_difference = 20
	thermal_conductivity = OPEN_HEAT_TRANSFER_COEFFICIENT

	buckle_lying = 1

	// BubbleWrap
/// A shell's thermal mass per m^2 of its surface (J/K): small beside its gas, so the gas and the surroundings stay coupled.
#define HE_PIPE_SHELL_CAPACITY 10
/// Shell-to-gas conductance (W/K) at the open-air conductivity.
#define HE_PIPE_GAS_CONDUCTANCE 100
/// Shell-to-surroundings conductance (W/K) at the open-air conductivity.
#define HE_PIPE_SURFACE_CONDUCTANCE 50
/// The sky an HE pipe in space radiates against: the temperature at which the sunlight on its edge-on surface balances what it radiates
/// (about 130 K), so a radiator in space settles there, as it always did.
#define HE_PIPE_SKY_TEMPERATURE ((AVERAGE_SOLAR_RADIATION * RADIATOR_EXPOSED_SURFACE_AREA_RATIO / STEFAN_BOLTZMANN_CONSTANT) ** 0.25 + TCMB)

CAPABILITIES(/obj/machinery/atmospherics/pipe/simple/heat_exchanging)
	// In space the pipeline's gas radiates through the pipe's surface (Stefan-Boltzmann, integrated exactly in Rust).
	when(nameof(in_space), heat_link(HEAT_PORT(1), HEAT_SKY(HE_PIPE_SKY_TEMPERATURE), 0, 1, nameof(surface)))
	owns_many(nameof(glow_watches), /datum/native_watch/gas)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(he_step)), when = nameof(tending))
	on_change(nameof(parent), ANY, then(PROC_REF(reconsider)))

TRACKED(/obj/machinery/atmospherics/pipe/simple/heat_exchanging, in_space)
TRACKED(/obj/machinery/atmospherics/pipe/simple/heat_exchanging, tending)

/// The pipe's shell is its heat body: it couples to its turf like any atom's (slot 0) and to its pipeline's gas (slot 1).
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/thermal_properties()
	var/share = effective_conductivity() / OPEN_HEAT_TRANSFER_COEFFICIENT
	return list(HE_PIPE_SHELL_CAPACITY * surface, HE_PIPE_SURFACE_CONDUCTANCE * share, THERMAL_EMISSIVITY_DEFAULT)

/// The shell's conductivity: an engineered material's measured conductance through its wall, else the type's.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/proc/effective_conductivity()
	var/datum/material/material = engineered_material()
	return material ? clamp(material.thermal_conductance(surface, 0.004, T20C) / 10000, 0.001, 1) : thermal_conductivity

/// The pipeline's persistent GasCoupling: slot 1 of the shell's heat body names this pipe's port, not a region, so it heats
/// the gas of whichever pipeline the port is in through every merge and split (the gas domain resolves it each step).
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/proc/couple_to_pipeline()
	if(QDELETED(src) || !length(rust_pipe_port_ids) || !rust_pipe_port_ids[1])
		return
	if(!create_heat_body(TRUE))
		return
	HEAT_BODY_RESOLVE(src)
	vg_heat_body_couple(heat_body, 1, HEAT_TARGET_PIPE_PORT, rust_pipe_port_ids[1], HE_PIPE_GAS_CONDUCTANCE * (effective_conductivity() / OPEN_HEAT_TRANSFER_COEFFICIENT))

/// Its port's region exists in Rust from here on: the shell couples to the pipeline.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 1)
		couple_to_pipeline()
		set_in_space(istype(loc, /turf/space))
		reconsider()

// BubbleWrap END
	color = "#404040" //we don't make use of the fancy overlay system for colours, use this to set the default.

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/init_dir()
	..()
	initialize_directions_he = initialize_directions	// The auto-detection from /pipe is good enough for a simple HE pipe
	initialize_directions = 0

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/get_init_dirs()
	return ..() | initialize_directions_he

// ---- its DM work: a body lying on it, and its glow; the heat itself is Rust's (its shell's heat body, its sky link) ----

/// Its glow is more than ten kelvin behind its gas, above 500 K.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/proc/glow_due()
	var/datum/gas_mixture/pipe_air = parent?.air
	if(!pipe_air)
		return FALSE
	var/pipe_temperature = pipe_air.return_temperature()
	return (icon_temperature > 500 || pipe_temperature > 500) && abs(pipe_temperature - icon_temperature) > 10

/// Whether it has work: in a pipeline, with a body on it or its glow behind. Asleep, it watches its pipeline's gas for the glow.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/proc/reconsider(datum/act/A)
	if(parent && (has_buckled_mobs() || glow_due()))
		gas_watch_many_clear(src, nameof(glow_watches))
		set_tending(TRUE)
		return
	set_tending(FALSE)
	if(parent)
		// Its glow follows its gas's temperature only: Rust reports every change of a pipe region, whoever wrote it.
		gas_watch_many(src, nameof(glow_watches), list(parent.air), GAS_DEPENDENCY_TEMPERATURE, PROC_REF(glow_heard))
	else
		gas_watch_many_clear(src, nameof(glow_watches))

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/proc/glow_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	if(glow_due())
		reconsider()

/// A body lies down on it or gets up: it tends it.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/post_buckle_mob(mob/living/M)
	. = ..()
	reconsider()

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	reconsider()

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/set_leaking(new_leaking)
	return // Heat-exchange pipes cannot leak.

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	reconsider()

// Use initialize_directions_he to connect to neighbors instead.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/can_be_node(obj/machinery/atmospherics/pipe/simple/heat_exchanging/target)
	if(!istype(target))
		return FALSE
	return (target.initialize_directions_he & get_dir(target,src)) && check_connectable(target) && target.check_connectable(src)

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/atmos_init()
	normalize_dir()
	var/node1_dir
	var/node2_dir

	for(var/direction in GLOB.cardinal)
		if(direction&initialize_directions_he)
			if (!node1_dir)
				node1_dir = direction
			else if (!node2_dir)
				node2_dir = direction

	for(var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/target in get_step(src,node1_dir))
		if(can_be_node(target, 1))
			rel_set(src, nameof(node1), target)
			break
	for(var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/target in get_step(src,node2_dir))
		if(can_be_node(target, 2))
			rel_set(src, nameof(node2), target)
			break
	if(!node1 && !node2)
		spent(src)
		return

	handle_leaking()
	return

/// One service interval of tending (its every()): the body on it and its gas meet (conserving) and a hot pipe burns it; its glow follows its gas.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/proc/he_step(datum/act/A)
	var/datum/gas_mixture/pipe_air = parent?.air
	if(!pipe_air)
		reconsider()
		return
	for(var/mob/living/L as anything in buckled_mob_list())
		heat_equalize(pipe_air, L) // the body lying on it and the gas inside meet, conserving
		var/heat_limit = 1000
		var/mob/living/carbon/human/H = L
		if(istype(H) && H.species)
			heat_limit = H.species.heat_level_3
		if(pipe_air.return_temperature() > heat_limit + 1)
			L.injure(INJURY_BURN, 4 * log(pipe_air.return_temperature() - heat_limit), BP_TORSO, src)
	//fancy radiation glowing
	if(glow_due())
		icon_temperature = pipe_air.return_temperature()
		var/h_r = heat2color_r(icon_temperature)
		var/h_g = heat2color_g(icon_temperature)
		var/h_b = heat2color_b(icon_temperature)
		if(icon_temperature < 2000) //scale up overlay until 2000K
			var/scale = (icon_temperature - 500) / 1500
			h_r = 64 + (h_r - 64)*scale
			h_g = 64 + (h_g - 64)*scale
			h_b = 64 + (h_b - 64)*scale
		animate(src, color = rgb(h_r, h_g, h_b), time = 20, easing = SINE_EASING)
	reconsider()

//
// Heat Exchange Junction - Interfaces HE pipes to normal pipes
//
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/junction
	desc = "An adaptor to transfer gasses between regular pipes and heat transferring ones. It doesn't conduct heat all that well."
	icon = 'icons/atmos/junction.dmi'
	icon_state = "intact"
	pipe_icon = "hejunction"
	level = 2
	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_HE
	construction_type = /obj/item/pipe/directional
	pipe_state = "junction"
	minimum_temperature_difference = 300
	thermal_conductivity = WALL_HEAT_TRANSFER_COEFFICIENT

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/junction/init_dir()
	..()
	switch ( dir )
		if ( SOUTH )
			initialize_directions = NORTH
			initialize_directions_he = SOUTH
		if ( NORTH )
			initialize_directions = SOUTH
			initialize_directions_he = NORTH
		if ( EAST )
			initialize_directions = WEST
			initialize_directions_he = EAST
		if ( WEST )
			initialize_directions = EAST
			initialize_directions_he = WEST

	// Allow ourselves to make connections to either HE or normal pipes depending on which node we are doing.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/junction/can_be_node(obj/machinery/atmospherics/target, node_num)
	var/target_initialize_directions
	switch(node_num)
		if(1)
			target_initialize_directions = target.initialize_directions // Node1 is towards normal pipes
		if(2)
			var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/H = target
			if(!istype(H))
				return FALSE
			target_initialize_directions = H.initialize_directions_he  // Node2 is towards HE pies.
	return (target_initialize_directions & get_dir(target,src)) && check_connectable(target) && target.check_connectable(src)

/obj/machinery/atmospherics/pipe/simple/heat_exchanging/junction/atmos_init()
	for(var/obj/machinery/atmospherics/target in get_step(src,initialize_directions))
		if(target.initialize_directions & get_dir(target,src))
			rel_set(src, nameof(node1), target)
			break
	for(var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/target in get_step(src,initialize_directions_he))
		if(target.initialize_directions_he & get_dir(target,src))
			rel_set(src, nameof(node2), target)
			break

	if(!node1&&!node2)
		spent(src)
		return

	handle_leaking()
	return

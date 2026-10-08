//
// Tanks - These are implemented as pipes with large volume
//
/obj/machinery/atmospherics/pipe/tank
	/// Its sprite (the map sprite is "<this>_map").
	var/tank_state = "air"
	icon = 'icons/atmos/tank.dmi'
	icon_state = "air_map"

	name = "Pressure Tank"
	desc = "A large vessel containing pressurized gas."

	volume = 10000 //in liters, 1 meters by 1 meters by 2 meters ~tweaked it a little to simulate a pressure tank without needing to recode them yet
	var/start_pressure = 75*ONE_ATMOSPHERE

	layer = ATMOS_LAYER
	level = 1
	dir = SOUTH
	initialize_directions = SOUTH
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY
	density = TRUE

/obj/machinery/atmospherics/pipe/tank/draw(datum/look/look)
	..()
	look.state(tank_state)

CAPABILITIES(/obj/machinery/atmospherics/pipe/tank)
	climb()

/obj/machinery/atmospherics/pipe/tank/init_dir()
	initialize_directions = dir

/obj/machinery/atmospherics/pipe/tank/pipeline_expansion()
	return list(node1)

/obj/machinery/atmospherics/pipe/tank/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node1, dir)

/obj/machinery/atmospherics/pipe/tank/hide()
	update_underlays()

/obj/machinery/atmospherics/pipe/tank/atmos_init()
	var/connect_direction = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,connect_direction))
		if (can_be_node(target, 1))
			rel_set(src, nameof(node1), target)
			break

	update_underlays()

/obj/machinery/atmospherics/pipe/tank/disconnect(obj/machinery/atmospherics/reference)
	if(reference == node1)
		if(istype(node1, /obj/machinery/atmospherics/pipe))
			rust_invalidate_pipeline_wrapper(parent)
		rel_clear(src, nameof(node1))

	update_underlays()

	return null


/obj/machinery/atmospherics/pipe/tank/air
	name = "Pressure Tank (Air)"
	icon_state = "air_map"

/obj/machinery/atmospherics/pipe/tank/air/Initialize(mapload)
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T20C)

	air_temporary.adjust_multi(GAS_O2,  (start_pressure*O2STANDARD)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()), \
								GAS_N2,(start_pressure*N2STANDARD)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

	. = ..()

/obj/machinery/atmospherics/pipe/tank/oxygen
	tank_state = "o2"
	name = "Pressure Tank (Oxygen)"
	icon_state = "o2_map"



/obj/machinery/atmospherics/pipe/tank/oxygen/Initialize(mapload)
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T20C)

	air_temporary.adjust_gas(GAS_O2, (start_pressure)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

	. = ..()

/obj/machinery/atmospherics/pipe/tank/nitrogen
	tank_state = "n2"
	name = "Pressure Tank (Nitrogen)"
	icon_state = "n2_map"
	volume = 40000



/obj/machinery/atmospherics/pipe/tank/nitrogen/Initialize(mapload)
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T20C)

	air_temporary.adjust_gas(GAS_N2, (start_pressure)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

	. = ..()

/obj/machinery/atmospherics/pipe/tank/carbon_dioxide
	tank_state = "co2"
	name = "Pressure Tank (Carbon Dioxide)"
	icon_state = "co2_map"



/obj/machinery/atmospherics/pipe/tank/carbon_dioxide/Initialize(mapload)
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T20C)

	air_temporary.adjust_gas(GAS_CO2, (start_pressure)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

	. = ..()

/obj/machinery/atmospherics/pipe/tank/phoron
	tank_state = "phoron"
	name = "Pressure Tank (Phoron)"
	icon_state = "phoron_map"
	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_FUEL



/obj/machinery/atmospherics/pipe/tank/phoron/Initialize(mapload)
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T20C)

	air_temporary.adjust_gas(GAS_PHORON, (start_pressure)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

	. = ..()

/obj/machinery/atmospherics/pipe/tank/nitrous_oxide
	tank_state = "n2o"
	name = "Pressure Tank (Nitrous Oxide)"
	icon_state = "n2o_map"



/obj/machinery/atmospherics/pipe/tank/nitrous_oxide/Initialize(mapload)
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T0C)

	air_temporary.adjust_gas(GAS_N2O, (start_pressure)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

	. = ..()

/obj/machinery/atmospherics/pipe/tank/methane
	tank_state = "ch4"
	name = "Pressure Tank (Methane)"
	icon_state = "ch4_map"
	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_FUEL



/obj/machinery/atmospherics/pipe/tank/methane/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(air_temporary), new /datum/gas_mixture)
	air_temporary.set_volume(volume)
	heat_set(air_temporary, T20C)

	air_temporary.adjust_gas(GAS_CH4, (start_pressure)*(air_temporary.return_volume())/(R_IDEAL_GAS_EQUATION*air_temporary.return_temperature()))

/obj/machinery/atmospherics/pipe/tank/phoron/full
	start_pressure = 15000

/obj/machinery/atmospherics/pipe/tank/air/full
	start_pressure = 15000

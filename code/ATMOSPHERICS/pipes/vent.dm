//
// Vent Pipe - Unpowered vent
//
/obj/machinery/atmospherics/pipe/vent
	icon = 'icons/obj/atmospherics/pipe_vent.dmi'
	icon_state = "intact"

	name = "Vent"
	desc = "A large air vent"

	level = 1

	volume = 250

	dir = SOUTH
	initialize_directions = SOUTH
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY
	construction_type = /obj/item/pipe/directional
	pipe_state = "passive_vent"
	// A passive vent is a permanent open face of its pipeline. Treat it exactly
	// like every other network-owned leak so all faces sharing a reservoir are
	// transferred in one Rust batch and can dependency-sleep when equalized.
	leaking = TRUE

/obj/machinery/atmospherics/pipe/vent/init_dir()
	initialize_directions = dir

/obj/machinery/atmospherics/pipe/vent/high_volume
	name = "Larger vent"
	volume = 1000

/obj/machinery/atmospherics/pipe/vent/pipeline_expansion()
	return list(node1)

/obj/machinery/atmospherics/pipe/vent/draw(datum/look/look)
	..()
	if(node1)
		look.state("intact")
		look.set_dir(get_dir(src, node1))
	else
		look.state("exposed")

/obj/machinery/atmospherics/pipe/vent/atmos_init()
	var/connect_direction = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,connect_direction))
		if (can_be_node(target, 1))
			rel_set(src, nameof(node1), target)
			break


/obj/machinery/atmospherics/pipe/vent/disconnect(obj/machinery/atmospherics/reference)
	if(reference == node1)
		if(istype(node1, /obj/machinery/atmospherics/pipe))
			rust_invalidate_pipeline_wrapper(parent)
		rel_clear(src, nameof(node1))


	return null

/obj/machinery/atmospherics/pipe/vent/hide(i) //to make the little pipe section invisible, the icon changes.
	if(node1)
		icon_state = "[i == 1 && istype(loc, /turf/simulated) ? "h" : "" ]intact"
		set_dir(get_dir(src, node1))
	else
		icon_state = "exposed"

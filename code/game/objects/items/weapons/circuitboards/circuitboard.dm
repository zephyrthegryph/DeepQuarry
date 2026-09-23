/obj/item/circuitboard
	name = "circuit board"
	icon = 'icons/obj/module.dmi'
	icon_state = "id_mod"
	density = FALSE
	anchored = FALSE
	w_class = ITEMSIZE_SMALL
	force = 5.0
	throwforce = 5.0
	throw_speed = 3
	throw_range = 15
	MATERIAL_BULK(MAT_GLASS, 40)
	var/build_path = null
	var/board_type = new /datum/frame/frame_types/computer
	var/list/req_components = null
	var/contain_parts = 1
	drop_sound = 'sound/items/drop/device.ogg'
	pickup_sound = 'sound/items/pickup/device.ogg'

	/// If true, this board should be ignored during the circuitboard printing unit test, and give an examine hint that the board may be hard to get if so.
	var/hidden = FALSE

/obj/item/circuitboard/Destroy()
	// Explosions can destroy an installed board before their containing machine.
	// Sever the owner's typed reference immediately so the board never waits in
	// GC behind a still-live (or separately queued) machine.
	if(istype(loc, /obj/machinery))
		var/obj/machinery/machine = loc
		if(machine.circuit == src)
			machine.circuit = null
	if(isobject(board_type)) // Some boards use text instead of an instance...
		QDEL_NULL(board_type)
	return ..()

//Called when the circuitboard is used to contruct a new machine.
/obj/item/circuitboard/proc/construct(obj/machinery/M)
	if(istype(M, build_path))
		return 1
	return 0

//Called when a computer is deconstructed to produce a circuitboard.
//Only used by computers, as other machines store their circuitboard instance.
/obj/item/circuitboard/atom_deconstruct(disassembled = TRUE, obj/machinery/M)
	if(istype(M, build_path))
		return 1
	return 0


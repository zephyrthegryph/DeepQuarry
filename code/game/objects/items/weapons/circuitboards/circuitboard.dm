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

REF_OWNED(/obj/item/circuitboard, "board_type")
REF_HELD(/obj/machinery, list("circuit", "paicard"))
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


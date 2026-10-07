//a trunk joining to a disposal bin or outlet on the same turf
/obj/structure/disposalpipe/trunk
	icon_state = "pipe-t"
	var/tmp/atom/linked	// The linked atom. It should have a disposal system connection to handle receiving disposal packets.

// ALLOW(init/INSTANCE_STATE): its pipe direction follows the way it was placed
/obj/structure/disposalpipe/trunk/Initialize(mapload)
	. = ..()
	dpdir = dir

CAPABILITIES(/obj/structure/disposalpipe/trunk)
	after_init(0, then(PROC_REF(link_after_init)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Links the machine on its tile, once it exists.
/obj/structure/disposalpipe/trunk/proc/link_after_init(datum/act/timer/A)
	update()

// its linked machine unlinks.
/obj/structure/disposalpipe/trunk/on_destroy(force)
	if(linked()) //Linked to something, better unlink.
		PUBLISH_LEGACY(linked(), /datum/notice/disposal_unlink)
	..()

// Override attackby so we disallow trunkremoval when somethings ontop

/// Old attackby.
/obj/structure/disposalpipe/trunk/proc/interaction_item(datum/act/op/A)
	//Linked atom.
	if(linked())
		return OP_PASS
	//Disposal constructors
	var/turf/T = get_turf(src)
	for(var/obj/structure/disposalconstruct/C in turf_contents_of_type(T, /obj/structure/disposalconstruct))
		if(C.ptype == DISPOSAL_PIPE_BIN || C.ptype == DISPOSAL_PIPE_OUTLET || C.ptype == DISPOSAL_PIPE_CHUTE)
			if(C.anchored)
				return OP_PASS

	return OP_DECLINE //Run the check from parent, instead of copypasta code

// would transfer to next pipe segment, but we are in a trunk
// if not entering from disposal bin,
// transfer to linked object (outlet or bin)
/obj/structure/disposalpipe/trunk/transfer(obj/structure/disposalholder/H)
	if(H.dir == DOWN)		// we just entered from a disposer
		return ..()		// so do base transfer proc

	if(linked())
		var/datum/act/send_disposal/send = ACT_TRY(src, send_disposal, H)
		if(!send)
			return //Sent, and handled. Our job is done.
		act_cancel(send)

	pipe_expel(H, get_turf(src), 0) // expel at turf if nothing handled it

	return null

// nextdir
/obj/structure/disposalpipe/trunk/nextdir(fromdir)
	if(fromdir == DOWN)
		return dir
	else
		return 0

/// The linked atom. It should have a disposal system connection to handle receiving disposal packets. (a relation view: it reads null once the target is deleted).
/obj/structure/disposalpipe/trunk/proc/linked() as /atom
	return linked

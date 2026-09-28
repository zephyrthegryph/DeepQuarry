//a trunk joining to a disposal bin or outlet on the same turf
/obj/structure/disposalpipe/trunk
	icon_state = "pipe-t"
	var/linked_handle	// The linked atom. It should have a /datum/component/disposal_connection to handle receiving disposal packets.

/obj/structure/disposalpipe/trunk/Initialize(mapload)
	..()
	dpdir = dir
	return INITIALIZE_HINT_LATELOAD

/obj/structure/disposalpipe/trunk/LateInitialize()
	update()

// LIFECYCLE: its linked machine unlinks.
/obj/structure/disposalpipe/trunk/Destroy()
	if(linked()) //Linked to something, better unlink.
		SEND_SIGNAL(linked(), COMSIG_DISPOSAL_UNLINK)
		linked_handle = null
	. = ..()

// Override attackby so we disallow trunkremoval when somethings ontop
/obj/structure/disposalpipe/trunk/attackby(obj/item/I, mob/user)
	//Linked atom.
	if(linked())
		return
	//Disposal constructors
	var/turf/T = get_turf(src)
	for(var/obj/structure/disposalconstruct/C in T)
		if(C.ptype == DISPOSAL_PIPE_BIN || C.ptype == DISPOSAL_PIPE_OUTLET || C.ptype == DISPOSAL_PIPE_CHUTE)
			if(C.anchored)
				return

	return ..() //Run the check from parent, instead of copypasta code

// would transfer to next pipe segment, but we are in a trunk
// if not entering from disposal bin,
// transfer to linked object (outlet or bin)
/obj/structure/disposalpipe/trunk/transfer(obj/structure/disposalholder/H)
	if(H.dir == DOWN)		// we just entered from a disposer
		return ..()		// so do base transfer proc

	if(linked())
		if(SEND_SIGNAL(src, COMSIG_DISPOSAL_SEND, H))
			return //Sent, and handled. Our job is done.

	pipe_expel(H, get_turf(src), 0) // expel at turf if nothing handled it

	return null

// nextdir
/obj/structure/disposalpipe/trunk/nextdir(fromdir)
	if(fromdir == DOWN)
		return dir
	else
		return 0

/// LC-refs: The linked atom. It should have a /datum/component/disposal_connection to handle receiving disposal packets. -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/disposalpipe/trunk/proc/linked() as /atom
	return om_resolve(linked_handle)

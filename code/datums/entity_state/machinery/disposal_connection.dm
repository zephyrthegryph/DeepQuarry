///Disposal connection (owned by its /obj), allows an atom to recieve and send disposal packages if attached to a disposal trunk.
/datum/disposal_system_connection
	//The connected trunk. Also determines if we're linked already or not.
	var/connected_trunk_handle

	/// The proc that the owner has that'll accept a list of items from recieved disposal packets.
	var/visible_connection
	/// The connected machine.
	var/obj/owner

/obj/var/tmp/datum/disposal_system_connection/disposal_connection
REF_OWNED(/obj, "disposal_connection")

/// Gives src a disposal network connection (owned; deleted with src). Returns it.
/obj/proc/add_disposal_connection(visibly_connects = TRUE)
	RETURN_TYPE(/datum/disposal_system_connection)
	if(disposal_connection)
		qdel(disposal_connection)
	disposal_connection = new /datum/disposal_system_connection(src, visibly_connects)
	return disposal_connection

/datum/disposal_system_connection/New(obj/new_owner, visibly_connects = TRUE)
	..()
	owner = new_owner
	visible_connection = visibly_connects
	om_hook(owner, /datum/om/event/before/disposal_flush, src, PROC_REF(on_flush))
	om_hook(owner, /datum/om/event/disposal_link, src, PROC_REF(link_to_trunk))
	om_hook(owner, /datum/om/event/disposal_unlink, src, PROC_REF(unlink_from_trunk))
	om_hook(owner, /datum/om/event/examine, src, PROC_REF(on_examine))

REF_BACK(/datum/disposal_system_connection, list("owner" = "disposal_connection"))

// owned state datum (was a component) unhooks and detaches from its owner.
/datum/disposal_system_connection/on_destroy(force)
	om_unhook_all(src)
	if(owner?.disposal_connection == src)
		owner.disposal_connection = null
	owner = null
	..()

// Signal handling
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/disposal_system_connection/proc/on_flush(datum/source, datum/om/event/before/disposal_flush/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	var/list/flushed_items = event.items
	var/datum/gas_mixture/flush_gas = event.gas
	// Important note, the flush_gas will be passed to the disposal packet when it's made. Caller should make a fresh gasmix datum after flushing this one!
	return handle_flush(flushed_items, flush_gas)

/datum/disposal_system_connection/proc/link_to_trunk(datum/source, datum/om/event/disposal_link/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	var/obj/structure/disposalpipe/trunk/trunk = event.trunk
	if(!trunk)
		return FALSE
	if(trunk.linked()) //Already linked to something
		return FALSE
	connected_trunk_handle = om_handle(trunk)
	trunk.linked_handle = om_handle(disposal_owner())
	om_hook(trunk, /datum/om/event/before/disposal_send, src, PROC_REF(on_recieve))

/datum/disposal_system_connection/proc/unlink_from_trunk(datum/source, datum/om/event/disposal_unlink/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	if(connected_trunk())
		connected_trunk().linked_handle = null
		om_unhook(connected_trunk(), /datum/om/event/before/disposal_send, src)
		connected_trunk_handle = null

/datum/disposal_system_connection/proc/on_recieve(datum/source, datum/om/event/before/disposal_send/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	var/obj/structure/disposalholder/packet = event.holder
	return handle_expel(packet)

/datum/disposal_system_connection/proc/on_examine(datum/source, datum/om/event/examine/event)
	EVENT_HANDLER
	var/list/examine_texts = event.texts
	if(!visible_connection)
		return
	examine_texts += span_notice("It [connected_trunk() ? "is connected" : "can be connected"] to a disposal pipe network.")

// Flush handling, can be override by subtypes but excepts parent proc to handle core logic
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/disposal_system_connection/proc/handle_flush(list/flushed_items, datum/gas_mixture/flush_gas)
	PROTECTED_PROC(TRUE)
	SHOULD_CALL_PARENT(TRUE)
	// if no trunk connected, return false
	if(!connected_trunk())
		return FALSE

	var/obj/structure/disposalholder/packet = new()	// virtual holder object which actually travels through the pipes.
	packet.init(flushed_items, flush_gas)

	// start the holder processing movement
	packet.forceMove(connected_trunk())
	packet.active = TRUE
	packet.set_dir(DOWN)
	packet.move()
	return TRUE

// Expel handling, can be override by subtypes but excepts parent proc to handle core logic
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/disposal_system_connection/proc/handle_expel(obj/structure/disposalholder/packet)
	// Returns true if our owner could handle this packet, used by our child procs to animate our owner.
	PROTECTED_PROC(TRUE)
	if(!packet || QDELETED(packet))
		return FALSE

	// We need to store the data in the packet to handle it with delays, then delete the packet so nothing else can handle it
	packet.active = FALSE // So it stops trying to move
	var/list/expelled_items = list()
	for(var/atom/movable/AM in packet)
		expelled_items += AM
		AM.forceMove(disposal_owner())
	var/datum/gas_mixture/gas = new()
	gas.copy_from(packet.gas)
	qdel(packet)
	OM_EMIT(disposal_owner(), /datum/om/event/disposal_receive, expelled_items, gas)
	return TRUE

/// The connected machine (our owner).
/datum/disposal_system_connection/proc/disposal_owner() as /atom
	return owner

/// LC-refs: the trunk we are linked to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/disposal_system_connection/proc/connected_trunk() as /obj/structure/disposalpipe/trunk
	return om_resolve(connected_trunk_handle)

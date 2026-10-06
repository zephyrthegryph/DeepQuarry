///Disposal connection (owned by its /obj), allows an atom to recieve and send disposal packages if attached to a disposal trunk.
/datum/disposal_system_connection
	//The connected trunk. Also determines if we're linked already or not.
	var/obj/structure/disposalpipe/trunk/connected_trunk

	/// The proc that the owner has that'll accept a list of items from recieved disposal packets.
	var/visible_connection
	/// The connected machine.
	var/obj/owner

/obj/var/tmp/datum/disposal_system_connection/disposal_connection

/// Gives src a disposal network connection (owned; deleted with src). Returns it.
/obj/proc/add_disposal_connection(visibly_connects = TRUE)
	RETURN_TYPE(/datum/disposal_system_connection)
	if(disposal_connection)
		own_clear(src, nameof(disposal_connection), OWN_DELETE)
	rel_set(src, nameof(disposal_connection), new /datum/disposal_system_connection(src, visibly_connects))
	return disposal_connection

/datum/disposal_system_connection/New(obj/new_owner, visibly_connects = TRUE)
	..()
	rel_set(src, nameof(owner), new_owner)
	visible_connection = visibly_connects
	observe(owner, /datum/act/flush_disposal, src, instead(then(PROC_REF(on_flush))))
	observe(owner, /datum/notice/disposal_link, src, then(PROC_REF(link_to_trunk)))
	observe(owner, /datum/notice/disposal_unlink, src, then(PROC_REF(unlink_from_trunk)))
	observe(owner, /datum/notice/examine, src, then(PROC_REF(on_examine)))


// Signal handling
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/disposal_system_connection/proc/on_flush(datum/act/flush_disposal/flush)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/list/flushed_items = flush.items
	var/datum/gas_mixture/flush_gas = flush.gas
	// Important note, the flush_gas will be passed to the disposal packet when it's made. Caller should make a fresh gasmix datum after flushing this one!
	return handle_flush(flushed_items, flush_gas) ? TRUE : HOOK_DECLINE

/datum/disposal_system_connection/proc/link_to_trunk(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/datum/notice/disposal_link/event = A
	var/obj/structure/disposalpipe/trunk/trunk = event.trunk
	if(!trunk)
		return FALSE
	if(trunk.linked()) //Already linked to something
		return FALSE
	rel_set(src, nameof(connected_trunk), trunk)
	rel_set(trunk, nameof(trunk.linked), disposal_owner())
	observe(trunk, /datum/act/send_disposal, src, instead(then(PROC_REF(on_recieve))))

/datum/disposal_system_connection/proc/unlink_from_trunk(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(connected_trunk())
		rel_clear(connected_trunk(), nameof(/datum/integrated_io::linked))
		unobserve(connected_trunk(), /datum/act/send_disposal, src)
		rel_clear(src, nameof(connected_trunk))

/datum/disposal_system_connection/proc/on_recieve(datum/act/send_disposal/send)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/obj/structure/disposalholder/packet = send.packet
	return handle_expel(packet) ? TRUE : HOOK_DECLINE

/datum/disposal_system_connection/proc/on_examine(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/examine/event = N
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

	// start the holder processing movement (its active declaration runs move())
	packet.forceMove(connected_trunk())
	packet.set_dir(DOWN)
	packet.set_active(TRUE)
	return TRUE

// Expel handling, can be override by subtypes but excepts parent proc to handle core logic
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/disposal_system_connection/proc/handle_expel(obj/structure/disposalholder/packet)
	// Returns true if our owner could handle this packet, used by our child procs to animate our owner.
	PROTECTED_PROC(TRUE)
	if(!packet || QDELETED(packet))
		return FALSE

	// We need to store the data in the packet to handle it with delays, then delete the packet so nothing else can handle it
	packet.set_active(FALSE) // So it stops trying to move
	var/list/expelled_items = list()
	for(var/atom/movable/AM in packet)
		expelled_items += AM
		AM.forceMove(disposal_owner())
	var/datum/gas_mixture/gas = new()
	gas.copy_from(packet.gas)
	spent(packet)
	OM_EMIT(disposal_owner(), /datum/om/event/disposal_receive, expelled_items, gas)
	return TRUE

/// The connected machine (our owner).
/datum/disposal_system_connection/proc/disposal_owner() as /atom
	return owner

/// The trunk we are linked to (a relation view).
/datum/disposal_system_connection/proc/connected_trunk() as /obj/structure/disposalpipe/trunk
	return connected_trunk

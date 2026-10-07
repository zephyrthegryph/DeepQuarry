// Physical inventory and containment adapters for the engine's declared space hooks.
// The engine owns path walking and extraction; these hooks supply the concrete inventory protocol.

/atom/space_ledger_location(atom/movable/inside)
	var/datum/om/relation/slot/def = dq_path_slot_of(src, inside)
	return def?.at

/atom/space_ledger_slot(slot_id)
	for(var/datum/om/relation/slot/def as anything in dq_slot_defs_for(src))
		if(def.slot_id == slot_id)
			return TRUE
	return FALSE

/atom/space_transfer_refusal(atom/movable/thing, mob/actor)
	return own_transfer_refusal(src, thing, null, actor)

/atom/space_bring_in(var_name, atom/movable/thing, mob/actor)
	return own_bring_in(src, var_name, thing, null, actor, TRUE, null, FALSE)

/obj/item/space_receive(atom/movable/thing, mob/actor)
	var/obj/item/as_item = thing
	return istype(as_item) && can_carry(as_item, actor) && carry(as_item, actor)

/mob/space_receive(atom/movable/thing, mob/actor)
	var/obj/item/as_item = thing
	return istype(as_item) && put_in_hands(as_item)

/datum/capability/construction/space_construction_graph()
	return graph

// Domain-specific transfer adapters; generic movement and atom interfaces are engine-owned.

/// A mob's hands and equipment: the item must be one it can let go of (NODROP, can_unequip).
/mob/release_refusal(atom/movable/thing, mob/user)
	if(isitem(thing))
		var/obj/item/I = thing
		var/id = inventory_slot_id(I)
		if(id)
			if(has_trait(I, TRAIT_NODROP))
				return user == src || !user ? "\the [I] is stuck to you" : "\the [I] is stuck to [src]"
			if(!I.mob_can_unequip(src, id, TRUE))
				return user == src || !user ? "you can't take off \the [I]" : "you can't take \the [I] from [src]"
	return ..()

/// Out of a mob's inventory through remove_from_mob(): the slot clears, the HUD drops the item,
/// the slot redraws and the item's dropped() runs.
/mob/release_to(atom/movable/thing, atom/destination, slot, mob/user, flags = 0)
	if(!isitem(thing))
		return ..()
	remove_from_mob(thing, destination)
	return thing.loc == destination

/// Out of a storage item through storage_exit(), remove_from_storage()'s commit (no stall: nothing
/// sleeps between the checks and the commit): its HUD and on_exit_storage() run.
/obj/item/storage/release_to(atom/movable/thing, atom/destination, slot, mob/user, flags = 0)
	if(!isitem(thing))
		return ..()
	var/obj/item/W = thing
	if(ismob(loc))
		W.dropped(loc)
	return storage_exit(W, destination, user, slot, flags, checked = TRUE)

/datum/transfer_outputs/refusal(mob/user, text)
	return refuse(user, text)
/datum/transfer_outputs/record(mob/user, datum/target, action, log, list/details)
	return dispatch_record(user, target, action, log, details)

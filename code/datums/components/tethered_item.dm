// A handheld item on a tether to its host item (defib paddles, radio
// handsets, mediguns, proton packs). The tether itself is an edge of
// /datum/om/relation/tethered_to (handheld -> host): TETHERED_HANDHELD(host)
// and TETHER_HOST(handheld) (om.dm) read it, and deleting the host deletes
// the handheld. This component only carries the behaviour: the verbs and
// signals that keep the handheld in its host or its wearer's hands.

/datum/om/relation/tethered_to
	name = "tether"
	source_single = TRUE
	target_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER

/datum/component/tethered_item
	VAR_PRIVATE/held_path

/datum/component/tethered_item/Initialize(handheld_item_path)
	if(!isitem(parent))
		return COMPONENT_INCOMPATIBLE
	held_path = handheld_item_path
	var/obj/item/host_item = parent
	host_item.verbs += /obj/item/proc/toggle_tethered_handheld
	host_item.actions_types += list(/datum/action/item_action/swap_tethered_item) // AddComponent for this must be called before . = ..() in Initilize()
	RegisterSignal(host_item, COMSIG_ITEM_ATTACK_SELF, PROC_REF(on_attackself))
	RegisterSignal(host_item, COMSIG_ATOM_ATTACKBY, PROC_REF(on_attackby))
	RegisterSignal(host_item, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))
	// Link handheld
	make_handheld()

/datum/component/tethered_item/Destroy()
	var/obj/item/host_item = parent
	UnregisterSignal(host_item, COMSIG_ITEM_ATTACK_SELF)
	UnregisterSignal(host_item, COMSIG_ATOM_ATTACKBY)
	UnregisterSignal(host_item, COMSIG_MOVABLE_MOVED)
	host_item.verbs -= /obj/item/proc/toggle_tethered_handheld
	var/obj/item/hand_held = host_item?.tethered_handheld()
	if(hand_held)
		UnregisterSignal(hand_held, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING))
		qdel(hand_held)
	. = ..()

// Signal handling
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// !!!! IMPORTANT NOTE !!!!
// Attackself signal is used by ui action hud buttons. As it calls attack_self() directly.
// Anything that uses this component must intercept attack_hand() and emit COMSIG_ITEM_ATTACK_SELF.
// This stops you from removing the item from your backpack slot while trying to take the handheld item out.
// There's no way to block the item pickup code, so it has to be done this way. Unfortunately.
// Will return COMPONENT_CANCEL_ATTACK_CHAIN if the component handled the action. Otherwise attack_hand() should resolve normally.
/datum/component/tethered_item/proc/on_attackself(obj/item/source, mob/living/carbon/human/user)
	SIGNAL_HANDLER
	var/obj/item/host_item = parent
	var/obj/item/hand_held = host_item?.tethered_handheld()
	if(hand_held.loc != host_item)
		reattach_handheld()
		return COMPONENT_CANCEL_ATTACK_CHAIN
	//Detach the handset into the user's hands
	if(!slot_check())
		if(ismob(host_item.loc))
			to_chat(user, span_warning("You need to equip \the [host_item] before taking out \the [hand_held]."))
		return
	if(!user.put_in_hands(hand_held))
		to_chat(user, span_warning("You need a free hand to hold the \the [hand_held]!"))
		return
	host_item.update_icon()
	hand_held.update_icon()
	to_chat(user,span_notice("You remove \the [hand_held] from \the [host_item]."))
	return COMPONENT_CANCEL_ATTACK_CHAIN

// Signal registry for handheld item
/datum/component/tethered_item/proc/make_handheld()
	// Not directly a signal handler, but putting this anywhere else makes this way more confusing.
	var/obj/item/host_item = parent
	if(host_item?.tethered_handheld())
		return
	var/obj/item/hand_held = new held_path(host_item)
	om_link(hand_held, host_item, /datum/om/relation/tethered_to)
	RegisterSignal(hand_held, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))
	RegisterSignal(hand_held, COMSIG_QDELETING, PROC_REF(on_qdelete_handheld))

/datum/component/tethered_item/proc/on_qdelete_handheld(obj/item/hand_held)
	SIGNAL_HANDLER
	// Safely unregister signals from handheld when it is deleted, then make a new one
	UnregisterSignal(hand_held, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING))
	var/obj/item/host_item = parent
	om_unlink(hand_held, host_item, /datum/om/relation/tethered_to)
	// We normally want to remake our handheld item if it gets destroyed, but not if our host is deleting
	if(!QDELETED(host_item))
		make_handheld()
		host_item.update_icon()
		var/obj/item/remade = host_item?.tethered_handheld()
		remade?.update_icon()

// Absolutely illegal to be anywhere else except in the slot you were allowed to remove it from
/datum/component/tethered_item/proc/on_moved(atom/source, atom/oldloc, direction, forced, list/old_locs, momentum_change)
	SIGNAL_HANDLER
	var/obj/item/host_item = parent
	var/obj/item/hand_held = host_item?.tethered_handheld()
	if(!hand_held || hand_held.loc == host_item) // handheld item is safely inside us
		return
	if(slot_check() && hand_held.loc == host_item.loc) // We are safely worn by our mob, and handheld item is safely inside our mob
		return
	// PANIC
	reattach_handheld()

// Putting the handset back into our host
/datum/component/tethered_item/proc/on_attackby(obj/item/source, obj/item/W, mob/user, params)
	SIGNAL_HANDLER
	var/obj/item/host_item = parent
	var/obj/item/hand_held = host_item?.tethered_handheld()
	if(W == hand_held)
		reattach_handheld()
		return COMPONENT_CANCEL_ATTACK_CHAIN

// Helpers
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/component/tethered_item/proc/reattach_handheld()
	var/obj/item/host_item = parent
	var/obj/item/hand_held = host_item?.tethered_handheld()
	if(!hand_held)
		return
	// Retracts back to host
	var/mob/handheld_mob = hand_held.loc
	if(istype(handheld_mob))
		to_chat(handheld_mob,span_notice("\The [hand_held] retracts back into \the [host_item]."))
		handheld_mob.drop_from_inventory(hand_held, host_item)
	else
		hand_held.forceMove(host_item)
	host_item.update_icon()
	hand_held.update_icon()

// Some objects need to communicate the state of the handheld item back to the host
/datum/component/tethered_item/proc/get_handheld()
	return parent?.tethered_handheld()

// By default this expects to be worn on your back
/datum/component/tethered_item/proc/slot_check()
	var/obj/item/host_item = parent
	var/mob/M = host_item.loc
	if(!istype(M))
		return FALSE
	if(HAS_TAG(host_item, TAG_WEAR_BACK) && M.get_equipped_item(slot_back) == host_item)
		return TRUE
	if(HAS_TAG(host_item, TAG_WEAR_BELT) && M.get_equipped_item(slot_belt) == host_item)
		return TRUE
	if(M.get_equipped_item(slot_s_store) == host_item) // There is no flag for this, just a whitelist on the suits themselves
		return TRUE
	return FALSE

// Helper verbs
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/obj/item/proc/toggle_tethered_handheld()
	set name = "Remove/Replace Handset"
	set category = "Object"

	// May only remove tethered while in the usr's direct inventory
	if(src.loc != usr)
		return
	SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_SELF, usr)

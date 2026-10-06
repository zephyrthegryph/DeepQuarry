// A handheld item on a tether to its host item (defib paddles, radio
// handsets, mediguns, proton packs). The tether is a pair of references: the handheld's
// tether_host_item (deleting the host deletes the handheld) and the host's tether_handheld_item
// (losing the handheld remakes it). The host carries the tether_host capability (was
// /datum/component/tethered_item) and the handheld tether_handheld: together they keep the
// handheld in its host or its wearer's hands.
//
// Set up with host.make_tethered(handheld_path) before . = ..() in Initialize().

/obj/item
	/// Path of the tethered handheld this host makes, or null (not a tether host).
	var/tether_path
	/// The handheld this host made (host side of the tether).
	var/obj/item/tether_handheld_item
	/// The host this handheld belongs to (handheld side of the tether).
	var/obj/item/tether_host_item

// The two references are declared in /obj/item's CAPABILITIES block (code/modules/mob/living/silicon/robot/component.dm).

/// The handheld this host is tethered to, or null.
/obj/item/proc/tethered_handheld()
	RETURN_TYPE(/obj/item)
	return tether_handheld_item

/// The host this handheld is tethered to, or null.
/obj/item/proc/tether_host()
	RETURN_TYPE(/obj/item)
	return tether_host_item

/// The handheld was deleted: a living host remakes it (out of the unlink).
/obj/item/proc/tether_handheld_lost(obj/item/handheld)
	if(QDELETED(src) || !tether_path)
		return
	after(src, 0, TYPE_PROC_REF(/obj/item, tether_remake_handheld))

CAPABILITY_TYPE(tether_host, CAP_TETHER_HOST, /datum/capability/tether_host, key = NONE)
/datum/capability/tether_host

// !!!! IMPORTANT NOTE !!!!
// The attack_self action is used by ui action hud buttons, as they call attack_self() directly.
// Anything that uses this must intercept attack_hand() and call tether_swap().
// This stops you from removing the item from your backpack slot while trying to take the handheld item out.
// There's no way to block the item pickup code, so it has to be done this way. Unfortunately.
/datum/capability/tether_host/entries()
	return list(
		extend(/datum/act/attack_self, instead(then(CAP_PROC(host_used_self)))),
		extend(/datum/act/attackby, instead(then(CAP_PROC(host_take_back)))),
		on_notice(/datum/notice/moved, then(CAP_PROC(host_moved))),
	)

/datum/capability/tether_host/on_deactivate(datum/activation/A)
	var/obj/item/host_item = A.holder
	revoke(host_item, granted_verb(/obj/item/proc/toggle_tethered_handheld), host_item)
	var/obj/item/hand_held = host_item.tethered_handheld()
	host_item.tether_path = null // no remake
	if(hand_held)
		spent(hand_held)

/// Takes the handheld out or puts it back; a swap that did nothing declines, so the use goes on.
/datum/capability/tether_host/proc/host_used_self(datum/act/attack_self/A)
	var/obj/item/host_item = A.holder
	if(!host_item.tether_swap(A.user))
		return HOOK_DECLINE
	return null

// Putting the handset back into our host; any other item is not ours to take (the use goes on).
/datum/capability/tether_host/proc/host_take_back(datum/act/attackby/A)
	var/obj/item/host_item = A.holder
	if(!A.item || A.item != host_item.tethered_handheld())
		return HOOK_DECLINE
	host_item.tether_reattach()

/datum/capability/tether_host/proc/host_moved(datum/act/A)
	var/obj/item/host_item = A.holder
	host_item.tether_check()

CAPABILITY_TYPE(tether_handheld, CAP_TETHER_HANDHELD, /datum/capability/tether_handheld, key = NONE)
/datum/capability/tether_handheld

/datum/capability/tether_handheld/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(handheld_moved))))

/datum/capability/tether_handheld/proc/handheld_moved(datum/act/A)
	var/obj/item/hand_held = A.holder
	var/obj/item/host_item = hand_held.tether_host()
	host_item?.tether_check()

/// Makes this item the host of a tethered `handheld_path`. Call before . = ..() in Initialize().
/obj/item/proc/make_tethered(handheld_path)
	tether_path = handheld_path
	grant(src, granted_verb(/obj/item/proc/toggle_tethered_handheld), src)
	actions_types += list(/datum/action/item_action/swap_tethered_item)
	grant(src, /datum/capability/tether_host, src)
	tether_make_handheld()

/// Takes the handheld out into `user`'s hands, or puts it back. TRUE if handled.
/obj/item/proc/tether_swap(mob/living/carbon/human/user)
	var/obj/item/hand_held = tethered_handheld()
	if(!hand_held)
		return FALSE
	if(hand_held.loc != src)
		tether_reattach()
		return TRUE
	//Detach the handset into the user's hands
	if(!tether_slot_check())
		if(ismob(loc))
			to_chat(user, span_warning("You need to equip \the [src] before taking out \the [hand_held]."))
		return FALSE
	if(!user.put_in_hands(hand_held))
		to_chat(user, span_warning("You need a free hand to hold the \the [hand_held]!"))
		return FALSE
	update_icon()
	hand_held.update_icon()
	to_chat(user,span_notice("You remove \the [hand_held] from \the [src]."))
	return TRUE

/// Makes the handheld if there is none.
/obj/item/proc/tether_make_handheld()
	if(!tether_path || tethered_handheld())
		return
	var/obj/item/hand_held = new tether_path(src)
	rel_set(hand_held, nameof(hand_held.tether_host_item), src)
	rel_set(src, nameof(tether_handheld_item), hand_held)
	grant(hand_held, /datum/capability/tether_handheld, hand_held)

/// after() target: remakes a deleted handheld.
/obj/item/proc/tether_remake_handheld()
	if(QDELETED(src) || !tether_path)
		return
	tether_make_handheld()
	update_icon()
	var/obj/item/remade = tethered_handheld()
	remade?.update_icon()

// Absolutely illegal to be anywhere else except in the slot you were allowed to remove it from
/obj/item/proc/tether_check()
	var/obj/item/hand_held = tethered_handheld()
	if(!hand_held || hand_held.loc == src) // handheld item is safely inside us
		return
	if(tether_slot_check() && hand_held.loc == loc) // We are safely worn by our mob, and handheld item is safely inside our mob
		return
	// PANIC
	tether_reattach()

/// Retracts the handheld back into this host.
/obj/item/proc/tether_reattach()
	var/obj/item/hand_held = tethered_handheld()
	if(!hand_held)
		return
	var/mob/handheld_mob = hand_held.loc
	if(istype(handheld_mob))
		to_chat(handheld_mob,span_notice("\The [hand_held] retracts back into \the [src]."))
		handheld_mob.drop_from_inventory(hand_held, src)
	else
		hand_held.forceMove(src)
	update_icon()
	hand_held.update_icon()

// By default this expects to be worn on your back
/obj/item/proc/tether_slot_check()
	var/mob/M = loc
	if(!istype(M))
		return FALSE
	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_BACK) == src)
		return TRUE
	if(HAS_TAG(src, TAG_WEAR_BELT) && M.get_equipped_item(SLOT_ID_BELT) == src)
		return TRUE
	if(M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src) // There is no flag for this, just a whitelist on the suits themselves
		return TRUE
	return FALSE

// Helper verbs
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/obj/item/proc/toggle_tethered_handheld()
	set name = "Remove/Replace Handset"
	set category = VERB_CAT_OBJECT

	// May only remove tethered while in the usr's direct inventory
	if(src.loc != usr)
		return
	tether_swap(usr)

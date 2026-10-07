// A handheld item on a tether to its host item (defib paddles, radio
// handsets, mediguns, proton packs). The host carries the tether_host capability (was
// /datum/component/tethered_item) and the handheld tether_handheld: together they keep the
// handheld in its host or its wearer's hands. Each end's activation data names the other end:
// the host's names its handheld (losing the handheld remakes it), the handheld's names its host
// (the host's capability ending, with the host, deletes the handheld).
//
// Set up with host.make_tethered(handheld_path) before . = ..() in Initialize().

/obj/item
	/// Path of the tethered handheld this host makes, or null (not a tether host).
	var/tether_path

/// The host side of a tether: the host and the handheld it made.
/datum/cap_data/tether_host
	var/obj/item/host
	var/obj/item/handheld

CAPABILITIES(/datum/cap_data/tether_host)
	ref_one(nameof(host), /obj/item)
	ref_one(nameof(handheld), /obj/item, on_unlink = PROC_REF(handheld_lost))

/// The handheld was deleted: a living host remakes it (out of the unlink).
/datum/cap_data/tether_host/proc/handheld_lost(obj/item/gone)
	if(QDELETED(host) || !host.tether_path)
		return
	after(host, 0, TYPE_PROC_REF(/obj/item, tether_remake_handheld))

/// The handheld side of a tether: its host.
/datum/cap_data/tether_handheld
	var/obj/item/host

CAPABILITIES(/datum/cap_data/tether_handheld)
	ref_one(nameof(host), /obj/item)

/// The handheld this host is tethered to, or null.
/obj/item/proc/tethered_handheld()
	RETURN_TYPE(/obj/item)
	var/datum/activation/A = cap_activation(src, CAP_TETHER_HOST, null)
	var/datum/cap_data/tether_host/D = A?.data
	return D?.handheld

/// The host this handheld is tethered to, or null.
/obj/item/proc/tether_host()
	RETURN_TYPE(/obj/item)
	var/datum/activation/A = cap_activation(src, CAP_TETHER_HANDHELD, null)
	var/datum/cap_data/tether_handheld/D = A?.data
	return D?.host

CAPABILITY_TYPE(tether_host, CAP_TETHER_HOST, /datum/capability/tether_host, key = NONE)
/datum/capability/tether_host

/datum/capability/tether_host/cap_data_type()
	return /datum/cap_data/tether_host

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
	var/datum/cap_data/tether_host/D = A.data
	var/obj/item/hand_held = D?.handheld
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

/datum/capability/tether_handheld/cap_data_type()
	return /datum/cap_data/tether_handheld

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
	redraw(src)
	redraw(hand_held)
	to_chat(user,span_notice("You remove \the [hand_held] from \the [src]."))
	return TRUE

/// Makes the handheld if there is none.
/obj/item/proc/tether_make_handheld()
	if(!tether_path || tethered_handheld())
		return
	var/datum/activation/host_side = cap_activation(src, CAP_TETHER_HOST, null)
	var/datum/cap_data/tether_host/host_data = host_side ? activation_data(host_side) : null
	if(!host_data)
		return
	var/obj/item/hand_held = new tether_path(src)
	var/datum/activation/handheld_side = grant(hand_held, /datum/capability/tether_handheld, hand_held)
	var/datum/cap_data/tether_handheld/handheld_data = handheld_side ? activation_data(handheld_side) : null
	rel_set(handheld_data, nameof(handheld_data.host), src)
	rel_set(host_data, nameof(host_data.host), src)
	rel_set(host_data, nameof(host_data.handheld), hand_held)

/// after() target: remakes a deleted handheld.
/obj/item/proc/tether_remake_handheld()
	if(QDELETED(src) || !tether_path)
		return
	tether_make_handheld()
	redraw(src)
	var/obj/item/remade = tethered_handheld()
	redraw(remade)

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
	redraw(src)
	redraw(hand_held)

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

/obj/item/bluespaceradio
	name = "bluespace radio"
	desc = "A powerful radio that uses a tiny bluespace wormhole to send signals directly to subspace receivers and transmitters, bypassing the limitations of subspace."
	icon = 'icons/obj/device.dmi'
	icon_override = 'icons/inventory/back/mob.dmi'
	icon_state = "radiopack"
	item_state = "radiopack"
	slot_flags = SLOT_BACK
	force = 5
	throwforce = 6
	preserve_item = 1
	w_class = ITEMSIZE_LARGE
	var/handset_path = /obj/item/radio/bluespacehandset/linked

/obj/item/bluespaceradio/Initialize(mapload)
	make_tethered(handset_path)
	. = ..()

CAPABILITIES(/obj/item/bluespaceradio)
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))
	drag_onto(PROC_REF(drop_input))

/// See important note in code/datums/behaviours/tethered_item.dm
/obj/item/bluespaceradio/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(tether_swap(user))
		return TRUE
	return OP_DECLINE

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). The worn pack is dragged into its wearer's hands.
/obj/item/bluespaceradio/proc/drop_input(datum/act/input/A)
	drag_backpack_with_actor(A.actor)
	return TRUE

/obj/item/bluespaceradio/proc/drag_backpack_with_actor(mob/user)
	if(ismob(loc))
		if(!CanMouseDrop(src, user))
			return
		var/mob/M = loc
		if(!M.unEquip(src))
			return
		add_fingerprint(user)
		M.put_in_any_hand_if_possible(src)

//Subspace Radio Handset
/obj/item/radio/bluespacehandset
	name = "bluespace radio handset"
	desc = "A large walkie talkie attached to the bluespace radio by a retractable cord. It sits comfortably on a slot in the radio when not in use."
	bluespace_radio = TRUE
	icon = 'icons/obj/device.dmi'
	icon_state = "handset"
	slot_flags = null
	w_class = ITEMSIZE_LARGE
	canhear_range = 1
	item_flags = NOSTRIP

/obj/item/radio/bluespacehandset/linked/receive_range(freq, list/level)
	//Only care about megabroadcasts or things that are targeted at us
	if(!(0 in level))
		return -1
	if(wire_is_cut(src, WIRE_RADIO_RECEIVER))
		return -1
	if(!listening)
		return -1
	if(!on)
		return -1
	if(!freq)
		return -1

	//Only listen on main freq
	if(freq == frequency)
		return canhear_range
	else
		return -1

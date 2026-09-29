/obj/structure/coatrack
	name = "coat rack"
	desc = "Rack that holds coats."
	icon = 'icons/obj/coatrack.dmi'
	icon_state = "coatrack0"
	var/coat_handle
	var/list/allowed = list(/obj/item/clothing/suit/storage/toggle/labcoat, /obj/item/clothing/suit/storage/det_trench) // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)

/obj/structure/coatrack/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/coatrack_hand,
		/datum/interaction/entry_item/coatrack_item,
	)
	..()

/// Old attack_hand: take the hung coat off the rack.
/datum/interaction/entry_hand/coatrack_hand
	id = "coatrack_hand"
	name = "Take coat"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/structure/coatrack/proc/coatrack_has_coat, null))
	effect = /obj/structure/coatrack/proc/interaction_hand

/obj/structure/coatrack/proc/coatrack_has_coat(mob/actor, atom/target, obj/item/held)
	return !!coat()

/obj/structure/coatrack/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	user.visible_message("[user] takes [coat()] off \the [src].", "You take [coat()] off the \the [src]")
	if(!user.put_in_active_hand(coat()))
		coat().forceMove(get_turf(user))
	coat_handle = null
	update_icon()
	return TRUE

/// Old attackby: hang a coat/labcoat on the rack.
/datum/interaction/entry_item/coatrack_item
	id = "coatrack_item"
	name = "Hang coat"
	effect = /obj/structure/coatrack/proc/interaction_item

/obj/structure/coatrack/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/can_hang = 0
	for (var/T in allowed)
		if(istype(W,T))
			can_hang = 1
	if (can_hang && !coat())
		user.visible_message("[user] hangs [W] on \the [src].", "You hang [W] on the \the [src]")
		coat_handle = om_handle(W)
		user.drop_from_inventory(coat(), src)
		update_icon()
	else
		to_chat(user, span_notice("You cannot hang [W] on [src]"))
	return TRUE

/obj/structure/coatrack/CanPass(atom/movable/mover, turf/target)
	var/can_hang = 0
	for (var/T in allowed)
		if(istype(mover,T))
			can_hang = 1

	if (can_hang && !coat())
		src.visible_message("[mover] lands on \the [src].")
		coat_handle = om_handle(mover)
		coat().forceMove(src)
		update_icon()
		return 0
	else
		return 1

DECLARE_APPEARANCE_PROC(/obj/structure/coatrack, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/coatrack/appearance_overlays()
	. = list()
	if (istype(coat(), /obj/item/clothing/suit/storage/toggle/labcoat))
		. += "coat_lab"
	if (istype(coat(), /obj/item/clothing/suit/storage/toggle/labcoat/cmo))
		. += "coat_cmo"
	if (istype(coat(), /obj/item/clothing/suit/storage/det_trench))
		. += "coat_det"

/// LC-refs: coat -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/coatrack/proc/coat() as /obj/item/clothing/suit
	return om_resolve(coat_handle)

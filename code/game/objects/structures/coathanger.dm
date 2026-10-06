/obj/structure/coatrack
	name = "coat rack"
	desc = "Rack that holds coats."
	icon = 'icons/obj/coatrack.dmi'
	icon_state = "coatrack0"
	var/obj/item/clothing/suit/coat
	var/list/allowed = list(/obj/item/clothing/suit/storage/toggle/labcoat, /obj/item/clothing/suit/storage/det_trench) // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)

CAPABILITIES(/obj/structure/coatrack)
	op("take_coat", hand(), label("Take coat"), when(nameof(coat)), then(PROC_REF(interaction_hand)))
	op("hang_coat", item(/obj/item), label("Hang coat"), then(PROC_REF(interaction_item)))

/// A hand takes the hung coat off the rack (offered only while one hangs there).
/obj/structure/coatrack/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF("You take [coat()] off %T%"), MSG_OTHERS("%U% takes [coat()] off %T%."))
	if(!user.put_in_active_hand(coat()))
		coat().forceMove(get_turf(user))
	rel_clear(src, nameof(coat))
	update_icon()
	return OP_OK

/// Anything held: a coat or a labcoat hangs on the rack; anything else is refused with a word.
/obj/structure/coatrack/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/can_hang = 0
	for (var/T in allowed)
		if(istype(W,T))
			can_hang = 1
	if (can_hang && !coat())
		if(!own_bring_in(src, nameof(coat), W, null, user, TRUE, null, FALSE))
			return OP_OK
		act_message(user, src, MSG_SELF("You hang [W] on %T%"), MSG_OTHERS("%U% hangs [W] on %T%."))
		rel_set(src, nameof(coat), W)
		update_icon()
	else
		to_chat(user, span_notice("You cannot hang [W] on [src]"))
	return OP_OK

/obj/structure/coatrack/CanPass(atom/movable/mover, turf/target)
	var/can_hang = 0
	for (var/T in allowed)
		if(istype(mover,T))
			can_hang = 1

	if (can_hang && !coat())
		src.visible_message("[mover] lands on \the [src].")
		rel_set(src, nameof(coat), mover)
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

/// Relation view: coat (reads null once it is gone).
/obj/structure/coatrack/proc/coat() as /obj/item/clothing/suit
	return coat

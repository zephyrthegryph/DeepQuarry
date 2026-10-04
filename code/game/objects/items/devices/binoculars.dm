/obj/item/binoculars
	name = "binoculars"
	desc = "A pair of binoculars."
	icon = 'icons/obj/device.dmi'
	icon_state = "binoculars"
	force = 5.0
	w_class = ITEMSIZE_SMALL
	throwforce = 5.0
	throw_range = 15
	throw_speed = 3
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE


CAPABILITIES(/obj/item/binoculars)
	op("zoom", in_hand(), then(PROC_REF(zoomed)))

/// Op payload arguments do not occupy zoom offset and view-size parameters. Someone looking through a remote view is too distracted to look through binoculars.
/obj/item/binoculars/proc/zoomed(datum/act/op/A)
	var/mob/user = A.actor
	var/refusal = zoom_view_allowed(user, src, null)
	if(refusal != TRUE)
		to_chat(user, span_warning(refusal))
		return OP_REFUSED
	zoom(user)
	return OP_OK

/obj/item/binoculars/spyglass
	name = "spyglass"
	desc = "It's a hand-held telescope, useful for star-gazing, peeping, and recon."
	icon_state = "spyglass"
	slot_flags = SLOT_BELT

/obj/item/binoculars/scope
	name = "rifle scope"
	desc = "It's a rifle scope. Would be better if it were actually attached to a rifle."
	icon_state = "rifle_scope"

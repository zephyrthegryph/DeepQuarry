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


MSG_DEF_SELF(binoculars/distracted, "You are too distracted to do that.")

CAPABILITIES(/obj/item/binoculars)
	op("zoom", in_hand(), label("Zoom"),
		needs(req(PROC_REF(view_available), because = MSG(binoculars/distracted))), then(PROC_REF(zoomed)))

/obj/item/binoculars/proc/view_available(datum/act/op/A)
	var/client/C = A.actor?.client // ALLOW(reads): native client view is queried immediately before instant zoom with no wait or prompt
	if(!C || !C.mob || !C.eye)
		return null
	if(isturf(C.mob.loc) && get_turf(C.eye) == get_turf(C.mob))
		return null
	if(ismecha(C.mob.loc) && C.eye == C.mob.loc)
		return null
	return (C.eye == C.mob) ? null : MSG(binoculars/distracted)

/// The op context does not occupy zoom's offset and view-size arguments.
/obj/item/binoculars/proc/zoomed(datum/act/op/A)
	zoom(A.actor)
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

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


DECLARE_INTERACTIONS(/obj/item/binoculars, INTERACT_USE(null, PROC_REF(interaction_zoom)))

/// Interaction payload arguments do not occupy zoom offset and view-size parameters.
/obj/item/binoculars/proc/interaction_zoom(mob/user, obj/item/held, datum/interaction/interaction)
	zoom(user)

/obj/item/binoculars/spyglass
	name = "spyglass"
	desc = "It's a hand-held telescope, useful for star-gazing, peeping, and recon."
	icon_state = "spyglass"
	slot_flags = SLOT_BELT

/obj/item/binoculars/scope
	name = "rifle scope"
	desc = "It's a rifle scope. Would be better if it were actually attached to a rifle."
	icon_state = "rifle_scope"

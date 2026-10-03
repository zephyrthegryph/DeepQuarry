/obj/item/wheelchair
	name = "wheelchair"
	desc = "A folded wheelchair that can be carried around."
	icon = 'icons/obj/wheelchair.dmi'
	icon_state = "wheelchair_folded"
	item_state = "wheelchair"
	w_class = ITEMSIZE_HUGE // Can't be put in backpacks. Oh well.
	var/unfolded_type = /obj/structure/bed/chair/wheelchair

CAPABILITIES(/obj/item/wheelchair)
	op("unfold", in_hand(), label("Unfold"), then(PROC_REF(unfolded)))

/// The folded chair is set up where its carrier stands, and is used up.
/obj/item/wheelchair/proc/unfolded(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/bed/chair/wheelchair/R = new unfolded_type(user.loc)
	R.add_fingerprint(user)
	R.name = src.name
	R.color = src.color
	consume(src, user)
	return OP_OK

/obj/item/wheelchair/motor
	name = "electric wheelchair"
	desc = "A motorized wheelchair controlled with a joystick on one armrest"
	icon_state = "motorchair_folded"
	item_state = "motorchair"
	unfolded_type = /obj/structure/bed/chair/wheelchair/motor

/obj/item/wheelchair/motor/small
	name = "small electric wheelchair"
	desc = "A small motorized wheelchair, it looks around the right size for a Teshari."
	icon_state = "teshchair_folded"
	item_state = "teshchair"
	unfolded_type = /obj/structure/bed/chair/wheelchair/smallmotor

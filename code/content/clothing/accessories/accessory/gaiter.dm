//Gaiter scarves
/obj/item/clothing/accessory/gaiter
	name = "red neck gaiter"
	desc = "A slightly worn neck gaiter, it's loose enough to be worn comfortably like a scarf. Commonly used by outdoorsmen and mercenaries, both to keep warm and keep debris away from the face."
	icon_state = "gaiter_red"
	w_class = ITEMSIZE_SMALL
	slot = ACCESSORY_SLOT_INSIGNIA // snowflakey, i know, shut up
	var/breath_masked = FALSE
	var/obj/item/clothing/mask/breath/breathmask
	special_handling = TRUE

/// Old attackby: tuck a breath mask behind the gaiter. Always falls through, as the old ..() did.
/obj/item/clothing/accessory/gaiter/proc/gaiter_tuck_mask_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/clothing/mask/breath))
		if(!own_bring_in(src, nameof(breathmask), I, null, user, TRUE, null, FALSE))
			return OP_DECLINE
		if(breathmask())
			gaiter_remove_mask_alt(A)
		to_chat(user, span_notice("You tuck [I] behind [src]."))
		rel_set(src, nameof(breathmask), I)
		breath_masked = TRUE
		set_item_flags(worn_of(src).flags & (~FLEXIBLEMATERIAL))
	return OP_DECLINE

/// Old click_alt: pull the tucked mask out. Falls through to the clothing alt-click (which ran first before).
/obj/item/clothing/accessory/gaiter/proc/gaiter_remove_mask_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(breath_masked && breathmask())
		var/obj/item/clothing/mask/breath/pulled = rel_take(src, nameof(breathmask))
		to_chat(user, span_notice("You pull [pulled] out from behind [src], and it drops to your feet."))
		pulled.forceMove(drop_location())
		breath_masked = FALSE
		set_item_flags(worn_of(src).flags & (~AIRTIGHT))
		set_item_flags(worn_of(src).flags | (FLEXIBLEMATERIAL))
	return OP_DECLINE

/// Old attack_self: pull the gaiter up or down.
/obj/item/clothing/accessory/gaiter/proc/gaiter_adjust_self(datum/act/op/A)
	var/mob/user = A.actor
	var/gaiterstring = "You pull [src] "
	if(src.icon_state == initial(icon_state))
		set_icon_state("[icon_state]_up")
		gaiterstring += "up over your nose[breath_masked ? " and secure the mask tucked underneath." : "."]"
		if(breath_masked)
			set_item_flags(worn_of(src).flags | (AIRTIGHT))
	else
		set_icon_state(initial(icon_state))
		gaiterstring += "down around your neck[breath_masked ? " and dislodge the mask tucked underneath." : "."]"
		set_body_parts_covered(worn_of(src).covers & (~FACE))
		if(breath_masked)
			set_item_flags(worn_of(src).flags & (~AIRTIGHT))
	to_chat(user, span_notice(gaiterstring))

/obj/item/clothing/accessory/gaiter/half //functions like a gaiter
	name = "black half-mask"
	icon_state = "half_mask"

/// the breathmask this refers to (a relation view: null once it is deleted).
/obj/item/clothing/accessory/gaiter/proc/breathmask() as /obj/item/clothing/mask/breath
	return breathmask

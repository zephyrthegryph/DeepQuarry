/obj/item/trash/cigbutt
	name = "cigarette butt"
	desc = "A manky old cigarette butt."
	icon = 'icons/inventory/face/item.dmi'
	icon_state = "cigbutt"
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/trash/cigbutt)
	configure(item_handling(randpixel = 10))
	configure(item_worn(slots = SLOT_EARS))
	configure(item_thrown(force = 1))
	rolls(ROLL_PIXEL, PIXEL_JITTER(10))
	rolls(nameof(transform), PROC_REF(roll_transform))

/// Rolled before init (rolls()): a butt lies at any angle.
/obj/item/trash/cigbutt/proc/roll_transform(datum/roller/R)
	return turn(transform, R.number(0, 360))

/obj/item/trash/cigbutt/cigarbutt
	name = "cigar butt"
	desc = "A manky old cigar butt."
	icon_state = "cigarbutt"

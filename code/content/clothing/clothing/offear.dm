/obj/item/clothing/ears/offear
	name = "Other ear"
	w_class = ITEMSIZE_HUGE
	icon = 'icons/mob/screen1_Midnight.dmi'
	icon_state = "block"

CAPABILITIES(/obj/item/clothing/ears/offear)
	configure(item_worn(slots = SLOT_EARS | SLOT_TWOEARS))
	derives(nameof(name), PROC_REF(containing_item_field))
	derives(nameof(desc), PROC_REF(containing_item_field))
	derives(nameof(icon), PROC_REF(containing_item_field))
	derives(nameof(icon_state), PROC_REF(containing_item_field))
	derives(nameof(dir), PROC_REF(containing_item_field))

/// A one-time constructor snapshot, not a live link to the original item's later appearance.
/obj/item/clothing/ears/offear/proc/containing_item_field(target)
	var/obj/O = isobj(loc) ? loc : src
	switch(target)
		if(nameof(name))
			return O.name
		if(nameof(desc))
			return O.desc
		if(nameof(icon))
			return O.icon
		if(nameof(icon_state))
			return O.icon_state
		if(nameof(dir))
			return O.dir

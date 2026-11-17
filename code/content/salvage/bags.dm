/obj/item/storage/bag/salvage
	name = "treasure satchel"
	desc = "A satchel for storing scavenged salvage. There be tresure."
	icon = 'icons/obj/mining.dmi'
	w_class = ITEMSIZE_NORMAL
	storage_slots = 15


CAPABILITIES(/obj/item/storage/bag/salvage)
	configure(item_worn(slots = SLOT_BELT | SLOT_POCKET))
	configure(storage(accepts = list(/obj/item/salvage), max_size = ITEMSIZE_NORMAL))

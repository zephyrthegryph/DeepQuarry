/obj/item/storage/bag/salvage
	name = "treasure satchel"
	desc = "A satchel for storing scavenged salvage. There be tresure."
	icon = 'icons/obj/mining.dmi'
	slot_flags = SLOT_BELT | SLOT_POCKET
	w_class = ITEMSIZE_NORMAL
	storage_slots = 15


CAPABILITIES(/obj/item/storage/bag/salvage)
	configure(storage(accepts = list(/obj/item/salvage), max_size = ITEMSIZE_NORMAL))

/obj/item/storage/bag/salvage/bluespace
	name = "bluespace treasure satchel"
	desc = "A satchel to store even more scavenged salvage! There be lots of treasure."
	storage_slots = 30
	icon_state = "satchel_bspace"

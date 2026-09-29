/obj/item/storage/bag/salvage
	name = "treasure satchel"
	desc = "A satchel for storing scavenged salvage. There be tresure."
	icon = 'icons/obj/mining.dmi'
	slot_flags = SLOT_BELT | SLOT_POCKET
	w_class = ITEMSIZE_NORMAL
	storage_slots = 15

TYPE_TABLE(/obj/item/storage/bag/salvage, hold_spec, list(HOLD_ONLY(list(/obj/item/salvage)), HOLD_MAX_SIZE(ITEMSIZE_NORMAL)))

/obj/item/storage/bag/salvage/bluespace
	name = "bluespace treasure satchel"
	desc = "A satchel to store even more scavenged salvage! There be lots of treasure."
	storage_slots = 30
	icon_state = "satchel_bspace"

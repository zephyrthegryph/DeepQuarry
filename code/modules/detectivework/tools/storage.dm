/obj/item/storage/box/swabs
	name = "box of swab kits"
	desc = "Sterilized equipment within. Do not contaminate."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "dnakit"
	storage_slots = 14

TYPE_TABLE(/obj/item/storage/box/swabs, hold_spec, list(HOLD_ONLY(list(/obj/item/forensics/swab)), HOLD_MAX_SIZE(ITEMSIZE_SMALL)))

/obj/item/storage/box/swabs/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots) // Fill 'er up.
		new /obj/item/forensics/swab(src)

/obj/item/storage/box/evidence
	name = "evidence bag box"
	desc = "A box claiming to contain evidence bags."
	storage_slots = 7

TYPE_TABLE(/obj/item/storage/box/evidence, hold_spec, list(HOLD_ONLY(list(/obj/item/evidencebag)), HOLD_MAX_SIZE(ITEMSIZE_SMALL)))

/obj/item/storage/box/evidence/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots)
		new /obj/item/evidencebag(src)

/obj/item/storage/box/fingerprints
	name = "box of fingerprint cards"
	desc = "Sterilized equipment within. Do not contaminate."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "dnakit"
	storage_slots = 14

TYPE_TABLE(/obj/item/storage/box/fingerprints, hold_spec, list(HOLD_ONLY(list(/obj/item/sample/print)), HOLD_MAX_SIZE(ITEMSIZE_SMALL)))

/obj/item/storage/box/fingerprints/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots)
		new /obj/item/sample/print(src)

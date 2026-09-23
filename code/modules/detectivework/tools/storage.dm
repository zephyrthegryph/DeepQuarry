/obj/item/storage/box/swabs
	name = "box of swab kits"
	desc = "Sterilized equipment within. Do not contaminate."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "dnakit"
	storage_slots = 14

/obj/item/storage/box/swabs/hold_constraint()
	var/list/holds = list(/obj/item/forensics/swab)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_SMALL))

/obj/item/storage/box/swabs/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots) // Fill 'er up.
		new /obj/item/forensics/swab(src)

/obj/item/storage/box/evidence
	name = "evidence bag box"
	desc = "A box claiming to contain evidence bags."
	storage_slots = 7

/obj/item/storage/box/evidence/hold_constraint()
	var/list/holds = list(/obj/item/evidencebag)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_SMALL))

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

/obj/item/storage/box/fingerprints/hold_constraint()
	var/list/holds = list(/obj/item/sample/print)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_SMALL))

/obj/item/storage/box/fingerprints/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots)
		new /obj/item/sample/print(src)

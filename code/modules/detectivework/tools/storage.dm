/obj/item/storage/box/swabs
	name = "box of swab kits"
	desc = "Sterilized equipment within. Do not contaminate."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "dnakit"
	storage_slots = 14


CAPABILITIES(/obj/item/storage/box/swabs, \
	configure(storage(accepts = list(/obj/item/forensics/swab))))

/obj/item/storage/box/swabs/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots) // Fill 'er up.
		new /obj/item/forensics/swab(src)

/obj/item/storage/box/evidence
	name = "evidence bag box"
	desc = "A box claiming to contain evidence bags."
	storage_slots = 7


CAPABILITIES(/obj/item/storage/box/evidence, \
	configure(storage(accepts = list(/obj/item/evidencebag))))

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


CAPABILITIES(/obj/item/storage/box/fingerprints, \
	configure(storage(accepts = list(/obj/item/sample/print))))

/obj/item/storage/box/fingerprints/Initialize(mapload)
	. = ..()
	for(var/i = 1 to storage_slots)
		new /obj/item/sample/print(src)

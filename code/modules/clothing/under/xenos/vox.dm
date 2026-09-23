/obj/item/clothing/under/vox
	has_sensor = 0
	starting_accessories = list(/obj/item/clothing/accessory/storage/vox)	// Dont' start with a backback, so free webbing
	flags = PHORONGUARD

/obj/item/clothing/under/vox/fit_constraint()
	var/list/bodytypes = list(SPECIES_VOX)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/clothing/under/vox/vox_casual
	name = "alien clothing"
	desc = "This doesn't look very comfortable."
	icon_state = "vox-casual-1"
	item_state = "vox-casual-1"
	body_parts_covered = LEGS

/obj/item/clothing/under/vox/vox_robes
	name = "alien robes"
	desc = "Weird and flowing!"
	icon_state = "vox-casual-2"
	item_state = "vox-casual-2"

//Vox Accessories
/obj/item/clothing/accessory/storage/vox
	name = "alien mesh"
	desc = "An alien mesh. Seems to be made up mostly of pockets and writhing flesh."
	icon_state = "webbing-vox"

	flags = PHORONGUARD

	slots = 3

/obj/item/clothing/accessory/storage/vox/Initialize(mapload)
	. = ..()
	hold.max_storage_space = slots * ITEMSIZE_COST_NORMAL
	hold.restrict_hold(null, ITEMSIZE_NORMAL)

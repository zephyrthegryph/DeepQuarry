/obj/item/clothing/suit/armor/vox_scrap
	name = "rusted metal armor"
	desc = "A hodgepodge of various pieces of metal scrapped together into a rudimentary vox-shaped piece of armor."
	armor_spec = "melee=60;bullet=30;laser=30;energy=5;bomb=40" //Higher melee armor versus lower everything else.
	icon_state = "vox-scrap"
	icon_state = "vox-scrap"
	body_parts_covered = CHEST|ARMS|LEGS
	siemens_coefficient = 1 //Its literally metal
	resistance_flags = FIRE_PROOF

/obj/item/clothing/suit/armor/vox_scrap/fit_constraint()
	var/list/bodytypes = list(SPECIES_VOX)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/clothing/suit/armor/vox_scrap/suit_storage_constraint()
	var/list/stores = list(POCKET_EMERGENCY, POCKET_EXPLO, POCKET_ALL_TANKS)
	return list(HOLD_ONLY(stores))

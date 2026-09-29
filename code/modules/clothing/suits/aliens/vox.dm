/obj/item/clothing/suit/armor/vox_scrap
	name = "rusted metal armor"
	desc = "A hodgepodge of various pieces of metal scrapped together into a rudimentary vox-shaped piece of armor."
	armor_spec = "melee=60;bullet=30;laser=30;energy=5;bomb=40" //Higher melee armor versus lower everything else.
	icon_state = "vox-scrap"
	icon_state = "vox-scrap"
	body_parts_covered = CHEST|ARMS|LEGS
	siemens_coefficient = 1 //Its literally metal
	resistance_flags = FIRE_PROOF

TYPE_TABLE(/obj/item/clothing/suit/armor/vox_scrap, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_VOX))))

TYPE_TABLE(/obj/item/clothing/suit/armor/vox_scrap, suit_storage_spec, list(HOLD_ONLY(list(POCKET_EMERGENCY, POCKET_EXPLO, POCKET_ALL_TANKS))))

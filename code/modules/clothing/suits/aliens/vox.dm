/obj/item/clothing/suit/armor/vox_scrap
	name = "rusted metal armor"
	desc = "A hodgepodge of various pieces of metal scrapped together into a rudimentary vox-shaped piece of armor."
	armor_spec = "melee=60;bullet=30;laser=30;energy=5;bomb=40" //Higher melee armor versus lower everything else.
	icon_state = "vox-scrap"
	icon_state = "vox-scrap"
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/suit/armor/vox_scrap)
	fits_as(FIT_VOX)
	suit_storage(list(POCKET_EMERGENCY, POCKET_EXPLO, POCKET_ALL_TANKS))
	configure(item_worn(covers = CHEST|ARMS|LEGS))
	configure(item_protection(siemens = 1))

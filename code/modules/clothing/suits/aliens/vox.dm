/obj/item/clothing/suit/armor/vox_scrap
	name = "rusted metal armor"
	desc = "A hodgepodge of various pieces of metal scrapped together into a rudimentary vox-shaped piece of armor."
	armor_spec = "melee=60;bullet=30;laser=30;energy=5;bomb=40" //Higher melee armor versus lower everything else.
	icon_state = "vox-scrap"
	icon_state = "vox-scrap"
	body_parts_covered = CHEST|ARMS|LEGS
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/suit/armor/vox_scrap)
	acceptance("fit", fits(list(SPECIES_VOX)), mode = ACCEPTANCE_REPLACE)
	acceptance("suit_storage", req_acceptance_type(list(POCKET_EMERGENCY, POCKET_EXPLO, POCKET_ALL_TANKS), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_protection(siemens = 1))

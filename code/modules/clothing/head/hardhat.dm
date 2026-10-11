/*
 * Contains:
 *		Hard Hats
 *		Firefighter Hats
 *		Ranger Hats
 */

/*
 * Hard Hats
 */

/obj/item/clothing/head/hardhat
	name = "hard hat"
	desc = "A piece of headgear used in dangerous working conditions to protect the head. Comes with a built-in flashlight."
	icon_state = "hardhat0_yellow"
	light_range = 4 //luminosity when on
	light_cone_y_offset = 14
	light_overlay = "hardhat_light"
	armor_spec = "melee=30;bullet=5;laser=20;energy=10;bomb=20;bio=10;rad=20"
	actions_types = list(/datum/action/item_action/toggle_head_light)
	w_class = ITEMSIZE_NORMAL
	ear_protection = 1
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/head/hardhat)
	configure(item_worn(hides = 0))
	configure(item_protection(siemens = 0.9))
	configure(item_sounds(drop = SFX_ITEMS_DROP_HELM, pickup = SFX_ITEMS_PICKUP_HELM))

/obj/item/clothing/head/hardhat/orange
	icon_state = "hardhat0_orange"
	name = "orange hard hat"

/obj/item/clothing/head/hardhat/white
	icon_state = "hardhat0_white"
	name = "sleek hard hat"

/obj/item/clothing/head/hardhat/dblue
	name = "blue hard hat"
	icon_state = "hardhat0_dblue"

/*
 * Firefighter Hats
 */

/obj/item/clothing/head/hardhat/red
	icon_state = "hardhat0_red"
	name = "emergency fire helmet"

CAPABILITIES(/obj/item/clothing/head/hardhat/red)
	configure(item_protection(max_heat = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE, min_pressure = 0.2* ONE_ATMOSPHERE, max_pressure = 20 * ONE_ATMOSPHERE))

/obj/item/clothing/head/hardhat/firefighter
	name = "firefighter helmet"
	desc = "A helmet with face mask specially designed for firefighting. It's airtight and has a port for internals."
	icon_state = "helmet_firefighter"
	flash_protection = FLASH_PROTECTION_MODERATE
	sprite_sheets = list(
		SPECIES_TAJARAN = 'icons/inventory/head/mob_tajaran.dmi',
		SPECIES_UNATHI = 'icons/inventory/head/mob_unathi.dmi'
		)

CAPABILITIES(/obj/item/clothing/head/hardhat/firefighter)
	configure(item_worn(flags = THICKMATERIAL | AIRTIGHT, hides = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE|BLOCKHAIR, covers = HEAD|FACE|EYES))
	configure(item_protection(permeability = 0, max_heat = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE+5000, min_pressure = 0.5 * ONE_ATMOSPHERE, max_pressure = 20 * ONE_ATMOSPHERE, min_cold = SPACE_HELMET_MIN_COLD_PROTECTION_TEMPERATURE))

/obj/item/clothing/head/hardhat/firefighter/atmos
	name = "atmospheric firefighter helmet"
	desc = "An atmospheric firefighter's helmet, includes a face mask specially designed for firefighting. It's airtight and has a port for internals."
	icon_state = "atmos_fire"

CAPABILITIES(/obj/item/clothing/head/hardhat/firefighter/atmos)
	configure(item_protection(max_heat = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE + 10000))

/obj/item/clothing/head/hardhat/firefighter/chief
	name = "chief firefighter helmet"
	desc = "A helmet with face mask specially designed for firefighting. This one is in the colors of the " + JOB_CHIEF_ENGINEER + ". It's airtight and has a port for internals."
	icon_state = "helmet_firefighter_ce"

CAPABILITIES(/obj/item/clothing/head/hardhat/firefighter/chief)
	configure(item_protection(max_heat = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE + 10000))

/obj/item/clothing/head/hardhat/old
	name = "classic hard hat"
	icon_state = "hardhat0_old_yellow"
	light_overlay = "hardhat_light_old"

/obj/item/clothing/head/hardhat/orange/old
	name = "classic orange hard hat"
	icon_state = "hardhat0_old_orange"
	light_overlay = "hardhat_light_old"

/obj/item/clothing/head/hardhat/white/old
	name = "classic sleek hard hat"
	icon_state = "hardhat0_old_white"
	light_overlay = "hardhat_light_old"

/obj/item/clothing/head/hardhat/dblue/old
	name = "classic blue hard hat"
	icon_state = "hardhat0_old_dblue"
	light_overlay = "hardhat_light_old"

/obj/item/clothing/head/hardhat/red/old
	name = "classic fire helmet"
	icon_state = "hardhat0_old_red"
	light_overlay = "hardhat_light_old"

/obj/item/clothing/head/hardhat/firefighter/old
	name = "classic firefighter helmet"
	icon_state = "helmet_firefighter_old"
	sprite_sheets = list(
		SPECIES_TAJARAN = 'icons/inventory/head/mob_tajaran.dmi'
		)

/obj/item/clothing/head/hardhat/firefighter/atmos/old
	name = "classic atmospheric firefighter helmet"
	icon_state = "atmos_fire_old"
	sprite_sheets = list(
		SPECIES_TAJARAN = 'icons/inventory/head/mob_tajaran.dmi'
		)

/obj/item/clothing/head/hardhat/firefighter/chief/old
	name = "classic chief firefighter helmet"
	icon_state = "helmet_firefighter_ce_old"
	sprite_sheets = list(
		SPECIES_TAJARAN = 'icons/inventory/head/mob_tajaran.dmi'
		)

/*
 * Ranger Hats
 */

	//Missing onmob sprites.


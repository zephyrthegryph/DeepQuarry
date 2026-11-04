///////////////////////////////////////////////////////////////////////
//Mask
/obj/item/clothing/mask
	name = "mask"
	icon = 'icons/inventory/face/item.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_masks.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_masks.dmi',
		)
	blood_sprite_state = "maskblood"
	item_icons = list(
		slot_wear_mask_str = 'icons/inventory/face/mob.dmi'
		)
	sprite_sheets = list(
		SPECIES_TESHARI		= 'icons/inventory/face/mob_teshari.dmi',
		SPECIES_VOX 		= 'icons/inventory/face/mob_vox.dmi',
		SPECIES_TAJARAN 	= 'icons/inventory/face/mob_tajaran.dmi',
		SPECIES_UNATHI 		= 'icons/inventory/face/mob_unathi.dmi',
		SPECIES_SERGAL 		= 'icons/inventory/face/mob_sergal.dmi',
		SPECIES_NEVREAN 	= 'icons/inventory/face/mob_nevrean.dmi',
		SPECIES_ZORREN_HIGH	= 'icons/inventory/face/mob_fox.dmi',
		SPECIES_ZORREN_FLAT = 'icons/inventory/face/mob_fennec.dmi',
		SPECIES_AKULA 		= 'icons/inventory/face/mob_akula.dmi',
		SPECIES_VULPKANIN 	= 'icons/inventory/face/mob_vulpkanin.dmi',
		SPECIES_XENOCHIMERA	= 'icons/inventory/face/mob_tajaran.dmi',
		SPECIES_WEREBEAST	= 'icons/inventory/face/mob_werebeast.dmi'
		)

	var/voicechange = 0
	var/list/say_messages
	var/list/say_verbs

CAPABILITIES(/obj/item/clothing/mask)
	configure(item_worn(slots = SLOT_MASK, covers = HEAD|FACE|EYES))
	configure(item_protection(heat_parts = FALSE, cold_parts = FALSE))
	configure(item_sounds(drop = SFX_GENERIC_DROP, pickup = SFX_GENERIC_PICKUP))

/obj/item/clothing/mask/proc/filter_air(datum/gas_mixture/air)
	return

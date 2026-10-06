/*
 * SC Engineering
 */


/obj/structure/closet/secure_closet/engineering_chief_wardrobe
	name = "chief engineer's wardrobe"
	req_access = list(ACCESS_CE)
	closet_appearance = /datum/decl/closet_appearance/secure_closet/engineering/ce

	starts_with = list(
		/obj/item/clothing/under/rank/chief_engineer,
		/obj/item/clothing/under/rank/chief_engineer/skirt,
		/obj/item/clothing/head/hardhat/white,
		/obj/item/clothing/shoes/brown,
		/obj/item/cartridge/ce,
		/obj/item/radio/headset/heads/ce,
		/obj/item/radio/headset/alt/heads/ce,
		/obj/item/clothing/suit/storage/hazardvest,
		/obj/item/clothing/mask/gas,
		/obj/item/tank/emergency/oxygen/engi,
		/obj/item/taperoll/engineering,
		/obj/item/clothing/suit/storage/hooded/wintercoat/engineering)

CAPABILITIES(/obj/structure/closet/secure_closet/engineering_chief_wardrobe)
	rolls(nameof(starts_with), PROC_REF(roll_starts_with))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/closet/secure_closet/engineering_chief_wardrobe/proc/roll_starts_with(datum/roller/R)
	. = islist(starts_with) ? list() + starts_with : starts_with
	if(R.chance(50))
		. += /obj/item/storage/backpack/industrial
	else
		. += /obj/item/storage/backpack/satchel/eng
	if(R.chance(50))
		. += /obj/item/storage/backpack/dufflebag/eng


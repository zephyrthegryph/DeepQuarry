/*
 * SC Security
 */


/obj/structure/closet/secure_closet/hos_wardrobe
	name = "head of security's locker"
	req_access = list(ACCESS_HOS)
	closet_appearance = /datum/decl/closet_appearance/secure_closet/security/hos

	starts_with = list(
		/obj/item/clothing/under/rank/head_of_security/jensen,
		/obj/item/clothing/under/rank/head_of_security/corp,
		/obj/item/clothing/suit/storage/vest/hoscoat/jensen,
		/obj/item/clothing/suit/storage/vest/hoscoat,
		/obj/item/cartridge/hos,
		/obj/item/radio/headset/heads/hos,
		/obj/item/clothing/glasses/sunglasses/sechud,
		/obj/item/storage/box/holobadge/hos,
		/obj/item/clothing/accessory/badge/holo/hos,
		/obj/item/clothing/accessory/holster/waist,
		/obj/item/clothing/head/beret/sec/corporate/hos,
		/obj/item/clothing/mask/gas/half)

CAPABILITIES(/obj/structure/closet/secure_closet/hos_wardrobe)
	rolls(nameof(starts_with), PROC_REF(roll_starts_with))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/closet/secure_closet/hos_wardrobe/proc/roll_starts_with(datum/roller/R)
	. = islist(starts_with) ? list() + starts_with : starts_with
	if(R.chance(50))
		. += /obj/item/storage/backpack/security
	else
		. += /obj/item/storage/backpack/satchel/sec
	if(R.chance(50))
		. += /obj/item/storage/backpack/dufflebag/sec


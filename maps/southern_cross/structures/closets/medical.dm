/*
 * SC Medical
 */


/obj/structure/closet/secure_closet/CMO_wardrobe
	name = "chief medical officer's locker"
	req_access = list(ACCESS_CMO)
	closet_appearance = /datum/decl/closet_appearance/secure_closet/cmo

	starts_with = list(
		/obj/item/clothing/under/rank/chief_medical_officer,
		/obj/item/clothing/under/rank/chief_medical_officer/skirt,
		/obj/item/clothing/suit/storage/toggle/labcoat/cmo,
		/obj/item/clothing/suit/storage/toggle/labcoat/cmoalt,
		/obj/item/clothing/suit/storage/toggle/labcoat/modern/cmo,
		/obj/item/cartridge/cmo,
		/obj/item/clothing/gloves/sterile/latex,
		/obj/item/clothing/shoes/brown,
		/obj/item/radio/headset/heads/cmo,
		/obj/item/clothing/suit/storage/hooded/wintercoat/medical,
		/obj/item/clothing/shoes/white)

CAPABILITIES(/obj/structure/closet/secure_closet/CMO_wardrobe)
	initial_contents(pick_one(list(/obj/item/storage/backpack/medic, /obj/item/storage/backpack/satchel/med)))
	initial_contents(/obj/item/storage/backpack/dufflebag/med, chance = 50)
	initial_contents(PROC_REF(roll_scrubs))


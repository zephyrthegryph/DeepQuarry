/obj/structure/closet/secure_closet/hydroponics
	name = "botanist's locker"
	req_access = list(ACCESS_HYDROPONICS)
	closet_appearance = /datum/decl/closet_appearance/secure_closet/hydroponics

	starts_with = list(
		/obj/item/storage/bag/plants,
		/obj/item/clothing/under/rank/hydroponics,
		/obj/item/clothing/gloves/botanic_leather,
		/obj/item/analyzer/plant_analyzer,
		/obj/item/radio/headset/service,
		/obj/item/radio/headset/alt/service,
		/obj/item/radio/headset/earbud/service,
		/obj/item/clothing/head/greenbandana,
		/obj/item/shovel/spade,
		/obj/item/material/minihoe,
		/obj/item/material/knife/machete/hatchet,
		/obj/item/reagent_containers/glass/beaker = 2,
		/obj/item/tool/wirecutters/clippers/trimmers,
		/obj/item/reagent_containers/spray/plantbgone,
		/obj/item/clothing/suit/storage/hooded/wintercoat/hydro,
		/obj/item/clothing/shoes/boots/winter/hydro,
		/obj/item/storage/belt/hydro,
		/obj/item/material/fishing_net/butterfly_net)

CAPABILITIES(/obj/structure/closet/secure_closet/hydroponics)
	rolls(nameof(starts_with), PROC_REF(roll_starts_with))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/closet/secure_closet/hydroponics/proc/roll_starts_with(datum/roller/R)
	. = islist(starts_with) ? list() + starts_with : starts_with
	if(R.chance(50))
		. += /obj/item/clothing/suit/storage/apron
	else
		. += /obj/item/clothing/suit/storage/apron/overalls

/obj/structure/closet/secure_closet/hydroponics/sci
	name = "xenoflorist's locker"
	req_access = list(ACCESS_XENOBIOLOGY)
	closet_appearance = /datum/decl/closet_appearance/secure_closet/hydroponics/xenoflora

CAPABILITIES(/obj/structure/closet/secure_closet/hydroponics/sci)
	rolls(nameof(starts_with), PROC_REF(roll_starts_with))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/closet/secure_closet/hydroponics/sci/roll_starts_with(datum/roller/R)
	. = islist(starts_with) ? list() + starts_with : starts_with
	. += /obj/item/clothing/head/bio_hood/scientist
	. += /obj/item/clothing/suit/bio_suit/scientist
	. += /obj/item/clothing/mask/gas/clear
	if(R.chance(1))
		. += /obj/item/chainsaw


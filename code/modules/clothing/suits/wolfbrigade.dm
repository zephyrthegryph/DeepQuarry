//Putting all the wolfbrigade stuff here because stupidop armor
/obj/item/clothing/suit/armor/wolfbrigade
	name = "Protect Gear chestpiece"
	desc = "Die Wölfe sind geschützt"
	icon = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_override = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_state = "wbsuit"
	item_state = "wbsuit-mob"
	blood_overlay_type = "suit"
	armor_spec = "melee=80;bullet=70;laser=50;energy=50;bomb=100;rad=10"

CAPABILITIES(/obj/item/clothing/suit/armor/wolfbrigade)
	configure(item_worn(covers = UPPER_TORSO))

/obj/item/clothing/suit/storage/armor/wolfbrigade2
	name = "Protect Gear chestpiece mod"
	desc = "Die Wölfe können mehr tragen"
	icon = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_override = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_state = "wbsuit2"
	item_state = "wbsuit2-mob"
	blood_overlay_type = "suit"
	slowdown = 0.5
	armor_spec = "melee=80;bullet=70;laser=50;energy=50;bomb=100;rad=10"

CAPABILITIES(/obj/item/clothing/suit/storage/armor/wolfbrigade2)
	configure(item_worn(covers = UPPER_TORSO))

/obj/item/clothing/mask/gas/wolfbrigade
	name = "Protect Gear mask"
	desc = "Die Wölfe können atmen"
	icon = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_override = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_state = "wbmask-mob"
	item_state = "wbmask-mob"
	item_state_slots = list(slot_r_hand_str = "gas", slot_l_hand_str = "gas")
	armor_spec = "melee=60;bullet=50;laser=30;energy=30;bomb=80;bio=20;rad=10"

CAPABILITIES(/obj/item/clothing/mask/gas/wolfbrigade)
	configure(item_worn(covers = HEAD|FACE|EYES))

/obj/item/clothing/head/helmet/wolfbrigade
	name = "Protect Gear helmet"
	desc = "Die Wölfe haben Köpfe aus Eisen"
	icon = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_override = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_state = "wbhelmet"
	item_state = "wbhelmet-mob"
	armor_spec = "melee=60;bullet=50;laser=30;energy=30;bomb=80;rad=10"

/obj/item/clothing/shoes/combat/wolfbrigade
	name = "Protect Gear boots"
	desc = "Die Wölfe können nicht ausrutschen"
	icon = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_override = 'icons/obj/clothing/wolfbrigade.dmi'
	icon_state = "wbboots-mob"
	item_state = "wbboots-mob"
	armor_spec = "melee=60;bullet=60;laser=40;energy=30;bomb=50;rad=10"

CAPABILITIES(/obj/item/clothing/shoes/combat/wolfbrigade)
	configure(item_worn(flags = NOSLIP))
	configure(item_combat(force = 5))
	configure(item_protection(siemens = 0.6, cold_parts = FEET, min_cold = SHOE_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = FEET, max_heat = SHOE_MAX_HEAT_PROTECTION_TEMPERATURE))

/obj/item/clothing/gloves/arm_guard/combat/wolfbrigade
	name = "Protect Gear armguards"
	desc = "Die Wölfe haben scharfe krallen" // 2 edgy

/obj/item/clothing/under/acj/wolfbrigade //Because never OP enough when you want to adminbuse
	name = "Kerberos uniform"
	desc = "Fürchte die Wölfe"

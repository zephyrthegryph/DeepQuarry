//Advanced Exploration 	Suit
/obj/item/rig/robotics
	name = "advanced suit control belt"
	suit_type = "advanced"
	desc = "A lightweight suit combining the utility of a RIG with the wearability of a voidsuit."
	icon_state = "void_explorer2"
	armor_spec = "melee=40;bullet=30;laser=20;energy=15;bomb=30;bio=100;rad=50"
	slowdown = 0.5
	offline_slowdown = 1
	offline_vision_restriction = 0
	emp_protection = -20
	rigsuit_max_pressure = 8 * ONE_ATMOSPHERE
	rigsuit_min_pressure = 0

	chest_type = /obj/item/clothing/suit/space/rig/advsuit
	helm_type =  /obj/item/clothing/head/helmet/space/rig/advsuit
	boot_type =  null
	glove_type = null
	cell_type =  null

	req_access = list()
	req_one_access = list()

CAPABILITIES(/obj/item/rig/robotics)
	acceptance("suit_storage", req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY, /obj/item/storage/box, /obj/item/storage/belt, /obj/item/defib_kit/compact), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_protection(siemens = 0.75))



/obj/item/clothing/head/helmet/space/rig/advsuit
	name = "suit helmet"

/obj/item/clothing/suit/space/rig/advsuit
	name = "Hardsuit" // Replcing Void with Hard to fit the naming convention. Specced down hardsuit for comfort

CAPABILITIES(/obj/item/clothing/suit/space/rig/advsuit)
	configure(item_worn(covers = CHEST|LEGS|ARMS|HANDS|FEET))
	configure(item_protection(heat_parts = CHEST|LEGS|ARMS|HANDS|FEET, cold_parts = CHEST|LEGS|ARMS|HANDS|FEET))

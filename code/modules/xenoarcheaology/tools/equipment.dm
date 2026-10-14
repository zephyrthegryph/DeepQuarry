/obj/item/clothing/suit/bio_suit/anomaly
	name = "Anomaly suit"
	desc = "A sealed bio suit capable of insulating against exotic alien energies."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "engspace_suit"
	item_state = "engspace_suit"
	armor_spec = "bio=100;rad=100;acid=60"

CAPABILITIES(/obj/item/clothing/suit/bio_suit/anomaly)
	configure(item_protection(max_pressure = 5   * ONE_ATMOSPHERE, min_pressure = 0.4 * ONE_ATMOSPHERE))

/obj/item/clothing/head/bio_hood/anomaly
	name = "Anomaly hood"
	desc = "A sealed bio hood capable of insulating against exotic alien energies."
	icon_state = "engspace_helmet"
	item_state = "engspace_helmet"
	armor_spec = "bio=100;rad=100;acid=60"

CAPABILITIES(/obj/item/clothing/head/bio_hood/anomaly)
	configure(item_protection(max_pressure = 5   * ONE_ATMOSPHERE, min_pressure = 0.4 * ONE_ATMOSPHERE))

/obj/item/clothing/suit/space/anomaly
	name = "Excavation suit"
	desc = "A pressure resistant excavation suit partially capable of insulating against exotic alien energies."
	icon_state = "cespace_suit"
	item_state = "cespace_suit"
	armor_spec = "bio=100;rad=100;cold=60"
	slowdown = 1
	// Pressure protection inherited from space suits



/obj/item/clothing/head/helmet/space/anomaly
	name = "Excavation hood"
	desc = "A pressure resistant excavation hood partially capable of insulating against exotic alien energies."
	icon_state = "cespace_helmet"
	item_state = "cespace_helmet"
	armor_spec = "bio=100;rad=100;cold=60"

/obj/item/clothing/suit/space/anomaly/heat
	name = "Heat Adapted Excavation suit"
	desc = "A pressure resistant excavation suit partially capable of insulating against exotic alien energies and heat."

CAPABILITIES(/obj/item/clothing/suit/space/anomaly/heat)
	configure(item_protection(heat_parts = CHEST|LEGS|FEET|ARMS|HANDS, max_heat = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE+1000, min_pressure = 0 * ONE_ATMOSPHERE, max_pressure = 5* ONE_ATMOSPHERE))

/obj/item/clothing/head/helmet/space/anomaly/heat
	name = "Heat Adapted Excavation hood"
	desc = "A pressure resistant excavation hood partially capable of insulating against exotic alien energies and heat."

CAPABILITIES(/obj/item/clothing/head/helmet/space/anomaly/heat)
	configure(item_protection(heat_parts = HEAD, max_heat = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE+1000, min_pressure = 0 * ONE_ATMOSPHERE, max_pressure = 5* ONE_ATMOSPHERE))

CAPABILITIES(/obj/item/clothing/suit/space/anomaly)
	acceptance("suit_storage", req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_MINING, POCKET_ALL_TANKS), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)

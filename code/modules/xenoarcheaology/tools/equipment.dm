/obj/item/clothing/suit/bio_suit/anomaly
	name = "Anomaly suit"
	desc = "A sealed bio suit capable of insulating against exotic alien energies."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "engspace_suit"
	item_state = "engspace_suit"
	armor_spec = "bio=100;rad=100;acid=60"
	max_pressure_protection = 5   * ONE_ATMOSPHERE // Not very good protection, but if an anomaly starts doing gas stuff you're not screwed
	min_pressure_protection = 0.4 * ONE_ATMOSPHERE

/obj/item/clothing/head/bio_hood/anomaly
	name = "Anomaly hood"
	desc = "A sealed bio hood capable of insulating against exotic alien energies."
	icon_state = "engspace_helmet"
	item_state = "engspace_helmet"
	armor_spec = "bio=100;rad=100;acid=60"
	max_pressure_protection = 5   * ONE_ATMOSPHERE // Not very good protection, but if an anomaly starts doing gas stuff you're not screwed
	min_pressure_protection = 0.4 * ONE_ATMOSPHERE

/obj/item/clothing/suit/space/anomaly
	name = "Excavation suit"
	desc = "A pressure resistant excavation suit partially capable of insulating against exotic alien energies."
	icon_state = "cespace_suit"
	item_state = "cespace_suit"
	armor_spec = "bio=100;rad=100;cold=60"
	slowdown = 1
	// Pressure protection inherited from space suits

/obj/item/clothing/suit/space/anomaly/suit_storage_constraint()
	var/list/stores = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_MINING, POCKET_ALL_TANKS)
	return list(HOLD_ONLY(stores))

/obj/item/clothing/head/helmet/space/anomaly
	name = "Excavation hood"
	desc = "A pressure resistant excavation hood partially capable of insulating against exotic alien energies."
	icon_state = "cespace_helmet"
	item_state = "cespace_helmet"
	armor_spec = "bio=100;rad=100;cold=60"

/obj/item/clothing/suit/space/anomaly/heat
	name = "Heat Adapted Excavation suit"
	desc = "A pressure resistant excavation suit partially capable of insulating against exotic alien energies and heat."
	heat_protection = CHEST|LEGS|FEET|ARMS|HANDS
	max_heat_protection_temperature = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE+1000
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 5* ONE_ATMOSPHERE

/obj/item/clothing/head/helmet/space/anomaly/heat
	name = "Heat Adapted Excavation hood"
	desc = "A pressure resistant excavation hood partially capable of insulating against exotic alien energies and heat."
	heat_protection = HEAD
	max_heat_protection_temperature = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE+1000
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 5* ONE_ATMOSPHERE

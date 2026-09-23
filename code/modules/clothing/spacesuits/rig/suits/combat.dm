/obj/item/clothing/head/helmet/space/rig/combat
	light_overlay = "helmet_light_dual_green"

/obj/item/rig/combat
	name = "combat hardsuit control module"
	desc = "A sleek and dangerous hardsuit for active combat."
	icon_state = "security_rig"
	suit_type = "combat hardsuit"
	armor_spec = "melee=80;bullet=70;laser=60;energy=15;bomb=80;bio=100;rad=60"
	slowdown = 0.5
	offline_slowdown = 1.5
	offline_vision_restriction = 1

	helm_type = /obj/item/clothing/head/helmet/space/rig/combat

/obj/item/rig/combat/suit_storage_constraint()
	var/list/stores = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_EXPLO, POCKET_BAYSUIT)
	return list(HOLD_ONLY(stores))

/obj/item/rig/combat/equipped

	initial_modules = list(
		/obj/item/rig_module/mounted,
		/obj/item/rig_module/vision/thermal,
		/obj/item/rig_module/grenade_launcher,
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/power_sink,
		/obj/item/rig_module/electrowarfare_suite,
		/obj/item/rig_module/chem_dispenser/combat
		)

/obj/item/rig/combat/empty
	initial_modules = list(
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/electrowarfare_suite,
		)

/obj/item/rig/military
	name = "military hardsuit control module"
	desc = "An austere hardsuit used by paramilitary groups and real soldiers alike."
	icon_state = "military_rig"
	suit_type = "military hardsuit"
	armor_spec = "melee=80;bullet=75;laser=65;energy=15;bomb=80;bio=100;rad=40"
	slowdown = 0.5
	offline_slowdown = 1.5
	offline_vision_restriction = 1

	chest_type = /obj/item/clothing/suit/space/rig/military
	helm_type = /obj/item/clothing/head/helmet/space/rig/military
	boot_type = /obj/item/clothing/shoes/magboots/rig/military
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/military

/obj/item/rig/military/suit_storage_constraint()
	var/list/stores = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_ENGINEERING, POCKET_CE, POCKET_SECURITY, POCKET_MEDICAL, POCKET_HEAVYTOOLS, POCKET_BAYSUIT)
	return list(HOLD_ONLY(stores))

/obj/item/clothing/head/helmet/space/rig/military
	light_overlay = "helmet_light_dual_green"

/obj/item/clothing/head/helmet/space/rig/military/fit_constraint()
	var/list/bodytypes = list(SPECIES_HUMAN,SPECIES_PROMETHEAN)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/clothing/suit/space/rig/military

/obj/item/clothing/suit/space/rig/military/fit_constraint()
	var/list/bodytypes = list(SPECIES_HUMAN,SPECIES_PROMETHEAN)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/clothing/shoes/magboots/rig/military

/obj/item/clothing/shoes/magboots/rig/military/fit_constraint()
	var/list/bodytypes = list(SPECIES_HUMAN,SPECIES_PROMETHEAN)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/clothing/gloves/gauntlets/rig/military

/obj/item/clothing/gloves/gauntlets/rig/military/fit_constraint()
	var/list/bodytypes = list(SPECIES_HUMAN,SPECIES_PROMETHEAN)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/rig/military/equipped
	initial_modules = list(
		/obj/item/rig_module/mounted/egun,
		/obj/item/rig_module/vision/multi,
		/obj/item/rig_module/grenade_launcher,
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/power_sink,
		/obj/item/rig_module/electrowarfare_suite,
		/obj/item/rig_module/chem_dispenser/combat,
		)

/obj/item/rig/military/empty
	initial_modules = list(
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/electrowarfare_suite,
		)

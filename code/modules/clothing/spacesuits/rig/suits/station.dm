/obj/item/clothing/head/helmet/space/rig/industrial
	camera_networks = list(NETWORK_MINE)

/obj/item/clothing/head/helmet/space/rig/ce
	camera_networks = list(NETWORK_ENGINEERING)

/obj/item/clothing/head/helmet/space/rig/eva
	light_overlay = "helmet_light_dual"
	camera_networks = list(NETWORK_ENGINEERING)

/obj/item/clothing/head/helmet/space/rig/hazmat
	light_overlay = "hardhat_light"
	camera_networks = list(NETWORK_RESEARCH)

/obj/item/clothing/head/helmet/space/rig/medical
	camera_networks = list(NETWORK_MEDICAL)

/obj/item/clothing/head/helmet/space/rig/hazard
	light_overlay = "helmet_light_dual"
	camera_networks = list(NETWORK_SECURITY)

//Internal Affairs suit
/obj/item/rig/internalaffairs
	name = "augmented tie"
	suit_type = "augmented suit"
	desc = "The last suit you'll ever wear."
	icon_state = "internalaffairs_rig"
	armor = list(melee = 0, bullet = 0, laser = 0,energy = 0, bomb = 0, bio = 0, rad = 0)
	siemens_coefficient = 0.9
	slowdown = 0
	offline_slowdown = 0
	offline_vision_restriction = 0

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, /obj/item/storage)

	req_access = list()
	req_one_access = list()

	glove_type = null
	helm_type = null
	boot_type = null

/obj/item/rig/internalaffairs/equipped

	req_access = list(ACCESS_LAWYER)

	initial_modules = list(
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/device/flash,
		/obj/item/rig_module/device/paperdispenser,
		/obj/item/rig_module/device/pen,
		/obj/item/rig_module/device/stamp
		)

	glove_type = null
	helm_type = null
	boot_type = null

//Mining suit
/obj/item/rig/industrial
	name = "industrial suit control module"
	suit_type = "industrial hardsuit"
	desc = "A heavy, powerful hardsuit used by construction crews and mining corporations."
	icon_state = "engineering_rig"
	armor = list(melee = 60, bullet = 50, laser = 30,energy = 15, bomb = 30, bio = 100, rad = 50)
	slowdown = 0.5
	offline_slowdown = 5
	offline_vision_restriction = 2
	emp_protection = -20
	siemens_coefficient= 0.75
	rigsuit_max_pressure = 15 * ONE_ATMOSPHERE			  // Max pressure the rig protects against when sealed
	rigsuit_min_pressure = 0							  // Min pressure the rig protects against when sealed

	helm_type = /obj/item/clothing/head/helmet/space/rig/industrial

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_MINING, POCKET_BAYSUIT)

	req_access = list()
	req_one_access = list()


/obj/item/rig/industrial/equipped

	initial_modules = list(
		/obj/item/rig_module/device/plasmacutter,
		/obj/item/rig_module/device/drill,
		/obj/item/rig_module/device/orescanner,
		/obj/item/rig_module/vision/material,
		/obj/item/rig_module/maneuvering_jets) //VOREStation Edit - Added maneuvering jets

//Engineering suit
/obj/item/rig/eva
	name = "EVA suit control module"
	suit_type = "EVA hardsuit"
	desc = "A light hardsuit for repairs and maintenance to the outside of habitats and vessels."
	icon_state = "eva_rig"
	armor = list(melee = 30, bullet = 10, laser = 20,energy = 25, bomb = 20, bio = 100, rad = 100)
	slowdown = 0
	offline_slowdown = 0.5
	offline_vision_restriction = 1
	siemens_coefficient = 0.75

	helm_type = /obj/item/clothing/head/helmet/space/rig/eva
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/eva

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, POCKET_CE, /obj/item/storage)

	req_access = list()
	req_one_access = list()
	max_heat_protection_temperature = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE

/obj/item/clothing/gloves/gauntlets/rig/eva
	name = "insulated gauntlets"
	siemens_coefficient = 0

/obj/item/rig/eva/equipped

	req_access = list(ACCESS_ENGINE)

	initial_modules = list(
		/obj/item/rig_module/device/plasmacutter,
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/device/rcd,
		/obj/item/rig_module/vision/meson
		)

//Chief Engineer's rig. This is sort of a halfway point between the old hardsuits (voidsuits) and the rig class. //CHOMPEDIT: if its a mechanized suit its a hardsuit
/obj/item/rig/ce

	name = "advanced hardsuit control module" //CHOMPEDIT: Hardsuit
	suit_type = "advanced hardsuit" //CHOMPEDIT: Hardsuit
	desc = "An advanced hardsuit that protects against hazardous, low pressure environments. Shines with a high polish."//CHOMPEDIT: Hardsuit
	icon_state = "ce_rig"
	armor = list(melee = 40, bullet = 10, laser = 30,energy = 25, bomb = 40, bio = 100, rad = 100)
	slowdown = 0
	offline_slowdown = 0
	offline_vision_restriction = 0
	siemens_coefficient= 0.75
	rigsuit_max_pressure = 20 * ONE_ATMOSPHERE			  // Max pressure the rig protects against when sealed
	rigsuit_min_pressure = 0							  // Min pressure the rig protects against when sealed

	helm_type = /obj/item/clothing/head/helmet/space/rig/ce
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/ce
	boot_type = /obj/item/clothing/shoes/magboots/rig/ce //VOREStation Add

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_MINING, POCKET_ENGINEERING, POCKET_CE, POCKET_BAYSUIT)

	req_access = list()
	req_one_access = list()
	max_heat_protection_temperature = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE

/obj/item/clothing/gloves/gauntlets/rig/ce
	name = "insulated gauntlets"
	siemens_coefficient = 0

/obj/item/clothing/shoes/magboots/rig/ce
	name = "advanced boots"
/obj/item/clothing/shoes/magboots/rig/ce/set_slowdown()
	if(magpulse)
		slowdown = shoes ? max(SHOES_SLOWDOWN, shoes.slowdown) : SHOES_SLOWDOWN	//So you can't put on magboots to make you walk faster.
	else if(shoes)
		slowdown = shoes.slowdown
	else
		slowdown = SHOES_SLOWDOWN

/obj/item/rig/ce/equipped

	req_access = list(ACCESS_CE)

	initial_modules = list(
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/device/plasmacutter,
		/obj/item/rig_module/device/rcd,
		/obj/item/rig_module/vision/meson
		)

//Research Director's suit. Just add red crowbar.
/obj/item/rig/hazmat

	name = "AMI control module"
	suit_type = "hazmat hardsuit"
	desc = "An Anomalous Material Interaction hardsuit that protects against the strangest energies the universe can throw at it."
	icon_state = "science_rig"
	armor = list(melee = 45, bullet = 5, laser = 45, energy = 80, bomb = 100, bio = 100, rad = 100)
	slowdown = 0.5
	offline_vision_restriction = 1
	siemens_coefficient= 0.75

	helm_type = /obj/item/clothing/head/helmet/space/rig/hazmat
	//ywadd start
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/hazmat
	boot_type = /obj/item/clothing/shoes/magboots/rig/hazmat
	//ywadd end

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_MINING, POCKET_XENOARC, POCKET_BAYSUIT)

	req_access = list()
	req_one_access = list()

//ywadd start
/obj/item/clothing/gloves/gauntlets/rig/hazmat
	icon_override = 'icons/vore/rig_yw/rigs_gauntlets_onmob.dmi'

/obj/item/clothing/shoes/magboots/rig/hazmat
	icon = 'icons/vore/rig_yw/rigs_shoes.dmi'
	icon_state = "science_rig"
	icon_override = 'icons/vore/rig_yw/rigs_shoes_onmob.dmi'
//ywadd end

/obj/item/rig/hazmat/equipped

	req_access = list(ACCESS_RD)

	initial_modules = list(
		/obj/item/rig_module/ai_container,
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/device/anomaly_scanner
		)

//Paramedic suit
/obj/item/rig/medical

	name = "rescue suit control module"
	suit_type = "rescue hardsuit"
	desc = "A durable suit designed for medical rescue in high risk areas."
	icon_state = "medical_rig"
	armor = list(melee = 30, bullet = 15, laser = 20, energy = 60, bomb = 30, bio = 100, rad = 100)
	slowdown = 0.5
	offline_vision_restriction = 1
	siemens_coefficient= 0.75
	seal_delay = 5

	helm_type = /obj/item/clothing/head/helmet/space/rig/medical

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_MEDICAL, POCKET_BAYSUIT, /obj/item/roller, /obj/item/storage/firstaid)

	req_access = list()
	req_one_access = list()

//Access restriction and seal delay, plus pat_module and rescue_pharm for medical suit
/obj/item/rig/medical/equipped
	req_access = list(ACCESS_MEDICAL)
	seal_delay = 5

	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/sprinter,
		/obj/item/rig_module/pat_module,
		/obj/item/rig_module/rescue_pharm
		)

//Security suit
/obj/item/rig/hazard
	name = "hazard hardsuit control module"
	suit_type = "hazard hardsuit"
	desc = "A Security hardsuit designed for prolonged EVA in dangerous environments."
	icon_state = "hazard_rig"
	armor = list(melee = 60, bullet = 40, laser = 30, energy = 15, bomb = 60, bio = 100, rad = 30)
	slowdown = 0.5
	offline_slowdown = 1.5
	offline_vision_restriction = 1
	siemens_coefficient= 0.7

	helm_type = /obj/item/clothing/head/helmet/space/rig/hazard

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_EXPLO, POCKET_BAYSUIT)

	req_access = list()
	req_one_access = list()


/obj/item/rig/hazard/equipped

	initial_modules = list(
		/obj/item/rig_module/vision/sechud,
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/grenade_launcher,
		/obj/item/rig_module/mounted/taser
		)

// 'Technomancer' hardsuit
/obj/item/rig/focalpoint
	name = "\improper F.P.E. hardsuit control module"
	desc = "A high-end hardsuit produced by Focal Point Energistics, focused around repair and construction."

	icon = 'icons/obj/rig_modules_vr.dmi' // the item
	default_mob_icon = 'icons/mob/rig_back_vr.dmi' // the onmob
	icon_state = "techno_rig"
	suit_type = "\improper F.P.E. hardsuit"
	cell_type = /obj/item/cell/hyper

	// Copied from CE rig
	slowdown = 0
	offline_slowdown = 0
	offline_vision_restriction = 0
	rigsuit_max_pressure = 20 * ONE_ATMOSPHERE			  // Max pressure the rig protects against when sealed
	rigsuit_min_pressure = 0							  // Min pressure the rig protects against when sealed
	min_cold_protection_temperature = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE // so it's like a rig firesuit
	armor = list("melee" = 40, "bullet" = 10, "laser" = 30, "energy" = 55, "bomb" = 70, "bio" = 100, "rad" = 100)
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, /obj/item/storage/backpack)
	chest_type = /obj/item/clothing/suit/space/rig/focalpoint
	helm_type = /obj/item/clothing/head/helmet/space/rig/focalpoint
	boot_type = /obj/item/clothing/shoes/magboots/rig/ce/focalpoint
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/focalpoint

/obj/item/rig/focalpoint/equipped
	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/teleporter, // Try not to set yourself on fire
		/obj/item/rig_module/device/rcd,
		/obj/item/rig_module/grenade_launcher/metalfoam
	)

/obj/item/clothing/head/helmet/space/rig/focalpoint
	icon_state = "techno_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

/obj/item/clothing/suit/space/rig/focalpoint
	icon_state = "techno_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

/obj/item/clothing/shoes/magboots/rig/ce/focalpoint
	icon_state = "techno_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

/obj/item/clothing/gloves/gauntlets/rig/focalpoint
	icon_state = "techno_rig"
	siemens_coefficient = 0
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

// 'Ironhammer' hardsuit
/obj/item/rig/hephaestus
	name = "\improper Hephaestus hardsuit control module"
	desc = "A high-end hardsuit produced by Hephaestus Industries, focused on destroying the competition. Literally."

	icon = 'icons/obj/rig_modules_vr.dmi' // the item
	default_mob_icon = 'icons/mob/rig_back_vr.dmi' // the onmob
	icon_state = "ihs_rig"
	suit_type = "\improper Hephaestus hardsuit"
	cell_type = /obj/item/cell/super
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, POCKET_SECURITY, POCKET_ENGINEERING, POCKET_BAYSUIT, /obj/item/storage/firstaid, /obj/item/roller)

	armor = list("melee" = 70, "bullet" = 70, "laser" = 70, "energy" = 50, "bomb" = 60, "bio" = 100, "rad" = 20)

	chest_type = /obj/item/clothing/suit/space/rig/hephaestus
	helm_type = /obj/item/clothing/head/helmet/space/rig/hephaestus
	boot_type = /obj/item/clothing/shoes/magboots/rig/hephaestus
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/hephaestus

/obj/item/rig/hephaestus/equipped
	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/grenade_launcher,
		/obj/item/rig_module/mounted/egun,
		/obj/item/rig_module/mounted/energy_blade
	)

/obj/item/clothing/head/helmet/space/rig/hephaestus
	icon_state = "ihs_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

/obj/item/clothing/suit/space/rig/hephaestus
	icon_state = "ihs_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

/obj/item/clothing/shoes/magboots/rig/hephaestus
	icon_state = "ihs_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

/obj/item/clothing/gloves/gauntlets/rig/hephaestus
	icon_state = "ihs_rig"
	// No animal people sprites for these yet, sad times
	species_restricted = list("exclude", SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA)
	sprite_sheets = null

// 'Zero' rig
/obj/item/rig/zero
	name = "null hardsuit control module"
	desc = "A very lightweight suit designed to allow use inside mechs and starfighters. It feels like you're wearing nothing at all."

	icon = 'icons/obj/rig_modules_vr.dmi' // the item
	default_mob_icon = 'icons/mob/rig_back_vr.dmi' // the onmob
	icon_state = "null_rig"
	suit_type = "null hardsuit"
	cell_type = /obj/item/cell/high

	chest_type = /obj/item/clothing/suit/space/rig/zero
	helm_type = /obj/item/clothing/head/helmet/space/rig/zero
	boot_type = null
	glove_type = null
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, POCKET_BAYSUIT)

	slowdown = 0
	offline_slowdown = 1
	offline_vision_restriction = 2
	armor = list("melee" = 20, "bullet" = 5, "laser" = 10, "energy" = 5, "bomb" = 35, "bio" = 100, "rad" = 20)

/obj/item/rig/zero/equipped
	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets
	)

/obj/item/clothing/head/helmet/space/rig/zero
	desc = "A bubble helmet that maximizes the field of view. A state of the art holographic display provides a stream of information."
	icon_state = "null_rig"
	sprite_sheets = ALL_VR_SPRITE_SHEETS_HEAD_MOB
	sprite_sheets_obj = ALL_VR_SPRITE_SHEETS_HEAD_ITEM
	slowdown = 0

/obj/item/clothing/suit/space/rig/zero
	icon_state = "null_rig"
	sprite_sheets = ALL_SPRITE_SHEETS_SUIT_MOB
	sprite_sheets_obj = SPECIES_SPRITE_SHEETS_SUIT_ITEM
	body_parts_covered = CHEST|LEGS|FEET|ARMS|HANDS // like a voidsuit
	slowdown = 0

// Medical rig from bay
/obj/item/rig/baymed
	name = "\improper Commonwealth medical hardsuit control module"
	desc = "A lightweight first responder hardsuit from the Commonwealth. Not suitable for combat use, but advanced myomer fibers can push the user to incredible speeds."
	interface_intro = "Commonwealth"

	icon = 'icons/obj/rig_modules_vr.dmi' // the item
	default_mob_icon = 'icons/mob/rig_back_vr.dmi' // the onmob
	icon_state = "medical_rig_bay"
	item_state = null
	suit_type = "medical hardsuit"
	cell_type = /obj/item/cell/high

	chest_type = /obj/item/clothing/suit/space/rig/baymed
	helm_type = /obj/item/clothing/head/helmet/space/rig/baymed
	boot_type = /obj/item/clothing/shoes/magboots/rig/ce/baymed
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/baymed

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, POCKET_MEDICAL, POCKET_BAYSUIT, /obj/item/roller)

	// speedy paper
	slowdown = -0.5
	armor = list("melee" = 10, "bullet" = 5, "laser" = 10, "energy" = 5, "bomb" = 25, "bio" = 100, "rad" = 20)

/obj/item/rig/baymed/equipped

	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/sprinter,
		/obj/item/rig_module/pat_module,
		/obj/item/rig_module/rescue_pharm
	)

/obj/item/clothing/head/helmet/space/rig/baymed
	icon_state = "medical_rig_bay"
	item_state = null
	sprite_sheets = ALL_VR_SPRITE_SHEETS_HEAD_MOB
	sprite_sheets_obj = ALL_VR_SPRITE_SHEETS_HEAD_ITEM
	camera_networks = list(NETWORK_MEDICAL)

/obj/item/clothing/suit/space/rig/baymed
	icon_state = "medical_rig_bay"
	item_state = null
	sprite_sheets = ALL_SPRITE_SHEETS_SUIT_MOB
	sprite_sheets_obj = SPECIES_SPRITE_SHEETS_SUIT_ITEM

/obj/item/clothing/shoes/magboots/rig/ce/baymed
	icon_state = "medical_rig_bay"
	item_state = null
	sprite_sheets = null
	sprite_sheets_obj = null

/obj/item/clothing/gloves/gauntlets/rig/baymed
	icon_state = "medical_rig_bay"
	item_state = null
	sprite_sheets = null
	sprite_sheets_obj = null

// Engineering/'Industrial' rig from bay
/obj/item/rig/bayeng
	name = "\improper Commonwealth engineering hardsuit control module"
	desc = "An advanced construction hardsuit from the Commonwealth. Built like a tank. Don't expect to be taking any tight corners while running."
	interface_intro = "Commonwealth"

	icon = 'icons/obj/rig_modules_vr.dmi' // the item
	default_mob_icon = 'icons/mob/rig_back_vr.dmi' // the onmob
	icon_state = "engineering_rig_bay"
	item_state = null
	suit_type = "engineering hardsuit"
	cell_type = /obj/item/cell/super

	chest_type = /obj/item/clothing/suit/space/rig/bayeng
	helm_type = /obj/item/clothing/head/helmet/space/rig/bayeng
	boot_type = /obj/item/clothing/shoes/magboots/rig/ce/bayeng
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/bayeng

	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ALL_TANKS, POCKET_MINING, POCKET_CE, POCKET_BAYSUIT)

	slowdown = 0
	offline_slowdown = 5 // very bulky
	armor = list(melee = 60, bullet = 50, laser = 30, energy = 15, bomb = 30, bio = 100, rad = 50)

/obj/item/rig/bayeng/equipped
	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/device/rcd,
		/obj/item/rig_module/grenade_launcher/metalfoam,
		/obj/item/rig_module/vision/meson,
		/obj/item/rig_module/ai_container
	)

/obj/item/clothing/head/helmet/space/rig/bayeng
	icon_state = "engineering_rig_bay"
	item_state = null
	sprite_sheets = ALL_VR_SPRITE_SHEETS_HEAD_MOB
	sprite_sheets_obj = ALL_VR_SPRITE_SHEETS_HEAD_ITEM
	camera_networks = list(NETWORK_ENGINEERING)

/obj/item/clothing/suit/space/rig/bayeng
	icon_state = "engineering_rig_bay"
	item_state = null
	sprite_sheets = ALL_SPRITE_SHEETS_SUIT_MOB
	sprite_sheets_obj = SPECIES_SPRITE_SHEETS_SUIT_ITEM

/obj/item/clothing/shoes/magboots/rig/ce/bayeng
	icon_state = "engineering_rig_bay"
	item_state = null
	sprite_sheets = null
	sprite_sheets_obj = null

/obj/item/clothing/gloves/gauntlets/rig/bayeng
	icon_state = "engineering_rig_bay"
	item_state = null
	sprite_sheets = null
	sprite_sheets_obj = null
	siemens_coefficient = 0 // insulated

// Pathfinder rig from bay - event/reward stuff here
/obj/item/rig/pathfinder
	name = "\improper Commonwealth pathfinder hardsuit control module"
	desc = "A Commonwealth pathfinder hardsuit is hard to come by... how'd this end up on the frontier?"
	interface_intro = "Commonwealth"

	icon = 'icons/obj/rig_modules_vr.dmi' // the item
	default_mob_icon = 'icons/mob/rig_back_vr.dmi' // the onmob
	icon_state = "pathfinder_rig_bay"
	item_state = null
	suit_type = "pathfinder hardsuit"
	cell_type = /obj/item/cell/super

	chest_type = /obj/item/clothing/suit/space/rig/pathfinder
	helm_type = /obj/item/clothing/head/helmet/space/rig/pathfinder
	boot_type = /obj/item/clothing/shoes/magboots/rig/pathfinder
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/pathfinder

	slowdown = 0.5
	offline_slowdown = 4 // bulky
	offline_vision_restriction = 2 // doesn't even have a way to see out without power
	armor = list(melee = 60, bullet = 50, laser = 30, energy = 15, bomb = 30, bio = 100, rad = 50)

/obj/item/rig/pathfinder//equipped
	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/teleporter,
		/obj/item/rig_module/stealth_field,
		/obj/item/rig_module/mounted/energy_blade
	)

/obj/item/clothing/head/helmet/space/rig/pathfinder
	icon_state = "pathfinder_rig_bay"
	item_state = null
	sprite_sheets = ALL_VR_SPRITE_SHEETS_HEAD_MOB
	sprite_sheets_obj = ALL_VR_SPRITE_SHEETS_HEAD_ITEM

/obj/item/clothing/suit/space/rig/pathfinder
	icon_state = "pathfinder_rig_bay"
	item_state = null
	sprite_sheets = ALL_SPRITE_SHEETS_SUIT_MOB
	sprite_sheets_obj = SPECIES_SPRITE_SHEETS_SUIT_ITEM

/obj/item/clothing/shoes/magboots/rig/pathfinder
	icon_state = "pathfinder_rig_bay"
	item_state = null
	sprite_sheets = null
	sprite_sheets_obj = null

/obj/item/clothing/gloves/gauntlets/rig/pathfinder
	icon_state = "pathfinder_rig_bay"
	item_state = null
	sprite_sheets = null
	sprite_sheets_obj = null

/obj/item/rig/industrial/vendor
	name = "discount industrial suit control module"
	desc = "A heavy, powerful hardsuit used by construction crews and mining corporations. This is a mass production model with reduced armor."
	armor = list(melee = 50, bullet = 10, laser = 20, energy = 15, bomb = 30, bio = 100, rad = 50)


// === merged from station_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//Hardsuits
/obj/item/rig/ch //Some blank bs
	name = DEVELOPER_WARNING_NAME
	desc = DEVELOPER_WARNING_NAME
	default_mob_icon = 'icons/mob/rig_back_ch.dmi'
	chest_type = /obj/item/clothing/suit/space/rig/ch
	helm_type = /obj/item/clothing/head/helmet/space/rig/ch
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/ch
	boot_type = /obj/item/clothing/shoes/magboots/rig/ch

/obj/item/clothing/suit/space/rig/ch
	icon_state = "nanomachine_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.
	icon = 'icons/obj/clothing/spacesuits_ch.dmi'

/obj/item/clothing/head/helmet/space/rig/ch
	icon_state = "nanomachine_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.

	icon = 'icons/obj/clothing/hats_ch.dmi'

/obj/item/clothing/gloves/gauntlets/rig/ch
	icon_state = "nanomachine_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.

	icon = 'icons/obj/clothing/gloves_ch.dmi'

/obj/item/clothing/shoes/magboots/rig/ch
	icon_state = "nanomachine_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.

	icon = 'icons/obj/clothing/shoes_ch.dmi'



//A second security suit. Comes with a grenade launcher that only accepts flashbangs and adds a new sprinter and flash modules.
/obj/item/rig/ch/pursuit
	name = "pursuit hardsuit control module"
	icon = 'icons/obj/rig_modules_ch.dmi'
	icon_state = "pursuit_rig"
	suit_type = "pursuit hardsuit"
	desc = "A Security hardsuit designed for chasing down the grey tide."
	armor = list(melee = 60, bullet = 40, laser = 40, energy = 25, bomb = 50, bio = 100, rad = 30)
	slowdown = 1
	offline_slowdown = 3
	offline_vision_restriction = 1
	siemens_coefficient= 0.7
	helm_type = /obj/item/clothing/head/helmet/space/rig/ch/pursuit
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_STORAGE, POCKET_EXPLO)

	req_access = list(ACCESS_HOS)
	req_one_access = list()

/obj/item/rig/ch/pursuit/equipped

	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/vision/sechud,
		/obj/item/rig_module/sprinter/pursuit,
		/obj/item/rig_module/grenade_launcher/nerfed,
		/obj/item/rig_module/mounted/taser
		)


//Camera networks and light_overlay which is for your HUD icon when you turn your suit light on. This is important, ties into the helm_type var that your suit will probably need.
/obj/item/clothing/head/helmet/space/rig/ch/pursuit
	light_overlay = "hardhat_light"
	camera_networks = list(NETWORK_SECURITY)











////////////////////////////////////////////////////////////////////////////////////////
//Backend stuff to make the sprites work. Copied and pasted from rig_pieces_vr.dm, but added ch to everything. Only reason for this to be touched is to add or remove species. This might just need to go in a new file named rig_pieces_ch.dm, but whatever, it's fine here. This is for our rigs, I'll just leave it here..

/obj/item/clothing/head/helmet/space/rig/ch
	sprite_sheets = list(
		SPECIES_HUMAN			= 'icons/mob/head.dmi',
		SPECIES_TAJARAN 		= 'icons/mob/species/tajaran/helmet.dmi',
		SPECIES_SKRELL 			= 'icons/mob/species/skrell/helmet.dmi',
		SPECIES_UNATHI 			= 'icons/mob/species/unathi/helmet.dmi',
		SPECIES_XENOHYBRID		= 'icons/mob/species/unathi/helmet.dmi',
		SPECIES_AKULA 			= 'icons/mob/species/akula/helmet.dmi',
		SPECIES_SERGAL			= 'icons/mob/species/sergal/helmet.dmi',
		SPECIES_NEVREAN			= 'icons/mob/species/sergal/helmet.dmi',
		SPECIES_VULPKANIN 		= 'icons/mob/species/vulpkanin/helmet.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/mob/species/fox/helmet.dmi',
		SPECIES_FENNEC 			= 'icons/mob/species/vulpkanin/helmet.dmi',
		SPECIES_PROMETHEAN		= 'icons/mob/species/skrell/helmet.dmi',
		SPECIES_TESHARI 		= 'icons/mob/species/teshari/helmet.dmi',
		SPECIES_VASILISSAN		= 'icons/mob/species/skrell/helmet.dmi',
		SPECIES_VOX				= 'icons/mob/species/vox/head.dmi'
		)

	sprite_sheets_obj = list(
		SPECIES_HUMAN			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_TAJARAN 		= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_SKRELL 			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_UNATHI 			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_XENOHYBRID		= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_AKULA 			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_SERGAL			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_NEVREAN			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_VULPKANIN 		= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_FENNEC 			= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_PROMETHEAN		= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_TESHARI 		= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_VASILISSAN		= 'icons/obj/clothing/hats_ch.dmi',
		SPECIES_VOX				= 'icons/obj/clothing/hats_ch.dmi'
		)

/obj/item/clothing/suit/space/rig/ch
	sprite_sheets = list(
		SPECIES_HUMAN			= 'icons/mob/spacesuit.dmi',
		SPECIES_TAJARAN 			= 'icons/mob/species/tajaran/suit_ch.dmi',
		SPECIES_SKRELL 			= 'icons/mob/species/skrell/suit_ch.dmi',
		SPECIES_UNATHI 			= 'icons/mob/species/unathi/suit_ch.dmi',
		SPECIES_XENOHYBRID		= 'icons/mob/species/unathi/suit_ch.dmi',
		SPECIES_AKULA 			= 'icons/mob/species/akula/suit_ch.dmi',
		SPECIES_SERGAL			= 'icons/mob/species/sergal/suit_ch.dmi',
		SPECIES_NEVREAN			= 'icons/mob/species/sergal/suit_ch.dmi',
		SPECIES_VULPKANIN		= 'icons/mob/species/vulpkanin/suit_ch.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/mob/species/fox/suit_ch.dmi',
		SPECIES_FENNEC			= 'icons/mob/species/vulpkanin/suit_ch.dmi',
		SPECIES_PROMETHEAN		= 'icons/mob/species/skrell/suit_ch.dmi',
		SPECIES_TESHARI 		= 'icons/mob/species/teshari/suit.dmi',
		SPECIES_VASILISSAN		= 'icons/mob/species/skrell/suit_ch.dmi',
		SPECIES_VOX				= 'icons/mob/species/vox/suit.dmi'
		)

	sprite_sheets_obj = list(
		SPECIES_HUMAN			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_TAJARAN 			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_SKRELL 			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_UNATHI 			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_XENOHYBRID		= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_AKULA 			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_SERGAL			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_NEVREAN			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_VULPKANIN 		= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_FENNEC 			= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_PROMETHEAN		= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_TESHARI 		= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_VASILISSAN		= 'icons/obj/clothing/spacesuits_ch.dmi',
		SPECIES_VOX				= 'icons/obj/clothing/spacesuits_ch.dmi'
		)

/obj/item/clothing/gloves/gauntlets/rig/ch
	sprite_sheets = list(
		SPECIES_HUMAN			= 'icons/mob/hands.dmi',
		SPECIES_TAJARAN 			= 'icons/mob/hands.dmi',
		SPECIES_SKRELL 			= 'icons/mob/hands.dmi',
		SPECIES_UNATHI 			= 'icons/mob/hands.dmi',
		SPECIES_XENOHYBRID		= 'icons/mob/hands.dmi',
		SPECIES_AKULA 			= 'icons/mob/hands.dmi',
		SPECIES_SERGAL			= 'icons/mob/hands.dmi',
		SPECIES_NEVREAN			= 'icons/mob/hands.dmi',
		SPECIES_VULPKANIN		= 'icons/mob/hands.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/mob/hands.dmi',
		SPECIES_FENNEC			= 'icons/mob/hands.dmi',
		SPECIES_PROMETHEAN		= 'icons/mob/hands.dmi',
		SPECIES_TESHARI 		= 'icons/mob/hands.dmi',
		SPECIES_VASILISSAN		= 'icons/mob/hands.dmi',
		SPECIES_VOX				= 'icons/mob/species/vox/gloves.dmi'
		)

	sprite_sheets_obj = list(
		SPECIES_HUMAN			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_TAJARAN 			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_SKRELL 			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_UNATHI 			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_XENOHYBRID		= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_AKULA 			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_SERGAL			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_NEVREAN			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_VULPKANIN 		= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_ZORREN_HIGH		= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_FENNEC 			= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_PROMETHEAN		= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_TESHARI 		= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_VASILISSAN		= 'icons/obj/clothing/gloves_ch.dmi',
		SPECIES_VOX				= 'icons/obj/clothing/gloves_ch.dmi'
		)

/obj/item/clothing/shoes/magboots/rig/ch
	sprite_sheets = list(
		SPECIES_HUMAN			= 'icons/mob/feet.dmi',
		SPECIES_TAJARAN 			= 'icons/mob/feet.dmi',
		SPECIES_SKRELL 			= 'icons/mob/feet.dmi',
		SPECIES_UNATHI 			= 'icons/mob/feet.dmi',
		SPECIES_XENOHYBRID		= 'icons/mob/feet.dmi',
		SPECIES_AKULA 			= 'icons/mob/feet.dmi',
		SPECIES_SERGAL			= 'icons/mob/feet.dmi',
		SPECIES_NEVREAN			= 'icons/mob/feet.dmi',
		SPECIES_VULPKANIN		= 'icons/mob/feet.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/mob/feet.dmi',
		SPECIES_FENNEC			= 'icons/mob/feet.dmi',
		SPECIES_PROMETHEAN		= 'icons/mob/feet.dmi',
		SPECIES_TESHARI 		= 'icons/mob/feet.dmi',
		SPECIES_VASILISSAN		= 'icons/mob/feet.dmi',
		SPECIES_VOX				= 'icons/mob/species/vox/shoes.dmi'
		)

	sprite_sheets_obj = list(
		SPECIES_HUMAN			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_TAJARAN 			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_SKRELL 			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_UNATHI 			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_XENOHYBRID		= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_AKULA 			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_SERGAL			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_NEVREAN			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_VULPKANIN 		= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_FENNEC 			= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_PROMETHEAN		= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_TESHARI 		= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_VASILISSAN		= 'icons/obj/clothing/shoes_ch.dmi',
		SPECIES_VOX				= 'icons/obj/clothing/shoes_ch.dmi'
		)



/*
/obj/item/clothing/head/helmet/space/rig/ch
	species_restricted = list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_GREY_YW/*ywedit*/)
	flags = PHORONGUARD //YAWN Edit

/obj/item/clothing/gloves/gauntlets/rig/ch
	species_restricted = list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_GREY_YW/*ywedit*/)
	flags = PHORONGUARD //YAWN Edit

/obj/item/clothing/shoes/magboots/rig/ch
	species_restricted = list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_GREY_YW/*ywedit*/)
	flags = PHORONGUARD //YAWN Edit

/obj/item/clothing/suit/space/rig/ch
	species_restricted = list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_GREY_YW/*ywedit*/)
	flags = PHORONGUARD //YAWN Edit
*/

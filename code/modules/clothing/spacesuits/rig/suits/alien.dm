/*
 *	UNATHI
 */

//ChompEdit begins

/obj/item/rig/breacher
	name = "\improper NT breacher chassis control module"
	desc = "A cheap NT knock-off of an Unathi battle-rig. Uses softer, but lighter, armour plating, producing a still-useful suit"
	suit_type = "\improper NT breacher"
	icon_state = "breacher_rig_cheap"
	armor = list(melee = 60, bullet = 45, laser = 45, energy = 10, bomb = 50, bio = 100, rad = 20)
	emp_protection = -20
	slowdown = 3  //This is too much, reducing from 6 to 3.  May edit again in the future.
	offline_slowdown = 5
	vision_restriction = 0  //This is dumb as hell and should be 0 if we want the suit to be even vaguely useful.
	offline_vision_restriction = 2 //This actually serves as a good weakness for them, making them vulnerable to Ion weapons.
	siemens_coefficient = 0.75
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_STORAGE) //CHOMPedit end
	chest_type = /obj/item/clothing/suit/space/rig/breacher
	helm_type = /obj/item/clothing/head/helmet/space/rig/breacher
	boot_type = /obj/item/clothing/shoes/magboots/rig/breacher

/obj/item/rig/breacher/fancy
	name = "breacher chassis control module"
	desc = "An authentic Unathi breacher chassis. Huge, bulky and absurdly heavy. It must be like wearing a tank."
	suit_type = "breacher chassis"
	icon_state = "breacher_rig"
	armor = list(melee = 85, bullet = 80, laser = 80, energy = 40, bomb = 80, bio = 100, rad = 60) //Still a tank just not indestructable
	vision_restriction = 0
	siemens_coefficient = 0.2
	slowdown = 6
	offline_slowdown = 10

/obj/item/clothing/head/helmet/space/rig/breacher
	species_restricted = list(SPECIES_UNATHI)
	force = 5

/obj/item/clothing/suit/space/rig/breacher
	species_restricted = list(SPECIES_UNATHI)

/obj/item/clothing/shoes/magboots/rig/breacher
	species_restricted = list(SPECIES_UNATHI)

//ChompEdit Ends

/*
 *	VOX
 */

/obj/item/rig/vox	//Just to get the flags set up
	name = "alien control module"
	desc = "This metal box writhes and squirms as if it were alive..."
	suit_type = "alien"
	icon_state = "vox_rig"
	armor = list(melee = 60, bullet = 50, laser = 40, energy = 15, bomb = 30, bio = 100, rad = 50)
	flags = PHORONGUARD
	item_flags = THICKMATERIAL
	siemens_coefficient = 0.2
	offline_slowdown = 2.5
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_EXPLO, POCKET_BAYSUIT)

	air_type = /obj/item/tank/vox

	helm_type = /obj/item/clothing/head/helmet/space/rig/vox
	boot_type = /obj/item/clothing/shoes/magboots/rig/vox
	chest_type = /obj/item/clothing/suit/space/rig/vox
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/vox

/obj/item/clothing/head/helmet/space/rig/vox
	species_restricted = list(SPECIES_VOX)
	flags_inv = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE

/obj/item/clothing/shoes/magboots/rig/vox
	name = "talons"
	species_restricted = list(SPECIES_VOX)
	sprite_sheets = list(
		SPECIES_VOX = 'icons/inventory/feet/mob_vox.dmi'
		)

/obj/item/clothing/suit/space/rig/vox
	species_restricted = list(SPECIES_VOX)

/obj/item/clothing/gloves/gauntlets/rig/vox
	name = DEVELOPER_WARNING_NAME
	siemens_coefficient = 0
	species_restricted = list(SPECIES_VOX)
	sprite_sheets = list(
		SPECIES_VOX = 'icons/inventory/hands/mob_vox.dmi'
		)

/obj/item/rig/vox/carapace
	name = "dense alien control module"
	suit_type = "dense alien"
	armor = list(melee = 60, bullet = 50, laser = 40, energy = 15, bomb = 30, bio = 100, rad = 50)
	emp_protection = 40 //change this to 30 if too high.

	req_access = list(ACCESS_SYNDICATE)

	cell_type =  /obj/item/cell/hyper

	initial_modules = list(
		/obj/item/rig_module/mounted/energy_blade,
		/obj/item/rig_module/sprinter,
		/obj/item/rig_module/electrowarfare_suite,
		/obj/item/rig_module/vision,
		/obj/item/rig_module/power_sink,
		/obj/item/rig_module/self_destruct
		)

/obj/item/rig/vox/stealth
	name = "sinister alien control module"
	suit_type = "sinister alien"
	icon_state = "voxstealth_rig"
	armor = list(melee = 40, bullet = 30, laser = 30, energy = 15, bomb = 30, bio = 100, rad = 50)
	emp_protection = 40 //change this to 30 if too high.

	req_access = list(ACCESS_SYNDICATE)

	cell_type =  /obj/item/cell/hyper

	initial_modules = list(
		/obj/item/rig_module/stealth_field,
		/obj/item/rig_module/electrowarfare_suite,
		/obj/item/rig_module/vision,
		/obj/item/rig_module/power_sink,
		/obj/item/rig_module/self_destruct
		)


// === merged from alien_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/head/helmet/space/rig/vox/ch
	icon_state = "vox_engineer_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.
	icon = 'icons/inventory/head/item.dmi'
	sprite_sheets = list(
		SPECIES_VOX = 'icons/inventory/head/mob_vox.dmi'
		)

/obj/item/clothing/shoes/magboots/rig/vox/ch
	icon_state = "vox_engineer_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.
	icon = 'icons/inventory/feet/item.dmi'
	sprite_sheets = list(
		SPECIES_VOX = 'icons/inventory/feet/mob_vox.dmi'
		)

/obj/item/clothing/suit/space/rig/vox/ch
	icon_state = "vox_engineer_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.
	icon = 'icons/inventory/suit/item.dmi'
	sprite_sheets = list(
		SPECIES_VOX = 'icons/inventory/suit/mob_vox.dmi'
		)

/obj/item/clothing/gloves/gauntlets/rig/vox/ch
	icon_state = "vox_engineer_rig" //The name is seen by players, but rigs do some funny things like overwriting the icon_state. The unit test will screech if a rig doesn't have an icon_state, so we set one here.
	icon = 'icons/inventory/hands/item.dmi'
	sprite_sheets = list(
		SPECIES_VOX = 'icons/inventory/hands/mob_vox.dmi'
		)

/obj/item/rig/vox/engineering
	name = "fluid alien control module"
	suit_type = "\improper industrial alien"
	icon_state = "vox_engineer_rig"
	desc = "A lightweight, alien rig dedicated for construction and engineering tasks. Not reccomended for hostile engagement."
	armor = list(melee = 25, bullet = 5, laser = 40, energy = 45, bomb = 50, bio = 100, rad = 100) //CE suit values but shuffled to a tighter focus on the job hazards
	flags = PHORONGUARD
	item_flags = THICKMATERIAL
	siemens_coefficient = 0
	offline_slowdown = 2.5
	slowdown = 0
	emp_protection = 40 //change this to 30 if too high.
	rigsuit_max_pressure = 20 * ONE_ATMOSPHERE			  // Max pressure the rig protects against when sealed
	rigsuit_min_pressure = 0							  // Min pressure the rig protects against when sealed

	req_one_access = list()
	req_access = list(ACCESS_ENGINE)
	allowed = list(POCKET_GENERIC, POCKET_ALL_TANKS, POCKET_SECURITY, POCKET_SUIT_REGULATORS)
	offline_vision_restriction = 1

	initial_modules = list(
		/obj/item/rig_module/maneuvering_jets,
		/obj/item/rig_module/device/plasmacutter,
		/obj/item/rig_module/device/rcd,
		/obj/item/rig_module/vision/meson
	)

	air_type = /obj/item/tank/nitrogen

	max_heat_protection_temperature = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE

	helm_type = /obj/item/clothing/head/helmet/space/rig/vox/ch
	boot_type = /obj/item/clothing/shoes/magboots/rig/vox/ch
	chest_type = /obj/item/clothing/suit/space/rig/vox/ch
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/vox/ch

/obj/item/rig/vox/security
	name = "sturdy alien control module"
	suit_type = "\improper sturdy alien"
	icon_state = "vox_sec_rig"
	desc = "A medium weight, alien control module. Built sturdy for security engagements."
	armor = list (melee = 60, bullet = 50, laser = 40, energy = 10, bomb = 20, bio = 100, rad = 50) //CE suit values but shuffled to a tighter focus on the job hazards
	flags = PHORONGUARD
	item_flags = THICKMATERIAL
	siemens_coefficient = 0.5
	offline_slowdown = 5
	slowdown = 0
	emp_protection = 40 //change this to 30 if too high.

	req_one_access = list()
	allowed = list(POCKET_GENERIC, POCKET_ALL_TANKS, POCKET_SECURITY, POCKET_SUIT_REGULATORS)
	offline_vision_restriction = 1

	initial_modules = list(
	)

	air_type = /obj/item/tank/vox

	max_heat_protection_temperature = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE

	helm_type = /obj/item/clothing/head/helmet/space/rig/vox/ch
	boot_type = /obj/item/clothing/shoes/magboots/rig/vox/ch
	chest_type = /obj/item/clothing/suit/space/rig/vox/ch
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/vox/ch

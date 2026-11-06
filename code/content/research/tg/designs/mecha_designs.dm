// Mecha cells
/datum/design_techweb/high_mech_cell
	name = "High-Capacity Mecha Cell"
	desc = "A tier 2 power cell for mecha."
	id = "high_mech_cell"
	build_type = PROTOLATHE | MECHFAB
	// req_tech = list(TECH_POWER = 3, TECH_MATERIAL = 3)
	materials = list(MAT_STEEL = 600, MAT_SILVER = 150, MAT_GLASS = 70)
	build_path = /obj/item/cell/mech/high
	category = list(
		RND_CATEGORY_MECHFAB_EQUIPMENT
	)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/super_mech_cell
	name = "Super-Capacity Mecha Cell"
	desc = "A tier 3 power cell for mecha."
	id = "super_mech_cell"
	build_type = PROTOLATHE | MECHFAB
	// req_tech = list(TECH_POWER = 5, TECH_MATERIAL = 4)
	materials = list(MAT_STEEL = 500, MAT_GOLD = 200, MAT_SILVER = 200, MAT_GLASS = 80)
	build_path = /obj/item/cell/mech/super
	category = list(
		RND_CATEGORY_MECHFAB_EQUIPMENT
	)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/synthetic_flash
	name = "Synthetic Flash"
	desc = "A synthetic flash with a singular charge."
	id = "sflash"
	//req_tech = list(TECH_MAGNET = 3, TECH_COMBAT = 2)
	build_type = MECHFAB
	materials = list(MAT_STEEL = 562, MAT_GLASS = 562)
	build_path = /obj/item/flash/synthetic
	category = list(
		RND_CATEGORY_TOOLS
	) //I really don't know what to put for this.
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/mechfab/scarab
	category = list(
		RND_CATEGORY_MECHFAB_SCARAB
	)

/datum/design_techweb/mechfab/scarab/chassis
	name = "Scarab Chassis"
	id = "scarab_chassis"
	build_path = /obj/item/mecha_parts/chassis/scarab
	materials = list(MAT_STEEL = 15000)

/datum/design_techweb/mechfab/scarab/torso
	name = "Scarab Torso"
	id = "scarab_torso"
	build_path = /obj/item/mecha_parts/part/scarab_torso
	materials = list(MAT_STEEL = 30000, MAT_GLASS = 10000)

/datum/design_techweb/mechfab/scarab/head
	name = "Scarab Head"
	id = "scarab_head"
	build_path = /obj/item/mecha_parts/part/scarab_head
	materials = list(MAT_STEEL = 12500, MAT_GLASS = 5000)

/datum/design_techweb/mechfab/scarab/left_arm
	name = "Scarab Left Arm"
	id = "scarab_left_arm"
	build_path = /obj/item/mecha_parts/part/scarab_left_arm
	materials = list(MAT_STEEL = 10000)

/datum/design_techweb/mechfab/scarab/right_arm
	name = "Scarab Right Arm"
	id = "scarab_right_arm"
	build_path = /obj/item/mecha_parts/part/scarab_right_arm
	materials = list(MAT_STEEL = 10000)

/datum/design_techweb/mechfab/scarab/left_leg
	name = "Scarab Left Legs"
	id = "scarab_left_legs"
	build_path = /obj/item/mecha_parts/part/scarab_left_legs
	materials = list(MAT_STEEL = 30000)

/datum/design_techweb/mechfab/scarab/right_leg
	name = "Scarab Right Legs"
	id = "scarab_right_legs"
	build_path = /obj/item/mecha_parts/part/scarab_right_legs
	materials = list(MAT_STEEL = 30000)

/datum/design_techweb/mechfab/phazon
	category = list(
		RND_CATEGORY_MECHFAB_PHAZON
	)

/datum/design_techweb/mechfab/phazon/chassis
	name = "Phazon Chassis"
	id = "phazon_chassis"
	build_path = /obj/item/mecha_parts/chassis/phazon
	materials = list(MAT_STEEL = 30000, MAT_DURASTEEL = 4000, MAT_PHORON = 4000, MAT_GOLD = 5000, MAT_VERDANTIUM = 4000)

/datum/design_techweb/mechfab/phazon/torso
	name = "Phazon Torso"
	id = "phazon_torso"
	build_path = /obj/item/mecha_parts/part/phazon_torso
	materials = list(MAT_STEEL = 30000, MAT_DURASTEEL = 2000, MAT_PHORON = 6000, MAT_GOLD = 6000, MAT_VERDANTIUM = 2000)

/datum/design_techweb/mechfab/phazon/head
	name = "Phazon Head"
	id = "phazon_head"
	build_path = /obj/item/mecha_parts/part/phazon_head
	materials = list(MAT_STEEL = 10000, MAT_DURASTEEL = 1000, MAT_PHORON = 4000, MAT_GOLD = 4000, MAT_VERDANTIUM = 500)

/datum/design_techweb/mechfab/phazon/left_arm
	name = "Phazon Left Arm"
	id = "phazon_left_arm"
	build_path = /obj/item/mecha_parts/part/phazon_left_arm
	materials = list(MAT_STEEL = 15000, MAT_PHORON = 2000, MAT_GOLD = 2000, MAT_VERDANTIUM = 500)

/datum/design_techweb/mechfab/phazon/right_arm
	name = "Phazon Right Arm"
	id = "phazon_right_arm"
	build_path = /obj/item/mecha_parts/part/phazon_right_arm
	materials = list(MAT_STEEL = 15000, MAT_PHORON = 2000, MAT_GOLD = 2000, MAT_VERDANTIUM = 500)

/datum/design_techweb/mechfab/phazon/left_leg
	name = "Phazon Left Leg"
	id = "phazon_left_leg"
	build_path = /obj/item/mecha_parts/part/phazon_left_leg
	materials = list(MAT_STEEL = 15000, MAT_PHORON = 2000, MAT_GOLD = 2000, MAT_VERDANTIUM = 500)

/datum/design_techweb/mechfab/phazon/right_leg
	name = "Phazon Right Leg"
	id = "phazon_right_leg"
	build_path = /obj/item/mecha_parts/part/phazon_right_leg
	materials = list(MAT_STEEL = 15000, MAT_PHORON = 2000, MAT_GOLD = 2000, MAT_VERDANTIUM = 500)

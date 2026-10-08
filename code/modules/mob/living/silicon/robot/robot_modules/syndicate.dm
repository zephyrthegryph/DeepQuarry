/* Syndicate modules */

/obj/item/robot_module/robot/syndicate
	name = "illegal robot module"
	hide_on_manifest = TRUE
	languages = list(
					LANGUAGE_SOL_COMMON = 1,
					LANGUAGE_TRADEBAND = 1,
					LANGUAGE_UNATHI = 0,
					LANGUAGE_SIIK	= 0,
					LANGUAGE_AKHANI = 0,
					LANGUAGE_SKRELLIAN = 0,
					LANGUAGE_ROOTLOCAL = 0,
					LANGUAGE_GUTTER = 1,
					LANGUAGE_SCHECHI = 0,
					LANGUAGE_EAL	 = 1,
					LANGUAGE_SIGN	 = 0,
					LANGUAGE_TERMINUS = 1,
					LANGUAGE_ZADDAT = 0
					)
	ui_theme = "syndicate"
	idcard_type = /obj/item/card/id/syndicate

// All syndie modules get these, and the base borg items (flash, crowbar, etc).
/obj/item/robot_module/robot/syndicate/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/pinpointer/shuttle/merc(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/blade/syndicate(src))
	rel_add(src, nameof(modules), new /obj/item/multitool/ai_detector/cyborg(src))

	var/datum/matter_synth/cloth = new /datum/matter_synth/cloth(40000)
	rel_add(src, nameof(synths), cloth)

	var/jetpack = new/obj/item/tank/jetpack/carbondioxide(src)
	rel_add(src, nameof(modules), jetpack)

	var/obj/item/card/id/robot_id = robot.idcard
	robot_id.forceMove(src)
	modules |= robot_id // ALLOW(ownership): the robot owns its idcard (robot.idcard); the module only lists it as a usable item

/obj/item/robot_module/robot/syndicate/adjust_gps(obj/item/gps/robot/robot_gps)
	robot_gps.long_range = TRUE
	robot_gps.hide_signal = TRUE
	robot_gps.can_hide_signal = TRUE

// Gets a big shield and a gun that shoots really fast to scare the opposing force.
/obj/item/robot_module/robot/syndicate/protector
	name = "protector robot module"
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/syndicate/protector/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/shield_projector/rectangle/weak(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/laser/dakkalaser(src))
	rel_add(src, nameof(modules), new /obj/item/handcuffs/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/baton(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/K9/syndie(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))

// 95% engi-borg and 15% roboticist.
/obj/item/robot_module/robot/syndicate/mechanist
	name = "mechanist robot module"

/obj/item/robot_module/robot/syndicate/mechanist/create_equipment(mob/living/silicon/robot/robot)
	..()
	// General engineering/hacking.
	rel_add(src, nameof(modules), new /obj/item/borg/sight/meson(src))
	rel_add(src, nameof(modules), new /obj/item/weldingtool/electric/mounted/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wirecutters/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/multitool/ai_detector(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/plasmacutter(src))
	rel_add(src, nameof(modules), new /obj/item/rcd/electric/mounted/borg/lesser(src)) // Can't eat rwalls to prevent AI core cheese.
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/blade/ionic(src))

	// FBP repair.
	rel_add(src, nameof(modules), new /obj/item/robotanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot/jumper(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/no_use/organ/robotics(src))

	// Hacking other things.
	rel_add(src, nameof(modules), new /obj/item/card/robot/syndi(src))
	rel_add(src, nameof(modules), new /obj/item/card/emag/borg(src))

	// Materials.
	var/datum/matter_synth/nanite = new /datum/matter_synth/nanite(10000)
	rel_add(src, nameof(synths), nanite)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire()
	rel_add(src, nameof(synths), wire)
	var/datum/matter_synth/metal = new /datum/matter_synth/metal(40000)
	rel_add(src, nameof(synths), metal)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(40000)
	rel_add(src, nameof(synths), glass)

	var/obj/item/stack/nanopaste/N = new /obj/item/stack/nanopaste(src)
	N.uses_charge = 1
	N.charge_costs = list(1000)
	rel_add(N, nameof(N.synths), nanite)
	rel_add(src, nameof(modules), N)

	var/obj/item/dogborg/sleeper/compactor/syndie/MD = new /obj/item/dogborg/sleeper/compactor/syndie(src)
	rel_set(MD, nameof(MD.metal), metal)
	rel_set(MD, nameof(MD.glass), glass)
	rel_add(src, nameof(modules), MD)

	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))

	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))



// Mediborg optimized for on-the-field healing, but can also do surgery if needed.
/obj/item/robot_module/robot/syndicate/combat_medic
	name = "combat medic robot module"
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/syndicate/combat_medic/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer/phasic(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/merc(src))

	// Surgery things.
	rel_add(src, nameof(modules), new /obj/item/autopsy_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/medical(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))

	// General healing.
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot/combat(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper(src)) // Allows borg to fix necrosis apparently
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))
	rel_add(src, nameof(modules), new /obj/item/roller_holder(src))

	// Materials.
	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(15000)
	rel_add(src, nameof(synths), medicine)

	var/obj/item/stack/medical/advanced/ointment/O = new /obj/item/stack/medical/advanced/ointment(src)
	var/obj/item/stack/medical/advanced/bruise_pack/B = new /obj/item/stack/medical/advanced/bruise_pack(src)
	var/obj/item/stack/medical/splint/S = new /obj/item/stack/medical/splint(src)
	O.uses_charge = 1
	O.charge_costs = list(1000)
	rel_add(O, nameof(O.synths), medicine)
	B.uses_charge = 1
	B.charge_costs = list(1000)
	rel_add(B, nameof(B.synths), medicine)
	S.uses_charge = 1
	S.charge_costs = list(1000)
	rel_add(S, nameof(S.synths), medicine)
	rel_add(src, nameof(modules), O)
	rel_add(src, nameof(modules), B)
	rel_add(src, nameof(modules), S)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/syndie(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/syndicate/combat_medic/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.set_mode(initial(S.mode))
		S.desc = initial(S.desc)
	..()

/obj/item/robot_module/robot/syndicate/ninja
	name = "ninja robot module"
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/syndicate/ninja/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/K9/syndie(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/syndicate(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/syndicate(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/syndicate(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/blade/ninja(src))
	rel_add(src, nameof(modules), new /obj/item/borg/cloak(src))
	//Removes the default sblade
	var/obj/item/melee/robotic/blade/syndicate/sblade = locate_in_list(src.modules, /obj/item/melee/robotic/blade/syndicate)
	if(sblade)
		rel_remove(src, nameof(modules), sblade)

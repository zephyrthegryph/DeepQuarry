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
	own_add(src, "modules", new /obj/item/pinpointer/shuttle/merc(src))
	own_add(src, "modules", new /obj/item/melee/robotic/blade/syndicate(src))
	own_add(src, "modules", new /obj/item/multitool/ai_detector/cyborg(src))

	var/datum/matter_synth/cloth = new /datum/matter_synth/cloth(40000)
	own_add(src, "synths", cloth)

	var/jetpack = new/obj/item/tank/jetpack/carbondioxide(src)
	own_add(src, "modules", jetpack)
	own_set(robot, "internals", jetpack)

	var/obj/item/card/id/robot_id = robot.idcard
	robot_id.forceMove(src)
	own_add(src, "modules", robot_id)

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
	own_add(src, "modules", new /obj/item/shield_projector/rectangle/weak(src))
	own_add(src, "modules", new /obj/item/gun/energy/robotic/laser/dakkalaser(src))
	own_add(src, "modules", new /obj/item/handcuffs/cyborg(src))
	own_add(src, "modules", new /obj/item/melee/robotic/baton(src))

	own_add(src, "modules", new /obj/item/dogborg/sleeper/K9/syndie(src))
	own_add(src, "modules", new /obj/item/dogborg/pounce(src))
	own_add(src, "modules", new /obj/item/robotic_multibelt/materials(src))

// 95% engi-borg and 15% roboticist.
/obj/item/robot_module/robot/syndicate/mechanist
	name = "mechanist robot module"

/obj/item/robot_module/robot/syndicate/mechanist/create_equipment(mob/living/silicon/robot/robot)
	..()
	// General engineering/hacking.
	own_add(src, "modules", new /obj/item/borg/sight/meson(src))
	own_add(src, "modules", new /obj/item/weldingtool/electric/mounted/cyborg(src))
	own_add(src, "modules", new /obj/item/tool/screwdriver/cyborg(src))
	own_add(src, "modules", new /obj/item/tool/wrench/cyborg(src))
	own_add(src, "modules", new /obj/item/tool/wirecutters/cyborg(src))
	own_add(src, "modules", new /obj/item/multitool/ai_detector(src))
	own_add(src, "modules", new /obj/item/pickaxe/plasmacutter(src))
	own_add(src, "modules", new /obj/item/rcd/electric/mounted/borg/lesser(src)) // Can't eat rwalls to prevent AI core cheese.
	own_add(src, "modules", new /obj/item/melee/robotic/blade/ionic(src))

	// FBP repair.
	own_add(src, "modules", new /obj/item/robotanalyzer(src))
	own_add(src, "modules", new /obj/item/shockpaddles/robot/jumper(src))
	own_add(src, "modules", new /obj/item/gripper/no_use/organ/robotics(src))

	// Hacking other things.
	own_add(src, "modules", new /obj/item/card/robot/syndi(src))
	own_add(src, "modules", new /obj/item/card/emag/borg(src))

	// Materials.
	var/datum/matter_synth/nanite = new /datum/matter_synth/nanite(10000)
	own_add(src, "synths", nanite)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire()
	own_add(src, "synths", wire)
	var/datum/matter_synth/metal = new /datum/matter_synth/metal(40000)
	own_add(src, "synths", metal)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(40000)
	own_add(src, "synths", glass)

	var/obj/item/stack/nanopaste/N = new /obj/item/stack/nanopaste(src)
	N.uses_charge = 1
	N.charge_costs = list(1000)
	rel_add(N, "synths", nanite)
	own_add(src, "modules", N)

	var/obj/item/dogborg/sleeper/compactor/syndie/MD = new /obj/item/dogborg/sleeper/compactor/syndie(src)
	rel_set(MD, "metal", metal)
	rel_set(MD, "glass", glass)
	own_add(src, "modules", MD)

	own_add(src, "modules", new /obj/item/dogborg/pounce(src))

	own_add(src, "modules", new /obj/item/robotic_multibelt/materials(src))



// Mediborg optimized for on-the-field healing, but can also do surgery if needed.
/obj/item/robot_module/robot/syndicate/combat_medic
	name = "combat medic robot module"
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/syndicate/combat_medic/create_equipment(mob/living/silicon/robot/robot)
	..()
	own_add(src, "modules", new /obj/item/healthanalyzer/phasic(src))
	own_add(src, "modules", new /obj/item/reagent_containers/borghypo/merc(src))

	// Surgery things.
	own_add(src, "modules", new /obj/item/autopsy_scanner(src))
	own_add(src, "modules", new /obj/item/robotic_multibelt/medical(src))
	own_add(src, "modules", new /obj/item/robotic_multibelt/medical(src))
	own_add(src, "modules", new /obj/item/gripper/medical(src))
	own_add(src, "modules", new /obj/item/robotic_multibelt/materials(src))

	// General healing.
	own_add(src, "modules", new /obj/item/shockpaddles/robot/combat(src))
	own_add(src, "modules", new /obj/item/reagent_containers/dropper(src)) // Allows borg to fix necrosis apparently
	own_add(src, "modules", new /obj/item/reagent_containers/syringe(src))
	own_add(src, "modules", new /obj/item/roller_holder(src))

	// Materials.
	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(15000)
	own_add(src, "synths", medicine)

	var/obj/item/stack/medical/advanced/ointment/O = new /obj/item/stack/medical/advanced/ointment(src)
	var/obj/item/stack/medical/advanced/bruise_pack/B = new /obj/item/stack/medical/advanced/bruise_pack(src)
	var/obj/item/stack/medical/splint/S = new /obj/item/stack/medical/splint(src)
	O.uses_charge = 1
	O.charge_costs = list(1000)
	rel_add(O, "synths", medicine)
	B.uses_charge = 1
	B.charge_costs = list(1000)
	rel_add(B, "synths", medicine)
	S.uses_charge = 1
	S.charge_costs = list(1000)
	rel_add(S, "synths", medicine)
	own_add(src, "modules", O)
	own_add(src, "modules", B)
	own_add(src, "modules", S)

	own_add(src, "modules", new /obj/item/dogborg/sleeper/syndie(src))
	own_add(src, "modules", new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/syndicate/combat_medic/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.mode = initial(S.mode)
		S.desc = initial(S.desc)
		S.update_icon()
	..()

/obj/item/robot_module/robot/syndicate/ninja
	name = "ninja robot module"
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/syndicate/ninja/create_equipment(mob/living/silicon/robot/robot)
	..()
	own_add(src, "modules", new /obj/item/dogborg/sleeper/K9/syndie(src))
	own_add(src, "modules", new /obj/item/dogborg/pounce(src))
	own_add(src, "modules", new /obj/item/gripper/syndicate(src))
	own_add(src, "modules", new /obj/item/robotic_multibelt/syndicate(src))
	own_add(src, "modules", new /obj/item/robotic_multibelt/syndicate(src))
	own_add(src, "modules", new /obj/item/melee/robotic/blade/ninja(src))
	own_add(src, "modules", new /obj/item/borg/cloak(src))
	//Removes the default sblade
	var/obj/item/melee/robotic/blade/syndicate/sblade = locate_in_list(src.modules, /obj/item/melee/robotic/blade/syndicate)
	if(sblade)
		own_take_member(src, "modules", sblade)
		qdel(sblade)

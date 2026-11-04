// Cyborgs (non-drones), default loadout. This will be given to every module.
/obj/item/robot_module/robot/create_equipment(mob/living/silicon/robot/robot)
	..()
	var/datum/matter_synth/water = new /datum/matter_synth(500)
	water.name = "Water reserves"
	water.recharge_rate = 10
	water.set_max_energy(1000)
	rel_set(robot, nameof(robot.water_res), water)
	rel_add(src, nameof(synths), water)
	var/obj/item/robot_tongue/T = new /obj/item/robot_tongue(src)
	rel_set(T, nameof(T.water), water)
	rel_add(src, nameof(modules), T)
	var/obj/item/gps/robot/robot_gps = new /obj/item/gps/robot(src)
	adjust_gps(robot_gps)
	rel_add(src, nameof(modules), robot_gps)
	rel_add(src, nameof(modules), new /obj/item/boop_module(src))
	rel_add(src, nameof(modules), new /obj/item/flash/robot(src))
	rel_add(src, nameof(modules), new /obj/item/extinguisher(src))
	rel_add(src, nameof(modules), new /obj/item/tool/crowbar/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/jaws/small(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/scene(src))
	rel_add(src, nameof(modules), new /obj/item/robo_dice(src))

/obj/item/robot_module/robot/proc/adjust_gps(obj/item/gps/robot/robot_gps)
	return

/obj/item/robot_module/robot/medical
	staffing_role = DEPARTMENT_MEDICAL
	name = "medical robot module"
	channels = list(CHANNEL_MEDICAL = 1)
	networks = list(NETWORK_MEDICAL)
	subsystems = list(/mob/living/silicon/proc/subsystem_crew_monitor)
	pto_type = PTO_MEDICAL
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/clerical
	name = "service robot module"
	channels = list(
		CHANNEL_SERVICE = 1,
		CHANNEL_COMMAND = 1
		)
	languages = list(
					LANGUAGE_SOL_COMMON	= 1,
					LANGUAGE_TRADEBAND	= 1,
					LANGUAGE_UNATHI		= 1,
					LANGUAGE_SIIK		= 1,
					LANGUAGE_SKRELLIAN	= 1,
					LANGUAGE_ROOTLOCAL	= 0,
					LANGUAGE_GUTTER		= 1,
					LANGUAGE_SCHECHI	= 1,
					LANGUAGE_SIGN		= 0,
					LANGUAGE_BIRDSONG	= 1,
					LANGUAGE_SAGARU		= 1,
					LANGUAGE_CANILUNZT	= 1,
					LANGUAGE_ECUREUILIAN= 1,
					LANGUAGE_DAEMON		= 1,
					LANGUAGE_ENOCHIAN	= 1,
					LANGUAGE_DRUDAKAR	= 1,
					LANGUAGE_TAVAN		= 1
					)
	pto_type = PTO_CIVILIAN

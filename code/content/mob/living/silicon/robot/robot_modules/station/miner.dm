/obj/item/robot_module/robot/miner
	staffing_role = DEPARTMENT_CARGO
	name = "miner robot module"
	channels = list(CHANNEL_SUPPLY = 1)
	networks = list(NETWORK_MINE)
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/pka, /obj/item/borg/upgrade/restricted/diamonddrill, /obj/item/borg/upgrade/restricted/adv_scanner, /obj/item/borg/upgrade/restricted/adv_snatcher, /obj/item/borg/upgrade/restricted/adv_mailbag)
	pto_type = PTO_CARGO
	idcard_type = /obj/item/card/id/synthetic/borg

/obj/item/robot_module/robot/miner/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/borg/sight/material(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/borgdrill(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/sheetsnatcher/borg(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/miner(src))
	rel_add(src, nameof(modules), new /obj/item/mining_scanner/robot(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src)) // Phasegun for regular mining cyborg.
	rel_add(src, nameof(modules), new /obj/item/vac_attachment(src))

	var/obj/item/card/id/robot_id = robot.idcard
	robot_id.name = "\improper Synthetic Miner ID"
	robot_id.set_initial_sprite_stack(list("base-stamp", "top-brown", "stamp-n", "stripe-purple"))
	robot_id.reset_icon()
	robot_id.forceMove(src)
	modules |= robot_id // ALLOW(ownership): the robot owns its idcard (robot.idcard); the module only lists it as a usable item
	rel_add(src, nameof(modules), new /obj/item/mail_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/mail/borg(src))
	rel_add(src, nameof(modules), new /obj/item/destTagger(src))
	rel_add(src, nameof(modules), new /obj/item/packageWrap/borg(src))
	rel_add(src, nameof(emag), new /obj/item/kinetic_crusher/machete/dagger(src))

	var/datum/matter_synth/beacon = new /datum/matter_synth/beacon(10000)
	rel_add(src, nameof(synths), beacon)

	var/obj/item/stack/marker_beacon/MB = new /obj/item/stack/marker_beacon(src)
	MB.set_uses_charge(1)
	MB.set_charge_costs(list(500))
	MB.add_synth(beacon)
	rel_add(src, nameof(modules), MB)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/supply(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

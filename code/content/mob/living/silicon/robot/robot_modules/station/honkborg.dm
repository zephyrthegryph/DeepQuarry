/obj/item/robot_module/robot/clerical/honkborg
	name = "clown robot module"
	channels = list("Service" = 1,
					"Entertainment" = 1)
	pto_type = PTO_CIVILIAN
	can_be_pushed = 0

/obj/item/robot_module/robot/clerical/honkborg/create_equipment(mob/living/silicon/robot/R)
	rel_add(src, nameof(modules), new /obj/item/gripper/service(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/bucket/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/botanical(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))
	rel_add(src, nameof(modules), new /obj/item/bikehorn(src))
	rel_add(src, nameof(modules), new /obj/item/gun/launcher/confetti_cannon/robot(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/spray/waterflower(src))

	var/obj/item/rsf/M = new /obj/item/rsf(src)
	M.stored_matter = 30
	rel_add(src, nameof(modules), M)

	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper/industrial(src))

	var/obj/item/flame/lighter/zippo/L = new /obj/item/flame/lighter/zippo(src) // starts unlit: lit, it would burn on the slow lane from module creation
	rel_add(src, nameof(modules), L)

	rel_add(src, nameof(modules), new /obj/item/tray/robotray(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/service(src))

	var/obj/item/dogborg/sleeper/compactor/honkborg/B = new /obj/item/dogborg/sleeper/compactor/honkborg(src)
	rel_add(src, nameof(modules), B)
	var/obj/item/reagent_containers/spray/LS = new /obj/item/reagent_containers/spray(src)
	rel_add(src, nameof(emag), LS)
	LS.reagents.add_reagent(REAGENT_ID_LUBE, 250)
	LS.name = "Lube spray"
	..()

/obj/item/robot_module/robot/clerical/honkborg/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/reagent_containers/spray/LS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(LS)
		LS.reagents.add_reagent(REAGENT_ID_LUBE, 2 * amount)

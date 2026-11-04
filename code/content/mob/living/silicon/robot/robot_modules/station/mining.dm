/obj/item/robot_module/drone/mining
	name = "miner drone module"
	channels = list(CHANNEL_SUPPLY = 1)
	networks = list(NETWORK_MINE)

/obj/item/robot_module/drone/mining/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/borg/sight/material(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/borgdrill(src))
	rel_add(src, nameof(modules), new /obj/item/ore_bag(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/sheetsnatcher/borg(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src)) // makes the mining borg able to defend itself.
	rel_add(src, nameof(emag), new /obj/item/pickaxe/diamonddrill(src))

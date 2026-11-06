/obj/item/robot_module/robot/standard
	name = "standard robot module"
	pto_type = PTO_CIVILIAN

/obj/item/robot_module/robot/standard/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/melee/baton/loaded(src))
	rel_add(src, nameof(emag), new /obj/item/melee/energy/sword(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/generic(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

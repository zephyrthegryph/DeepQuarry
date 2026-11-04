/obj/item/robot_module/robot/security/general
	name = "security robot module"

/obj/item/robot_module/robot/security/general/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/handcuffs/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/baton(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/taser(src))
	rel_add(src, nameof(modules), new /obj/item/taperoll/police(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/spray/pepper(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/security(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src)) // Phasegun for regular sec cyborg.
	rel_add(src, nameof(modules), new /obj/item/ticket_printer(src))
	rel_add(src, nameof(emag), new /obj/item/gun/energy/robotic/laser/rifle(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/K9(src)) //Eat criminals. Bring them to the brig.
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src)) //Pounce

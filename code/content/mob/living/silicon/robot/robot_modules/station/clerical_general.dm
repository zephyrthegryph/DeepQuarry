/obj/item/robot_module/robot/clerical/general
	name = "clerical robot module"

/obj/item/robot_module/robot/clerical/general/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/pen/robopen(src))
	rel_add(src, nameof(modules), new /obj/item/form_printer(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/paperwork(src))
	rel_add(src, nameof(modules), new /obj/item/hand_labeler(src))
	rel_add(src, nameof(modules), new /obj/item/stamp(src))
	rel_add(src, nameof(modules), new /obj/item/stamp/denied(src))
	rel_add(src, nameof(emag), new /obj/item/stamp/chameleon(src))
	rel_add(src, nameof(emag), new /obj/item/pen/chameleon(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/generic(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

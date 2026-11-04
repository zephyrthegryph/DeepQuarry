/obj/item/robot_module/robot/security/combat
	name = "combat robot module"
	hide_on_manifest = TRUE
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/security/combat/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/handcuffs/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/taperoll/police(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/laser/rifle(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/disabler(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/plasmacutter/borg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/blade/dagger(src))
	rel_add(src, nameof(modules), new /obj/item/borg/combat/shield(src))
	rel_add(src, nameof(modules), new /obj/item/borg/combat/mobility(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/borg_combat_shocker(src))
	rel_add(src, nameof(modules), new /obj/item/ticket_printer(src))
	rel_add(src, nameof(emag), new /obj/item/gun/energy/robotic/laser/heavy(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/K9/ert(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))

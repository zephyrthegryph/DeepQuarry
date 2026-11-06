/* Drones */

/obj/item/robot_module/drone
	names_assemblies = TRUE
	name = "drone module"
	hide_on_manifest = TRUE
	no_slip = 1
	networks = list(NETWORK_ENGINEERING)

/// Drones have no belly and can't be ridden.
/obj/item/robot_module/drone/on_robot_equip(mob/living/silicon/robot/robot)
	return

/obj/item/robot_module/drone/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/borg/sight/meson(src))
	rel_add(src, nameof(modules), new /obj/item/weldingtool/electric/mounted/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/crowbar/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wirecutters/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/t_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/multitool/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/drone(src))
	rel_add(src, nameof(modules), new /obj/item/soap(src))
	rel_add(src, nameof(modules), new /obj/item/extinguisher(src))
	rel_add(src, nameof(modules), new /obj/item/pipe_painter(src))
	rel_add(src, nameof(modules), new /obj/item/floor_painter(src))
	rel_add(src, nameof(modules), new /obj/item/pipe_dispenser(src))

	rel_add(src, nameof(modules), new/obj/item/tank/jetpack/carbondioxide(src))

	var/obj/item/pickaxe/plasmacutter/borg/PC = new /obj/item/pickaxe/plasmacutter/borg(src)
	rel_add(src, nameof(emag), PC)
	PC.name = "Plasma Cutter"

	var/datum/matter_synth/metal = new /datum/matter_synth/metal(25000)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(25000)
	var/datum/matter_synth/wood = new /datum/matter_synth/wood(25000)
	var/datum/matter_synth/plastic = new /datum/matter_synth/plastic(25000)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire(30)
	rel_add(src, nameof(synths), metal)
	rel_add(src, nameof(synths), glass)
	rel_add(src, nameof(synths), wood)
	rel_add(src, nameof(synths), plastic)
	rel_add(src, nameof(synths), wire)

	var/obj/item/matter_decompiler/MD = new /obj/item/matter_decompiler(src)
	rel_set(MD, nameof(MD.metal), metal)
	rel_set(MD, nameof(MD.glass), glass)
	rel_set(MD, nameof(MD.wood), wood)
	rel_set(MD, nameof(MD.plastic), plastic)
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))
	rel_add(src, nameof(modules), MD)

/obj/item/robot_module/drone/construction
	name = "construction drone module"
	hide_on_manifest = TRUE
	channels = list(CHANNEL_ENGINEERING = 1)
	languages = list()

/obj/item/robot_module/drone/construction/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/rcd/electric/mounted/borg/lesser(src))

/obj/item/robot_module/drone/respawn_consumable(mob/living/silicon/robot/R, amount)
	var/obj/item/lightreplacer/LR = locate_in_list(src.modules, /obj/item/lightreplacer)
	LR?.Charge(R, amount)
	..()
	return

/obj/item/robot_module/drone/talon
	name = "talon drone module"
	idcard_type = /obj/item/card/id/talon
	channels = list(CHANNEL_TALON = 1)
	networks = list(NETWORK_TALON_SHIP)

/obj/item/robot_module/robot/engineering
	staffing_role = DEPARTMENT_ENGINEERING
	names_assemblies = TRUE
	name = "engineering robot module"
	channels = list(CHANNEL_ENGINEERING = 1)
	networks = list(NETWORK_ENGINEERING)
	subsystems = list(/mob/living/silicon/proc/subsystem_power_monitor)
	pto_type = PTO_ENGINEERING

/obj/item/robot_module/robot/engineering/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/borg/sight/meson(src))
	rel_add(src, nameof(modules), new /obj/item/t_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/analyzer(src))
	rel_add(src, nameof(modules), new /obj/item/assembly/signaler(src)) // Anomaly handling
	rel_add(src, nameof(modules), new /obj/item/geiger(src))
	rel_add(src, nameof(modules), new /obj/item/taperoll/engineering(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/engineering(src))
	rel_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	rel_add(src, nameof(modules), new /obj/item/pipe_dispenser(src))
	rel_add(src, nameof(modules), new /obj/item/floor_painter(src))
	rel_add(src, nameof(modules), new /obj/item/rms(src))
	rel_add(src, nameof(modules), new /obj/item/inflatable_dispenser/robot(src))
	rel_add(src, nameof(emag), new /obj/item/melee/robotic/baton/arm(src))
	rel_add(src, nameof(modules), new /obj/item/rcd/electric/mounted/borg(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/plasmacutter/borg(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/stasis_clamp(src))
	rel_add(src, nameof(modules), new /obj/item/storage/pouch/eng_parts/borg(src))
	rel_add(src, nameof(modules), new /obj/item/holosign_creator/combifan(src))

	var/datum/matter_synth/metal = new /datum/matter_synth/metal(40000)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(40000)
	var/datum/matter_synth/plasteel = new /datum/matter_synth/plasteel(20000)
	var/datum/matter_synth/wood = new /datum/matter_synth/wood(40000)
	var/datum/matter_synth/plastic = new /datum/matter_synth/plastic(40000)

	var/datum/matter_synth/wire = new /datum/matter_synth/wire()
	rel_add(src, nameof(synths), metal)
	rel_add(src, nameof(synths), glass)
	rel_add(src, nameof(synths), plasteel)
	rel_add(src, nameof(synths), wood)
	rel_add(src, nameof(synths), plastic)
	rel_add(src, nameof(synths), wire)

	var/obj/item/dogborg/sleeper/compactor/decompiler/BD = new /obj/item/dogborg/sleeper/compactor/decompiler(src)
	rel_set(BD, nameof(BD.metal), metal)
	rel_set(BD, nameof(BD.glass), glass)
	rel_set(BD, nameof(BD.wood), wood)
	rel_set(BD, nameof(BD.plastic), plastic)
	rel_add(src, nameof(modules), BD)

	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

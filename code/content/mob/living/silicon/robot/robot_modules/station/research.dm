/obj/item/robot_module/robot/research
	staffing_role = DEPARTMENT_RESEARCH
	name = "research module"
	channels = list(CHANNEL_SCIENCE = 1)
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/advrped, /obj/item/borg/upgrade/restricted/anomalygun)
	pto_type = PTO_SCIENCE

/obj/item/robot_module/robot/research/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/experi_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/robotanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/card/robot(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/research(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/botanical(src))
	rel_add(src, nameof(modules), new /obj/item/surgical/hemostat/cyborg(src)) //Synth repair
	rel_add(src, nameof(modules), new /obj/item/surgical/surgicaldrill/cyborg(src)) //NIF repair
	rel_add(src, nameof(modules), new /obj/item/surgical/circular_saw/cyborg(src)) // Synth limb replacement
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/beaker/large/borg(src))
	rel_add(src, nameof(modules), new /obj/item/storage/part_replacer(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot/jumper(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/baton/slime(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/taser/xeno(src))
	rel_add(src, nameof(modules), new /obj/item/xenoarch_multi_tool(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/excavationdrill(src))
	// Anomaly handling
	rel_add(src, nameof(modules), new /obj/item/analyzer(src))
	rel_add(src, nameof(modules), new /obj/item/assembly/signaler(src))
	rel_add(src, nameof(modules), new /obj/item/anomaly_scanner(src))

	rel_add(src, nameof(emag), new /obj/item/hand_tele(src))

	var/datum/matter_synth/nanite = new /datum/matter_synth/nanite(10000)
	rel_add(src, nameof(synths), nanite)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire()						//Added to allow repairs, would rather add cable now than be asked to add it later,
	rel_add(src, nameof(synths), wire) //Cable code, taken from engiborg,

	var/obj/item/stack/nanopaste/N = new /obj/item/stack/nanopaste(src)
	N.set_uses_charge(1)
	N.set_charge_costs(list(1000))
	N.add_synth(nanite)
	rel_add(src, nameof(modules), N)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/analyzer(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/research/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.set_mode(initial(S.mode))
		S.desc = initial(S.desc)

	..()

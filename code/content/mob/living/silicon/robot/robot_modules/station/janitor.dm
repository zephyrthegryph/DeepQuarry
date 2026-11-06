/obj/item/robot_module/robot/janitor
	staffing_role = JOB_JANITOR
	eats_trash = TRUE
	name = "janitorial robot module"
	channels = list(CHANNEL_SERVICE = 1)
	pto_type = PTO_CIVILIAN

/obj/item/robot_module/robot/janitor/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/soap/nanotrasen(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/trash(src))
	rel_add(src, nameof(modules), new /obj/item/mop(src))
	rel_add(src, nameof(modules), new /obj/item/pupscrubber(src))
	rel_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	rel_add(src, nameof(modules), new /obj/item/vac_attachment(src))
	rel_add(src, nameof(modules), new /obj/item/borg/sight/janitor(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/bucket/cyborg(src))
	var/obj/item/reagent_containers/spray/LS = new /obj/item/reagent_containers/spray(src)
	rel_add(src, nameof(emag), LS)
	LS.reagents.add_reagent(REAGENT_ID_LUBE, 250)
	LS.name = "Lube spray"

	//Starts empty. Can only recharge with recycled material.
	var/datum/matter_synth/metal = new /datum/matter_synth/metal()
	metal.name = "Steel reserves"
	metal.recharge_rate = 0
	metal.set_max_energy(50000)
	metal.set_energy(0)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass()
	glass.name = "Glass reserves"
	glass.recharge_rate = 0
	glass.set_max_energy(50000)
	glass.set_energy(0)

	rel_add(src, nameof(synths), metal)
	rel_add(src, nameof(synths), glass)

	//Sheet refiners can only produce raw sheets.
	var/obj/item/stack/material/cyborg/steel/M = new (src)
	M.name = "steel recycler"
	M.desc = "A device that refines recycled steel into sheets."
	M.add_synth(metal)
	// Shared recipe tables, like material.get_recipes(): never owned by one stack.
	M.set_recipes(stack_own_recipes(STACK_RECIPES_STEEL_RECYCLER))
	rel_add(src, nameof(modules), M)

	var/obj/item/stack/material/cyborg/glass/G = new (src)
	G.name = "glass recycler"
	G.desc = "A device that refines recycled glass into sheets."
	G.set_material(get_material_by_name("placeholder")) //Hacky shit but we want sheets, not windows.
	G.add_synth(glass)
	G.set_recipes(stack_own_recipes(STACK_RECIPES_GLASS_RECYCLER))
	rel_add(src, nameof(modules), G)

	var/obj/item/dogborg/sleeper/compactor/C = new /obj/item/dogborg/sleeper/compactor(src)
	rel_set(C, nameof(C.metal), metal)
	rel_set(C, nameof(C.glass), glass)
	rel_add(src, nameof(modules), C)

	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/janitor/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/lightreplacer/LR = locate_in_list(src.modules, /obj/item/lightreplacer)
	LR?.Charge(R, amount)

	var/obj/item/reagent_containers/spray/LS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(LS)
		LS.reagents.add_reagent(REAGENT_ID_LUBE, 2 * amount)

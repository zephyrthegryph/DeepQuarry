/obj/item/robot_module/robot/medical/crisis
	name = "crisis robot module"

/obj/item/robot_module/robot/medical/crisis/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/sleevemate(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_scanner/adv(src))
	rel_add(src, nameof(modules), new /obj/item/roller_holder(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/crisis(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/beaker/large/borg(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper/industrial(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/medical(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot(src))
	//Surgeon Modules below
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	//Surgeon Modules End
	rel_add(src, nameof(modules), new /obj/item/inflatable_dispenser/robot(src))
	rel_add(src, nameof(modules), new /obj/item/holosign_creator/medical(src))
	var/obj/item/reagent_containers/spray/PS = new /obj/item/reagent_containers/spray(src)
	rel_add(src, nameof(emag), PS)
	PS.reagents.add_reagent(REAGENT_ID_PACID, 250)
	PS.name = "Polyacid spray"

	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(30000)
	rel_add(src, nameof(synths), medicine)

	var/obj/item/stack/medical/advanced/clotting/C = new (src)
	var/obj/item/stack/medical/advanced/ointment/O = new /obj/item/stack/medical/advanced/ointment(src)
	var/obj/item/stack/medical/advanced/bruise_pack/B = new /obj/item/stack/medical/advanced/bruise_pack(src)
	var/obj/item/stack/medical/splint/S = new /obj/item/stack/medical/splint(src)
	C.set_uses_charge(1)
	C.set_charge_costs(list(5000))
	C.add_synth(medicine)
	O.set_uses_charge(1)
	O.set_charge_costs(list(1000))
	O.add_synth(medicine)
	B.set_uses_charge(1)
	B.set_charge_costs(list(1000))
	B.add_synth(medicine)
	S.set_uses_charge(1)
	S.set_charge_costs(list(1000))
	S.add_synth(medicine)
	rel_add(src, nameof(modules), O)
	rel_add(src, nameof(modules), B)
	rel_add(src, nameof(modules), S)
	rel_add(src, nameof(modules), C)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/medical/crisis/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.set_mode(initial(S.mode))
		S.desc = initial(S.desc)

	var/obj/item/reagent_containers/spray/PS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(PS)
		PS.reagents.add_reagent(REAGENT_ID_PACID, 2 * amount)

	..()

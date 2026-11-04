//This is a constant back and forth debate. 11 years ago, the 'medical' borg was split into surgery and crisis.
//Two years ago(?), they were combined into Crisis elsewhere and the idea seems to be well appreciated.
//However, given this seems as though it will remain a hot topic for as long as SS13 exists, we are going to leave the surgeon module here in the event that we split them. Again.
//This also goes for the sprite datums. It's be a lot of work to 'clear' them of having surgery in their path just to have to split them again in 2-3 years.
/obj/item/robot_module/robot/medical/surgeon
	name = "surgeon robot module"

/obj/item/robot_module/robot/medical/surgeon/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/sleevemate(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/surgeon(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/medical(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper(src)) // Allows surgeon borg to fix necrosis
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))

	var/obj/item/reagent_containers/spray/PS = new /obj/item/reagent_containers/spray(src)

	rel_add(src, nameof(emag), PS)
	PS.reagents.add_reagent(REAGENT_ID_PACID, 250)
	PS.name = "Polyacid spray"

	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(10000)
	rel_add(src, nameof(synths), medicine)

	var/obj/item/stack/nanopaste/N = new /obj/item/stack/nanopaste(src)
	var/obj/item/stack/medical/advanced/bruise_pack/B = new /obj/item/stack/medical/advanced/bruise_pack(src)
	var/obj/item/stack/medical/advanced/ointment/O = new /obj/item/stack/medical/advanced/ointment(src) // edit: we have burn surgeries so they should be able to do them
	N.set_uses_charge(1)
	N.set_charge_costs(list(1000))
	N.add_synth(medicine)
	B.set_uses_charge(1)
	B.set_charge_costs(list(1000))
	B.add_synth(medicine)
	O.set_uses_charge(1)
	O.set_charge_costs(list(1000))
	O.add_synth(medicine)
	rel_add(src, nameof(modules), N)
	rel_add(src, nameof(modules), B)
	rel_add(src, nameof(modules), O)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/trauma(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/medical/surgeon/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.set_mode(initial(S.mode))
		S.desc = initial(S.desc)

	var/obj/item/reagent_containers/spray/PS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(PS)
		PS.reagents.add_reagent(REAGENT_ID_PACID, 2 * amount)

	..()

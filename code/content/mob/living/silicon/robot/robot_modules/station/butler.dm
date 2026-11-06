/obj/item/robot_module/robot/clerical/butler
	staffing_role = JOB_BOTANIST
	channels = list(CHANNEL_SERVICE = 1)

/obj/item/robot_module/robot/clerical/butler
	name = "service robot module"

/obj/item/robot_module/robot/clerical/butler/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/gripper/service(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/service(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/serviceborg(src))

	var/obj/item/rsf/M = new /obj/item/rsf(src)
	M.stored_matter = 30
	rel_add(src, nameof(modules), M)

	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper/industrial(src))

	var/obj/item/flame/lighter/zippo/L = new /obj/item/flame/lighter/zippo(src) // starts unlit: lit, it would burn on the slow lane from module creation
	rel_add(src, nameof(modules), L)

	rel_add(src, nameof(modules), new /obj/item/tray/robotray(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/service(src))
	var/obj/item/reagent_containers/food/drinks/bottle/small/beer/PB = new /obj/item/reagent_containers/food/drinks/bottle/small/beer(src)
	rel_add(src, nameof(emag), PB)

	var/datum/reagents/R = new/datum/reagents(50)
	rel_set(PB, nameof(PB.reagents), R)
	rel_set(R, nameof(R.my_atom), PB)
	R.add_reagent(REAGENT_ID_BEER2, 50)
	PB.name = "Auntie Hong's Final Sip"
	PB.desc = "A bottle of very special mix of alcohol and poison. Some may argue that there's alcohol to die for, but Auntie Hong took it to next level."

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/brewer(src))

	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/clerical/butler/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/reagent_containers/food/drinks/bottle/small/beer/PB = locate_in_list(src.emag, /obj/item/reagent_containers/food/drinks/bottle/small/beer)
	if(PB)
		PB.reagents.add_reagent(REAGENT_ID_BEER2, 2 * amount)

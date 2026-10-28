/// Every type that answers a generic hit itself (it used to override attack_generic()) takes the hit over through the hit/generic action:
/// generic_hit() reports FALSE, the attacker is untouched, and nothing runtimes.
/datum/unit_test/dq_generic_hit_takeover/Run()
	var/static/list/taken_types = list(
		/obj/structure/grille, /obj/structure/window/basic, /obj/structure/girder, /obj/structure/mirror, /obj/structure/low_wall,
		/obj/structure/table/steel, /obj/structure/closet, /obj/structure/alien/wall, /obj/vehicle/bike,
		/obj/item/reagent_containers/food/snacks/aesirsalad, /obj/machinery/portable_atmospherics/hydroponics)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	for(var/type in taken_types)
		var/atom/target = allocate(type, run_loc_floor_bottom_left)
		TEST_ASSERT(!QDELETED(target), "[type] survives its initialization")
		TEST_ASSERT(!generic_hit(target, user, 0, "bites"), "[type] takes a zero-damage generic hit over")
		TEST_ASSERT(!generic_hit(target, user, 3, "bites"), "[type] takes a light generic hit over")
		TEST_ASSERT(!QDELETED(user), "[type] leaves its attacker alone")

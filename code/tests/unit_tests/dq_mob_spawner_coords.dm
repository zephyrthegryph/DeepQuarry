/// The GM mob spawner puts the mob at the coordinates typed in the window, not where the admin stands.
/datum/unit_test/dq_mob_spawner_typed_coordinates/Run()
	var/datum/eventkit/mob_spawner/spawner = allocate(/datum/eventkit/mob_spawner)
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/turf/target = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y + 1, run_loc_floor_bottom_left.z)
	spawner.apply_spawner_setting("select_path", /mob/living/simple_mob/animal/passive/mouse)
	var/before = length(target.contents)
	spawner.apply_spawn_choice(admin, 1, "", "", null, null, null, null, "typed mouse", 1, target.x, target.y, target.z)
	var/mob/living/simple_mob/animal/passive/mouse/made = locate() in target
	TEST_ASSERT_NOTNULL(made, "the mob is made on the typed turf")
	TEST_ASSERT(length(target.contents) > before, "the typed turf gained the mob")
	TEST_ASSERT_NULL(locate(/mob/living/simple_mob/animal/passive/mouse) in run_loc_floor_bottom_left, "nothing is made where the admin stands")
	qdel(made)
	TEST_ASSERT(!spawner.apply_spawn_choice(admin, 1, "", "", null, null, null, null, "typed mouse", 1, "abc", target.y, target.z), "text coordinates are refused")

/// A mob spawner's step waits for its spawn cooldown instead of waking every 2 s for nothing (spawn_wait()).
/datum/unit_test/dq_mob_spawner_waits_for_its_cooldown

/datum/unit_test/dq_mob_spawner_waits_for_its_cooldown/Run()
	var/obj/structure/mob_spawner/mouse_nest/mousehole/nest = allocate(/obj/structure/mob_spawner/mouse_nest/mousehole, run_loc_floor_bottom_left)
	COOLDOWN_START(nest, spawn_cooldown, 5 MINUTES)
	TEST_ASSERT(nest.spawn_wait(null) >= 5 MINUTES - 1 SECONDS, "a nest on cooldown wakes before the cooldown ends ([nest.spawn_wait(null)] ds)")
	COOLDOWN_RESET(nest, spawn_cooldown)
	TEST_ASSERT_EQUAL(nest.spawn_wait(null), 2 SECONDS, "a nest that may spawn now does not look again soon")
	nest.simultaneous_spawns = 0
	TEST_ASSERT_EQUAL(nest.spawn_wait(null), 1 MINUTES, "a full nest polls faster than once a minute")

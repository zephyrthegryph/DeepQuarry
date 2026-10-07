// Change-channel wake tests: machines sleeping on watched channels and the AI brain's
// chunk hibernation. Held steady, each must stay asleep; after its input changes, it must
// wake. Each also checks sleep_violation() while asleep.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_om_keys_wake_turret

/datum/unit_test/dq_om_keys_wake_turret/Run()
	var/turf/T = locate(1, 1, 1)
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, T)
	dq_machine_clear(turret)
	turret.set_enabled(FALSE)
	TEST_ASSERT(!turret.armed, "a switched-off turret is not armed (its scan parks)")
	turret.set_enabled(TRUE)
	TEST_ASSERT(turret.armed, "switching it on arms it again (its scan wakes)")

/datum/unit_test/dq_om_keys_wake_calm_brain

/datum/unit_test/dq_om_keys_wake_calm_brain/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, T)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "simple mob did not receive an AI brain")
	rel_clear(B, nameof(B.primary_threat))
	B.active_behavior_type = null
	var/mob/living/visitor = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	TEST_ASSERT(B.hibernate_calm(), "calm brain refused to hibernate")
	TEST_ASSERT_NULL(B.sleep_violation(), "a calm hibernating brain reported a violation")
	var/failure = om_wake_test(B, om_callable(visitor, TYPE_PROC_REF(/atom/movable, forceMove), T))
	TEST_ASSERT(!failure, failure)
	TEST_ASSERT(B.loop_running(DQAI_PROCESSING), "woken brain did not rejoin strategic processing")
	// The audit catches a brain asleep with a threat.
	B.hibernate_calm()
	rel_set(B, nameof(B.primary_threat), visitor)
	TEST_ASSERT(B.sleep_violation(), "the audit missed a hibernating brain with a threat")
	rel_clear(B, nameof(B.primary_threat))

/// One mob chunk key, two mask bits: a mob without a client wakes any-mob subscribers only.
/datum/unit_test/dq_om_keys_mob_chunk_masks

/datum/unit_test/dq_om_keys_mob_chunk_masks/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/players = allocate(/datum/om_wake_test_subscriber)
	var/datum/anyone = allocate(/datum/om_wake_test_subscriber)
	om_attach(players, /datum/om/behaviour/sleeper/test_subscriber)
	om_attach(anyone, /datum/om/behaviour/sleeper/test_subscriber)
	var/list/player_tokens = watch_mob_chunks(players, mob_chunks_around(T, 0), CHANGE_CHUNK_PLAYER, /datum/om/behaviour/sleeper/test_subscriber)
	var/list/any_tokens = watch_mob_chunks(anyone, list(mob_chunk(mob_chunk_id(T))), CHANGE_CHUNK_ANY_MOB, /datum/om/behaviour/sleeper/test_subscriber)
	var/mob/living/npc = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	om_trace(players)
	om_trace(anyone)
	om_test_ticks(4)
	npc.forceMove(T)
	TEST_ASSERT(om_wait_for_wake(anyone), "a mob moving into the chunk did not wake an any-mob subscriber")
	TEST_ASSERT(!om_traced_count(players), "a mob without a client woke a player-chunk subscriber")
	om_untrace(players)
	om_untrace(anyone)
	unwatch_mob_chunks(players, player_tokens, CHANGE_CHUNK_PLAYER, /datum/om/behaviour/sleeper/test_subscriber)
	unwatch_mob_chunks(anyone, any_tokens, CHANGE_CHUNK_ANY_MOB, /datum/om/behaviour/sleeper/test_subscriber)

#endif


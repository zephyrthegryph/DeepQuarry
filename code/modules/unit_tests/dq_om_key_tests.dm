// Change-channel wake tests: machines sleeping on watched channels and the AI brain's
// chunk hibernation. Held steady, each must stay asleep; after its input changes, it must
// wake. Each also checks om_sleep_violation() while asleep.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_om_keys_wake_power_monitor

/datum/unit_test/dq_om_keys_wake_power_monitor/Run()
	var/turf/T = test_floor()
	var/datum/powernet/P = new
	var/obj/machinery/power/sensor/S = allocate(/obj/machinery/power/sensor, T)
	var/obj/machinery/computer/power_monitor/M = allocate(/obj/machinery/computer/power_monitor, T)
	S.powernet = P
	M.power_monitor.grid_sensors = list(S)
	MACHINE_WAKE(M)
	M.machine_step()
	TEST_ASSERT(M.asleep_on_keys(), "stable power monitor did not sleep on its grid keys")
	TEST_ASSERT_NULL(M.om_sleep_violation(), "a stable sleeping power monitor reported a violation")
	var/failure = om_wake_test(M, CALLBACK(P, TYPE_PROC_REF(/datum/powernet, trigger_warning)))
	TEST_ASSERT(!failure, failure)
	qdel(P)

/datum/unit_test/dq_om_keys_wake_shield_capacitor

/datum/unit_test/dq_om_keys_wake_shield_capacitor/Run()
	var/datum/powernet/P = new
	var/obj/machinery/shield_capacitor/C = allocate(/obj/machinery/shield_capacitor, test_floor())
	// The keys process() sleeps on when the grid gives it nothing.
	TEST_ASSERT(C.sleep_until_keys(list(P, CHANGE_POWERNET_RATE|CHANGE_POWERNET_STATE)), "capacitor refused to sleep")
	var/failure = om_wake_test(C, CALLBACK(P, TYPE_PROC_REF(/datum/powernet, test_set_brownout), TRUE))
	TEST_ASSERT(!failure, failure)
	// A topology-only change is not the capacitor's input.
	C.sleep_until_keys(list(P, CHANGE_POWERNET_RATE|CHANGE_POWERNET_STATE))
	// Let the brownout wake above finish landing before the window opens.
	om_settle(C)
	om_trace(C)
	om_changed(P, CHANGE_POWERNET_TOPOLOGY)
	om_test_ticks(4)
	// Only a watch wake (CHANGE_RELATED) can come from P. The capacitor has other real inputs
	// (its area's power, a machine timer) that a full-suite world can move inside the window:
	// those are not what this asserts, so they are reported but not counted.
	var/stray = om_traced_wake_bits(C)
	TEST_ASSERT(!(stray & CHANGE_RELATED), "a topology change woke a rate subscriber (wake bits [stray], [om_traced_count(C)] wake(s))")
	if(om_traced_count(C))
		log_test("dq_om_keys_wake_shield_capacitor: unrelated wake(s) in the window, bits [stray]")
	om_untrace(C)
	qdel(P)

/datum/unit_test/dq_om_keys_wake_turret

/datum/unit_test/dq_om_keys_wake_turret/Run()
	var/turf/T = locate(1, 1, 1)
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, T)
	turret.stat = 0
	turret.enabled = FALSE
	turret.machine_step()
	TEST_ASSERT(turret.asleep_on_keys(), "disabled turret did not sleep on its settings key")
	TEST_ASSERT_NULL(turret.om_sleep_violation(), "a disabled sleeping turret reported a violation")
	var/failure = om_wake_test(turret, CALLBACK(turret, TYPE_PROC_REF(/obj/machinery/porta_turret, emp_reenable)))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_om_keys_wake_point_defense

/datum/unit_test/dq_om_keys_wake_point_defense/Run()
	var/obj/machinery/pointdefense/PD = allocate(/obj/machinery/pointdefense, test_floor())
	PD.stat = 0
	PD.active = TRUE
	if(LAZYLEN(REGISTRY_MEMBERS(REGISTRY_METEORS)))
		return
	PD.machine_step()
	TEST_ASSERT(PD.asleep_on_keys(), "idle point defense did not sleep on the meteor key")
	TEST_ASSERT_NULL(PD.om_sleep_violation(), "an idle point defense reported a violation")
	// The meteor key is what /obj/effect/meteor publishes on Initialize and Destroy.
	var/failure = om_wake_test(PD, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(om_changed), GLOB.meteor_watch, CHANGE_METEORS))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_om_keys_wake_disposal

/datum/unit_test/dq_om_keys_wake_disposal/Run()
	var/obj/machinery/disposal/D = allocate(/obj/machinery/disposal, test_floor())
	if(!D.air_contents)
		return
	D.stat = 0
	D.flush = 0
	D.mode = 2 // DISPOSALMODE_CHARGED, which disposal_machines.dm #undefs
	for(var/atom/movable/AM as anything in D.contents)
		qdel(AM)
	D.machine_step()
	TEST_ASSERT(D.asleep_on_keys(), "idle disposal did not sleep on its key")
	TEST_ASSERT_NULL(D.om_sleep_violation(), "an idle disposal reported a violation")
	var/failure = om_wake_test(D, CALLBACK(D, TYPE_PROC_REF(/obj/machinery/disposal, wake_for_state_change)))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_om_keys_wake_calm_brain

/datum/unit_test/dq_om_keys_wake_calm_brain/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, T)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "simple mob did not receive an AI brain")
	B.primary_threat = null
	B.active_behavior_type = null
	var/mob/living/visitor = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	TEST_ASSERT(B.hibernate_calm(), "calm brain refused to hibernate")
	TEST_ASSERT_NULL(B.om_sleep_violation(), "a calm hibernating brain reported a violation")
	var/failure = om_wake_test(B, CALLBACK(visitor, TYPE_PROC_REF(/atom/movable, forceMove), T))
	TEST_ASSERT(!failure, failure)
	TEST_ASSERT(B.loop_running(DQAI_PROCESSING), "woken brain did not rejoin strategic processing")
	// The audit catches a brain asleep with a threat.
	B.hibernate_calm()
	B.primary_threat = visitor
	TEST_ASSERT(B.om_sleep_violation(), "the audit missed a hibernating brain with a threat")
	B.primary_threat = null

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

/// A brownout as refresh() reports one from Rust, without a Rust region.
/datum/powernet/proc/test_set_brownout(value)
	brownout = value
	om_changed(src, CHANGE_POWERNET_STATE)

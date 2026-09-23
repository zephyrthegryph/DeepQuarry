// S2 wake tests (doc/rewrite/reactor.md §7): every subscriber type moved off SSmachines'
// reactive keys and SSai's chunk hibernation. Held steady, each must stay asleep; after its
// input changes, it must wake. Each also checks react_sleep_violation() while asleep.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_s2_wake_power_monitor

/datum/unit_test/dq_s2_wake_power_monitor/Run()
	var/turf/T = test_floor()
	var/datum/powernet/P = new
	var/obj/machinery/power/sensor/S = allocate(/obj/machinery/power/sensor, T)
	var/obj/machinery/computer/power_monitor/M = allocate(/obj/machinery/computer/power_monitor, T)
	S.powernet = P
	M.power_monitor.grid_sensors = list(S)
	START_MACHINE_PROCESSING(M)
	M.process()
	TEST_ASSERT(M.asleep_on_keys(), "stable power monitor did not sleep on its grid keys")
	TEST_ASSERT_NULL(M.react_sleep_violation(), "a stable sleeping power monitor reported a violation")
	var/failure = react_wake_test(M, CALLBACK(P, TYPE_PROC_REF(/datum/powernet, trigger_warning)))
	TEST_ASSERT(!failure, failure)
	qdel(P)

/datum/unit_test/dq_s2_wake_shield_capacitor

/datum/unit_test/dq_s2_wake_shield_capacitor/Run()
	var/datum/powernet/P = new
	var/obj/machinery/shield_capacitor/C = allocate(/obj/machinery/shield_capacitor, test_floor())
	// The keys process() sleeps on when the grid gives it nothing.
	TEST_ASSERT(C.sleep_until_keys(list(REACT_KEY_POWERNET, REACT_ID(P), REACT_POWERNET_RATE|REACT_POWERNET_STATE)), "capacitor refused to sleep")
	var/failure = react_wake_test(C, CALLBACK(P, TYPE_PROC_REF(/datum/powernet, publish_monitor_dependency)))
	TEST_ASSERT(!failure, failure)
	// A topology-only change is not the capacitor's input.
	C.sleep_until_keys(list(REACT_KEY_POWERNET, REACT_ID(P), REACT_POWERNET_RATE|REACT_POWERNET_STATE))
	SSreactor.trace(C)
	REACT_PUBLISH(REACT_KEY_POWERNET, REACT_ID(P), REACT_POWERNET_TOPOLOGY)
	react_test_ticks(4)
	TEST_ASSERT(!SSreactor.traced_wakes(C), "a topology change woke a rate subscriber")
	SSreactor.untrace(C)
	qdel(P)

/datum/unit_test/dq_s2_wake_apc

/datum/unit_test/dq_s2_wake_apc/Run()
	var/obj/machinery/power/apc/A
	for(var/obj/machinery/power/apc/candidate as anything in GLOB.apcs)
		if(candidate.terminal?.powernet && candidate.cell)
			A = candidate
			break
	if(!A)
		return
	A.cell.charge = A.cell.maxcharge
	A.charging = 0
	A.power_distributor.charging = 0
	START_MACHINE_PROCESSING(A)
	for(var/i in 1 to 5)
		A.process()
		if(A.asleep_on_keys())
			break
	TEST_ASSERT(A.asleep_on_keys(), "stable APC did not sleep on its keys")
	TEST_ASSERT_NULL(A.react_sleep_violation(), "a stable sleeping APC reported a violation")
	var/datum/powernet/PN = A.terminal.powernet
	var/failure = react_wake_test(A, CALLBACK(PN, TYPE_PROC_REF(/datum/powernet, publish_dependency)))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_s2_wake_turret

/datum/unit_test/dq_s2_wake_turret/Run()
	var/turf/T = locate(1, 1, 1)
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, T)
	turret.stat = 0
	turret.enabled = FALSE
	turret.process()
	TEST_ASSERT(turret.asleep_on_keys(), "disabled turret did not sleep on its settings key")
	TEST_ASSERT_NULL(turret.react_sleep_violation(), "a disabled sleeping turret reported a violation")
	var/failure = react_wake_test(turret, CALLBACK(turret, TYPE_PROC_REF(/obj/machinery/porta_turret, emp_reenable)))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_s2_wake_point_defense

/datum/unit_test/dq_s2_wake_point_defense/Run()
	var/obj/machinery/pointdefense/PD = allocate(/obj/machinery/pointdefense, test_floor())
	PD.stat = 0
	PD.active = TRUE
	if(LAZYLEN(GLOB.meteor_list))
		return
	PD.process()
	TEST_ASSERT(PD.asleep_on_keys(), "idle point defense did not sleep on the meteor key")
	TEST_ASSERT_NULL(PD.react_sleep_violation(), "an idle point defense reported a violation")
	// The meteor key is what /obj/effect/meteor publishes on Initialize and Destroy.
	var/failure = react_wake_test(PD, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(vg_react_publish), REACT_KEY_METEORS, 1, REACT_KEY_CHANGED))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_s2_wake_disposal

/datum/unit_test/dq_s2_wake_disposal/Run()
	var/obj/machinery/disposal/D = allocate(/obj/machinery/disposal, test_floor())
	if(!D.air_contents)
		return
	D.stat = 0
	D.flush = 0
	D.mode = 2 // DISPOSALMODE_CHARGED, which disposal_machines.dm #undefs
	for(var/atom/movable/AM as anything in D.contents)
		qdel(AM)
	D.process()
	TEST_ASSERT(D.asleep_on_keys(), "idle disposal did not sleep on its key")
	TEST_ASSERT_NULL(D.react_sleep_violation(), "an idle disposal reported a violation")
	var/failure = react_wake_test(D, CALLBACK(D, TYPE_PROC_REF(/obj/machinery/disposal, wake_for_state_change)))
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_s2_wake_calm_brain

/datum/unit_test/dq_s2_wake_calm_brain/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, T)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "simple mob did not receive an AI brain")
	B.primary_threat = null
	B.active_behavior_type = null
	var/mob/living/visitor = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	TEST_ASSERT(B.hibernate_calm(), "calm brain refused to hibernate")
	TEST_ASSERT_NULL(B.react_sleep_violation(), "a calm hibernating brain reported a violation")
	var/failure = react_wake_test(B, CALLBACK(visitor, TYPE_PROC_REF(/atom/movable, forceMove), T))
	TEST_ASSERT(!failure, failure)
	TEST_ASSERT(B in SSai.processing, "woken brain did not rejoin strategic processing")
	// The audit catches a brain asleep with a threat.
	B.hibernate_calm()
	B.primary_threat = visitor
	TEST_ASSERT(B.react_sleep_violation(), "the audit missed a hibernating brain with a threat")
	B.primary_threat = null

/// One mob chunk key, two mask bits: a mob without a client wakes any-mob subscribers only.
/datum/unit_test/dq_s2_mob_chunk_masks

/datum/unit_test/dq_s2_mob_chunk_masks/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/players = allocate(/datum/react_test_subscriber)
	var/datum/anyone = allocate(/datum/react_test_subscriber)
	var/list/player_tokens = SSreactor.subscribe_player_chunks(players, T, 0)
	var/list/any_tokens = SSreactor.sleep_on_keys(anyone, list(REACT_KEY_MOB_CHUNK, SSreactor.mob_chunk_id(T), REACT_CHUNK_ANY_MOB))
	var/mob/living/npc = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	SSreactor.trace(players)
	SSreactor.trace(anyone)
	react_test_ticks(4)
	npc.forceMove(T)
	react_test_ticks(4)
	TEST_ASSERT(SSreactor.traced_wakes(anyone), "a mob moving into the chunk did not wake an any-mob subscriber")
	TEST_ASSERT(!SSreactor.traced_wakes(players), "a mob without a client woke a player-chunk subscriber")
	SSreactor.untrace(players)
	SSreactor.untrace(anyone)
	SSreactor.unsubscribe_player_chunks(players, player_tokens)
	SSreactor.cancel_keys(anyone, any_tokens)

#endif

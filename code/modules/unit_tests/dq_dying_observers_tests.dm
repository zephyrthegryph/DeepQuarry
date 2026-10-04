// Notices from an entity that is being deleted (its qdeleting notice, and what it spills while it goes) reach the observers that are still
// alive. Each observer below hears its source die: none may runtime, touch the deleted holder in a way that raises, or keep a reference to it.

/// Runtimes (world/Error calls) since `before`.
/proc/dq_dying_runtimes_since(before)
	return GLOB.total_runtimes - before

/datum/unit_test/dq_dying_observers_cogbar_and_progressbar

/datum/unit_test/dq_dying_observers_cogbar_and_progressbar/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/pen/target = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	var/before = GLOB.total_runtimes
	var/datum/cogbar/bar = new(H, 'icons/effects/effects.dmi', "cog")
	var/datum/progressbar/progress = new(H, 10, target)
	TEST_ASSERT(!QDELETED(bar) && !QDELETED(progress), "both bars exist while the user lives")
	qdel(H)
	TEST_ASSERT(QDELETED(bar), "the cogbar goes with its user")
	TEST_ASSERT(QDELETED(progress), "the progress bar goes with its user")
	TEST_ASSERT_NULL(bar.user(), "the cogbar kept no reference to the dead user")
	TEST_ASSERT_NULL(progress.user(), "nor did the progress bar")
	TEST_ASSERT_EQUAL(dq_dying_runtimes_since(before), 0, "no runtime while the user was torn down")

/datum/unit_test/dq_dying_observers_range_and_proximity

/datum/unit_test/dq_dying_observers_range_and_proximity/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/obj/dq_hook_hand_receiver/range_host = allocate(/obj/dq_hook_hand_receiver, start)
	var/obj/dq_hook_hand_receiver/prox_host = allocate(/obj/dq_hook_hand_receiver, start)
	var/datum/dq_range_probe/probe = new
	var/before = GLOB.total_runtimes
	var/watching_before = GLOB.range_watch_count
	var/datum/connect_range/watcher = new(probe, range_host, list(RANGE_ENTERED = TYPE_PROC_REF(/datum/dq_range_probe, on_enter)), 3)
	var/datum/proximity_monitor/monitor = new(prox_host, 1)
	qdel(range_host)
	TEST_ASSERT(QDELETED(watcher), "the range watcher goes with what it tracks")
	qdel(prox_host)
	TEST_ASSERT_NULL(monitor.host(), "the proximity monitor let go of its dead host")
	qdel(monitor)
	TEST_ASSERT_EQUAL(GLOB.range_watch_count, watching_before, "both left the grid")
	qdel(probe)
	TEST_ASSERT_EQUAL(dq_dying_runtimes_since(before), 0, "no runtime while the tracked atoms were torn down")

/datum/unit_test/dq_dying_observers_overlay_lighting

/datum/unit_test/dq_dying_observers_overlay_lighting/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/carrier = allocate(/mob/living/carbon/human, start)
	var/obj/item/pen/lamp = allocate(/obj/item/pen, start)
	lamp.set_light(4, 1, "#ffffff", TRUE)
	var/before = GLOB.total_runtimes
	lamp.forceMove(carrier) // the carrier is now the lamp's holder
	qdel(carrier)
	var/datum/overlay_lighting/light = lamp.overlay_light
	if(!QDELETED(lamp) && light)
		TEST_ASSERT_NULL(light.current_holder(), "the light let go of its dead holder")
		TEST_ASSERT_NULL(light.parent_attached_to(), "and of the dead atom it was attached to")
	// Then the lamp itself dies with the light on.
	if(!QDELETED(lamp))
		lamp.forceMove(start)
	qdel(lamp)
	TEST_ASSERT_EQUAL(dq_dying_runtimes_since(before), 0, "no runtime while the holder and the parent were torn down")

/datum/unit_test/dq_dying_observers_mind_host

/datum/unit_test/dq_dying_observers_mind_host/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = dq_test_remove_brain(H)
	var/obj/item/mmi/mmi = allocate(/obj/item/mmi)
	mmi.insert_brain(brain, "unit test")
	var/datum/mind_host/host = get_mind_host(mmi)
	var/before = GLOB.total_runtimes
	qdel(brain)
	TEST_ASSERT_NULL(host.tissue, "the host let go of the brain that was deleted")
	TEST_ASSERT_EQUAL(dq_dying_runtimes_since(before), 0, "no runtime while the brain was torn down")

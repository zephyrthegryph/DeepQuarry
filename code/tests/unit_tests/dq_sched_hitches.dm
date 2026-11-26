/// A shape that arrives is told to its viewers a few at a time: with no budget one viewer is told per call, and the rest stay queued, in order, until each is told once.
/datum/unit_test/dq_client_glow_arrival_fanout_is_stepped

/datum/unit_test/dq_client_glow_arrival_fanout_is_stepped/Run()
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	set_var(B, nameof(B.arrivals), list())
	var/key = "32|0,0,9,9|"
	var/list/holders = list()
	for(var/i in 1 to 4)
		var/datum/client_glow_holder/H = new
		LAZYSET(H.held, "h[i]", list(image(null), image(null)))
		LAZYSET(H.held_shape, "h[i]", key)
		holders += H
	B.arrivals += list(list(key, 'icons/effects/light_overlays/light_32.dmi', holders.Copy()))
	var/steps_before = B.arrival_steps
	for(var/told in 1 to 4)
		TEST_ASSERT_EQUAL(client_glow_arrivals_run(-1), 1, "a call with no budget tells exactly one viewer")
		var/datum/client_glow_holder/H = holders[told]
		TEST_ASSERT_EQUAL(LAZYACCESS(H.cut_shape, "h[told]"), key, "the viewers are told in order: viewer [told] shows the shape")
		if(told < 4)
			var/datum/client_glow_holder/next = holders[told + 1]
			TEST_ASSERT_NULL(LAZYACCESS(next.cut_shape, "h[told + 1]"), "and the next one waits")
			TEST_ASSERT_EQUAL(length(B.arrivals), 1, "the shape stays queued while viewers wait")
	TEST_ASSERT_EQUAL(length(B.arrivals), 0, "told to all four, the shape leaves the queue")
	TEST_ASSERT_EQUAL(B.arrival_steps, steps_before + 4, "four calls, four steps counted")
	TEST_ASSERT_EQUAL(client_glow_arrivals_run(-1), 0, "nothing queued, nothing told")
	for(var/datum/client_glow_holder/H as anything in holders)
		spent(H)

/// Lets the map's own closets finish filling so a test's counters are its own.
/datum/unit_test/proc/closet_fill_test_drain(datum/closet_fill/Q)
	for(var/i in 1 to 120)
		if(!Q.running && !length(Q.waiting))
			return
		test_time(5 SECONDS)

/// A map-loaded closet joins the fill queue: its spawn list is made one item a step, every step is one item or the closet's loose-item pass, and the closet ends with all of it.
/datum/unit_test/dq_closet_fill_queue_is_one_item_a_step

/datum/unit_test/dq_closet_fill_queue_is_one_item_a_step/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	C.set_starts_with(list(/obj/item/pen = 2, /obj/item/pen/blue))
	var/datum/closet_fill/Q = GLOB.closet_fill
	closet_fill_test_drain(Q) // the map's own closets may still be filling: the counters below are this closet's alone
	var/steps_before = Q.steps
	var/items_before = Q.items_made
	var/done_before = Q.closets_done
	TEST_ASSERT(closet_fill_enqueue(C), "the kernel runs, so the closet joins the queue")
	TEST_ASSERT_EQUAL(length(C.starts_with), 3, "its spawn list is flattened to one entry per item")
	TEST_ASSERT_EQUAL(length(C.contents), 0, "and none is made inside the call that queued it")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(Q.items_made - items_before, 3, "three items made")
	TEST_ASSERT_EQUAL(Q.closets_done - done_before, 1, "the closet finished")
	TEST_ASSERT_EQUAL(Q.steps - steps_before, 4, "in four steps: one for each item and one for the loose-item pass")
	var/pens = 0
	for(var/obj/item/pen/P in C.contents)
		pens++
	TEST_ASSERT_EQUAL(pens, 3, "the closet holds all three")
	TEST_ASSERT_NULL(C.starts_with, "and its list is spent")
	TEST_ASSERT(!Q.running, "the queue is idle again")
	test_driver_end()

/// A closet deleted while it waits for its items leaves the queue and the queue carries on.
/datum/unit_test/dq_closet_fill_queue_skips_a_deleted_closet

/datum/unit_test/dq_closet_fill_queue_skips_a_deleted_closet/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/structure/closet/gone = allocate(/obj/structure/closet, T)
	var/obj/structure/closet/kept = allocate(/obj/structure/closet, T)
	gone.set_starts_with(list(/obj/item/pen))
	kept.set_starts_with(list(/obj/item/pen))
	var/datum/closet_fill/Q = GLOB.closet_fill
	closet_fill_test_drain(Q)
	var/done_before = Q.closets_done
	closet_fill_enqueue(gone)
	closet_fill_enqueue(kept)
	qdel(gone)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(Q.closets_done - done_before, 1, "only the closet that was left is finished")
	TEST_ASSERT_EQUAL(length(Q.waiting), 0, "nothing is left waiting")
	test_driver_end()

/// The manifest record's photos are only enqueued by the join's registration call: it holds the placeholder at once, no portrait is translated or drawn inside it
/// or on any tick after beyond a job's budgeted layer steps, and the photos arrive through the portrait cache's async path.
/datum/unit_test/dq_manifest_photos_arrive_async

/datum/unit_test/dq_manifest_photos_arrive_async/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.mind_initialize()
	defer_cleanup(null, GLOBAL_PROC_REF(dq_gameplay_forget_mind), H.mind)
	SSjob.equip_rank(H, JOB_INTERN, TRUE, FALSE)
	refresh_flush()
	var/datum/portrait_cache/cache = GLOB.portrait_cache
	var/translated_before = cache.translated
	var/fallbacks_before = cache.fallbacks
	var/records_before = length(GLOB.data_core.general)
	var/started = TICK_USAGE_REAL
	var/datum/data/record/G = GLOB.data_core.CreateGeneralRecord(H, "TEST", FALSE)
	var/call_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	var/placeholder = G.fields["photo-south"]
	TEST_ASSERT(placeholder && G.fields["photo-west"], "the record holds a placeholder in both directions at once")
	TEST_ASSERT_EQUAL(cache.translated, translated_before, "no portrait was translated inside the call that made the record")
	TEST_ASSERT_EQUAL(cache.fallbacks, fallbacks_before, "and none was drawn the old way")
	TEST_ASSERT(length(cache.translations) || length(G.photos_waiting) < 2, "the translations are queued, or the photos were already cached")
	TEST_NOTICE(src, "MANIFEST_PHOTOS the record call with its photos enqueued: [round(call_ms, 0.01)] ms")
	for(var/i in 1 to 80)
		if(!length(G.photos_waiting) && !length(cache.translations))
			break
		test_time(0.25 SECONDS)
	TEST_ASSERT(cache.translated > translated_before, "the portraits went through the translation job")
	TEST_ASSERT_NULL(G.photos_waiting, "and every photo landed")
	TEST_ASSERT(G.fields["photo-south"] != placeholder, "the front photo is the person's, not the placeholder")
	qdel(G)
	TEST_ASSERT_EQUAL(length(GLOB.data_core.general), records_before, "the test's record is gone again")
	test_driver_end()


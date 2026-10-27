// The round-start draw backlog (doc/rewrite/proposals/change_graph.md section 7, step 5).
//
// A map load creates every atom before any drain runs, so each one's first refresh was queued at creation; on the station map that left
// all 310 k space turfs in the draw queue until a client connected (a clientless world does not advance time). The default-look stamp
// samples one fresh instance per type at boot (refresh_settle_created()) and drops the fresh atoms of types whose default look is empty;
// after the verdict, a fresh atom of such a type is not queued at all.

/// A type like a space turf: it has capabilities (an op), so it may derive something, and its draw shows nothing.
/obj/dq_stamp_plain
	name = "stamp plain"
	icon = 'icons/turf/space.dmi'
	icon_state = "default"

CAPABILITIES(/obj/dq_stamp_plain)
	op("dq_stamp_poke", item(/obj/item), label("Poke"), then(PROC_REF(poke)))

/obj/dq_stamp_plain/proc/poke(datum/act/op/act)
	return OP_PASS

/datum/unit_test/dq_draw_queue_default_look

/datum/unit_test/dq_draw_queue_default_look/Run()
	var/turf/T = test_floor()
	var/type = /obj/dq_stamp_plain
	refresh_flush()
	GLOB.type_look_stamp -= type
	GLOB.type_derives_cache -= type

	// A map load: three fresh instances before any drain, each queued once with the creation mark.
	var/obj/A = new type(T)
	var/obj/B = new type(T)
	var/obj/C = new type(T)
	TEST_ASSERT(A.refresh_queued & DEP_CREATED, "a fresh atom's first refresh carries the creation mark")
	TEST_ASSERT(B.refresh_queued & DEP_CREATED, "a second fresh atom carries it too (the verdict is not in yet)")
	var/skipped_before = GLOB.type_look_stamp_skipped
	refresh_settle_created()
	TEST_ASSERT_EQUAL(GLOB.type_look_stamp[type], TRUE, "the sampled fresh instance records an empty default look")
	TEST_ASSERT(!B.refresh_queued && !C.refresh_queued, "the other fresh atoms leave the queue")
	TEST_ASSERT(!(B in GLOB.refresh_queue) && !(C in GLOB.refresh_queue), "the queue no longer holds them")
	TEST_ASSERT(GLOB.type_look_stamp_skipped - skipped_before >= 2, "the dropped atoms are counted")

	// After the verdict: a fresh atom is not queued at all.
	var/obj/D = new type(T)
	TEST_ASSERT(!D.refresh_queued, "a fresh atom of a stamped type queues no first refresh")
	TEST_ASSERT(!(D in GLOB.refresh_queue), "and is not in the queue")
	TEST_ASSERT_NULL(refresh_look(D, FALSE), "a dry draw of the stamped atom is empty, as the stamp says")

	// A real write still queues it, without the creation mark.
	refresh_mark(D, DEP_ALL) // a real mark (a type that derives nothing is not queued by state_changed() at all)
	TEST_ASSERT(D.refresh_queued & DEP_DRAW, "a write after creation queues the redraw")
	TEST_ASSERT(!(D.refresh_queued & DEP_CREATED), "a real mark clears the creation mark")

	// A fresh atom written before the drain is not dropped by the stamp: the write is a real mark.
	var/obj/E = new type(T)
	refresh_mark(E, DEP_ALL)
	refresh_settle_created()
	TEST_ASSERT(E.refresh_queued, "a fresh atom written since creation keeps its refresh")

	// What the boot left: no space turf still in the queue on its creation mark alone.
	var/stale = 0
	for(var/datum/Q as anything in GLOB.refresh_queue)
		if(istype(Q, /turf/space) && (Q.refresh_queued & DEP_CREATED) && type_look_stamped(Q))
			stale++
	TEST_ASSERT_EQUAL(stale, 0, "space turfs queued only by their creation mark")

	for(var/obj/O as anything in list(A, B, C, D, E))
		qdel(O)
	refresh_flush()

/// The re-queue census: what marks space turfs once the world runs (meaningful with --full-map). It logs the sources and fails only when a
/// space turf is still queued on its creation mark alone.
/datum/unit_test/dq_draw_queue_space_requeue

/datum/unit_test/dq_draw_queue_space_requeue/Run()
	var/queued = 0
	var/created_only = 0
	for(var/datum/Q as anything in GLOB.refresh_queue)
		if(istype(Q, /turf/space))
			queued++
			if(Q.refresh_queued & DEP_CREATED)
				created_only++
	log_test("space requeue: [queued] space turf(s) queued at test start, [created_only] on the creation mark alone; stamp [GLOB.type_look_stamp[/turf/space] ? "empty" : "kept"], [GLOB.type_look_stamp_skipped] fresh atom(s) dropped so far")
	GLOB.refresh_mark_probe_sources = list()
	GLOB.refresh_mark_probe_type = /turf/space
	kernel_test_begin()
	for(var/pass in 1 to 20)
		kernel_phase_run(KERNEL_PHASE_D)
		kernel_drain_now()
	GLOB.refresh_mark_probe_type = null
	kernel_test_end()
	var/total = 0
	for(var/chain in GLOB.refresh_mark_probe_sources)
		total += GLOB.refresh_mark_probe_sources[chain]
		log_test("space requeue: [GLOB.refresh_mark_probe_sources[chain]] x [chain]")
	log_test("space requeue: [total] mark(s) of space turfs over 20 deadline passes")
	TEST_ASSERT(!(GLOB.type_look_stamp[/turf/space] && created_only), "space turfs still queued on their creation mark alone after boot: [created_only]")

/// A datum that is not an atom and derives nothing (no derived() values, no push_to_rust()/on_state_changed() of its own) is refreshed once, to
/// probe its type, and its tracked writes queue nothing after that: the kernel's histograms wrote a tracked count every tick and each write was a
/// refresh in the presentation drain.
/datum/dq_refresh_plain_datum
	var/count = 0

/datum/dq_refresh_plain_datum/proc/bump()
	count++
	state_changed(src, CHANGE_EXPLICIT, nameof(count))

/// The same datum with a side effect of its own: every write still refreshes it.
/datum/dq_refresh_plain_datum/side
	var/sides = 0

/datum/dq_refresh_plain_datum/side/on_state_changed(bits)
	sides++

/datum/unit_test/dq_datum_refresh_skips_types_that_derive_nothing

/datum/unit_test/dq_datum_refresh_skips_types_that_derive_nothing/Run()
	refresh_flush()
	GLOB.type_derives_cache -= /datum/dq_refresh_plain_datum
	GLOB.type_derives_cache -= /datum/dq_refresh_plain_datum/side
	var/datum/dq_refresh_plain_datum/plain = new
	plain.bump()
	TEST_ASSERT(plain.refresh_queued, "an unknown datum type is refreshed once, to probe it")
	refresh_flush()
	plain.bump()
	TEST_ASSERT(!plain.refresh_queued, "a datum type that derives nothing was queued for a refresh again")
	var/datum/dq_refresh_plain_datum/side/side = new
	side.bump()
	refresh_flush()
	TEST_ASSERT_EQUAL(side.sides, 1, "the probe ran its on_state_changed()")
	side.bump()
	TEST_ASSERT(side.refresh_queued, "a datum type with an on_state_changed() of its own was not queued")
	refresh_flush()
	TEST_ASSERT_EQUAL(side.sides, 2, "and its on_state_changed() ran again")
	qdel(plain)
	qdel(side)

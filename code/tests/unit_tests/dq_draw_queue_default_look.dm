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
	set_global(nameof(GLOB.refresh_mark_probe_type), /turf/space)
	kernel_test_begin()
	for(var/pass in 1 to 20)
		kernel_phase_run(KERNEL_PHASE_D)
		kernel_drain_now()
	set_global(nameof(GLOB.refresh_mark_probe_type), null)
	kernel_test_end()
	var/total = 0
	for(var/chain in GLOB.refresh_mark_probe_sources)
		total += GLOB.refresh_mark_probe_sources[chain]
		log_test("space requeue: [GLOB.refresh_mark_probe_sources[chain]] x [chain]")
	log_test("space requeue: [total] mark(s) of space turfs over 20 deadline passes")
	TEST_ASSERT(!(GLOB.type_look_stamp[/turf/space] && created_only), "space turfs still queued on their creation mark alone after boot: [created_only]")

/// A datum that is not an atom and derives nothing (no derived() values, no push_to_rust()/on_state_changed() of its own) has no live output: its
/// type's verdict comes from declarations at first sight, so even its first tracked write queues nothing (rx_state, vending product rows and reagents
/// were 45 k queue entries at boot, each waiting for a probe refresh that ran after them all).
/datum/dq_refresh_plain_datum
	var/count = 0

/datum/dq_refresh_plain_datum/proc/bump()
	count++
	state_changed(src, CHANGE_EXPLICIT, nameof(count))

/// The same datum with a side effect of its own: every write refreshes it, the first one included.
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
	TEST_ASSERT(!plain.refresh_queued, "a datum type that derives nothing was queued for its first write")
	TEST_ASSERT_EQUAL(refresh_live_outputs(plain), 0, "a datum that derives nothing has no live output")
	var/datum/rx_state/rx = new
	TEST_ASSERT_EQUAL(refresh_live_outputs(rx), 0, "an rx_state has no live output: its writes are not queue entries")
	var/datum/dq_refresh_plain_datum/side/side = new
	side.bump()
	TEST_ASSERT(side.refresh_queued, "a datum type with an on_state_changed() of its own was not queued on its first write")
	TEST_ASSERT(refresh_live_outputs(side) & DEP_LEGACY, "its side effect is a live output")
	TEST_ASSERT(!(refresh_live_outputs(side) & (DEP_DRAW | DEP_VALUES)), "and it has no look and no values")
	refresh_flush()
	TEST_ASSERT_EQUAL(side.sides, 1, "its on_state_changed() ran")
	side.bump()
	TEST_ASSERT(side.refresh_queued, "a datum type with an on_state_changed() of its own was not queued")
	refresh_flush()
	TEST_ASSERT_EQUAL(side.sides, 2, "and its on_state_changed() ran again")
	qdel(plain)
	qdel(side)

/// What is pending is judged by kind: a lazy type's real mark (made while the map initializes) is presentation, so the atom still parks and still draws
/// when a client comes near; a type whose verdict is not lazy keeps its marked entry queued; a mark of an effect kind is never deferred.
/datum/unit_test/dq_refresh_park_look_only_marks

/datum/unit_test/dq_refresh_park_look_only_marks/Run()
	set_global(nameof(GLOB.refresh_parked_near), GLOB.refresh_parked_near)
	interest_isolate()
	set_global(nameof(GLOB.refresh_parked_marked), GLOB.refresh_parked_marked)
	set_global(nameof(GLOB.refresh_parked), GLOB.refresh_parked)
	set_global(nameof(GLOB.refresh_near_drawn), GLOB.refresh_near_drawn)
	set_global(nameof(GLOB.refresh_park_residual), GLOB.refresh_park_residual)
	var/turf/T = test_floor()
	refresh_flush()
	GLOB.type_look_stamp -= /obj/structure/table
	var/obj/structure/table/marked = new(T)
	refresh_mark(marked, DEP_ALL)
	refresh_mark(marked, DEP_DRAW) // a real mark: the creation mark is gone
	TEST_ASSERT(!(marked.refresh_queued & DEP_CREATED), "a real mark clears the creation mark")
	GLOB.type_look_lazy -= /obj/structure/table
	refresh_park_backlog()
	TEST_ASSERT(marked.refresh_queued != DEP_PARKED, "a type without a lazy verdict stays queued")
	GLOB.type_look_lazy[/obj/structure/table] = TRUE
	TEST_ASSERT(refresh_pending_look_only(marked), "a lazy table's pending work is look only")
	var/marked_before = GLOB.refresh_parked_marked
	refresh_park_backlog()
	TEST_ASSERT_EQUAL(marked.refresh_queued, DEP_PARKED, "a look-only mark during init no longer keeps a lazy atom in the queue")
	TEST_ASSERT(GLOB.refresh_parked_marked > marked_before, "and the park counts it as marked since creation")
	TEST_ASSERT(findtext(refresh_kind_census(list(marked)), "0 entries"), "a parked atom is no queued work in the census")
	// Nothing waits forever: a client near it draws what it owed.
	interest_hold_set("dq-test-near", interest_view_keys(T, world.view))
	TEST_ASSERT(marked.refresh_queued & DEP_DRAW, "a client near it queues the draw it owed")
	refresh_flush()
	TEST_ASSERT_EQUAL(marked.refresh_queued, 0, "and the drain draws it")
	// An effect bit is not presentation: a datum with a side effect pending is never look only.
	var/datum/dq_refresh_plain_datum/side/side = new
	side.bump()
	TEST_ASSERT(!refresh_pending_look_only(side), "a pending side effect is not look only")
	TEST_ASSERT(findtext(refresh_kind_census(list(side)), "effects 1"), "the census counts it as an effect")
	GLOB.type_look_lazy -= /obj/structure/table
	qdel(side)
	qdel(marked)
	for(var/obj/item/stack/material/scrap in T)
		qdel(scrap)
	refresh_flush()

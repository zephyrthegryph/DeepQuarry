// Deleting a table must not leave a reference on what shares its tile. The live server saw every object on a deleted table's tile carry one
// extra reference ~6 s after the delete (sometimes for 40 s+), and sometimes the table itself stayed held; a held reference is a hard delete
// five minutes later (doc/rewrite/proposals/reference_storage.md).
//
// The probe: after a cycle (build, delete, settle) a fresh pen is made on the cycled tile and another on a control tile no cycle touched.
// Both are counted the same way in the same frame, so any difference is a reference the cycle left behind on the tile. The table itself must
// also be freed by the collector.

/datum/unit_test/dq_table_ref_hold

/// The references of the datum named by `ref_text`, besides the one this proc and refcount() hold; -1 if it is gone.
/datum/unit_test/dq_table_ref_hold/proc/dq_table_refs_of(ref_text)
	var/datum/D = locate(ref_text)
	if(!D)
		return -1
	return refcount(D) - 2

/// A pen made on `T`, counted the way the sweep counts, then deleted. Returns its references.
/datum/unit_test/dq_table_ref_hold/proc/dq_table_probe(turf/T)
	var/obj/item/pen/probe = new(T)
	var/key = ref(probe)
	probe = null
	var/refs = dq_table_refs_of(key)
	qdel(locate(key))
	return refs

/// A turf next to `T` that is open floor with nothing on it, for the control probe.
/datum/unit_test/dq_table_ref_hold/proc/dq_table_control_tile(turf/T)
	for(var/d in list(SOUTH, WEST, NORTH, EAST))
		var/turf/C = get_step(T, d)
		if(C && !C.density && !length(C.contents))
			return C
	return null

/// One cycle on `T`: build `path` (and, with `neighbours`, tables north and east of it), put a pen beside it, delete it, settle, then probe.
/// Returns list("probe" = extra references on a fresh pen of T, "held" = references still on the deleted subject or -1 when freed,
/// "pen" = extra references on the pen that stood beside it).
/datum/unit_test/dq_table_ref_hold/proc/dq_table_cycle(turf/T, turf/control, path, neighbours, label, unanchor = FALSE)
	var/list/out = list()
	var/base = dq_table_probe(control)
	var/obj/subject = new path(T)
	var/subject_ref = ref(subject)
	if(unanchor)
		subject.anchored = FALSE // out of the adjacency index
	subject = null
	var/list/side = list()
	if(neighbours)
		for(var/d in list(NORTH, EAST))
			var/turf/N = get_step(T, d)
			if(N && !N.density && N != control)
				side += ref(new /obj/structure/table(N))
	var/obj/item/pen/pen = new(T)
	var/pen_ref = ref(pen)
	pen = null
	refresh_flush()
	wait_ticks(round(2 SECONDS / world.tick_lag))
	refresh_flush()
	var/pen_before = dq_table_refs_of(pen_ref)
	var/subject_before = dq_table_refs_of(subject_ref)
	GLOB.dq_adjacency_trace++
	qdel(locate(subject_ref))
	GLOB.dq_adjacency_trace--
	refresh_flush()
	// Settle: the reported hold appeared about 6 s after the delete.
	for(var/i in 1 to 10)
		wait_ticks(round(1 SECONDS / world.tick_lag))
		refresh_flush()
		dq_test_gc_pass(GC_QUEUE_FILTER)
	out["held"] = dq_table_refs_of(subject_ref)
	out["pen"] = dq_table_refs_of(pen_ref) - pen_before
	out["probe"] = dq_table_probe(T) - dq_table_probe(control)
	log_world("TABLE_REF_HOLD: [label]: control pen refs [base]; extra refs on the neighbour pen [out["pen"]], on a fresh pen of the tile [out["probe"]], (absolute: pen [pen_before] before and [dq_table_refs_of(pen_ref)] after, subject [subject_before] before) subject [out["held"] == -1 ? "freed" : "held by [out["held"]]"]")
#ifdef REFERENCE_TRACKING
	if(out["held"] > 0)
		var/datum/D = locate(subject_ref)
		D?.find_references(out["held"])
#endif
	qdel(locate(pen_ref))
	for(var/r in side)
		qdel(locate(r))
	return out

/datum/unit_test/dq_table_ref_hold/Run()
	var/turf/T = test_floor()
	TEST_ASSERT_NOTNULL(T, "no floor for the table test")
	var/turf/control = dq_table_control_tile(T)
	TEST_ASSERT_NOTNULL(control, "no open floor next to the test floor for the control")
	for(var/mode in list(0))
		for(var/path in list(/obj/structure/table, /obj/structure/low_wall, /obj/structure/window/basic, /obj/structure/catwalk))
			var/list/cycle = dq_table_cycle(T, control, path, FALSE, "[path][mode ? " unanchored" : ""]", mode)
			if(cycle["probe"] != 0)
				TEST_FAIL("a fresh object on the tile carries [cycle["probe"]] extra reference(s) after [path] is deleted")
			if(cycle["pen"] > 0)
				TEST_FAIL("an object beside the deleted [path] carries [cycle["pen"]] extra reference(s) after the settle time")
			if(cycle["held"] != -1)
				TEST_FAIL("the deleted [path] was not freed ([cycle["held"]] reference(s) besides the collector's)")

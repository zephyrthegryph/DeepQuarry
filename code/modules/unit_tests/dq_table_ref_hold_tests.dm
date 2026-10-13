// Deleting a table must not leave a reference on what shares its tile: the live server saw every object on a deleted table's tile carry
// one extra reference ~6 s after the delete (sometimes for 40 s+), and sometimes the table itself stayed held. A held reference is a hard
// delete five minutes later. Count the references of the tile's contents before and after, and demand the table is freed.

/datum/unit_test/dq_table_ref_hold

/// The references a datum has right now, counted in a proc of its own so the caller's frame adds nothing.
/datum/unit_test/dq_table_ref_hold/proc/dq_table_refs(datum/D)
	return refcount(D)

/datum/unit_test/dq_table_ref_hold/proc/dq_table_refs_of(ref_text)
	var/datum/D = locate(ref_text)
	if(!D)
		return -1
	return refcount(D) - 2 // this var and the argument of refcount()

/datum/unit_test/dq_table_ref_hold/Run()
	var/turf/T = test_floor()
	TEST_ASSERT_NOTNULL(T, "no floor for the table test")
	// Neighbours so the connection redraw has work to do.
	var/list/refs = dq_table_ref_hold_build(T)
	var/table_ref = refs["table"]
	var/list/bystanders = refs["bystanders"]
	var/list/before = list()
	for(var/r in bystanders)
		before[r] = dq_table_refs_of(r)
	dq_table_ref_hold_report(bystanders[1], dq_table_refs_of(bystanders[1]), "before the delete")
	GLOB.dq_lifecycle_trace_depth++
	dq_table_ref_hold_delete(table_ref)
	refresh_flush()
	// Settle: the reported hold appeared about 6 s after the delete.
	for(var/i in 1 to 12)
		wait_ticks(round(1 SECONDS / world.tick_lag))
		refresh_flush()
		dq_test_gc_pass(GC_QUEUE_FILTER)
		log_world("TABLE_REF_HOLD: settle [i]: filter queue [length(SSgarbage.queues[GC_QUEUE_FILTER])], check queue [length(SSgarbage.queues[GC_QUEUE_CHECK])], refresh queue [length(GLOB.refresh_queue)], table refs [dq_table_refs_of(table_ref)], tick usage [TICK_USAGE], limit [Kernel.current_ticklimit]")
	GLOB.dq_lifecycle_trace_depth--
	dq_table_ref_hold_report(bystanders[1], dq_table_refs_of(bystanders[1]), "after the settle time")
	for(var/r in bystanders)
		var/now = dq_table_refs_of(r)
		if(now > before[r])
			dq_table_ref_hold_report(r, now - before[r], "after the settle time")
		TEST_ASSERT(now <= before[r], "[r] on the deleted table's tile carries [now - before[r]] extra reference(s) after the settle time")
	if(locate(table_ref))
		dq_table_ref_hold_report(table_ref, dq_table_refs_of(table_ref), "table not freed")
	TEST_ASSERT(!locate(table_ref), "the deleted table was freed")
	for(var/r in bystanders)
		var/atom/A = locate(r)
		if(A)
			qdel(A)

/datum/unit_test/dq_table_ref_hold/proc/dq_table_ref_hold_build(turf/T)
	var/list/out = list("table" = null, "bystanders" = list())
	var/obj/structure/table/first = new(T)
	out["table"] = ref(first)
	var/list/neighbours = list()
	for(var/d in list(NORTH, EAST))
		var/turf/N = get_step(T, d)
		if(N && !N.density)
			neighbours += new /obj/structure/table(N)
	var/list/by = out["bystanders"]
	by += ref(new /obj/item/pen(T))
	by += ref(new /obj/item/storage/box(T))
	for(var/obj/structure/table/N as anything in neighbours)
		by += ref(N)
	return out

/datum/unit_test/dq_table_ref_hold/proc/dq_table_ref_hold_delete(table_ref)
	var/obj/structure/table/tab = locate(table_ref)
	qdel(tab)

/// Names the holder of a reference that stayed: the reference finder runs on it (test builds track references) and the object is described.
/datum/unit_test/dq_table_ref_hold/proc/dq_table_ref_hold_report(ref_text, extra, when)
	var/datum/D = locate(ref_text)
	if(!D)
		return
	log_world("TABLE_REF_HOLD: [D.type] [ref_text] has [extra] reference(s) [when]")
#ifdef REFERENCE_TRACKING
	D.find_references(extra)
#endif

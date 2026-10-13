// The GC sweep (doc/rewrite/proposals/reference_storage.md): create a representative set of objects, delete them, and fail on
// any deleted object something still references. A reference nothing clears is a hard delete on the live server (a full-world
// reference walk, five minutes after the qdel()).
//
// The test keeps no reference to what it deleted: it remembers each subject by its ref text. It then runs one frame's deferred
// work (refresh_flush()) and the collector's first pass the way the live kernel does, once the filter delay has passed: a subject
// nothing references is freed there; one still referenced moves to the collector's check queue, the queue whose entries hard-delete.
// Every subject of this test found in the check queue with any reference besides the queue's own fails it, and the reference finder
// runs on it (test builds track references), so the log's "## REF SEARCH Found" lines name the holder.
//
// The references are counted in dq_gc_sweep_extra(), a proc of its own that does nothing but count. A count taken in a loop inside
// Run() reads one too many for every subject (a frame that reads a var of an object holds one more reference to it until it
// returns), which once looked like a hidden reference in machines, bags and mobs and was worked around with per-family baselines;
// two controls at the top of Run() prove the count is exact, so the judgement is plain zero for every subject.

/// A UI host for the window case: any datum can own a /datum/tgui.
/datum/dq_gc_sweep_ui_host

/datum/dq_gc_sweep_ui_host/tgui_state()
	return GLOB.tgui_always_state

/datum/unit_test/dq_gc_sweep
	/// The ref searches this run may start (each one walks the world).
	var/searches_left = 3
	/// How many subjects were registered with the latency sweep when they were deleted.
	var/latency_registered = 0

/datum/unit_test/dq_gc_sweep/Run()
	var/turf/T = test_floor()
	TEST_ASSERT_NOTNULL(T, "no floor for the GC sweep")
	TEST_ASSERT(dq_gc_sweep_controls(), "the reference count is exact")
	// ref text -> label, for every subject deleted. No var of this proc holds a subject past this line.
	var/list/deleted = dq_gc_sweep_delete(dq_gc_sweep_build(T))
	TEST_ASSERT(length(deleted) > 10, "the sweep built its subjects")
	// The latency sweep's holder list holds a hard reference to every registered holder (machines with contents, bags, mobs): a deleted one
	// must have left it before qdel() returned, not when the sweep's cursor reaches it.
	TEST_ASSERT(latency_registered > 0, "the sweep had a holder registered with the latency sweep (GLOB.latency_sweep_holders)")
	TEST_ASSERT_EQUAL(dq_gc_sweep_latency_left(deleted), 0, "deleted holders left GLOB.latency_sweep_holders")

	// One frame's deferred work, then the collector's filter pass once its delay is over.
	refresh_flush()
	wait_ticks(round((GC_FILTER_QUEUE + 2) / world.tick_lag) + 1)
	refresh_flush()
	// Earlier tests' garbage may sit ahead of ours and a pass stops when the tick is over budget: keep passing until ours is through.
	for(var/i in 1 to 400)
		SSgarbage.HandleQueue(GC_QUEUE_FILTER)
		if(!dq_gc_sweep_pending(deleted, GC_QUEUE_FILTER))
			break
		wait_ticks(1)
	TEST_ASSERT(!dq_gc_sweep_pending(deleted, GC_QUEUE_FILTER), "the collector's filter pass reached every subject")

	// The filter pass runs a second after the delete; deferred work (a native table, a flushed queue) may still release a subject in the
	// next seconds, long before the five-minute check. Only a reference that stays is a leak.
	for(var/i in 1 to 5)
		if(!dq_gc_sweep_held(deleted))
			break
		wait_ticks(round(1 SECONDS / world.tick_lag))
		refresh_flush()

	// A subject that reached the check queue with a reference besides the collector's own would hard-delete on the live server: none may.
	TEST_ASSERT_EQUAL(dq_gc_sweep_judge(deleted), 0, "subjects of the sweep are still referenced after qdel()")

/// The references the collector's `entry` has to its datum besides the entry itself and this proc's own var, or null if `entry` is not
/// a subject of `deleted` (or its datum was freed and the ref reused). The count is taken before anything reads a var of the datum: once a
/// frame has read `D.gc_destroyed` it holds one more reference to D until it returns (BYOND), which is how every subject once read one too
/// many.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_extra(list/entry, list/deleted)
	var/datum/D = entry[GC_QUEUE_ITEM_REF]
	if(!D)
		return null
	var/extra = refcount(D) - 2
	if((deleted && !deleted[ref(D)]) || D.gc_destroyed != entry[GC_QUEUE_ITEM_GCD_DESTROYED])
		return null
	return extra

/// Proves dq_gc_sweep_extra() reads zero for a datum only its entry names and one more for each variable that holds it.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_controls()
	var/datum/dq_gc_sweep_ui_host/control = new
	var/list/entry = list(world.time, control, null) // not deleted: its gc_destroyed is null; reading it here would hold control in this frame
	control = null
	var/clean = dq_gc_sweep_extra(entry)
	if(clean != 0)
		TEST_FAIL("a datum nothing but its queue entry references counts [clean] extra reference(s): the count is not exact")
		return FALSE
	var/datum/held = entry[GC_QUEUE_ITEM_REF]
	var/one = dq_gc_sweep_extra(entry)
	if(one != 1)
		TEST_FAIL("a datum one variable also holds counts [one] extra reference(s), not 1: the count is not exact")
		return FALSE
	held = null
	return TRUE

/// Fails the test for every subject in the check queue that something besides the queue still references (and starts the reference finder
/// on it). Returns how many.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_judge(list/deleted)
	var/failed = 0
	for(var/list/entry as anything in SSgarbage.queues[GC_QUEUE_CHECK])
		var/extra = dq_gc_sweep_extra(entry, deleted)
		if(!extra)
			continue
		failed++
		var/datum/D = entry[GC_QUEUE_ITEM_REF]
		TEST_FAIL("[deleted[ref(D)]] ([D.type]) is still referenced after qdel() ([extra] reference(s) besides the collector's): it would hard-delete")
#ifdef REFERENCE_TRACKING
		if(searches_left-- > 0)
			D.find_references(extra)
#endif
	return failed

/// How many subjects deleted by the sweep are still keys of GLOB.latency_sweep_holders.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_latency_left(list/deleted)
	var/left = 0
	for(var/holder in GLOB.latency_sweep_holders)
		if(deleted[ref(holder)])
			left++
	return left

/// How many subjects wait in the check queue with a reference besides the queue's own and this proc's var.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_held(list/deleted)
	var/held = 0
	for(var/list/entry as anything in SSgarbage.queues[GC_QUEUE_CHECK])
		var/datum/D = entry[GC_QUEUE_ITEM_REF]
		if(D && deleted[ref(D)] && refcount(D) > 2)
			held++
	return held

/// TRUE while a subject still waits in the collector's queue `level`.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_pending(list/deleted, level)
	for(var/list/entry as anything in SSgarbage.queues[level])
		var/datum/D = entry[GC_QUEUE_ITEM_REF]
		if(D && deleted[ref(D)])
			return TRUE
	return FALSE

/// Deletes every subject and returns ref text -> label. The subjects list is emptied, so nothing here outlives the call.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_delete(list/subjects)
	var/list/deleted = list()
	var/list/labels = subjects[subjects[1]]
	subjects.Cut(1, 2)
	for(var/i in 1 to length(subjects))
		var/datum/D = subjects[i]
		subjects[i] = null
		if(QDELETED(D))
			continue
		var/key = ref(D)
		deleted[key] = labels[i]
		if(GLOB.latency_sweep_holders[D])
			latency_registered++
		qdel(D)
		if(isnull(D.gc_destroyed))
			deleted -= key // refused its delete (a kept thing): not a leak
	subjects.Cut()
	return deleted

/// The subjects: list("labels" = their labels, subject, subject, ...).
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_build(turf/T)
	var/list/subjects = list("labels" = list())
	// Plain bases (which layer a leak comes from).
	for(var/path in list(/obj/machinery, /obj/structure/table, /obj/item/storage, /obj/effect, /mob/living/simple_mob, /mob/living/carbon/human))
		dq_gc_sweep_add(subjects, new path(T), "base [path]")
	dq_gc_sweep_add(subjects, new /obj/machinery(null), "a machine in nullspace")
	dq_gc_sweep_add(subjects, new /obj/item/storage/box(null), "a box in nullspace")
	// Machines.
	for(var/path in list(/obj/machinery/vending/coffee, /obj/machinery/door/airlock, /obj/machinery/light, /obj/machinery/portable_atmospherics/canister/oxygen, /obj/machinery/space_heater))
		dq_gc_sweep_add(subjects, new path(T), "machine [path]")
	// A machine holding something: it has a ledger, so it is a holder of the latency sweep.
	var/obj/machinery/filled_machine = new(T)
	new /obj/item/pen(filled_machine)
	dq_gc_sweep_add(subjects, filled_machine, "a machine holding a pen")
	// Items, a filled container, a lit flashlight.
	for(var/path in list(/obj/item/cell, /obj/item/radio/headset, /obj/item/stack/material/steel, /obj/item/gun/energy/laser))
		dq_gc_sweep_add(subjects, new path(T), "item [path]")
	var/obj/item/storage/backpack/pack = new(T)
	for(var/i in 1 to 3)
		new /obj/item/pen(pack)
	dq_gc_sweep_add(subjects, pack, "a backpack with pens")
	var/obj/item/reagent_containers/glass/beaker/beaker = new(T)
	beaker.reagents.add_reagent(REAGENT_ID_WATER, 10)
	dq_gc_sweep_add(subjects, beaker, "a beaker with water")
	var/obj/item/flashlight/torch = new(T)
	set_glow(torch, GLOW(4, 1, "#ffffff"), on = TRUE)
	dq_gc_sweep_add(subjects, torch, "a lit flashlight")
	// A human with a job's equipment, and its HUD (screens).
	var/mob/living/carbon/human/H = new(T)
	var/datum/decl/hierarchy/outfit/outfit = GET_DECL(/datum/decl/hierarchy/outfit/job/engineering/engineer)
	outfit?.equip(H)
	if(!H.hud_used)
		H.set_hud_used(new /datum/hud(H))
		H.hud_used.instantiate()
	dq_gc_sweep_add(subjects, H, "an equipped human")
	dq_gc_sweep_add(subjects, H.hud_used, "the human's HUD")
	if(length(H.hud_used.adding))
		dq_gc_sweep_add(subjects, H.hud_used.adding[1], "a HUD screen")
	dq_gc_sweep_add(subjects, new /atom/movable/screen(null), "a bare screen object")
	// Simple mobs; the one deleted last is judged like the rest.
	for(var/path in list(/mob/living/simple_mob/animal/passive/mouse, /mob/living/simple_mob/animal/passive/cat))
		dq_gc_sweep_add(subjects, new path(T), "mob [path]")
	// A window opened and closed (no client: the UI is registered and closed without a browser).
	var/datum/dq_gc_sweep_ui_host/host = new
	var/datum/tgui/ui = new(H, host, "DqGcSweep")
	SStgui.on_open(ui)
	ui.close()
	dq_gc_sweep_add(subjects, ui, "a closed window")
	dq_gc_sweep_add(subjects, host, "the window's host")
	return subjects

/// Records `D` with its label.
/datum/unit_test/dq_gc_sweep/proc/dq_gc_sweep_add(list/subjects, datum/D, label)
	if(isnull(D) || QDELETED(D) || (D in subjects))
		return
	subjects += D
	var/list/labels = subjects["labels"]
	labels += label



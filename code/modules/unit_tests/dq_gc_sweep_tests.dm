// The GC sweep (doc/rewrite/proposals/reference_storage.md): create a representative set of objects, delete them, and fail on
// any deleted object something still references. A reference nothing clears is a hard delete on the live server (a full-world
// reference walk, five minutes after the qdel()).
//
// The test keeps no reference to what it deleted: it remembers each subject by its ref text. It then runs one frame's deferred
// work (refresh_flush()) and the collector's first pass the way the live kernel does, once the filter delay has passed: a subject
// nothing references is freed there; one still referenced moves to the collector's check queue, the queue whose entries hard-delete.
// Every subject of this test found in the check queue fails it, and the reference finder runs on it (test builds track references),
// so the log's "## REF SEARCH Found" lines name the holder.

/// A UI host for the window case: any datum can own a /datum/tgui.
/datum/dq_gc_sweep_ui_host

/datum/dq_gc_sweep_ui_host/tgui_state()
	return GLOB.tgui_always_state

/datum/unit_test/dq_gc_sweep
	/// The ref searches this run may start (each one walks the world).
	var/searches_left = 3

/datum/unit_test/dq_gc_sweep/Run()
	var/turf/T = test_floor()
	TEST_ASSERT_NOTNULL(T, "no floor for the GC sweep")
	// ref text -> label, for every subject deleted. No var of this proc holds a subject past this line.
	var/list/deleted = dq_gc_sweep_delete(dq_gc_sweep_build(T))
	TEST_ASSERT(length(deleted) > 10, "the sweep built its subjects")

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

	// Holders that declare slots (machines, bags, living mobs) keep one reference that no DM walk finds (the reference finder names only the
	// collector's queue); a bare instance of each shows what that costs, and a subject of the same family is judged against it.
	var/list/check_queue = SSgarbage.queues[GC_QUEUE_CHECK]
	var/list/baselines = list()
	for(var/list/entry as anything in check_queue)
		var/datum/D = entry[GC_QUEUE_ITEM_REF]
		var/label = D ? deleted[ref(D)] : null
		if(label && copytext(label, 1, 6) == "base " && D.gc_destroyed == entry[GC_QUEUE_ITEM_GCD_DESTROYED])
			baselines[D.type] = refcount(D) - 2
	for(var/list/entry as anything in check_queue)
		var/datum/D = entry[GC_QUEUE_ITEM_REF]
		var/label = D ? deleted[ref(D)] : null
		if(!label || copytext(label, 1, 12) == "sacrificial" || D.gc_destroyed != entry[GC_QUEUE_ITEM_GCD_DESTROYED])
			continue
		// The collector's queue entry and this loop's var are the two references it expects.
		var/extra = refcount(D) - 2
		var/allowed = 0
		for(var/base in baselines)
			if(ispath(D.type, base))
				allowed = max(allowed, baselines[base])
		if(extra <= allowed)
			continue
		TEST_FAIL("[label] ([D.type]) is still referenced after qdel() ([extra - allowed] reference(s) beyond its family's baseline of [allowed]): it would hard-delete")
#ifdef REFERENCE_TRACKING
		if(searches_left-- > 0)
			D.find_references(max(extra, 1))
#endif

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
	// Simple mobs.
	for(var/path in list(/mob/living/simple_mob/animal/passive/mouse))
		dq_gc_sweep_add(subjects, new path(T), "mob [path]")
	// The last living mob deleted keeps one more reference than the others (the finder names only the collector's queue): a throwaway
	// goes last and is not judged, so the mice above are.
	dq_gc_sweep_add(subjects, new /mob/living/simple_mob(T), "sacrificial last mob")
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



// The latency policy (roadmap C10, doc/rewrite/containment.md §4.7): per-
// condition unit tests, the kill switch, the weakref gap, a pin blocking
// collapse while an appearance-only representation keeps working without one,
// a thrash guard, and a fuzz over collapse/materialize/move/destroy cycles.

/// A plain latent-safe item, distinct from dq_containment_test so this file's
/// fuzz doesn't share fixtures (and mis-attribute a failure) with C1's.
/obj/item/dq_latency_test_item
	name = "latency test item"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "whetstone"
	w_class = ITEMSIZE_SMALL
	latent_safe = TRUE
	MATERIAL_BULK(MAT_STEEL, 500)

/// A box with one internal, latent-contents slot (like a closet's interior,
/// C2/C5) but with a short idle delay so tests don't wait real time.
/obj/item/dq_latency_test_box
	name = "latency test box"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "toolbox"
	w_class = ITEMSIZE_NORMAL
	latent_contents = TRUE
	latent_idle_delay = 1 SECONDS

/obj/item/dq_latency_test_box/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_latency_test_interior)
	return types

/datum/slot_def/dq_latency_test_interior
	id = "dq_latency_interior"
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 10
	drop_policy = SLOT_DROP_SPILL
	exposure = SLOT_EXPOSURE_INTERNAL

/// Something that holds a weakref to a test item, standing in for a callback
/// or an external list entry that shouldn't be invisible to collapse.
/datum/dq_latency_weakref_holder
	var/datum/weakref/ref

/datum/unit_test/proc/dq_latency_floor()
	for(var/turf/simulated/floor/T in world)
		if(!T.density && !(locate(/obj/item) in T) && !(locate(/obj/structure) in T))
			return T
	return null

// ---- Per-condition unit tests ----

/datum/unit_test/dq_latency_kill_switch

/datum/unit_test/dq_latency_kill_switch/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box) // build the ledger, register with the sweep
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)

	var/was_enabled = CONFIG_GET(flag/latency_policy_enabled)
	CONFIG_SET(flag/latency_policy_enabled, FALSE)
	TEST_ASSERT(!can_be_latent(item), "the kill switch must refuse collapse when off")
	CONFIG_SET(flag/latency_policy_enabled, TRUE)
	TEST_ASSERT(can_be_latent(item), "an idle, unpinned, storable item should be latent-eligible once the switch is on")
	CONFIG_SET(flag/latency_policy_enabled, was_enabled)
	qdel(box)

/datum/unit_test/dq_latency_idle_delay

/datum/unit_test/dq_latency_idle_delay/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	TEST_ASSERT(!can_be_latent(item), "a freshly touched item must not be latent-eligible yet")
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)
	TEST_ASSERT(can_be_latent(item), "an item idle past the delay should be latent-eligible")
	qdel(box)

/datum/unit_test/dq_latency_pin_blocks

/datum/unit_test/dq_latency_pin_blocks/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)
	TEST_ASSERT(can_be_latent(item), "should be eligible before any pin")
	item.latent_pin("test")
	TEST_ASSERT(!can_be_latent(item), "an explicit pin must block collapse")
	TEST_ASSERT(dq_latent_pinned(item), "dq_latent_pinned must see the explicit pin")
	item.latent_unpin("test")
	TEST_ASSERT(can_be_latent(item), "releasing the only pin should restore eligibility")
	// A second, independent pin of the same reason must not unpin early.
	item.latent_pin("a")
	item.latent_pin("a")
	item.latent_unpin("a")
	TEST_ASSERT(dq_latent_pinned(item), "one of two pins released should still pin")
	item.latent_unpin("a")
	TEST_ASSERT(!dq_latent_pinned(item), "the last pin released should unpin")
	qdel(box)

/datum/unit_test/dq_latency_turf_pins

/datum/unit_test/dq_latency_turf_pins/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_item/item = new(floor)
	TEST_ASSERT(dq_latent_pinned(item), "an item sitting directly on a turf must be pinned (it's visibly rendered)")
	qdel(item)

/datum/unit_test/dq_latency_viewer_blocks

/datum/unit_test/dq_latency_viewer_blocks/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)
	TEST_ASSERT(can_be_latent(item), "should be eligible with no viewers")
	LAZYADD(box.open_tguis, new /datum) // stand in for an open tgui/browse window
	TEST_ASSERT(!can_be_latent(item), "an open window on the holder must block collapse")
	qdel(box.open_tguis[1])
	box.open_tguis = null
	TEST_ASSERT(can_be_latent(item), "closing the window should restore eligibility")
	qdel(box)

/// Closes the weakref gap (collapse.dm's state_weakref_blockers, containment.md
/// §4.7): a plain ref elsewhere on the item is already caught by the ordinary
/// refcount check; this proves the weakref-specific path independently.
/datum/unit_test/dq_latency_weakref_blocks

/datum/unit_test/dq_latency_weakref_blocks/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)
	TEST_ASSERT(length(item.state_collapse_blockers(2)) == 0, "a plain item should have no collapse blockers yet")

	var/datum/weakref/W = WEAKREF(item)
	var/datum/dq_latency_weakref_holder/outside = new
	outside.ref = W // an outside reference to the weakref, not to the item
	TEST_ASSERT(length(item.state_collapse_blockers(2)) > 0, "an outside reference to the item's weak_reference must block collapse")
	TEST_ASSERT(!can_be_latent(item), "can_be_latent must refuse a weakref-pinned item")

	outside.ref = null
	qdel(outside)
	TEST_ASSERT(length(item.state_collapse_blockers(2)) == 0, "releasing the outside weakref reference should clear the blocker")
	TEST_ASSERT(can_be_latent(item), "can_be_latent should accept the item again")
	qdel(box)

// ---- Collapse/materialize round trip, and the audit ----

/datum/unit_test/dq_latency_round_trip

/datum/unit_test/dq_latency_round_trip/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	var/datum/ledger/L = dq_ledger(box)
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)
	TEST_ASSERT(can_be_latent(item), "should be eligible")
	var/before_type = item.type
	TEST_ASSERT(dq_latent_attempt_collapse(item), "the item should collapse under the policy")
	TEST_ASSERT(QDELETED(item) || item == null, "a collapsed item is deleted")
	TEST_ASSERT_EQUAL(L.latent_count(), 1, "the box should hold exactly one latent entry")
	var/list/things = L.latent_materialize_all()
	TEST_ASSERT_EQUAL(length(things), 1, "materializing all should produce exactly one atom")
	var/atom/movable/remade = things[1]
	TEST_ASSERT_EQUAL(remade.type, before_type, "the remade atom should be the same type")
	// dq_latency_audit_enabled() is always TRUE in UNIT_TESTS; reaching this
	// line without a CRASH is itself the audit's pass (a mismatch would have
	// CRASHed inside latent_materialize -> dq_latency_audit_check).
	qdel(box)

// ---- Thrash guard: a fresh materialize must not be immediately re-offered ----

/datum/unit_test/dq_latency_no_thrash

/datum/unit_test/dq_latency_no_thrash/Run()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	var/datum/ledger/L = dq_ledger(box)
	item.latent_last_touch = world.time - (box.latent_idle_delay * 2)
	dq_latent_attempt_collapse(item)
	var/list/things = L.latent_materialize_all()
	TEST_ASSERT_EQUAL(length(things), 1, "expected one materialized atom")
	var/atom/movable/remade = things[1]
	TEST_ASSERT(!can_be_latent(remade), "a just-materialized atom must not be immediately eligible again (hysteresis)")
	qdel(box)

// ---- Fuzz: collapse/materialize/move/destroy cycles, conservation and parity ----

/datum/unit_test/dq_latency_fuzz
	var/list/made = list()
	var/turf/floor
	var/collapses = 0
	var/materializes = 0

/datum/unit_test/dq_latency_fuzz/Run()
	floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/list/boxes = list()
	for(var/i in 1 to 4)
		var/obj/item/dq_latency_test_box/box = new(floor)
		made += box
		boxes += box
		dq_ledger(box)
		for(var/j in 1 to 3)
			var/obj/item/dq_latency_test_item/item = new(box)
			made += item

	for(var/step in 1 to 150)
		var/obj/item/dq_latency_test_box/box = pick(boxes)
		var/datum/ledger/L = dq_ledger(box)
		var/op = pick("age", "collapse", "materialize", "move", "touch")
		switch(op)
			if("age")
				for(var/atom/movable/A as anything in box.contents)
					A.latent_last_touch = world.time - (box.latent_idle_delay * 2)
			if("collapse")
				for(var/atom/movable/A as anything in box.contents.Copy())
					if(dq_latent_attempt_collapse(A))
						collapses++
						break
			if("materialize")
				if(L.latent_total > 0)
					var/list/made_now = L.latent_materialize_all()
					materializes += length(made_now)
					made += made_now
			if("move")
				var/list/real = list()
				for(var/atom/movable/A as anything in box.contents)
					real += A
				if(length(real))
					var/atom/movable/A = pick(real)
					var/obj/item/dq_latency_test_box/dest = pick(boxes)
					if(dest != box)
						A.forceMove(dest)
						dq_latent_touch(A)
			if("touch")
				for(var/atom/movable/A as anything in box.contents)
					dq_latent_touch(A)
		if(!check_conservation(boxes, "step [step] ([op])"))
			break

	TEST_ASSERT(collapses > 0, "the fuzz should have collapsed at least one item")
	TEST_ASSERT(materializes > 0, "the fuzz should have materialized at least one entry")
	check_conservation(boxes, "final")

/// Total real + latent count across every box must stay exactly 12 (4 boxes *
/// 3 items): nothing is lost or duplicated by any collapse/materialize/move.
/datum/unit_test/dq_latency_fuzz/proc/check_conservation(list/boxes, label)
	var/total = 0
	for(var/obj/item/dq_latency_test_box/box as anything in boxes)
		if(QDELETED(box))
			continue
		var/datum/ledger/L = dq_ledger(box)
		total += length(box.contents) + L.latent_total
	if(total != 12)
		TEST_FAIL("conservation broke at [label]: [total] items across all boxes, expected 12")
		return FALSE
	return TRUE

/datum/unit_test/dq_latency_fuzz/Destroy()
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	made = null
	return ..()

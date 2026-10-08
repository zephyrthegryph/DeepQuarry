// The latency policy (roadmap C10, doc/rewrite/containment.md §4.7): per-
// condition unit tests, the kill switch, a pin blocking
// collapse while an appearance-only representation keeps working without one,
// a thrash guard, and a fuzz over collapse/materialize/move/destroy cycles.

/// A plain latent-safe item, distinct from dq_containment_test so this file's
/// fuzz doesn't share fixtures (and mis-attribute a failure) with C1's.
/obj/item/dq_latency_test_item
	name = "latency test item"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "whetstone"
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 500)

/// A box with one internal, latent-contents slot (like a closet's interior,
/// C2/C5) but with a short idle delay so tests don't wait real time.
/obj/item/dq_latency_test_box
	name = "latency test box"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "toolbox"
	w_class = ITEMSIZE_NORMAL

/datum/om/relation/slot/dq_latency_test_interior
	holder = /obj/item/dq_latency_test_box
	slot_id = "dq_latency_interior"
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 10
	drop_policy = SLOT_DROP_SPILL
	exposure = SLOT_EXPOSURE_INTERNAL

/// A machinery-shaped holder with both an internals slot (eligible for the
/// sweep, like C6's real machine internals) and a stock slot (C9's own,
/// excluded per containment.md §4.7 "Rollout" since vending machines are
/// machinery too and can't be excluded by holder any more).
/obj/item/dq_latency_test_machine
	name = "latency test machine"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "toolbox"
	w_class = ITEMSIZE_NORMAL

// The real internals and stock slots (stock.dm), held by this test machine: the sweep's stock
// exclusion keys on CONTAINER_SLOT_STOCK, so the subtypes keep the production semantics.
/datum/om/relation/slot/machine_internals/dq_latency_test
	holder = /obj/item/dq_latency_test_machine
	is_default = TRUE

/datum/om/relation/slot/stock/dq_latency_test
	holder = /obj/item/dq_latency_test_machine

/// Which of can_be_latent()'s conditions refuses `A`, for failure messages.
/proc/dq_latency_explain(atom/movable/A)
	if(!A || QDELETED(A) || !A.loc)
		return "gone or loc-less"
	var/list/why = list()
	if(!A.loc?.latent_contents_enabled())
		why += "holder has no latent_contents"
	if(!dq_latent_eligible(A.type))
		why += "type not latent-eligible"
	if(A.latent_explicitly_pinned())
		why += "explicitly pinned"
	if(isturf(A.loc))
		why += "on a turf"
	var/list/blockers = A.state_collapse_blockers(1, TRUE)
	if(length(blockers))
		why += "blockers: [jointext(blockers, "; ")]"
	var/list/nodes = list(A)
	state_collect_subtree(A, nodes)
	var/list/counts = state_internal_ref_counts(nodes, nodes.Copy())
	why += "internal refs one-pass [counts[1]] vs per-node [state_internal_refs(A, nodes.Copy())]"
	why += "idle [ELAPSED(A, latent_touched_at, CLOCK_WORLD)] of [A.loc?.latent_idle_delay_value()]"
	return jointext(why, ", ")

/// can_be_latent() asked from a test's Run(), which holds `A` in one local variable. Calling this
/// as src.latent_ok() moves Run()'s last-method-call reference onto the test datum, so the frames
/// above hold exactly that local and this argument.
/datum/unit_test/proc/latent_ok(atom/movable/A)
	return can_be_latent(A, 2)

/// dq_latent_attempt_collapse() asked the same way (see latent_ok()): Run() holds `A` in one
/// variable (a local or its loop variable).
/datum/unit_test/proc/collapse_now(atom/movable/A)
	return dq_latent_attempt_collapse(A, 2)

/// dq_latent_pinned() asked the same way (see latent_ok()).
/datum/unit_test/proc/pinned_now(atom/movable/A)
	return dq_latent_pinned(A, 2)

/datum/unit_test/proc/dq_latency_floor()
	for(var/turf/simulated/floor/T in world)
		if(!T.density && !(locate_within(T, /obj/item)) && !(locate_within(T, /obj/structure)))
			return T
	return null

/// Eligibility diagnostics are shared scratch; every test restores the values present at entry.
/datum/unit_test/proc/dq_latency_isolate_diagnostics()
	set_global("latency_last_ineligible", GLOB.latency_last_ineligible)
	set_global("latency_last_pin_reason", GLOB.latency_last_pin_reason)

// ---- Per-condition unit tests ----

/datum/unit_test/dq_latency_kill_switch

/datum/unit_test/dq_latency_kill_switch/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box) // build the ledger, register with the sweep
	refresh_flush() // a fresh atom sits in the refresh queue until it flushes: a reference the eligibility check would see
	item.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)

	set_config(/datum/config_entry/flag/latency_policy_enabled, FALSE)
	TEST_ASSERT(!latent_ok(item), "the kill switch must refuse collapse when off")
	set_config(/datum/config_entry/flag/latency_policy_enabled, TRUE)
	TEST_ASSERT(latent_ok(item), "an idle, unpinned, storable item should be latent-eligible once the switch is on ([dq_latency_explain(item)]): [GLOB.latency_last_ineligible]")
	qdel(box)

/datum/unit_test/dq_latency_idle_delay

/datum/unit_test/dq_latency_idle_delay/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	TEST_ASSERT(!latent_ok(item), "a freshly touched item must not be latent-eligible yet")
	item.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)
	TEST_ASSERT(latent_ok(item), "an item idle past the delay should be latent-eligible: [GLOB.latency_last_ineligible]")
	qdel(box)

/datum/unit_test/dq_latency_pin_blocks

/datum/unit_test/dq_latency_pin_blocks/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	item.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)
	TEST_ASSERT(latent_ok(item), "should be eligible before any pin: [GLOB.latency_last_ineligible]")
	item.latent_pin("test")
	TEST_ASSERT(!latent_ok(item), "an explicit pin must block collapse")
	TEST_ASSERT(pinned_now(item), "dq_latent_pinned must see the explicit pin")
	item.latent_unpin("test")
	TEST_ASSERT(latent_ok(item), "releasing the only pin should restore eligibility: [GLOB.latency_last_ineligible]")
	// A second, independent pin of the same reason must not unpin early.
	item.latent_pin("a")
	item.latent_pin("a")
	item.latent_unpin("a")
	TEST_ASSERT(pinned_now(item), "one of two pins released should still pin")
	item.latent_unpin("a")
	TEST_ASSERT(!pinned_now(item), "the last pin released should unpin")
	qdel(box)

/datum/unit_test/dq_latency_turf_pins

/datum/unit_test/dq_latency_turf_pins/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_item/item = new(floor)
	TEST_ASSERT(pinned_now(item), "an item sitting directly on a turf must be pinned (it's visibly rendered)")
	qdel(item)

/datum/unit_test/dq_latency_viewer_blocks

/datum/unit_test/dq_latency_viewer_blocks/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	dq_ledger(box)
	item.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)
	TEST_ASSERT(latent_ok(item), "should be eligible with no viewers: [GLOB.latency_last_ineligible]")
	LAZYADD(box.open_tguis, new /datum) // stand in for an open tgui/browse window
	TEST_ASSERT(!latent_ok(item), "an open window on the holder must block collapse")
	qdel(box.open_tguis[1])
	box.open_tguis = null
	TEST_ASSERT(latent_ok(item), "closing the window should restore eligibility: [GLOB.latency_last_ineligible]")
	qdel(box)

/// Rollout (containment.md §4.7): machine internals are eligible, the stock
/// slot is not, on the same holder -- proves the exclusion is per slot, not
/// per holder type, now that /obj/machinery sets latent_contents = TRUE.
/datum/unit_test/dq_latency_stock_slot_excluded

/datum/unit_test/dq_latency_stock_slot_excluded/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_machine/machine = new(floor)
	var/obj/item/dq_latency_test_item/part = new(machine)
	var/obj/item/dq_latency_test_item/product = new(floor)
	TEST_ASSERT(move_into(machine, CONTAINER_SLOT_STOCK, product), "the product should move into the stock slot")
	dq_ledger(machine)
	part.latent_touched_at = world.time - (machine?.latent_idle_delay_value() * 2)
	product.latent_touched_at = world.time - (machine?.latent_idle_delay_value() * 2)
	TEST_ASSERT(latent_ok(part), "an idle item in the internals slot should be latent-eligible: [GLOB.latency_last_ineligible]")
	TEST_ASSERT(!latent_ok(product), "an idle item in the stock slot must not be latent-eligible (C9 owns it)")
	qdel(machine)

/// Worn/held pin path (containment.md §4.7): equipped()/dropped() pin and
/// unpin, independent of whether mobs are latent_contents holders yet (C3
/// hasn't landed, so can_be_latent() never even reaches this for a worn
/// item today -- but the pin bookkeeping itself must already be correct so
/// nothing has to change here once C3 does).
/datum/unit_test/dq_latency_worn_held_pins

/datum/unit_test/dq_latency_worn_held_pins/Run()
	dq_latency_isolate_diagnostics()
	var/obj/holder = new()
	var/mob/living/carbon/human/H = new(holder)
	H.set_species(SPECIES_HUMAN)
	var/obj/item/dq_latency_test_item/item = new(holder)
	TEST_ASSERT(!pinned_now(item), "an unworn item should not be pinned")
	TEST_ASSERT(H.equip_to_slot_if_possible(item, SLOT_ID_HAND_L), "the item should equip into a hand")
	TEST_ASSERT(pinned_now(item), "a held item must be pinned")
	H.unEquip(item)
	TEST_ASSERT(!pinned_now(item), "dropping should release the pin")
	qdel(holder)

// ---- Collapse/materialize round trip, and the audit ----

/datum/unit_test/dq_latency_round_trip

/datum/unit_test/dq_latency_round_trip/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	var/datum/ledger/L = dq_ledger(box)
	item.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)
	TEST_ASSERT(latent_ok(item), "should be eligible: [GLOB.latency_last_ineligible]")
	var/before_type = item.type
	TEST_ASSERT(collapse_now(item), "the item should collapse under the policy")
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
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = new(floor)
	var/obj/item/dq_latency_test_item/item = new(box)
	var/datum/ledger/L = dq_ledger(box)
	item.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)
	collapse_now(item)
	var/list/things = L.latent_materialize_all()
	TEST_ASSERT_EQUAL(length(things), 1, "expected one materialized atom")
	var/atom/movable/remade = things[1]
	TEST_ASSERT(!latent_ok(remade), "a just-materialized atom must not be immediately eligible again (hysteresis)")
	qdel(box)

// ---- Fuzz: collapse/materialize/move/destroy cycles, conservation and parity ----

/datum/unit_test/dq_latency_fuzz
	/// The fuzz's boxes (filled at once by Run()). Items are not listed: a list holding them is an
	/// outside reference, and would keep every one from collapsing.
	var/list/made
	var/turf/floor
	var/collapses = 0
	var/materializes = 0

CAPABILITIES(/datum/unit_test/dq_latency_fuzz)
	owns_many(nameof(made))

/datum/unit_test/dq_latency_fuzz/Run()
	dq_latency_isolate_diagnostics()
	own_take_all(src, nameof(made))
	rel_set(src, nameof(floor), dq_latency_floor())
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/list/boxes = list()
	for(var/i in 1 to 4)
		var/obj/item/dq_latency_test_box/box = new(floor)
		rel_add(src, nameof(made), box)
		boxes += box
		dq_ledger(box)
		for(var/j in 1 to 3)
			new /obj/item/dq_latency_test_item(box)

	for(var/step in 1 to 150)
		var/op = pick("age", "collapse", "materialize", "move", "touch")
		fuzz_step(pick(boxes), op, boxes)
		if(!check_conservation(boxes, "step [step] ([op])"))
			break

	check_conservation(boxes, "final")
	var/fuzz_ok = collapses > 0 && materializes > 0
	// Boxes spill their contents when deleted: delete what they hold first.
	for(var/obj/item/dq_latency_test_box/box as anything in boxes)
		if(QDELETED(box))
			continue
		var/datum/ledger/fuzz_ledger = dq_ledger(box)
		if(fuzz_ledger.latent_total)
			fuzz_ledger.latent_materialize_all()
		for(var/atom/movable/A as anything in contents_of(box))
			qdel(A)
	if(!fuzz_ok)
		TEST_FAIL("the fuzz should have collapsed ([collapses]) and materialized ([materializes]) at least one item: [GLOB.latency_last_ineligible] / [GLOB.latent_last_refusal]")


/// One fuzz operation on `box`. Its own frame: Run()'s locals live for the whole proc, and a
/// list or variable there still naming an item is an outside reference that blocks collapse.
/datum/unit_test/dq_latency_fuzz/proc/fuzz_step(obj/item/dq_latency_test_box/box, op, list/boxes)
	var/datum/ledger/L = dq_ledger(box)
	switch(op)
		if("age")
			dq_latency_age_contents(box)
		if("collapse")
			if(dq_latency_fuzz_collapse_one(box))
				collapses++
		if("materialize")
			if(L.latent_total > 0)
				materializes += length(L.latent_materialize_all())
		if("move")
			dq_latency_fuzz_move_one(box, pick(boxes))
		if("touch")
			for(var/atom/movable/A as anything in contents_of(box))
				dq_latent_touch(A)

/// Tries to collapse one real item in `box` through the policy; TRUE if one collapsed.
/// This frame's loop holds each item as the sweep's does (LATENCY_SWEEP_FRAME_REFS).
/proc/dq_latency_fuzz_collapse_one(atom/box)
	for(var/atom/movable/A as anything in contents_of(box))
		if(dq_latent_attempt_collapse(A, 2))
			return TRUE
	return FALSE

/// Moves one random real item from `box` to `dest`.
/proc/dq_latency_fuzz_move_one(atom/box, atom/dest)
	if(dest == box || !length(box.contents))
		return
	var/atom/movable/A = pick(box.contents)
	A.forceMove(dest)
	dq_latent_touch(A)

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

/// The real sweep frame (the budgeted, time-capped periodic step) collapses an idle item nothing
/// else holds. The test keeps no reference to the item itself: a test-held local is an outside
/// reference the collapse check rightly refuses.
/datum/unit_test/dq_latency_sweep_collapses

/datum/unit_test/dq_latency_sweep_collapses/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	// Built in a helper: a frame that creates the item (new() calls its procs) keeps a reference.
	var/obj/item/dq_latency_test_box/box = dq_latency_new_box_with_item(floor)
	var/datum/ledger/L = dq_ledger(box)
	dq_latency_age_contents(box)
	var/list/saved = GLOB.latency_sweep_holders.Copy()
	GLOB.latency_sweep_holders.Cut()
	GLOB.latency_sweep_holders[box] = TRUE
	GLOB.latency_sweep.cursor = 0
	set_global("latency_last_ineligible", "")
	GLOB.latency_sweep.periodic_step(2 SECONDS)
	var/sweep_reason = GLOB.latency_last_ineligible
	set_global("latency_sweep_holders", saved)
	TEST_ASSERT_EQUAL(L.latent_total, 1, "the sweep should collapse the idle item: sweep said '[sweep_reason]', collapse said '[GLOB.latent_last_refusal]'")
	TEST_ASSERT_EQUAL(length(box.contents), 0, "the collapsed item is no longer real")
	qdel(box)

/// Ages every real item in `box` past its idle delay without the caller holding one.
/proc/dq_latency_age_contents(atom/box)
	for(var/atom/movable/A as anything in contents_of(box))
		A.latent_touched_at = world.time - (box?.latent_idle_delay_value() * 2)




/// A test box holding one test item, made outside the caller's frame.
/proc/dq_latency_new_box_with_item(turf/floor)
	var/obj/item/dq_latency_test_box/box = new(floor)
	new /obj/item/dq_latency_test_item(box)
	return box

/// The sweep's reference credit covers only its own frame: one outside holder keeps the item real.
/datum/unit_test/dq_latency_sweep_outside_ref_blocks
	var/list/outside_holder

/datum/unit_test/dq_latency_sweep_outside_ref_blocks/Run()
	dq_latency_isolate_diagnostics()
	var/turf/floor = dq_latency_floor()
	TEST_ASSERT_NOTNULL(floor, "need a clean floor")
	var/obj/item/dq_latency_test_box/box = dq_latency_new_box_with_item(floor)
	var/datum/ledger/L = dq_ledger(box)
	outside_holder = box.contents.Copy()
	dq_latency_age_contents(box)
	var/list/saved = GLOB.latency_sweep_holders.Copy()
	GLOB.latency_sweep_holders.Cut()
	GLOB.latency_sweep_holders[box] = TRUE
	GLOB.latency_sweep.cursor = 0
	GLOB.latency_sweep.periodic_step(2 SECONDS)
	set_global("latency_sweep_holders", saved)
	TEST_ASSERT_EQUAL(L.latent_total, 0, "an item with an outside holder must stay real")
	TEST_ASSERT_EQUAL(length(box.contents), 1, "the held item is still in the box")
	outside_holder = null
	qdel(box)

/datum/type_metadata_registry/register_test_defaults()
	register(/obj/item/dq_containment_test/hooked, TYPE_META_SLOT_HOOKS, TRUE)
	register(/obj/item/dq_destroy_transaction_content_probe, TYPE_META_SLOT_HOOKS, TRUE)
	register(/obj/item/dq_destroy_transaction_mind_probe, TYPE_META_SLOT_HOOKS, TRUE)
	register(/obj/item/dq_latency_test_item, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/dq_latency_test_box, TYPE_META_LATENT_CONTENTS, TRUE)
	register(/obj/item/dq_latency_test_box, TYPE_META_LATENT_IDLE_DELAY, 1 SECONDS)
	register(/obj/item/dq_latency_test_machine, TYPE_META_LATENT_CONTENTS, TRUE)
	register(/obj/item/dq_latency_test_machine, TYPE_META_LATENT_IDLE_DELAY, 1 SECONDS)
	register(/obj/item/dq_diag_init_refuser, TYPE_META_LATENT_SAFE, FALSE)

GLOBAL_VAR_INIT(dq_type_metadata_constructed, 0)

/obj/dq_type_metadata_probe
/obj/dq_type_metadata_probe/Initialize(mapload)
	. = ..()
	GLOB.dq_type_metadata_constructed++
/obj/dq_type_metadata_probe/sub
/obj/dq_type_metadata_probe/sub/leaf
/obj/dq_type_metadata_redirect
	parent_type = /obj/dq_type_metadata_probe

/datum/unit_test/dq_type_metadata_inheritance/Run()
	set_global("dq_type_metadata_constructed", 0)
	var/datum/type_metadata_registry/R = allocate(/datum/type_metadata_registry)
	R.register(/obj/dq_type_metadata_probe, TYPE_META_LATENT_SAFE, TRUE)
	R.register(/obj/dq_type_metadata_probe, TYPE_META_LATENT_IDLE_DELAY, 3 SECONDS)
	R.register(/obj/dq_type_metadata_probe/sub, TYPE_META_LATENT_SAFE, FALSE)
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_probe, TYPE_META_LATENT_SAFE, FALSE), TRUE, "An explicit type declaration is readable without an instance")
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_probe/sub/leaf, TYPE_META_LATENT_SAFE, TRUE), FALSE, "An explicit false subtype declaration overrides its true ancestor")
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_probe/sub/leaf, TYPE_META_LATENT_IDLE_DELAY, 2 MINUTES), 3 SECONDS, "Other keys continue to inherit through the false override")
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_redirect, TYPE_META_LATENT_SAFE, FALSE), TRUE, "Inheritance follows actual parent_type rather than path prefixes")
	TEST_ASSERT_EQUAL(R.value(/obj, TYPE_META_SLOT_HOOKS, FALSE), FALSE, "An undeclared type uses the supplied default")
	TEST_ASSERT_EQUAL(GLOB.dq_type_metadata_constructed, 0, "Dry type queries never allocate or initialize a content prototype")
	TEST_ASSERT(latent_type_safe(/obj/item/paper), "Production registrations preserve a latent-safe parent")
	TEST_ASSERT(!latent_type_safe(/obj/item/paper/sticky), "Production registrations preserve its explicit unsafe subtype")

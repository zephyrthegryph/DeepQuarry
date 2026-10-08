// The destroy transaction (roadmap L track, doc/rewrite/lifecycle.md §8):
// phase ordering, children-first nesting, mind pre-order, LEDGER_MOVE_DESTROYING,
// generic occupant-style ejection, pair symmetry and re-entrancy, no nullspace
// parking, a mass-delete leak check, and per-phase timing. Written now, run
// once the testing freeze lifts (doc/rewrite/lifecycle.md, ledger-joint L1/L2/L3).
//
// Not to be confused with dq_lifecycle_tests.dm (roadmap L2, doc/rewrite/
// state.md section 6): that file's "lifecycle" is the latent-safety
// Initialize()/materialize() sandbox, an unrelated, pre-existing L2.

// ---- Shared log (signal handlers and hook overrides can't close over
// unit-test locals, so they all append to this instead; each test clears it
// first and reads it back at the end). ----
GLOBAL_LIST_EMPTY(dq_destroy_transaction_log)

/proc/dq_destroy_transaction_log_reset()
	GLOB.dq_destroy_transaction_log = list()

/proc/dq_destroy_transaction_log(entry)
	GLOB.dq_destroy_transaction_log += entry

// ---- Fixtures: phase ordering ----

/// A one-slot holder whose every overridable phase hook logs its name.
/// slot "main" is plain SPILL, so on_unslotted() logging happens in phase 3.
/obj/item/dq_destroy_transaction_phase_probe
	name = "phase probe"
	w_class = ITEMSIZE_NORMAL
	var/datum/dq_destroy_transaction_owned_child/child

CAPABILITIES(/obj/item/dq_destroy_transaction_phase_probe)
	owns_one(nameof(child), /datum/dq_destroy_transaction_owned_child)

/obj/item/dq_destroy_transaction_phase_probe/Initialize(mapload)
	. = ..()
	observe(src, /datum/notice/qdeleting, src, then(PROC_REF(on_qdeleting)))
	rel_set(src, nameof(child), new /datum/dq_destroy_transaction_owned_child(src))

/obj/item/dq_destroy_transaction_phase_probe/proc/on_qdeleting(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	dq_destroy_transaction_log("guard")

/obj/item/dq_destroy_transaction_phase_probe/lifecycle_unbind()
	. = ..()
	dq_destroy_transaction_log("unbind")

/obj/item/dq_destroy_transaction_phase_probe/lifecycle_dematerialize()
	. = ..()
	dq_destroy_transaction_log("dematerialize")


/obj/item/dq_destroy_transaction_phase_probe/destroy_effects()
	var/static/datum/destroy_effects_data/dq_destroy_transaction_logging_effects/data = new
	return data

/obj/item/dq_destroy_transaction_phase_probe/on_destroy(force)
	dq_destroy_transaction_log("destroy")
	..()

/datum/om/relation/slot/dq_destroy_transaction_probe_main
	holder = /obj/item/dq_destroy_transaction_phase_probe
	slot_id = "main"
	is_default = TRUE
	drop_policy = SLOT_DROP_SPILL

/// Sits in the probe's "main" slot; logs "contents" from on_unslotted(), the
/// phase-3 removal, and records whether LEDGER_MOVE_DESTROYING was set.
/obj/item/dq_destroy_transaction_content_probe
	name = "content probe"
	w_class = ITEMSIZE_SMALL
	var/saw_destroying_flag = FALSE
	var/loc_when_unslotted

/obj/item/dq_destroy_transaction_content_probe/on_unslotted(atom/holder, slot_id, flags = 0)
	dq_destroy_transaction_log("contents")
	saw_destroying_flag = (flags & LEDGER_MOVE_DESTROYING) ? TRUE : FALSE
	loc_when_unslotted = loc // doMove() already committed `loc =` before note_exit/on_unslotted runs

/// An owned child (declared owns_one on the probe): its own Destroy() logs "links" (phase 4 deletes it).
/datum/dq_destroy_transaction_owned_child

/datum/dq_destroy_transaction_owned_child/on_destroy(force)
	dq_destroy_transaction_log("links")
	..()

/// destroy_effects() data whose apply() logs "effects" before doing the
/// (harmless, since there's no turf work needed for this assertion) base work.
/datum/destroy_effects_data/dq_destroy_transaction_logging_effects

/datum/destroy_effects_data/dq_destroy_transaction_logging_effects/apply(datum/D)
	dq_destroy_transaction_log("effects")
	return ..()

// ---- Fixtures: REL_PAIR ----

/datum/dq_destroy_transaction_pair_fixture
	var/datum/dq_destroy_transaction_pair_fixture/partner

/datum/dq_destroy_transaction_pair_fixture/relations()
	. = ..()
	. += rel_one(nameof(partner), back = nameof(/datum/dq_destroy_transaction_pair_fixture::partner))

// ---- Tests: phase ordering ----

/datum/unit_test/dq_destroy_transaction_phase_order

/datum/unit_test/dq_destroy_transaction_phase_order/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_phase_probe/probe = allocate(/obj/item/dq_destroy_transaction_phase_probe, T)
	var/obj/item/dq_destroy_transaction_content_probe/content = allocate(/obj/item/dq_destroy_transaction_content_probe, T)
	TEST_ASSERT(move_into(probe, "main", content), "content probe into the phase probe's slot")

	dq_destroy_transaction_log_reset()
	qdel(probe)

	var/list/log = GLOB.dq_destroy_transaction_log
	// "contents" (the content probe's on_unslotted) is folded in among these
	// via phase 3; check every phase we can hook fired, in the declared order.
	var/list/expected = list("guard", "unbind", "dematerialize", "contents", "destroy", "links", "effects")
	TEST_ASSERT_EQUAL(jointext(log, ","), jointext(expected, ","), "every hookable phase fired, in doc/rewrite/lifecycle.md's order")
	TEST_ASSERT(content.saw_destroying_flag, "the phase-3 removal carried LEDGER_MOVE_DESTROYING")
	TEST_ASSERT_EQUAL(content.loc_when_unslotted, T, "loc was already the drop turf when on_unslotted fired -- no nullspace parking")

/// The same removal outside a destroy transaction must NOT carry
/// LEDGER_MOVE_DESTROYING -- the flag means "the transaction is the mover",
/// not "any forced move".
/datum/unit_test/dq_destroy_transaction_destroying_flag_scoped

/datum/unit_test/dq_destroy_transaction_destroying_flag_scoped/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_phase_probe/probe = allocate(/obj/item/dq_destroy_transaction_phase_probe, T)
	var/obj/item/dq_destroy_transaction_content_probe/content = allocate(/obj/item/dq_destroy_transaction_content_probe, T)
	TEST_ASSERT(move_into(probe, "main", content), "content probe into the phase probe's slot")

	TEST_ASSERT(probe.slot_remove(content, T), "an ordinary slot_remove, not a destroy transaction")
	TEST_ASSERT(!content.saw_destroying_flag, "and it did not carry LEDGER_MOVE_DESTROYING")

// ---- Tests: children-first nested resolution ----

/obj/item/dq_destroy_transaction_nest_outer
	name = "nesting outer"
	w_class = ITEMSIZE_NORMAL

/datum/om/relation/slot/dq_destroy_transaction_nest_outer_slot
	holder = /obj/item/dq_destroy_transaction_nest_outer
	slot_id = "child_holder"
	is_default = TRUE
	drop_policy = SLOT_DROP_DELETE

/obj/item/dq_destroy_transaction_nest_inner
	name = "nesting inner"
	w_class = ITEMSIZE_SMALL

/obj/item/dq_destroy_transaction_nest_inner/on_destroy(force)
	dq_destroy_transaction_log("inner-destroy")
	..()

/datum/om/relation/slot/dq_destroy_transaction_nest_inner_slot
	holder = /obj/item/dq_destroy_transaction_nest_inner
	slot_id = "grandchild"
	is_default = TRUE
	drop_policy = SLOT_DROP_SPILL

/datum/unit_test/dq_destroy_transaction_children_first_nested

/datum/unit_test/dq_destroy_transaction_children_first_nested/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_nest_outer/outer = allocate(/obj/item/dq_destroy_transaction_nest_outer, T)
	var/obj/item/dq_destroy_transaction_nest_inner/inner = allocate(/obj/item/dq_destroy_transaction_nest_inner, T)
	var/obj/item/dq_containment_test/grandchild = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(move_into(outer, null, inner), "inner into outer")
	TEST_ASSERT(move_into(inner, null, grandchild), "grandchild into inner")

	dq_destroy_transaction_log_reset()
	qdel(outer)

	TEST_ASSERT(QDELETED(inner), "outer's DELETE policy deleted inner")
	TEST_ASSERT_EQUAL(grandchild.loc, T, "inner's own SPILL policy released the grandchild before inner itself finished dying")
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_destroy_transaction_log, ","), "inner-destroy", "inner ran its whole transaction (spilling the grandchild in its own phase 3) before outer's phase 3 loop moved on")

// ---- Tests: mind pre-order (phase 0.5) ----

/// A minimal 3-level tree (body > head > brain), each declaring its own
/// mind slot -- proving the generic pre-order walk, without any real body
/// plan (DQ Medical, O2, not landed here).
/obj/item/dq_destroy_transaction_mind_level
	name = "mind level"
	w_class = ITEMSIZE_NORMAL
	var/level_name

/datum/om/relation/slot/dq_destroy_transaction_mind_slot
	holder = /obj/item/dq_destroy_transaction_mind_level
	slot_id = "mind"
	is_mind_slot = TRUE
	drop_policy = SLOT_DROP_SPILL

/datum/om/relation/slot/dq_destroy_transaction_mind_body_slot
	holder = /obj/item/dq_destroy_transaction_mind_level
	slot_id = "body"
	is_default = TRUE
	drop_policy = SLOT_DROP_DELETE

/// Occupies a level's mind slot; logs its level name and whether the level
/// still had a loc (fully registered) when it left.
/obj/item/dq_destroy_transaction_mind_probe
	name = "mind probe"
	w_class = ITEMSIZE_TINY
	var/still_registered

/obj/item/dq_destroy_transaction_mind_probe/on_unslotted(atom/holder, slot_id, flags = 0)
	if(istype(holder, /obj/item/dq_destroy_transaction_mind_level))
		var/obj/item/dq_destroy_transaction_mind_level/level = holder
		dq_destroy_transaction_log(level.level_name)
	// QDELETED(holder) is already true here by design (phase 0 marks it); "valid" means it
	// is still placed in the world, which phase 3 would undo.
	still_registered = !!holder.loc

/datum/unit_test/dq_destroy_transaction_mind_pre_order

/datum/unit_test/dq_destroy_transaction_mind_pre_order/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_mind_level/body = allocate(/obj/item/dq_destroy_transaction_mind_level, T)
	body.level_name = "body"
	var/obj/item/dq_destroy_transaction_mind_level/head = allocate(/obj/item/dq_destroy_transaction_mind_level, T)
	head.level_name = "head"
	var/obj/item/dq_destroy_transaction_mind_level/brain = allocate(/obj/item/dq_destroy_transaction_mind_level, T)
	brain.level_name = "brain"
	var/obj/item/dq_destroy_transaction_mind_probe/body_mind = allocate(/obj/item/dq_destroy_transaction_mind_probe, T)
	var/obj/item/dq_destroy_transaction_mind_probe/head_mind = allocate(/obj/item/dq_destroy_transaction_mind_probe, T)
	var/obj/item/dq_destroy_transaction_mind_probe/brain_mind = allocate(/obj/item/dq_destroy_transaction_mind_probe, T)

	TEST_ASSERT(move_into(body, "body", head), "head into body")
	TEST_ASSERT(move_into(head, "body", brain), "brain into head")
	TEST_ASSERT(move_into(body, "mind", body_mind), "body's own mind occupant")
	TEST_ASSERT(move_into(head, "mind", head_mind), "head's own mind occupant")
	TEST_ASSERT(move_into(brain, "mind", brain_mind), "brain's own mind occupant")

	dq_destroy_transaction_log_reset()
	qdel(body)

	TEST_ASSERT_EQUAL(jointext(GLOB.dq_destroy_transaction_log, ","), "body,head,brain", "mind slots resolve pre-order: outermost (body) first, then head, then brain")
	TEST_ASSERT(body_mind.still_registered, "the body was still fully valid (had a loc) when its mind slot resolved")
	TEST_ASSERT(head_mind.still_registered, "the head was still valid and had a loc when its mind slot resolved -- phase 0.5 runs tree-wide before any DELETE in phase 3 tears the tree down")
	TEST_ASSERT(brain_mind.still_registered, "same for the brain, deepest in the tree")

// ---- Tests: generic occupant-style ejection (TRANSFER + resolver) ----

/obj/structure/dq_destroy_transaction_occupant_holder
	name = "occupant holder"
	anchored = TRUE

/datum/om/relation/slot/dq_destroy_transaction_occupant
	holder = /obj/structure/dq_destroy_transaction_occupant_holder
	slot_id = "occupant"
	is_default = TRUE
	exposure = SLOT_EXPOSURE_SEALED
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_TRANSFER

/datum/om/relation/slot/dq_destroy_transaction_occupant/drop_resolver(atom/holder, atom/movable/thing, atom/drop)
	// Occupant machines eject to a turf, not into whatever the holder itself
	// happens to be sitting in (containment.md §10, lifecycle.md §3).
	return get_turf(holder)

/datum/unit_test/dq_destroy_transaction_occupant_ejection

/datum/unit_test/dq_destroy_transaction_occupant_ejection/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/dq_destroy_transaction_occupant_holder/pod = allocate(/obj/structure/dq_destroy_transaction_occupant_holder, T)
	var/obj/item/dq_containment_test/occupant = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(move_into(pod, null, occupant), "occupant into the pod's sealed slot")

	qdel(pod)

	TEST_ASSERT_EQUAL(occupant.loc, T, "TRANSFER + drop_resolver() ejected the occupant to the pod's turf, not nullspace or nowhere")

// ---- Tests: REL_PAIR symmetry and re-entrancy ----

/datum/unit_test/dq_destroy_transaction_pair_symmetry

/datum/unit_test/dq_destroy_transaction_pair_symmetry/Run()
	var/datum/dq_destroy_transaction_pair_fixture/A = allocate(/datum/dq_destroy_transaction_pair_fixture)
	var/datum/dq_destroy_transaction_pair_fixture/B = allocate(/datum/dq_destroy_transaction_pair_fixture)
	rel_set(A, nameof(A.partner), B)
	TEST_ASSERT_EQUAL(A.partner, B, "linked")
	TEST_ASSERT_EQUAL(B.partner, A, "both ways")

	qdel(A)

	TEST_ASSERT_NULL(B.partner, "destroying A nulled B's side of the pair too (phase 4)")

/// A destroyed inside B's own transaction (B's /datum/om/event/qdeleting handler
/// qdels its partner) -- the relation teardown must not double-clear or crash when
/// the reciprocal side is already gone by the time phase 4 reaches it.
/datum/dq_destroy_transaction_reentrant_pair
	var/datum/dq_destroy_transaction_reentrant_pair/partner
	var/qdel_partner_on_signal = FALSE

/datum/dq_destroy_transaction_reentrant_pair/relations()
	. = ..()
	. += rel_one(nameof(partner), back = nameof(/datum/dq_destroy_transaction_reentrant_pair::partner))

/datum/dq_destroy_transaction_reentrant_pair/proc/watch()
	observe(src, /datum/notice/qdeleting, src, then(PROC_REF(on_qdeleting)))

/datum/dq_destroy_transaction_reentrant_pair/proc/on_qdeleting(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	if(qdel_partner_on_signal && partner && !QDELETED(partner))
		qdel(partner)

/datum/unit_test/dq_destroy_transaction_pair_reentrancy

/datum/unit_test/dq_destroy_transaction_pair_reentrancy/Run()
	var/datum/dq_destroy_transaction_reentrant_pair/A = allocate(/datum/dq_destroy_transaction_reentrant_pair)
	var/datum/dq_destroy_transaction_reentrant_pair/B = allocate(/datum/dq_destroy_transaction_reentrant_pair)
	rel_set(A, nameof(A.partner), B)
	A.watch()
	A.qdel_partner_on_signal = TRUE

	qdel(A)

	TEST_ASSERT(QDELETED(A), "A is gone")
	TEST_ASSERT(QDELETED(B), "B, qdel'd re-entrantly from A's own qdeleting hook, is gone too")
	TEST_ASSERT_NULL(A.partner, "A's own side is null (either its own phase 4, or B's phase 4 racing it, leaves no dangling ref)")

// ---- Tests: scrub (phase 8) catches a re-set after the links phase ----

/datum/dq_destroy_transaction_scrub_fixture
	var/datum/dq_destroy_transaction_pair_fixture/partner
	var/reset_after_links = FALSE

/datum/dq_destroy_transaction_scrub_fixture/relations()
	. = ..()
	. += rel_one(nameof(partner), back = nameof(/datum/dq_destroy_transaction_pair_fixture::partner))

/// Re-sets the fixture's declared pair var from phase 6 (effects), after phase 4
/// cleared it: only phase 8's scrub can null it again.
/datum/destroy_effects_data/dq_destroy_transaction_scrub_reset

/datum/destroy_effects_data/dq_destroy_transaction_scrub_reset/apply(datum/D)
	var/datum/dq_destroy_transaction_scrub_fixture/fixture = D
	rel_set(fixture, nameof(fixture.partner), new /datum/dq_destroy_transaction_pair_fixture)
	fixture.reset_after_links = TRUE
	return null

/datum/dq_destroy_transaction_scrub_fixture/destroy_effects()
	var/static/datum/destroy_effects_data/dq_destroy_transaction_scrub_reset/data = new
	return data

/datum/unit_test/dq_destroy_transaction_scrub_catches_leftover_reset

/datum/unit_test/dq_destroy_transaction_scrub_catches_leftover_reset/Run()
	var/datum/dq_destroy_transaction_scrub_fixture/fixture = allocate(/datum/dq_destroy_transaction_scrub_fixture)
	qdel(fixture)
	TEST_ASSERT(fixture.reset_after_links, "phase 6 re-set the pair var after phase 4 cleared it")
	TEST_ASSERT_NULL(fixture.partner, "phase 8 nulled the declared pair var re-set after the links phase")

// ---- Tests: mass delete, no leaks ----

/datum/unit_test/dq_destroy_transaction_mass_delete_no_leak

/datum/unit_test/dq_destroy_transaction_mass_delete_no_leak/Run()
	var/turf/T = dq_containment_floor()
	var/list/holders = list()
	var/list/contents_items = list()
	for(var/i in 1 to 100)
		var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
		var/obj/item/dq_containment_test/wood/item = allocate(/obj/item/dq_containment_test/wood, T)
		TEST_ASSERT(move_into(box, "main", item), "item [i] into its box")
		holders += box
		contents_items += item

	for(var/obj/item/dq_containment_box/box as anything in holders)
		qdel(box)

	for(var/obj/item/dq_containment_box/box as anything in holders)
		TEST_ASSERT(QDELETED(box), "every holder in the batch is gone")
	for(var/obj/item/dq_containment_test/wood/item as anything in contents_items)
		TEST_ASSERT_EQUAL(item.loc, T, "every item spilled to the turf, none stuck referencing a dead holder")
		TEST_ASSERT(!QDELETED(item), "and none were accidentally deleted with their box")

// ---- Tests: per-phase timing ----

/datum/unit_test/dq_destroy_transaction_phase_timing_recorded

/datum/unit_test/dq_destroy_transaction_phase_timing_recorded/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_test/thing = allocate(/obj/item/dq_containment_test, T)
	qdel(thing)

	var/datum/qdel_item/info = SSgarbage.items[/obj/item/dq_containment_test]
	TEST_ASSERT_NOTNULL(info, "qdel recorded stats for the type")
	TEST_ASSERT_NOTNULL(info.phase_ms, "and per-phase timing (doc/rewrite/lifecycle.md §8)")
	TEST_ASSERT_NOTNULL(info.phase_ms[LIFECYCLE_PHASE_DESTROY], "phase 7 (leftover Destroy()) was timed")

// ---- Tests: batched destroy (code/datums/lifecycle/batch.dm, init_and_turfs.md §4.4) ----

/// Logs every move onto a turf, so a test can tell "deleted without moving".
/obj/item/dq_containment_test/wood/dq_batch_probe

/obj/item/dq_containment_test/wood/dq_batch_probe/Moved()
	. = ..()
	if(isturf(loc))
		dq_destroy_transaction_log("moved:[REF(src)]")

/datum/unit_test/dq_destroy_batch_doomed_contents_not_moved

/datum/unit_test/dq_destroy_batch_doomed_contents_not_moved/Run()
	var/turf/T = dq_containment_floor()
	var/list/boxes = list()
	var/list/items = list()
	for(var/i in 1 to 20)
		var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
		var/obj/item/dq_containment_test/wood/dq_batch_probe/item = allocate(/obj/item/dq_containment_test/wood/dq_batch_probe, T)
		TEST_ASSERT(move_into(box, "main", item), "item [i] into its box")
		boxes += box
		items += item
	dq_destroy_transaction_log_reset()

	// The turf is doomed: everything on it, and everything that would spill onto it, goes.
	var/destroyed = qdel_batch(null, list(T))

	TEST_ASSERT(destroyed >= 40, "the batch destroyed every box and item (got [destroyed])")
	for(var/obj/item/dq_containment_box/box as anything in boxes)
		TEST_ASSERT(QDELETED(box), "every box is gone")
	for(var/obj/item/dq_containment_test/wood/dq_batch_probe/item as anything in items)
		TEST_ASSERT(QDELETED(item), "every item went with its box")
	TEST_ASSERT_EQUAL(length(GLOB.dq_destroy_transaction_log), 0, "no item was moved onto the doomed turf first")
	TEST_ASSERT_NULL(GLOB.dq_destroy_batch, "no batch left running")

/datum/unit_test/dq_destroy_batch_spills_to_surviving_turf

/datum/unit_test/dq_destroy_batch_spills_to_surviving_turf/Run()
	var/turf/T = dq_containment_floor()
	var/list/boxes = list()
	var/list/items = list()
	for(var/i in 1 to 10)
		var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
		var/obj/item/dq_containment_test/wood/item = allocate(/obj/item/dq_containment_test/wood, T)
		TEST_ASSERT(move_into(box, "main", item), "item [i] into its box")
		boxes += box
		items += item

	qdel_batch(boxes)

	for(var/obj/item/dq_containment_box/box as anything in boxes)
		TEST_ASSERT(QDELETED(box), "every box is gone")
	for(var/obj/item/dq_containment_test/wood/item as anything in items)
		TEST_ASSERT(!QDELETED(item), "contents whose drop survives are not doomed")
		TEST_ASSERT_EQUAL(item.loc, T, "they spilled to the turf as usual")

/datum/unit_test/dq_destroy_batch_edges_dropped

/datum/unit_test/dq_destroy_batch_edges_dropped/Run()
	var/datum/dq_destroy_transaction_pair_fixture/A = allocate(/datum/dq_destroy_transaction_pair_fixture)
	var/datum/dq_destroy_transaction_pair_fixture/B = allocate(/datum/dq_destroy_transaction_pair_fixture)
	var/datum/dq_destroy_transaction_pair_fixture/C = allocate(/datum/dq_destroy_transaction_pair_fixture)
	var/datum/dq_destroy_transaction_pair_fixture/D = allocate(/datum/dq_destroy_transaction_pair_fixture)
	rel_set(A, nameof(A.partner), B)
	rel_set(C, nameof(C.partner), D)

	// A and B are doomed together; C is doomed with its partner D surviving.
	qdel_batch(list(A, B, C))

	TEST_ASSERT(QDELETED(A) && QDELETED(B) && QDELETED(C), "the set is gone")
	TEST_ASSERT_NULL(A.partner, "a doomed pair is dropped")
	TEST_ASSERT_NULL(B.partner, "on both sides")
	TEST_ASSERT(!QDELETED(D), "the surviving partner lives")
	TEST_ASSERT_NULL(D.partner, "and its side of an edge out of the set is still cleared")

/datum/unit_test/dq_destroy_batch_collecting_scope

/datum/unit_test/dq_destroy_batch_collecting_scope/Run()
	var/turf/T = dq_containment_floor()
	var/list/things = list()
	for(var/i in 1 to 10)
		things += allocate(/obj/item/dq_containment_test, T)

	dq_destroy_collect_begin()
	for(var/obj/item/dq_containment_test/thing as anything in things)
		qdel(thing)
	for(var/obj/item/dq_containment_test/thing as anything in things)
		TEST_ASSERT(QDELETED(thing), "marked first: QDELETED as soon as qdel() defers it")
		TEST_ASSERT_EQUAL(thing.gc_destroyed, GC_BATCH_DOOMED, "and doomed, not yet destroyed")
	var/destroyed = dq_destroy_collect_end()

	TEST_ASSERT_EQUAL(destroyed, 10, "closing the scope ran one batch over everything collected")
	for(var/obj/item/dq_containment_test/thing as anything in things)
		TEST_ASSERT(thing.gc_destroyed != GC_BATCH_DOOMED, "every transaction ran")
		TEST_ASSERT_NULL(thing.loc, "and every thing left its turf")
	TEST_ASSERT_EQUAL(GLOB.dq_destroy_collect_depth, 0, "the scope is closed")

// Observe the actual nested-ledger cleanup position without replacing disposal.
/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_order

/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_order/ownership_field_disposed(var_name)
	if(var_name == nameof(forensic_data))
		dq_destroy_transaction_log(containment_ledger() ? "ledger-before-forensic-hook" : "ledger-missing-before-forensic-hook")
	. = ..()
	if(var_name == nameof(light))
		dq_destroy_transaction_log(containment_ledger() ? "ledger-survives-light-hook" : "ledger-cleared-before-light-hook")

/datum/unit_test/dq_destroy_transaction_runtime_ledger_order

/datum/unit_test/dq_destroy_transaction_runtime_ledger_order/Run()
	var/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_order/probe = allocate(/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_order, dq_containment_floor())
	var/datum/ledger/before = probe.containment_ledger()
	var/datum/rx_state/before_state = probe.rx
	TEST_ASSERT_EQUAL(dq_ledger_peek(probe), before, "ledger peek preserves the initialized ledger identity")
	TEST_ASSERT_EQUAL(probe.rx, before_state, "ledger peek does not allocate a new runtime record")
	var/datum/ledger/L = dq_ledger(probe)
	TEST_ASSERT(L, "the real inherited slot builds a ledger")
	var/datum/rx_state/S = probe.rx
	TEST_ASSERT_EQUAL(owner_of(L), S, "runtime record is the declared ledger owner")
	var/list/saved_log = GLOB.dq_destroy_transaction_log
	dq_destroy_transaction_log_reset()
	qdel(probe)
	var/list/ledger_log = GLOB.dq_destroy_transaction_log
	GLOB.dq_destroy_transaction_log = saved_log
	TEST_ASSERT(QDELETED(L), "holder disposal deletes the nested owned ledger")
	TEST_ASSERT_NULL(S.containment_ledger, "runtime ownership releases the disposed ledger")
	TEST_ASSERT_NULL(probe.rx, "holder disposal detaches runtime state")
	TEST_ASSERT("ledger-before-forensic-hook" in ledger_log, "ledger remains live through preceding forensic cleanup")
	TEST_ASSERT("ledger-cleared-before-light-hook" in ledger_log, "ledger is cleared before following light cleanup")

/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_abort

/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_abort/on_destroy(force)
	..()
	CRASH("runtime ledger abort fixture")

/datum/unit_test/dq_destroy_transaction_runtime_ledger_abort

/datum/unit_test/dq_destroy_transaction_runtime_ledger_abort/Run()
	var/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_abort/probe = allocate(/obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_abort, dq_containment_floor())
	var/datum/ledger/L = dq_ledger(probe)
	TEST_ASSERT(L, "real slot initializes ledger before aborted disposal")
	var/datum/rx_state/S = probe.rx
	var/list/saved_log = GLOB.dq_destroy_transaction_log
	var/list/saved_capture = GLOB.dq_caught_capture
	GLOB.dq_destroy_transaction_log = list()
	GLOB.dq_caught_capture = list()
	qdel(probe)
	var/list/capture = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = saved_capture
	GLOB.dq_destroy_transaction_log = saved_log
	TEST_ASSERT(dq_diag_capture_has(capture, "destroy transaction of /obj/item/dq_destroy_transaction_phase_probe/runtime_ledger_abort"), "real on_destroy fault exercises aborted lifecycle")
	TEST_ASSERT(QDELETED(probe), "aborted holder still reaches deletion")
	TEST_ASSERT(QDELETED(L), "abort disposes declared runtime-owned ledger")
	TEST_ASSERT_NULL(S.containment_ledger, "abort clears ledger ownership field")
	TEST_ASSERT_NULL(probe.rx, "abort detaches native runtime record")

// Reuse e1_solo's real declared holder-destroy hook as the observation.
/obj/e1_fixture/late_destroy_abort

/obj/e1_fixture/late_destroy_abort/destroy_effects()
	var/static/datum/destroy_effects_data/dq_late_destroy_abort/data = new
	return data

/datum/destroy_effects_data/dq_late_destroy_abort

/datum/destroy_effects_data/dq_late_destroy_abort/apply(datum/D)
	CRASH("late destroy effects abort fixture")

/datum/unit_test/dq_destroy_transaction_late_abort_hook_once

/datum/unit_test/dq_destroy_transaction_late_abort_hook_once/Run()
	var/obj/e1_fixture/late_destroy_abort/probe = allocate(/obj/e1_fixture/late_destroy_abort, dq_containment_floor())
	var/list/saved_log = GLOB.e1_log
	var/list/saved_capture = GLOB.dq_caught_capture
	GLOB.e1_log = list()
	GLOB.dq_caught_capture = list()
	qdel(probe)
	var/list/capture = GLOB.dq_caught_capture
	var/list/hook_log = GLOB.e1_log
	GLOB.dq_caught_capture = saved_capture
	GLOB.e1_log = saved_log
	var/hook_count = 0
	for(var/entry in hook_log)
		if(entry == "holder_destroy:/obj/e1_fixture/late_destroy_abort")
			hook_count++
	TEST_ASSERT(dq_diag_capture_has(capture, "destroy transaction of /obj/e1_fixture/late_destroy_abort"), "actual effects fault exercises late aborted cleanup")
	TEST_ASSERT(QDELETED(probe), "late-aborted holder reaches deletion")
	TEST_ASSERT_EQUAL(hook_count, 1, "completed declared destroy hook is not repeated after a later phase faults")
	TEST_ASSERT_NULL(probe.rx, "late abort retains completed runtime teardown")

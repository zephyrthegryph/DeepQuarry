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

/obj/item/dq_destroy_transaction_phase_probe/Initialize(mapload)
	. = ..()
	RegisterSignal(src, COMSIG_QDELETING, PROC_REF(on_qdeleting))
	child = new(src)

/obj/item/dq_destroy_transaction_phase_probe/proc/on_qdeleting(datum/source, force)
	SIGNAL_HANDLER
	dq_destroy_transaction_log("guard")

/obj/item/dq_destroy_transaction_phase_probe/lifecycle_unbind()
	dq_destroy_transaction_log("unbind")

/obj/item/dq_destroy_transaction_phase_probe/lifecycle_dematerialize()
	dq_destroy_transaction_log("dematerialize")

/obj/item/dq_destroy_transaction_phase_probe/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_destroy_transaction_probe_main)
	return types

/obj/item/dq_destroy_transaction_phase_probe/declared_owned_vars()
	var/static/list/vars = list("child")
	return vars

/obj/item/dq_destroy_transaction_phase_probe/destroy_effects()
	var/static/datum/destroy_effects_data/dq_destroy_transaction_logging_effects/data = new
	return data

/obj/item/dq_destroy_transaction_phase_probe/Destroy()
	dq_destroy_transaction_log("destroy")
	return ..()

/datum/slot_def/dq_destroy_transaction_probe_main
	id = "main"
	is_default = TRUE
	drop_policy = SLOT_DROP_SPILL

/// Sits in the probe's "main" slot; logs "contents" from on_unslotted(), the
/// phase-3 removal, and records whether LEDGER_MOVE_DESTROYING was set.
/obj/item/dq_destroy_transaction_content_probe
	name = "content probe"
	w_class = ITEMSIZE_SMALL
	has_slot_hooks = TRUE
	var/saw_destroying_flag = FALSE
	var/loc_when_unslotted

/obj/item/dq_destroy_transaction_content_probe/on_unslotted(atom/holder, slot_id, flags = 0)
	dq_destroy_transaction_log("contents")
	saw_destroying_flag = (flags & LEDGER_MOVE_DESTROYING) ? TRUE : FALSE
	loc_when_unslotted = loc // doMove() already committed `loc =` before note_exit/on_unslotted runs

/// A REF_OWNED child: its own Destroy() logs "links" (phase 4 deletes it).
/datum/dq_destroy_transaction_owned_child

/datum/dq_destroy_transaction_owned_child/Destroy()
	dq_destroy_transaction_log("links")
	return ..()

/// destroy_effects() data whose apply() logs "effects" before doing the
/// (harmless, since there's no turf work needed for this assertion) base work.
/datum/destroy_effects_data/dq_destroy_transaction_logging_effects

/datum/destroy_effects_data/dq_destroy_transaction_logging_effects/apply(datum/D)
	dq_destroy_transaction_log("effects")
	return ..()

// ---- Fixtures: REF_PAIR ----

/datum/dq_destroy_transaction_pair_fixture
	var/datum/dq_destroy_transaction_pair_fixture/partner

/datum/dq_destroy_transaction_pair_fixture/declared_pair_vars()
	var/static/list/vars = list("partner" = "partner")
	return vars

// ---- Tests: phase ordering ----

/datum/unit_test/dq_destroy_transaction_phase_order

/datum/unit_test/dq_destroy_transaction_phase_order/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_phase_probe/probe = allocate(/obj/item/dq_destroy_transaction_phase_probe, T)
	var/obj/item/dq_destroy_transaction_content_probe/content = allocate(/obj/item/dq_destroy_transaction_content_probe, T)
	TEST_ASSERT(content.move_into(probe, "main"), "content probe into the phase probe's slot")

	dq_destroy_transaction_log_reset()
	qdel(probe)

	var/list/log = GLOB.dq_destroy_transaction_log
	// "contents" (the content probe's on_unslotted) is folded in among these
	// via phase 3; check every phase we can hook fired, in the declared order.
	var/list/expected = list("guard", "unbind", "dematerialize", "contents", "links", "effects", "destroy")
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
	TEST_ASSERT(content.move_into(probe, "main"), "content probe into the phase probe's slot")

	TEST_ASSERT(probe.slot_remove(content, T), "an ordinary slot_remove, not a destroy transaction")
	TEST_ASSERT(!content.saw_destroying_flag, "and it did not carry LEDGER_MOVE_DESTROYING")

// ---- Tests: children-first nested resolution ----

/obj/item/dq_destroy_transaction_nest_outer
	name = "nesting outer"
	w_class = ITEMSIZE_NORMAL

/obj/item/dq_destroy_transaction_nest_outer/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_destroy_transaction_nest_outer_slot)
	return types

/datum/slot_def/dq_destroy_transaction_nest_outer_slot
	id = "child_holder"
	is_default = TRUE
	drop_policy = SLOT_DROP_DELETE

/obj/item/dq_destroy_transaction_nest_inner
	name = "nesting inner"
	w_class = ITEMSIZE_SMALL

/obj/item/dq_destroy_transaction_nest_inner/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_destroy_transaction_nest_inner_slot)
	return types

/obj/item/dq_destroy_transaction_nest_inner/Destroy()
	dq_destroy_transaction_log("inner-destroy")
	return ..()

/datum/slot_def/dq_destroy_transaction_nest_inner_slot
	id = "grandchild"
	is_default = TRUE
	drop_policy = SLOT_DROP_SPILL

/datum/unit_test/dq_destroy_transaction_children_first_nested

/datum/unit_test/dq_destroy_transaction_children_first_nested/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_nest_outer/outer = allocate(/obj/item/dq_destroy_transaction_nest_outer, T)
	var/obj/item/dq_destroy_transaction_nest_inner/inner = allocate(/obj/item/dq_destroy_transaction_nest_inner, T)
	var/obj/item/dq_containment_test/grandchild = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(inner.move_into(outer), "inner into outer")
	TEST_ASSERT(grandchild.move_into(inner), "grandchild into inner")

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

/obj/item/dq_destroy_transaction_mind_level/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_destroy_transaction_mind_slot, /datum/slot_def/dq_destroy_transaction_mind_body_slot)
	return types

/datum/slot_def/dq_destroy_transaction_mind_slot
	id = "mind"
	is_mind_slot = TRUE
	drop_policy = SLOT_DROP_SPILL

/datum/slot_def/dq_destroy_transaction_mind_body_slot
	id = "body"
	is_default = TRUE
	drop_policy = SLOT_DROP_DELETE

/// Occupies a level's mind slot; logs its level name and whether the level
/// still had a loc (fully registered) when it left.
/obj/item/dq_destroy_transaction_mind_probe
	name = "mind probe"
	w_class = ITEMSIZE_TINY
	has_slot_hooks = TRUE
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

	TEST_ASSERT(head.move_into(body, "body"), "head into body")
	TEST_ASSERT(brain.move_into(head, "body"), "brain into head")
	TEST_ASSERT(body_mind.move_into(body, "mind"), "body's own mind occupant")
	TEST_ASSERT(head_mind.move_into(head, "mind"), "head's own mind occupant")
	TEST_ASSERT(brain_mind.move_into(brain, "mind"), "brain's own mind occupant")

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

/obj/structure/dq_destroy_transaction_occupant_holder/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_destroy_transaction_occupant)
	return types

/datum/slot_def/dq_destroy_transaction_occupant
	id = "occupant"
	is_default = TRUE
	exposure = SLOT_EXPOSURE_SEALED
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_TRANSFER

/datum/slot_def/dq_destroy_transaction_occupant/drop_resolver(atom/holder, atom/movable/thing, atom/drop)
	// Occupant machines eject to a turf, not into whatever the holder itself
	// happens to be sitting in (containment.md §10, lifecycle.md §3).
	return get_turf(holder)

/datum/unit_test/dq_destroy_transaction_occupant_ejection

/datum/unit_test/dq_destroy_transaction_occupant_ejection/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/dq_destroy_transaction_occupant_holder/pod = allocate(/obj/structure/dq_destroy_transaction_occupant_holder, T)
	var/obj/item/dq_containment_test/occupant = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(occupant.move_into(pod), "occupant into the pod's sealed slot")

	qdel(pod)

	TEST_ASSERT_EQUAL(occupant.loc, T, "TRANSFER + drop_resolver() ejected the occupant to the pod's turf, not nullspace or nowhere")

// ---- Tests: REF_PAIR symmetry and re-entrancy ----

/datum/unit_test/dq_destroy_transaction_pair_symmetry

/datum/unit_test/dq_destroy_transaction_pair_symmetry/Run()
	var/datum/dq_destroy_transaction_pair_fixture/A = allocate(/datum/dq_destroy_transaction_pair_fixture)
	var/datum/dq_destroy_transaction_pair_fixture/B = allocate(/datum/dq_destroy_transaction_pair_fixture)
	link_set(A, "partner", B, "partner")
	TEST_ASSERT_EQUAL(A.partner, B, "linked")
	TEST_ASSERT_EQUAL(B.partner, A, "both ways")

	qdel(A)

	TEST_ASSERT_NULL(B.partner, "destroying A nulled B's side of the pair too (phase 4)")

/// A destroyed inside B's own transaction (B's COMSIG_QDELETING handler
/// qdels its partner) -- link_clear() must not double-clear or crash when
/// the reciprocal side is already gone by the time phase 4 reaches it.
/datum/dq_destroy_transaction_reentrant_pair
	var/datum/dq_destroy_transaction_reentrant_pair/partner
	var/qdel_partner_on_signal = FALSE

/datum/dq_destroy_transaction_reentrant_pair/declared_pair_vars()
	var/static/list/vars = list("partner" = "partner")
	return vars

/datum/dq_destroy_transaction_reentrant_pair/proc/watch()
	RegisterSignal(src, COMSIG_QDELETING, PROC_REF(on_qdeleting))

/datum/dq_destroy_transaction_reentrant_pair/proc/on_qdeleting(datum/source, force)
	SIGNAL_HANDLER
	if(qdel_partner_on_signal && partner && !QDELETED(partner))
		qdel(partner)

/datum/unit_test/dq_destroy_transaction_pair_reentrancy

/datum/unit_test/dq_destroy_transaction_pair_reentrancy/Run()
	var/datum/dq_destroy_transaction_reentrant_pair/A = allocate(/datum/dq_destroy_transaction_reentrant_pair)
	var/datum/dq_destroy_transaction_reentrant_pair/B = allocate(/datum/dq_destroy_transaction_reentrant_pair)
	link_set(A, "partner", B, "partner")
	A.watch()
	A.qdel_partner_on_signal = TRUE

	qdel(A)

	TEST_ASSERT(QDELETED(A), "A is gone")
	TEST_ASSERT(QDELETED(B), "B, qdel'd re-entrantly from A's own COMSIG_QDELETING, is gone too")
	TEST_ASSERT_NULL(A.partner, "A's own side is null (either its own phase 4, or B's phase 4 racing it, leaves no dangling ref)")

// ---- Tests: scrub (phase 8) catches a leftover Destroy() re-set ----

/datum/dq_destroy_transaction_scrub_fixture
	var/datum/dq_destroy_transaction_pair_fixture/partner

/datum/dq_destroy_transaction_scrub_fixture/declared_pair_vars()
	var/static/list/vars = list("partner" = "partner")
	return vars

/datum/dq_destroy_transaction_scrub_fixture/Destroy()
	// Phase 4 already nulled `partner` (and the partner's own side) by the
	// time this runs (phase 7). Re-setting it here simulates a leftover
	// Destroy() body that still assigns a declared pair/owned var by hand --
	// phase 8 must null it again so nothing keeps this alive past its own death.
	partner = new /datum/dq_destroy_transaction_pair_fixture
	return ..()

/datum/unit_test/dq_destroy_transaction_scrub_catches_leftover_reset

/datum/unit_test/dq_destroy_transaction_scrub_catches_leftover_reset/Run()
	var/datum/dq_destroy_transaction_scrub_fixture/fixture = allocate(/datum/dq_destroy_transaction_scrub_fixture)
	qdel(fixture)
	TEST_ASSERT_NULL(fixture.partner, "phase 8 nulled the declared pair var Destroy() (phase 7) re-set")

// ---- Tests: mass delete, no leaks ----

/datum/unit_test/dq_destroy_transaction_mass_delete_no_leak

/datum/unit_test/dq_destroy_transaction_mass_delete_no_leak/Run()
	var/turf/T = dq_containment_floor()
	var/list/holders = list()
	var/list/contents_items = list()
	for(var/i in 1 to 100)
		var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
		var/obj/item/dq_containment_test/wood/item = allocate(/obj/item/dq_containment_test/wood, T)
		TEST_ASSERT(item.move_into(box, "main"), "item [i] into its box")
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

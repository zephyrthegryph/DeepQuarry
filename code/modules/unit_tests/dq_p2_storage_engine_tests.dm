// The engine pieces the storage conversion needed (doc/rewrite/engine_contracts.md, "Phase 2 additions"): passes() in a click, and a read of the contents
// of a holder that has not been asked yet inside a condition or an output. The fixtures are code/tests/engine/p2_storage_fixtures.dm.

/datum/unit_test/dq_p2_storage_engine
	abstract_type = /datum/unit_test/dq_p2_storage_engine

/datum/unit_test/dq_p2_storage_engine/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_p2_storage_engine/proc/run_gate()
	return

/// An op that passes and commits lets the next candidate run; one that does not pass is the only one that runs.
/datum/unit_test/dq_p2_storage_engine/passes_runs_the_next_candidate
/datum/unit_test/dq_p2_storage_engine/passes_runs_the_next_candidate/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/p2s_chain/chain = allocate(/obj/p2s_chain, run_loc_floor_bottom_left)
	var/obj/p2s_chain_stop/stop = allocate(/obj/p2s_chain_stop, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	test_click(H, chain, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(chain.first, 1, "the passing op ran")
	TEST_ASSERT_EQUAL(chain.second, 1, "and the next candidate ran after it")
	test_click(H, stop, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(stop.first, 1, "the op that does not pass ran")
	TEST_ASSERT_EQUAL(stop.second, 0, "and nothing ran after it")

/// An op that passes but is refused ran nothing, so nothing passes.
/datum/unit_test/dq_p2_storage_engine/a_refused_op_does_not_pass
/datum/unit_test/dq_p2_storage_engine/a_refused_op_does_not_pass/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/p2s_chain_refused/refused = allocate(/obj/p2s_chain_refused, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	test_click(H, refused, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(refused.first, 0, "the refused op ran nothing")
	TEST_ASSERT_EQUAL(refused.second, 0, "and passed nothing on")

/// Reading what a storage holds is not a write, even when the read is the first to ask and adopts contents that arrived without a move.
/datum/unit_test/dq_p2_storage_engine/ledger_read_in_a_condition_is_pure
/datum/unit_test/dq_p2_storage_engine/ledger_read_in_a_condition_is_pure/run_gate()
	var/obj/item/storage/box/B = allocate(/obj/item/storage/box, run_loc_floor_bottom_left)
	var/obj/item/p2_storage_probe/tiny/inside = new(B) // in the box with no move: the ledger has not seen it
	TEST_ASSERT_EQUAL(inside.loc, B, "the thing is in the box")
	GLOB.op_pure_violations.Cut()
	GLOB.op_pure_expected = TRUE
	op_pure_begin()
	var/total = storage_total(B)
	op_pure_end()
	GLOB.op_pure_expected = FALSE
	TEST_ASSERT_EQUAL(total, 1, "the read adopted the thing and counted it")
	TEST_ASSERT_EQUAL(length(GLOB.op_pure_violations), 0, "and wrote nothing a condition may not write")

/// A look that is the first to read the contents of a storage adopts them without the refresh finding its holder marking itself.
/datum/unit_test/dq_p2_storage_engine/first_look_adopting_contents_is_not_a_self_mark
/datum/unit_test/dq_p2_storage_engine/first_look_adopting_contents_is_not_a_self_mark/run_gate()
	GLOB.refresh_self_marks.Cut()
	var/obj/item/storage/fancy/crayons/box = allocate(/obj/item/storage/fancy/crayons, run_loc_floor_bottom_left)
	box.update_icon()
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(length(GLOB.refresh_self_marks), 0, "no refresh marked its own holder changed")
	TEST_ASSERT(length(box.held_things()) > 0, "the box holds its crayons")

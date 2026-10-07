// The phase-2 machine library (code/library/machine, code/library/access, code/engine/present) through fixture types
// (code/tests/engine/p2_fixtures.dm). The APC behaviour tests (dq_p2_apc_behaviour.dm) exercise the same pieces on a real machine.

/// Base: the kernel on its injected clock around the test, a clean driver after.
/datum/unit_test/dq_p2_lib
	abstract_type = /datum/unit_test/dq_p2_lib

/datum/unit_test/dq_p2_lib/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_p2_lib/proc/run_gate()
	return

/datum/unit_test/dq_p2_lib/proc/actor()
	return allocate(/mob/living/simple_mob/e0_fixture)

/// Clicks `target` with `held` and lets every tool wait run out.
/datum/unit_test/dq_p2_lib/proc/touch(mob/actor, atom/target, obj/item/held)
	var/datum/op_result/result = test_click(actor, target, held)
	test_time(10 SECONDS)
	return result

/// An ID card that opens the p2 box.
/datum/unit_test/dq_p2_lib/proc/box_id()
	var/obj/item/card/id/card = allocate(/obj/item/card/id)
	card.access = list(ACCESS_ENGINE_EQUIP)
	return card

// ---------------------------------------------------------------------------------------------------------------------
// maintenance_hatch(): the rules between the cover, the panel, the lock, the emag and the wires.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_lib/hatch_cover_and_panel

/datum/unit_test/dq_p2_lib/hatch_cover_and_panel/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/machinery/p2_box/B = allocate(/obj/machinery/p2_box)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	var/obj/item/tool/screwdriver/driver = allocate(/obj/item/tool/screwdriver)
	TEST_ASSERT(lock_locked(B), "the lock starts engaged (lock_at_start)")
	TEST_ASSERT(!cover_open(B, null) && !panel_open(B), "closed up")
	touch(M, B, driver)
	TEST_ASSERT(panel_open(B), "a screwdriver opens the panel with the cover closed")
	touch(M, B, crowbar)
	TEST_ASSERT(cover_open(B, null), "a crowbar opens the cover")
	touch(M, B, driver)
	TEST_ASSERT(!panel_open(B), "an open panel can always be closed, the cover open or not (intended_changes.md: the panel latch)")
	touch(M, B, crowbar)
	TEST_ASSERT(!cover_open(B, null), "the crowbar closes the cover")
	touch(M, B, driver)
	TEST_ASSERT(panel_open(B), "and the screwdriver opens the panel again")
	touch(M, B, driver)
	TEST_ASSERT(!panel_open(B), "and closes it")
	touch(M, B, crowbar)
	touch(M, B, driver)
	TEST_ASSERT(cover_open(B, null) && !panel_open(B), "with the cover open the panel does not open either")

/datum/unit_test/dq_p2_lib/hatch_lock_and_emag

/datum/unit_test/dq_p2_lib/hatch_lock_and_emag/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/machinery/p2_box/B = allocate(/obj/machinery/p2_box)
	var/obj/item/card/id/good = box_id()
	var/obj/item/card/id/bad = allocate(/obj/item/card/id)
	bad.access = list(ACCESS_CAPTAIN)
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	touch(M, B, bad)
	TEST_ASSERT(lock_locked(B), "a card without the access does not open the lock")
	touch(M, B, good)
	TEST_ASSERT(!lock_locked(B), "a card with it unlocks")
	touch(M, B, good)
	TEST_ASSERT(lock_locked(B), "and locks again")
	touch(M, B, crowbar)
	touch(M, B, good)
	TEST_ASSERT(lock_locked(B), "the lock does not move with the cover open")
	touch(M, B, emag)
	TEST_ASSERT_EQUAL(B.emag_ran, 0, "nor does an emag work with the cover open")
	touch(M, B, crowbar)
	var/uses = emag.uses
	touch(M, B, emag)
	TEST_ASSERT_EQUAL(B.emag_ran, 1, "an emag works closed up: its effect ran")
	TEST_ASSERT(emag_emagged(B), "the emag key is set")
	TEST_ASSERT(is_emagged(B), "and the legacy reader sees it")
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "the card paid one use")
	touch(M, B, emag)
	TEST_ASSERT_EQUAL(B.emag_ran, 1, "a second emag is refused: one-shot")
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "and costs nothing")

/datum/unit_test/dq_p2_lib/hatch_wires_behind_the_panel

/datum/unit_test/dq_p2_lib/hatch_wires_behind_the_panel/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/machinery/p2_box/B = allocate(/obj/machinery/p2_box)
	var/obj/item/tool/screwdriver/driver = allocate(/obj/item/tool/screwdriver)
	var/obj/item/multitool/multitool = allocate(/obj/item/multitool)
	TEST_ASSERT(!wire_is_cut(B, WIRE_IDSCAN), "no wire is cut")
	var/datum/op_result/closed = test_click(M, B, multitool)
	TEST_ASSERT_NOTEQUAL(closed?.outcome, ACT_COMMITTED, "the wires are not reachable behind a closed panel (refused with the panel's reason, intended_changes.md: physical paths)")
	touch(M, B, driver)
	var/datum/op_result/open = touch(M, B, multitool)
	TEST_ASSERT_EQUAL(open?.outcome, ACT_COMMITTED, "with the panel open the multitool reaches them")
	var/datum/cap_data/wires/W = wiring_of(B)
	TEST_ASSERT_NOTNULL(W, "the wire record is made with the box")
	TEST_ASSERT_EQUAL(W.def?.name, "p2 box", "of the wiring the capability names")
	wires_cut(B, WIRE_IDSCAN)
	TEST_ASSERT(wire_is_cut(B, WIRE_IDSCAN), "a cut wire is read through the accessor")
	wires_toggle(B, WIRE_IDSCAN)
	TEST_ASSERT(!wire_is_cut(B, WIRE_IDSCAN), "and mending it too")

/datum/unit_test/dq_p2_lib/hatch_cell_bay_behind_the_cover

/datum/unit_test/dq_p2_lib/hatch_cell_bay_behind_the_cover/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/machinery/p2_box/B = allocate(/obj/machinery/p2_box)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	var/obj/item/cell/cell = allocate(/obj/item/cell)
	var/datum/op_result/refused = test_click(M, B, cell)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a cell does not go in behind a closed cover")
	TEST_ASSERT_NULL(B.cell, "and the bay stays empty")
	touch(M, B, crowbar)
	touch(M, B, cell)
	TEST_ASSERT_EQUAL(B.cell, cell, "with the cover open it does")
	TEST_ASSERT_EQUAL(cell_charge_percent(B), cell.percent(), "the charge is read through the bay")
	var/datum/op_result/taken = test_click(M, B, null)
	TEST_ASSERT_EQUAL(taken?.key, "cell_bay.cell.take", "an empty hand takes it out")
	TEST_ASSERT_NULL(B.cell, "the bay is empty again")
	TEST_ASSERT_EQUAL(cell_charge_percent(B), 0, "an empty bay reads 0, not null")

// ---------------------------------------------------------------------------------------------------------------------
// The presentation bridge: look layers, examine lines, the window's data and its buttons, a wait a proc sizes.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_lib/present_outputs

/datum/unit_test/dq_p2_lib/present_outputs/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/machinery/p2_box/B = allocate(/obj/machinery/p2_box)
	var/forbidden = reason_text(/datum/msg/p2/ui_forbidden)
	TEST_ASSERT(!(forbidden in examine_collect(B, M)), "an examine line is absent while its condition is false")
	TEST_ASSERT(("p2-label" in look_layers_of(B)), "a look layer is drawn while its var is truthy")
	B.set_label_shown(FALSE)
	TEST_ASSERT(forbidden in examine_collect(B, M), "the examine line appears when its condition holds")
	TEST_ASSERT(!("p2-label" in look_layers_of(B)), "and the layer goes")
	var/list/data = list()
	present_tgui_data(B, M, data)
	TEST_ASSERT_EQUAL(data["viewer"], M.name, "ui_data() gets the viewer as A.actor")
	TEST_ASSERT_EQUAL(B.ui_interface(M), "P2Box", "interface() names the window")
	cap_key_set(B, LOCK_LOCKED, FALSE) // the lock gates every window button
	var/datum/op_result/pressed = present_ui_act(B, M, "press", list("n" = 4))
	TEST_ASSERT_EQUAL(pressed?.outcome, ACT_COMMITTED, "a window button runs its op")
	TEST_ASSERT_EQUAL(B.pressed_with, 4, "with the argument typed")
	present_ui_act(B, M, "press", list("n" = 99))
	TEST_ASSERT_EQUAL(B.pressed_with, 9, "an argument outside the schema is clamped to its range before the handler")
	TEST_ASSERT_NULL(present_ui_act(B, M, "no_such_button", list()), "an action with no op is not answered (the legacy UI rows follow)")

/datum/unit_test/dq_p2_lib/wait_time_from_a_proc

/datum/unit_test/dq_p2_lib/wait_time_from_a_proc/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/machinery/p2_box/B = allocate(/obj/machinery/p2_box)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench)
	var/datum/op_result/started = test_click(M, B, wrench)
	TEST_ASSERT_NULL(started?.outcome, "the op waits")
	TEST_ASSERT_EQUAL(B.began, 1, "begins() was told when the wait started, not when it ended")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(B.fitted, 0, "a second in, the two-second wait is not over")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(B.fitted, 1, "it ends on the time the proc gave")
	TEST_ASSERT_EQUAL(B.began, 1, "and begins() is not told again at the end")
	B.fitting_time = 50
	test_click(M, B, wrench)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(B.fitted, 1, "the time is read when the op starts: now five seconds")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(B.fitted, 2, "and it ends then")

/datum/unit_test/dq_p2_lib/heard_notice_is_wanted

/datum/unit_test/dq_p2_lib/heard_notice_is_wanted/run_gate()
	var/obj/machinery/p2_box/plain = allocate(/obj/machinery/p2_box)
	var/obj/machinery/p2_box/slasher/listener = allocate(/obj/machinery/p2_box/slasher)
	TEST_ASSERT(!op_notice_wanted(plain, /datum/notice/slashed), "nothing listens: req_heard() does not offer the op")
	TEST_ASSERT(op_notice_wanted(listener, /datum/notice/slashed), "a hook on the notice makes it wanted")

// ---------------------------------------------------------------------------------------------------------------------
// graph_place(): a thing created part-built.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_lib/graph_place_stage

/datum/unit_test/dq_p2_lib/graph_place_stage/run_gate()
	var/obj/e0_fixture/door_assembly/A = allocate(/obj/e0_fixture/door_assembly)
	TEST_ASSERT(graph_place(A, STAGE_DOOR_WIRED), "the instance is placed at a stage of its graph")
	TEST_ASSERT_EQUAL(graph_current(A), STAGE_DOOR_WIRED, "it is there")
	TEST_ASSERT(built(A, STAGE_DOOR_WIRED), "built() agrees")
	TEST_ASSERT(!built(A, STAGE_DOOR_BOARDED), "and has not been past it")
	TEST_ASSERT_NULL(graph_top(A), "no history: nothing is refunded for the way there")


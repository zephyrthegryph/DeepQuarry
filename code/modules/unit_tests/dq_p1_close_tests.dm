// The gate of the phase-1 close (doc/rewrite/final_api.html, sections 8, 9, 10, 11, 12; section 19 "E0 proofs", the E2 gaps): a capability's every(),
// activation contributions to stats, the purity guard, waits that subscribe to reads, the menu cache keyed by generations, the interned resolver index,
// the bay library (cover, compartment, cell bay, telekinesis), state-graph edges as ops with a ledger, the admin verbs and the part-constructor
// name clash. The fixtures are code/tests/engine/p1_fixtures.dm, fixtures.dm and e1_fixtures.dm.

/// Base: the kernel on its injected clock around the test, a clean driver after.
/datum/unit_test/dq_p1
	abstract_type = /datum/unit_test/dq_p1

/datum/unit_test/dq_p1/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_p1/proc/run_gate()
	return

/datum/unit_test/dq_p1/proc/actor()
	return allocate(/mob/living/simple_mob/e0_fixture)

// ---------------------------------------------------------------------------------------------------------------------
// every() of a capability: runs on the holder's clock while the activation lives; a shadowed activation keeps its clock and skips the handler.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/every_runs_while_the_activation_lives

/datum/unit_test/dq_p1/every_runs_while_the_activation_lives/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/e0_fixture/vest/other = allocate(/obj/item/e0_fixture/vest)
	var/datum/activation/strong = grant(M, p1_ticker(2), source = src)
	TEST_ASSERT_NOTNULL(strong, "the grant attaches")
	test_time(3 SECONDS)
	var/ran_alone = M.p1_ticks
	var/dt = M.p1_last_dt
	var/source = M.p1_last_source
	// a weaker activation of the same capability: BEST(power) runs one handler, not two
	grant(M, p1_ticker(1), source = other)
	test_time(3 SECONDS)
	var/ran_with_both = M.p1_ticks - ran_alone
	// the strong one goes: the shadowed one was never stopped, it runs from the next interval
	revoke(M, p1_ticker(2), source = src)
	test_time(2 SECONDS)
	var/ran_after_revoke = M.p1_ticks - ran_alone - ran_with_both
	revoke(M, p1_ticker(1), source = other)
	var/ticks_at_revoke = M.p1_ticks
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(ran_alone, 3, "every(1 SECOND) ran three times in three seconds")
	TEST_ASSERT_EQUAL(dt, 1 SECOND, "A.dt is the interval")
	TEST_ASSERT_EQUAL(source, src, "A.source is the activation's source")
	TEST_ASSERT_EQUAL(ran_with_both, 3, "two activations of a BEST capability run one handler per interval")
	TEST_ASSERT_EQUAL(ran_after_revoke, 2, "the shadowed activation takes over with its own clock")
	TEST_ASSERT_EQUAL(M.p1_ticks, ticks_at_revoke, "a revoked activation never runs again")

// ---------------------------------------------------------------------------------------------------------------------
// A granted capability's contributions are in the stat on the next line and gone with the revoke.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/granted_contributions_follow_the_activation

/datum/unit_test/dq_p1/granted_contributions_follow_the_activation/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/before_density = M.density
	var/before_invisibility = M.invisibility
	grant(M, e0_phased(), source = src)
	var/granted_density = M.density
	var/granted_invisibility = M.invisibility
	var/granted_mask = stat_value(M, STAT_ACTS_VIA)
	revoke(M, e0_phased(), source = src)
	TEST_ASSERT_EQUAL(before_density, TRUE, "a mob is solid")
	TEST_ASSERT_EQUAL(granted_density, FALSE, "granted: the density contribution applies on the next line")
	TEST_ASSERT(granted_invisibility > before_invisibility, "and the invisibility")
	TEST_ASSERT_EQUAL(granted_mask, ORIGIN_VERB | ORIGIN_HOTKEY, "and the origin mask")
	TEST_ASSERT_EQUAL(M.density, TRUE, "revoked: solid again in the same step")
	TEST_ASSERT_EQUAL(M.invisibility, before_invisibility, "visible again")
	TEST_ASSERT_EQUAL(stat_value(M, STAT_ACTS_VIA), ORIGIN_ALL, "the mask is whole again")

// ---------------------------------------------------------------------------------------------------------------------
// The purity guard: a condition or requirement that writes, publishes or messages is reported; one that only reads is not.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/purity_guard_reports_impure_conditions

/datum/unit_test/dq_p1/purity_guard_reports_impure_conditions/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e0_fixture/p1_impure/X = allocate(/obj/e0_fixture/p1_impure)
	var/obj/item/e2_key/key = allocate(/obj/item/e2_key)
	GLOB.op_pure_expected = TRUE
	GLOB.op_pure_violations.Cut()
	// a menu read evaluates the when() of "writes" and the requirement of "touches"
	action_options(M, X, null)
	var/list/found = GLOB.op_pure_violations.Copy()
	GLOB.op_pure_violations.Cut()
	var/touched_after_read = X.touched
	var/locked_after_read = X.locked
	// the other verbs of the guard, called inside an evaluation the way a condition would: a message
	op_pure_begin()
	to_chat(null, "a message inside an evaluation")
	op_pure_end()
	var/list/also_found = GLOB.op_pure_violations.Copy()
	GLOB.op_pure_violations.Cut()
	// the read-only condition leaves nothing
	var/datum/op_result/clean = perform_op(M, X, "clean", key, origin = ORIGIN_SYSTEM)
	var/list/clean_found = GLOB.op_pure_violations.Copy()
	GLOB.op_pure_expected = FALSE
	GLOB.op_pure_violations.Cut()
	var/wrote_in_condition = FALSE
	var/wrote_in_requirement = FALSE
	for(var/line in found)
		if(findtext(line, "touched was written"))
			wrote_in_condition = TRUE
		if(findtext(line, "locked was written"))
			wrote_in_requirement = TRUE
	var/spoke = FALSE
	for(var/line in also_found)
		if(findtext(line, "message was sent"))
			spoke = TRUE
	TEST_ASSERT(wrote_in_condition, "a when() that writes a tracked var is reported: [jointext(found, " | ")]")
	TEST_ASSERT(wrote_in_requirement, "a requirement that writes a tracked var is reported: [jointext(found, " | ")]")
	TEST_ASSERT(spoke, "a message sent inside an evaluation is reported: [jointext(also_found, " | ")]")
	TEST_ASSERT(touched_after_read && locked_after_read, "the guard reports; it does not refuse the write")
	TEST_ASSERT_EQUAL(length(clean_found), 0, "a condition that only reads is clean")
	TEST_ASSERT_EQUAL(clean?.outcome, ACT_COMMITTED, "and its op runs")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, 0, "the guard is balanced after every evaluation")

// ---------------------------------------------------------------------------------------------------------------------
// A wait subscribes to what it reads: a published read ends it at once, with no time passing and no poll.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/wait_rechecks_on_a_published_read

/datum/unit_test/dq_p1/wait_rechecks_on_a_published_read/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e0_fixture/p1_waiter/W = allocate(/obj/e0_fixture/p1_waiter)
	// The index also holds the watches of things that live on after other tests (a contagion's every() parked on its host relation), so the test
	// counts what its own wait adds and removes, not the absolute size.
	var/watchers_before = length(GLOB.op_watchers)
	var/pending_before = length(GLOB.op_pending_all)
	var/datum/op_result/waiting = test_click(M, W, null)
	var/datum/pending_op/P = op_pending_of(M)
	var/watching = length(P?.watching)
	var/watchers_while_waiting = length(GLOB.op_watchers) - watchers_before
	var/timer_pending = P ? after_left(P, "op_recheck") : 0
	W.set_ready(FALSE) // the requirement's read is published: the wait re-checks inside this call
	var/outcome_without_time = waiting?.outcome
	var/reason_without_time = waiting?.reason
	var/pending_after = op_pending_of(M)
	// the keeps: moving the actor away breaks ADJACENT the moment it moves
	W.set_ready(TRUE)
	var/datum/op_result/second = test_click(M, W, null)
	var/outcome_before_move = second?.outcome
	M.forceMove(run_loc_floor_top_right)
	var/outcome_after_move = second?.outcome
	TEST_ASSERT_NOTNULL(waiting, "the press went into a wait")
	TEST_ASSERT(watching > 0, "the wait subscribed to its reads and keeps")
	TEST_ASSERT(watchers_while_waiting > 0, "and sits in the watch index")
	TEST_ASSERT_EQUAL(timer_pending, 0, "no poll timer is armed")
	TEST_ASSERT_EQUAL(outcome_without_time, ACT_REFUSED, "clearing the read it needs cancelled the wait with no time passing")
	TEST_ASSERT_EQUAL(reason_without_time, /datum/msg/p1/not_ready, "with the requirement's own reason")
	TEST_ASSERT_NULL(pending_after, "the actor is free again")
	TEST_ASSERT_NULL(outcome_before_move, "the second press waits")
	TEST_ASSERT_EQUAL(outcome_after_move, ACT_REFUSED, "moving the actor out of reach cancelled it at once (the ADJACENT keep)")
	TEST_ASSERT_EQUAL(length(GLOB.op_watchers), watchers_before, "an ended wait leaves nothing in the watch index ([unit_test_watch_index_text()])")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending_all), pending_before, "or in the pending list")
	TEST_ASSERT_EQUAL(W.finished, 0, "and nothing ran")

// ---------------------------------------------------------------------------------------------------------------------
// The menu cache is keyed by generations: another entity's change leaves it alone, the target's or the provider set's does not.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/menu_cache_is_keyed_by_generations

/datum/unit_test/dq_p1/menu_cache_is_keyed_by_generations/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e0_fixture/cabinet/C = allocate(/obj/e0_fixture/cabinet)
	var/obj/e0_fixture/cabinet/C2 = allocate(/obj/e0_fixture/cabinet)
	var/builds_start = GLOB.op_menu_builds
	var/list/first = action_options(M, C, null)
	var/built_first = GLOB.op_menu_builds - builds_start
	var/list/again = action_options(M, C, null)
	var/built_again = GLOB.op_menu_builds - builds_start
	perform_op(M, C2, "cover.open", origin = ORIGIN_SYSTEM) // another entity changes
	action_options(M, C, null)
	var/built_after_other = GLOB.op_menu_builds - builds_start
	perform_op(M, C, "cover.open", origin = ORIGIN_SYSTEM) // the target's own state changes
	var/list/after_cover = action_options(M, C, null)
	var/built_after_target = GLOB.op_menu_builds - builds_start
	grant(M, telekinesis(), source = src) // the actor's provider set changes
	action_options(M, C, null)
	var/built_after_provider = GLOB.op_menu_builds - builds_start
	TEST_ASSERT_EQUAL(built_first, 1, "the first read builds the menu")
	TEST_ASSERT_EQUAL(built_again, 1, "the second read of the same state is the cached one")
	TEST_ASSERT(first ~= again, "and equals it")
	TEST_ASSERT(e0_menu_has(first, "cell_bay.cell.take", TRUE), "with the cover open the take op is enabled")
	TEST_ASSERT_EQUAL(built_after_other, 1, "a change of some other entity does not flush it: there is no epoch")
	TEST_ASSERT_EQUAL(built_after_target, 2, "a change of the target makes the old entry unreachable")
	TEST_ASSERT(!e0_menu_has(after_cover, "cell_bay.cell.take", TRUE), "and the new read shows the closed cover: the take op is no longer enabled")
	TEST_ASSERT_EQUAL(built_after_provider, 3, "so does a change of the actor's provider set")

// ---------------------------------------------------------------------------------------------------------------------
// The resolver index: rows interned by (origin, authority, gesture, intents, side, held type); a click walks the rows that can answer.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/resolver_index_interns_rows

/datum/unit_test/dq_p1/resolver_index_interns_rows/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e2_bench_stack/S = allocate(/obj/e2_bench_stack)
	var/obj/item/e2_bench_key7/key7 = allocate(/obj/item/e2_bench_key7)
	var/obj/item/e2_bench_key9/key9 = allocate(/obj/item/e2_bench_key9)
	var/datum/type_table/T = table_of(S)
	var/before = length(T.op_row_cache)
	var/datum/op_resolution/R7 = op_resolve(M, S, key7, ORIGIN_CLICK, AUTH_PHYSICAL, GESTURE_CLICK, null)
	var/datum/op_cand/winner = op_resolution_winner(R7)
	var/after_first = length(T.op_row_cache)
	// the stack's own thirty-one ops: the base types of the stack and the actor bring candidates of their own that this index does not prune
	var/candidates_with_key7 = 0
	for(var/datum/op_cand/stack_cand as anything in R7.all)
		if(stack_cand.holder == S && (stack_cand.oplan.key == "hand_use" || copytext(stack_cand.oplan.key, 1, 4) == "key"))
			candidates_with_key7++
	op_resolve(M, S, key7, ORIGIN_CLICK, AUTH_PHYSICAL, GESTURE_CLICK, null)
	var/after_same_shape = length(T.op_row_cache)
	var/datum/op_resolution/R9 = op_resolve(M, S, key9, ORIGIN_CLICK, AUTH_PHYSICAL, GESTURE_CLICK, null)
	var/after_other_type = length(T.op_row_cache)
	var/datum/op_cand/winner9 = op_resolution_winner(R9)
	TEST_ASSERT_EQUAL(winner?.oplan?.key, "key7", "a key7 click resolves to its own op")
	TEST_ASSERT_EQUAL(winner9?.oplan?.key, "key9", "a key9 click resolves to its own")
	TEST_ASSERT(after_first > before, "the first resolution interned the rows of its shape")
	TEST_ASSERT(candidates_with_key7 <= 3, "only the rows that can answer became candidates, not the thirty ops of the type: [candidates_with_key7]")
	TEST_ASSERT_EQUAL(after_same_shape, after_first, "the same shape is not interned again")
	TEST_ASSERT(after_other_type > after_same_shape, "another held type is another shape")

// ---------------------------------------------------------------------------------------------------------------------
// The bay library: the cover gates the compartment, the cell bay's ops move the cell, telekinesis reaches.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/cell_bay_takes_and_inserts_behind_the_cover

/datum/unit_test/dq_p1/cell_bay_takes_and_inserts_behind_the_cover/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e0_fixture/cabinet/C = allocate(/obj/e0_fixture/cabinet)
	var/obj/item/e0_fixture/cell/start_cell = C.cell
	var/started_with_cell = !isnull(start_cell)
	var/cover_started_open = cover_open(C, null)
	var/datum/op_result/taken = test_click(M, C, null)
	var/cell_after_take = C.cell
	var/obj/item/e0_fixture/cell/cell = start_cell
	var/datum/op_result/inserted = test_click(M, C, cell)
	var/cell_after_insert = C.cell
	var/cell_in_holder = cell?.loc == C
	var/datum/op_result/second_insert = perform_op(M, C, "cell_bay.cell.insert", cell, origin = ORIGIN_SYSTEM) // a click would take the cell instead: the take op is the higher tier
	perform_op(M, C, "cover.open", origin = ORIGIN_SYSTEM) // the cover closes
	// The take is behind the closed cover, so a click sets it aside and the cover's own op answers: it opens the cover.
	var/datum/op_result/closed_click = test_click(M, C, null)
	var/cover_open_after_click = cover_open(C, null)
	var/cell_after_closed_click = C.cell
	perform_op(M, C, "cover.open", origin = ORIGIN_SYSTEM) // closed again
	// Asked for by name, the take has no other candidate to yield to: it refuses with the door's reason.
	var/datum/op_result/closed_take = perform_op(M, C, "cell_bay.cell.take")
	var/cell_after_closed_take = C.cell
	TEST_ASSERT(started_with_cell, "the bay starts with the cell its holder declared")
	TEST_ASSERT_EQUAL(cover_started_open, TRUE, "the cover starts open")
	TEST_ASSERT_EQUAL(taken?.key, "cell_bay.cell.take", "an empty hand on an open bay takes the cell")
	TEST_ASSERT_EQUAL(taken?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_NULL(cell_after_take, "the bay is empty")
	TEST_ASSERT_EQUAL(inserted?.key, "cell_bay.cell.insert", "the cell in hand goes back by the insert op")
	TEST_ASSERT_EQUAL(inserted?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_EQUAL(cell_after_insert, cell, "the bay names the cell")
	TEST_ASSERT(cell_in_holder, "and the cell is in the cabinet")
	TEST_ASSERT_EQUAL(second_insert?.outcome, ACT_REFUSED, "a full bay refuses another cell")
	TEST_ASSERT_EQUAL(second_insert?.reason, /datum/msg/bay/full, "with its reason")
	TEST_ASSERT_EQUAL(closed_click?.key, "cover.open", "an empty hand on a closed bay opens the cover instead of reaching through it")
	TEST_ASSERT_EQUAL(closed_click?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_EQUAL(cover_open_after_click, TRUE, "the cover is open")
	TEST_ASSERT_EQUAL(cell_after_closed_click, cell, "and the cell is still in the bay")
	TEST_ASSERT_EQUAL(closed_take?.outcome, ACT_REFUSED, "a closed cover refuses the take: the bay is a compartment")
	TEST_ASSERT_EQUAL(closed_take?.reason, /datum/msg/cover/closed, "with the cover's reason")
	TEST_ASSERT_EQUAL(cell_after_closed_take, cell, "and the cell stays")

// ---------------------------------------------------------------------------------------------------------------------
// State-graph edges are ops with a ledger: undo refunds exactly what the edge took in.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/graph_undo_refunds_the_ledger

/// The units of cable on `where`'s turf.
/datum/unit_test/dq_p1/graph_undo_refunds_the_ledger/proc/coil_units(atom/where)
	. = 0
	for(var/obj/item/stack/cable_coil/C in get_turf(where))
		. += C.amount

/datum/unit_test/dq_p1/graph_undo_refunds_the_ledger/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e0_fixture/door_assembly/A = allocate(/obj/e0_fixture/door_assembly)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil)
	var/units_before = coil_units(A)
	var/turf/floor = get_turf(A)
	var/list/menu_at_frame = action_options(M, A, coil)
	var/datum/op_result/wired = test_click(M, A, coil)
	var/units_while_wired = coil_units(A)
	var/stage_wired = graph_current(A)
	var/list/menu_at_wired = action_options(M, A, null)
	var/datum/op_result/unwired = test_click(M, A, null) // the way back of a stack edge is a hand
	var/units_after_undo = coil_units(A)
	var/stage_after_undo = graph_current(A)
	TEST_ASSERT(e0_menu_has(menu_at_frame, "construction.build:door_wired", TRUE), "at the frame the wired edge is an op with a stack in hand")
	TEST_ASSERT_EQUAL(wired?.key, "construction.build:door_wired", "the click ran the edge")
	TEST_ASSERT_EQUAL(wired?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_EQUAL(stage_wired, STAGE_DOOR_WIRED, "the instance moved along the edge")
	TEST_ASSERT_EQUAL(units_while_wired, units_before - 5, "the edge spent five units")
	TEST_ASSERT(e0_menu_has(menu_at_wired, "construction.undo:door_wired", TRUE), "the way back is an op while the instance is at the stage")
	TEST_ASSERT_EQUAL(unwired?.key, "construction.undo:door_wired", "an empty hand undoes it")
	TEST_ASSERT_EQUAL(unwired?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_EQUAL(stage_after_undo, STAGE_DOOR_FRAME, "back to the frame")
	TEST_ASSERT_EQUAL(units_after_undo, units_before, "the ledger refunded exactly the five units")
	TEST_ASSERT(!built(A, STAGE_DOOR_WIRED), "and wired is no longer built")
	own_turf_contents(floor) // the refunded stack is the test to clean up

// ---------------------------------------------------------------------------------------------------------------------
// The admin verbs are registered by name.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/engine_admin_verbs_are_registered

/datum/unit_test/dq_p1/engine_admin_verbs_are_registered/run_gate()
	var/list/names = list()
	for(var/verb_type in subtypesof(/datum/admin_verb))
		var/datum/admin_verb/V = verb_type
		names += initial(V.name)
	for(var/wanted in list("Explain Type", "List Activations", "List Pending Ops", "Explain Interaction"))
		TEST_ASSERT(wanted in names, "the admin verb \"[wanted]\" is registered")
	// the procs behind them answer
	var/mob/living/simple_mob/e0_fixture/M = actor()
	TEST_ASSERT(length(explain_type(/obj/e0_fixture/cabinet)) > 0, "Explain Type prints the merged table")
	TEST_ASSERT(length(explain_activations(M)) >= 0, "List Activations answers")
	TEST_ASSERT_EQUAL(op_pending_all_text(), "no pending ops", "List Pending Ops answers when nothing waits")

// ---------------------------------------------------------------------------------------------------------------------
// A type with its own procs named like part constructors still builds the engine's parts.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/part_constructors_survive_a_type_proc_of_the_same_name

/datum/unit_test/dq_p1/part_constructors_survive_a_type_proc_of_the_same_name/run_gate()
	var/list/found = list()
	GLOB.declare_report_capture = found // the type's table is built when its first instance is
	var/obj/item/p1_telecube/cube = allocate(/obj/item/p1_telecube)
	var/datum/type_table/T = table_of(cube)
	GLOB.declare_report_capture = null
	var/datum/op_plan/zap = op_plan_for(cube, "zap", list())
	TEST_ASSERT_EQUAL(length(found), 0, "the table builds without a report: [jointext(found, " | ")]")
	TEST_ASSERT_NOTNULL(T, "the type has a table")
	TEST_ASSERT_NOTNULL(zap, "the op was built")
	TEST_ASSERT_EQUAL(zap?.cooldown_t, 5 SECONDS, "cooldown() is the engine's part, not the type's proc")
	TEST_ASSERT_EQUAL(zap?.label, "Zap", "label() too")
	TEST_ASSERT_NOTNULL(zap?.says, "and says()")
	TEST_ASSERT_EQUAL(cube.captured, 0, "no declaration called a proc of the type")

// ---------------------------------------------------------------------------------------------------------------------
// Telekinesis is a provider: granting it brings a far cover into the menu, revoking it takes it out; the cover still gates what is inside.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p1/telekinesis_is_a_provider_with_reach_and_sight

/datum/unit_test/dq_p1/telekinesis_is_a_provider_with_reach_and_sight/run_gate()
	var/mob/living/simple_mob/e0_fixture/far = allocate(/mob/living/simple_mob/e0_fixture, run_loc_floor_top_right)
	var/obj/e0_fixture/cabinet/C = allocate(/obj/e0_fixture/cabinet)
	var/spread = get_dist(C, far)
	var/hand_reaches = e0_menu_has(action_options(far, C, null), "cover.open")
	var/datum/activation/tk = grant(far, telekinesis(), source = src)
	var/datum/op_resolution/R = op_resolve(far, C, null, ORIGIN_MENU, AUTH_PHYSICAL, null, "cover.open", TRUE)
	var/explained = jointext(op_explain_lines(R), "\n") + "\nspread [spread], line clear [reach_line_clear(far, C)], providers [length(providers_for(far, null))], world.view [world.view]"
	var/tk_reaches = e0_menu_has(action_options(far, C, null), "cover.open")
	var/datum/op_result/far_open = perform_op(far, C, "cover.open", origin = ORIGIN_MENU)
	var/cover_after_far_open = cover_open(C, null)
	revoke(far, telekinesis(), source = src)
	var/after_revoke = e0_menu_has(action_options(far, C, null), "cover.open")
	TEST_ASSERT(spread >= 2, "the far actor is out of a hand's reach")
	TEST_ASSERT_EQUAL(hand_reaches, FALSE, "a hand does not reach")
	TEST_ASSERT_NOTNULL(tk, "the grant attaches")
	TEST_ASSERT(tk_reaches, "a telekinesis provider reaches the cover:\n[explained]")
	TEST_ASSERT_EQUAL(far_open?.outcome, ACT_COMMITTED, "and the op runs through it")
	TEST_ASSERT_EQUAL(cover_after_far_open, FALSE, "it closed the open cover from across the room")
	TEST_ASSERT_EQUAL(after_revoke, FALSE, "revoked, it is out of reach again")

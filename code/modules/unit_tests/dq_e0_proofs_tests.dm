// The ten E0 proofs (doc/rewrite/final_api.html, section 19 "The E0 proofs"; round 5 rewrites of proofs 3, 4, 5 and 6).
//
// Ten small executable fixtures that pin the semantic contracts most likely to force an expensive redesign after content
// conversion begins. They are written first, as failing fixtures against E0's stubs, and go green as E1 to E6 land; all ten
// must pass before any content conversion. Each is written with the forms of the test driver (code/tests/driver/), the public
// engine verbs a fixture may call (grant, revoke, rel_set, act_done, move_into, action_options, screentip_for, built()), and
// the test-only capabilities and types of code/tests/engine/, and uses nothing else.
//
// How a proof fails today. Every driver form and verb a proof calls reaches an E0 stub, which records what it needs and
// returns null. A proof therefore reads what it needs into locals as it drives, calls E0_GATE once, and only then asserts:
// while any stub was hit the proof fails with "E1-E6 not implemented: <what>; <what>" naming every missing piece it touched,
// instead of running its assertions on nulls. Once the engines land the gate is silent and the assertions below run unchanged.
//
// Tier. The proofs are TEST_TIER_E0, a tier of their own: a plain dm-test run and `--tier=all` skip them (they cannot pass until
// E1-E6 land, and the normal suite must stay green), and `dm-test --tier=e0` or a focused run by name runs them. See
// doc/testing.md "The E0 proofs" and doc/rewrite/engine_contracts.md.

/// The base of the ten proofs: a clean driver before and after, and one entry point for the proof.
/datum/unit_test/dq_e0_proof
	abstract_type = /datum/unit_test/dq_e0_proof
	tier = TEST_TIER_E0

/datum/unit_test/dq_e0_proof/Run()
	test_driver_begin()
	run_proof()
	test_driver_end()

/// The proof itself: drive, read into locals, E0_GATE, assert.
/datum/unit_test/dq_e0_proof/proc/run_proof()
	return Fail("[type]/run_proof() is not implemented", __FILE__, __LINE__)

/// The reason text of a refused op, from the /datum/msg type its result carries.
/datum/unit_test/dq_e0_proof/proc/reason_text(reason)
	if(isnull(reason))
		return null
	var/datum/msg/message_type = reason
	return initial(message_type.self)

// ---------------------------------------------------------------------------------------------------------------------
// Proof 1: open a door and immediately read the correct density.
// Exercises: immediate stats and gated contributions (section 7); X1 attach. A TOP density stat, an op that toggles() DOOR_OPEN.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p01_open_door_density

/datum/unit_test/dq_e0_proof/p01_open_door_density/run_proof()
	var/mob/living/simple_mob/e0_fixture/actor = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/e0_fixture/door/D = allocate(/obj/e0_fixture/door)
	var/was_dense = D.density
	var/datum/op_result/opened = perform_op(actor, D, "e0_door.toggle", origin = ORIGIN_SYSTEM)
	var/dense_after_open = D.density // the very next line: no test_drain() between the op and this read
	var/datum/op_result/closed = perform_op(actor, D, "e0_door.toggle", origin = ORIGIN_SYSTEM)
	var/dense_after_close = D.density
	E0_GATE
	TEST_ASSERT_EQUAL(was_dense, TRUE, "a closed door is solid")
	TEST_ASSERT_NOTNULL(opened, "perform_op returns a result")
	TEST_ASSERT_EQUAL(opened.outcome, ACT_COMMITTED, "opening the door commits")
	TEST_ASSERT_EQUAL(dense_after_open, FALSE, "an open door is not solid on the line after the op, with no drain in between")
	TEST_ASSERT_NOTNULL(closed, "the second toggle returns a result")
	TEST_ASSERT_EQUAL(closed.outcome, ACT_COMMITTED, "closing the door commits")
	TEST_ASSERT_EQUAL(dense_after_close, TRUE, "a closed door is solid again on the line after the op")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 2: grant the same effect from two sources and remove either: one roll.
// Exercises: activations and stacking (X1, section 11). mirror_plating stacks = BEST(reflect_chance).
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p02_two_mirrors_one_roll

/// Hits `wearer` with seeds until the mirror reflects, collecting how many rolls each hit drew; returns the source the reflect handler saw.
/datum/unit_test/dq_e0_proof/p02_two_mirrors_one_roll/proc/hit_until_reflected(mob/living/simple_mob/e0_fixture/wearer, list/rolls_seen)
	for(var/seed in 1 to 60)
		wearer.last_reflect_source = null
		test_rng(seed)
		wearer.e0_beam_hit()
		rolls_seen += test_rolls()
		if(wearer.last_reflect_source)
			return wearer.last_reflect_source
	return null

/datum/unit_test/dq_e0_proof/p02_two_mirrors_one_roll/run_proof()
	var/mob/living/simple_mob/e0_fixture/wearer = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/item/e0_fixture/vest/vest = allocate(/obj/item/e0_fixture/vest)
	var/obj/item/e0_fixture/shield/shield = allocate(/obj/item/e0_fixture/shield)
	var/list/rolls_seen = list()
	grant(wearer, e0_mirror_plating(30), source = vest)
	grant(wearer, e0_mirror_plating(45), source = shield)
	var/source_with_both = hit_until_reflected(wearer, rolls_seen)
	revoke(wearer, e0_mirror_plating(45), source = shield)
	var/source_vest_alone = hit_until_reflected(wearer, rolls_seen)
	grant(wearer, e0_mirror_plating(45), source = shield)
	revoke(wearer, e0_mirror_plating(30), source = vest)
	var/source_shield_alone = hit_until_reflected(wearer, rolls_seen)
	grant(wearer, e0_mirror_plating(30), source = vest)
	var/source_both_again = hit_until_reflected(wearer, rolls_seen)
	E0_GATE
	TEST_ASSERT_EQUAL(source_with_both, shield, "with both mirrors the winning activation is the stronger: A.source is the shield")
	TEST_ASSERT_EQUAL(source_vest_alone, vest, "the vest was shadowed, not removed: with the shield revoked it runs")
	TEST_ASSERT_EQUAL(source_shield_alone, shield, "the shield alone, after the vest is revoked")
	TEST_ASSERT_EQUAL(source_both_again, shield, "granting the vest back does not take the roll from the shield")
	for(var/rolls in rolls_seen)
		TEST_ASSERT_EQUAL(rolls, 1, "every hit draws exactly one roll, never two that compound")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 3: remove an ability while its ongoing effect is active.
// Exercises: activation ownership and the one teardown path (X1). A phase shift and a species change; a handler that ends its own shift.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p03_species_change_ends_phase_shift

/datum/unit_test/dq_e0_proof/p03_species_change_ends_phase_shift/run_proof()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/datum/e0_species/shifter/shifter = allocate(/datum/e0_species/shifter)
	var/datum/e0_species/plain/plain = allocate(/datum/e0_species/plain)
	// Case A: the species changes while the mob is phased.
	rel_set(M, nameof(M.species), shifter)
	var/datum/op_result/shifted = perform_op(M, M, "phase_shift.shift", origin = ORIGIN_VERB)
	test_time(2 SECONDS) // the every(1 SECOND) drain handler runs twice
	var/energy_after_drain = M.dark_energy
	var/phased_density = M.density
	var/phased_invisibility = M.invisibility
	var/phased_acts_via = e0_var(M, "acts_via") // a base stat of E3's: absent from the mob until it lands
	var/phased_granted = granted(M, /datum/e0_cap/phased)
	rel_set(M, nameof(M.species), plain)
	test_drain()
	var/solid_density = M.density
	var/solid_invisibility = M.invisibility
	var/solid_acts_via = e0_var(M, "acts_via")
	var/phased_after = granted(M, /datum/e0_cap/phased)
	var/ability_after = granted(M, /datum/e0_cap/phase_shift)
	// Case B: exactly the shift's cost in energy, so the first drain step finds none and the handler ends the shift itself.
	var/mob/living/simple_mob/e0_fixture/broke = allocate(/mob/living/simple_mob/e0_fixture)
	broke.dark_energy = 50
	rel_set(broke, nameof(broke.species), shifter)
	var/datum/op_result/broke_shifted = perform_op(broke, broke, "phase_shift.shift", origin = ORIGIN_VERB)
	test_time(1 SECOND) // the handler finds no energy, performs the unshift, and revokes the activation that owns it
	var/broke_phased = granted(broke, /datum/e0_cap/phased)
	var/broke_density = broke.density
	test_record(broke)
	test_time(5 SECONDS) // nothing of that activation may run again
	var/list/after_end = test_recorded()
	E0_GATE
	TEST_ASSERT_NOTNULL(shifted, "the shift returns a result")
	TEST_ASSERT_EQUAL(shifted.outcome, ACT_COMMITTED, "the shift commits")
	TEST_ASSERT(energy_after_drain < 50, "the drain handler spent energy while phased")
	TEST_ASSERT_EQUAL(phased_density, FALSE, "phased: through walls and people")
	TEST_ASSERT(phased_invisibility > 0, "phased: invisible")
	TEST_ASSERT_EQUAL(phased_acts_via, ORIGIN_VERB | ORIGIN_HOTKEY, "phased: abilities only, so the way back still works")
	TEST_ASSERT_EQUAL(phased_granted, TRUE, "the phased capability is granted while the shift lasts")
	TEST_ASSERT_EQUAL(solid_density, TRUE, "dropping the ability ends what it owns in the same step: solid again")
	TEST_ASSERT_EQUAL(solid_invisibility, 0, "visible again")
	TEST_ASSERT_EQUAL(solid_acts_via, ORIGIN_ALL, "the origin mask is whole again")
	TEST_ASSERT_EQUAL(phased_after, FALSE, "the phased activation went with its owner")
	TEST_ASSERT_EQUAL(ability_after, FALSE, "the new species has no phase shift")
	TEST_ASSERT_NOTNULL(broke_shifted, "the second shift returns a result")
	TEST_ASSERT_EQUAL(broke_shifted.outcome, ACT_COMMITTED, "the second shift commits")
	TEST_ASSERT_EQUAL(broke_phased, FALSE, "the handler ended its own shift when the energy ran out")
	TEST_ASSERT_EQUAL(broke_density, TRUE, "and the mob is solid")
	TEST_ASSERT_EQUAL(length(after_end), 0, "nothing of the ended activation ran again: no outcome, no reservation, no notice, no delta")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 4: confirm a selected object while another actor changes the selection: the capture holds.
// Exercises: workflows and the resume policy (X3, section 13). confirms() with captures(nameof(selected_id)).
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p04_capture_holds

/datum/unit_test/dq_e0_proof/p04_capture_holds/run_proof()
	var/mob/living/simple_mob/e0_fixture/rae = allocate(/mob/living/simple_mob/e0_fixture)
	var/mob/living/simple_mob/e0_fixture/kai = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/e0_fixture/library/L = allocate(/obj/e0_fixture/library)
	// The default policy: the value the first actor confirmed is the value the op uses.
	test_ui(rae, L, "select", list("id" = 5))
	var/datum/op_result/printing = test_ui(rae, L, "print", list())
	var/outcome_while_waiting = printing?.outcome
	test_ui(kai, L, "select", list("id" = 9))
	var/datum/op_result/printed = test_answer(rae, TRUE)
	var/obj/item/e0_fixture/book/book = locate() in get_turf(L)
	var/produced_id = book?.book_id
	var/live_selection = L.selected_id
	var/list/logs = test_logs()
	var/logged_captured = FALSE
	for(var/datum/test_log/line in logs)
		if(findtext(line.text, "5") && !findtext(line.text, "9"))
			logged_captured = TRUE
	if(book)
		qdel(book)
	// The variant with resume = CANCEL_IF_CHANGED: the op ends refused, "it changed while you were deciding".
	var/obj/e0_fixture/library/strict/strict = allocate(/obj/e0_fixture/library/strict)
	test_ui(rae, strict, "select", list("id" = 5))
	var/datum/op_result/strict_printing = test_ui(rae, strict, "print", list())
	test_ui(kai, strict, "select", list("id" = 9))
	var/datum/op_result/strict_result = test_answer(rae, TRUE)
	var/obj/item/e0_fixture/book/strict_book = locate() in get_turf(strict)
	var/strict_produced = !isnull(strict_book)
	if(strict_book)
		qdel(strict_book)
	E0_GATE
	TEST_ASSERT_NOTNULL(printing, "the print press returns a result")
	TEST_ASSERT_NULL(outcome_while_waiting, "the op is suspended in confirms(): no outcome yet")
	TEST_ASSERT_EQUAL(live_selection, 9, "the second actor really changed the live selection")
	TEST_ASSERT_NOTNULL(printed, "the confirm returns the waiting op's result")
	TEST_ASSERT_EQUAL(printed.outcome, ACT_COMMITTED, "the print commits")
	TEST_ASSERT_EQUAL(produced_id, 5, "the produced object carries the id the first actor confirmed, not the live selection")
	TEST_ASSERT(logged_captured, "the log line carries the captured id")
	TEST_ASSERT_NOTNULL(strict_printing, "the strict print press returns a result")
	TEST_ASSERT_NOTNULL(strict_result, "the strict confirm returns a result")
	TEST_ASSERT_EQUAL(strict_result.outcome, ACT_REFUSED, "CANCEL_IF_CHANGED: the changed selection refuses the op")
	TEST_ASSERT_EQUAL(strict_produced, FALSE, "and nothing was produced")
	TEST_ASSERT(findtext(reason_text(strict_result.reason), "changed while you were deciding"), "the reason says it changed while the actor was deciding")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 5: refuse an insertion after the outer op has started, with no resource lost.
// Exercises: the commit contract and resource transactions (X2, section 9). The hopper of 16.14.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p05_refused_insert_loses_nothing

/datum/unit_test/dq_e0_proof/p05_refused_insert_loses_nothing/run_proof()
	var/mob/living/simple_mob/e0_fixture/rae = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/e0_fixture/hopper/H = allocate(/obj/e0_fixture/hopper)
	var/obj/item/e0_fixture/sheets/raes = allocate(/obj/item/e0_fixture/sheets)
	var/obj/item/e0_fixture/sheets/kais = allocate(/obj/item/e0_fixture/sheets)
	raes.amount = E0_SHEETS_PER_LOAD
	test_record(rae, H, raes)
	var/datum/op_result/loading = test_click(rae, H, raes) // the wait(2 SECONDS) is pending
	var/outcome_while_waiting = loading?.outcome
	H.e0_fill_to_capacity(kais) // Kai's fill, landing inside Rae's wait
	test_time(2 SECONDS) // the wait ends; Require, then the insert's pre-check, refuse
	var/outcome_after = loading?.outcome
	var/list/events = test_recorded()
	var/sheets_left = raes.amount
	var/list/logs = test_logs()
	var/op_done = test_notice_count(/datum/notice/op_done)
	var/refusal_logged = FALSE
	for(var/datum/test_log/line in logs)
		if(findtext(line.key, "load") && line.outcome == ACT_REFUSED)
			refusal_logged = TRUE
	E0_GATE
	TEST_ASSERT_NOTNULL(loading, "the click resolved to the load op")
	TEST_ASSERT_NULL(outcome_while_waiting, "the op is in its wait: no outcome yet")
	TEST_ASSERT_EQUAL(outcome_after, ACT_REFUSED, "the insert's pre-check refused it once the hopper was full")
	TEST_ASSERT_EQUAL(sheets_left, E0_SHEETS_PER_LOAD, "Rae still has every sheet")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_RESERVE), 0, "nothing was reserved: the refusal came before the reservation")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_COMMIT), 0, "nothing was committed")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_RELEASE), 0, "so nothing needed releasing")
	TEST_ASSERT_EQUAL(op_done, 0, "no op_done notice for a refused op")
	TEST_ASSERT(refusal_logged, "the refusal is logged with its key chain")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 6: invoke one op by click, by UI and by AI with identical outcomes and logs.
// Exercises: input bindings; origin, reach, provider and authority (section 8). hand() and ui_act() on one op.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p06_click_ui_ai_identical

/// A log as comparable text, minus the origin field, which differs by design.
/datum/unit_test/dq_e0_proof/p06_click_ui_ai_identical/proc/log_rows(list/logs)
	. = list()
	for(var/datum/test_log/line in logs)
		. += "[line.key]|[line.outcome]|[line.text]"

/datum/unit_test/dq_e0_proof/p06_click_ui_ai_identical/run_proof()
	var/mob/living/simple_mob/e0_fixture/by_click = allocate(/mob/living/simple_mob/e0_fixture)
	var/mob/living/simple_mob/e0_fixture/by_ui = allocate(/mob/living/simple_mob/e0_fixture)
	var/mob/living/simple_mob/e0_fixture/by_ai = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/e0_fixture/door/door_click = allocate(/obj/e0_fixture/door)
	var/obj/e0_fixture/door/door_ui = allocate(/obj/e0_fixture/door)
	var/obj/e0_fixture/door/door_ai = allocate(/obj/e0_fixture/door)
	test_record(by_click, door_click)
	var/datum/op_result/clicked = test_click(by_click, door_click, null)
	var/list/events_click = test_recorded()
	var/list/logs_click = log_rows(test_logs())
	test_record(by_ui, door_ui)
	var/datum/op_result/pressed = test_ui(by_ui, door_ui, "toggle", list())
	var/list/events_ui = test_recorded()
	var/list/logs_ui = log_rows(test_logs())
	test_record(by_ai, door_ai)
	var/datum/op_result/performed = perform_op(by_ai, door_ai, "e0_door.toggle", origin = ORIGIN_AI) // through hand(), which accepts ORIGIN_AI
	var/list/events_ai = test_recorded()
	var/list/logs_ai = log_rows(test_logs())
	E0_GATE
	TEST_ASSERT_NOTNULL(clicked, "the click resolved")
	TEST_ASSERT_NOTNULL(pressed, "the press resolved")
	TEST_ASSERT_NOTNULL(performed, "the AI call resolved")
	TEST_ASSERT_EQUAL(clicked.outcome, ACT_COMMITTED, "the click committed")
	TEST_ASSERT_EQUAL(pressed.outcome, clicked.outcome, "the UI outcome is the click's")
	TEST_ASSERT_EQUAL(performed.outcome, clicked.outcome, "the AI outcome is the click's")
	TEST_ASSERT_EQUAL(pressed.reason, clicked.reason, "the UI reason is the click's")
	TEST_ASSERT_EQUAL(performed.reason, clicked.reason, "the AI reason is the click's")
	TEST_ASSERT_EQUAL(pressed.rolled, clicked.rolled, "the UI roll is the click's")
	TEST_ASSERT_EQUAL(performed.rolled, clicked.rolled, "the AI roll is the click's")
	TEST_ASSERT_EQUAL(clicked.origin, ORIGIN_CLICK, "the origin is the one field that differs, by design")
	TEST_ASSERT_EQUAL(pressed.origin, ORIGIN_UI, "the UI origin")
	TEST_ASSERT_EQUAL(performed.origin, ORIGIN_AI, "the AI origin")
	var/diff_ui = test_events_diff(events_click, list(by_click, door_click), events_ui, list(by_ui, door_ui))
	TEST_ASSERT_NULL(diff_ui, "the record of the UI run differs from the click run: [diff_ui]")
	var/diff_ai = test_events_diff(events_click, list(by_click, door_click), events_ai, list(by_ai, door_ai))
	TEST_ASSERT_NULL(diff_ai, "the record of the AI run differs from the click run: [diff_ai]")
	TEST_ASSERT(length(events_click) > 0, "the click run recorded something to compare")
	TEST_ASSERT(jointext(logs_ui, "\n") == jointext(logs_click, "\n"), "the UI log lines are the click's, minus origin")
	TEST_ASSERT(jointext(logs_ai, "\n") == jointext(logs_click, "\n"), "the AI log lines are the click's, minus origin")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 7: change reach, containment and capability state while cached menus and waits exist: the caches update.
// Exercises: the graph contract (section 7). Menus read by two actors, a provides capability, a cover, a slot.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p07_caches_follow_the_graph

/// The keys of a menu read, so two reads compare as text.
/datum/unit_test/dq_e0_proof/p07_caches_follow_the_graph/proc/menu_keys(mob/actor, obj/e0_fixture/cabinet/C, obj/item/held)
	var/list/menu = action_options(actor, C, held)
	var/list/keys = list()
	for(var/list/entry in menu)
		keys += "[entry["key"]][entry["enabled"] ? "" : " (greyed)"]"
	return sortList(keys)

/datum/unit_test/dq_e0_proof/p07_caches_follow_the_graph/run_proof()
	var/mob/living/simple_mob/e0_fixture/near = allocate(/mob/living/simple_mob/e0_fixture)
	var/mob/living/simple_mob/e0_fixture/far = allocate(/mob/living/simple_mob/e0_fixture, run_loc_floor_top_right)
	var/obj/e0_fixture/cabinet/C = allocate(/obj/e0_fixture/cabinet)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	var/obj/item/e0_fixture/cell/cell = allocate(/obj/item/e0_fixture/cell)
	var/spread = get_dist(C, far)
	// The first reads: two actors on one target, so a cache keyed on counters alone would let them share an entry.
	var/near_before = menu_keys(near, C, crowbar)
	var/far_before = menu_keys(far, C, null)
	var/tip_before = screentip_for(near, C, crowbar, GESTURE_CLICK)
	var/datum/op_result/prying = test_click(near, C, crowbar) // a wait for the pending op
	var/outcome_while_waiting = prying?.outcome
	// A provides capability (the provider set generation): telekinesis puts the far actor in reach, revoking it takes it away.
	grant(far, telekinesis(), source = src)
	test_drain()
	var/far_with_tk = menu_keys(far, C, null)
	revoke(far, telekinesis(), source = src)
	test_drain()
	var/far_without_tk = menu_keys(far, C, null)
	// A cover closing: the bay is no longer exposed, so the cell op leaves the menu.
	var/menu_open = menu_keys(near, C, null)
	perform_op(near, C, "cover.open", origin = ORIGIN_SYSTEM)
	test_drain()
	var/menu_covered = menu_keys(near, C, null)
	var/tip_covered = screentip_for(near, C, null, GESTURE_CLICK)
	// A slot change: the cell goes in, so insert gives way to take.
	perform_op(near, C, "cover.open", origin = ORIGIN_SYSTEM)
	var/menu_empty_bay = menu_keys(near, C, cell)
	cell.forceMove(C)
	C.cell = cell
	test_drain()
	var/menu_filled_bay = menu_keys(near, C, null)
	C.cell = null
	cell.forceMove(get_turf(C))
	test_time(5 SECONDS)
	var/outcome_after_wait = prying?.outcome
	E0_GATE
	TEST_ASSERT(spread >= 2, "the test zone is big enough that the far actor is out of a hand's reach")
	TEST_ASSERT_NOTNULL(prying, "the click went into a wait")
	TEST_ASSERT_NULL(outcome_while_waiting, "the pending op has no outcome yet")
	TEST_ASSERT(jointext(near_before, ",") != jointext(far_before, ","), "two actors on one target read their own menus")
	TEST_ASSERT(!findtext(jointext(far_before, ","), "cover.open"), "out of reach: the cover is not a candidate for the far actor")
	TEST_ASSERT(findtext(jointext(far_with_tk, ","), "cover.open"), "granting a provider that reaches puts the cover in the far actor's menu after one drain")
	TEST_ASSERT(!findtext(jointext(far_without_tk, ","), "cover.open"), "revoking it takes the cover out again: the cached menu followed the provider set")
	TEST_ASSERT(findtext(jointext(menu_open, ","), "cell_bay.cell"), "with the cover open the bay's ops are listed")
	TEST_ASSERT(!findtext(jointext(menu_covered, ","), "cell_bay.cell.take") || findtext(jointext(menu_covered, ","), "cell_bay.cell.take (greyed)"), "a closing cover hides or greys the bay's take op")
	TEST_ASSERT_NOTNULL(tip_before, "the screentip names the op a click would run")
	TEST_ASSERT(tip_before != tip_covered, "and it followed the cover closing")
	TEST_ASSERT(findtext(jointext(menu_empty_bay, ","), "cell_bay.cell.insert"), "an empty bay offers insert")
	TEST_ASSERT(findtext(jointext(menu_filled_bay, ","), "cell_bay.cell.take"), "a filled bay offers take: the slot change reached the cached menu")
	TEST_ASSERT_NOTNULL(outcome_after_wait, "the wait ended with an outcome once time passed")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 8: a station-wide cascade under budget, with no lost effects and no dropped notices.
// Exercises: marked fan-out, phase S and the notice queue (sections 2, 7, 8). Measures whether membership edges can be promoted to inline.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p08_cascade_under_budget

#define E0_CASCADE_LAMPS 60
#define E0_CASCADE_CHAIN 5

/datum/unit_test/dq_e0_proof/p08_cascade_under_budget/run_proof()
	var/list/lamps = list()
	for(var/i in 1 to E0_CASCADE_LAMPS)
		lamps += allocate(/obj/e0_fixture/lamp)
	test_budget(LANE_SIMULATION, 20 * TEST_EVAL_COST) // 20 evaluations per marked drain: 60 lamps cannot settle in one
	test_counters_reset()
	GLOB.e0_chain_handled = 0
	e0_flip_night(TRUE)
	e0_start_notice_chain(E0_CASCADE_CHAIN)
	var/ticks = 0
	var/settled = FALSE
	for(var/i in 1 to 30) // successive ticks: each tick's D, P and R drains recompute what the budget allows
		test_time(world.tick_lag)
		test_drain()
		ticks++
		settled = TRUE
		for(var/obj/e0_fixture/lamp/L as anything in lamps)
			if(L.e0_lamp_range != E0_LAMP_NIGHT_RANGE)
				settled = FALSE
				break
		if(settled)
			break
	var/spills = test_spill_count()
	var/handled = GLOB.e0_chain_handled
	var/published = test_notice_count(/datum/notice/e0_chain) + test_notice_queued_count(/datum/notice/e0_chain)
	var/unsettled = 0
	for(var/obj/e0_fixture/lamp/L as anything in lamps)
		if(L.e0_lamp_range != E0_LAMP_NIGHT_RANGE)
			unsettled++
	E0_GATE
	TEST_ASSERT(spills > 0, "60 lamps against a 20-evaluation budget spill: the marked pass stopped at its budget")
	TEST_ASSERT(ticks > 1, "so the cascade took more than one drain point")
	TEST_ASSERT(settled, "and it settled: no effect was lost")
	TEST_ASSERT_EQUAL(unsettled, 0, "every lamp reads the night range at the end")
	TEST_ASSERT_EQUAL(handled, E0_CASCADE_CHAIN, "the handler ran once per notice in the chain: none dropped")
	TEST_ASSERT_EQUAL(published, E0_CASCADE_CHAIN, "the engine counted every notice, published or queued")

#undef E0_CASCADE_LAMPS
#undef E0_CASCADE_CHAIN

// ---------------------------------------------------------------------------------------------------------------------
// Proof 9: a construction with two predecessors undoes to the actual one, with the right refund.
// Exercises: state graphs, history and the ledger (X4, section 12). The door-assembly graph and a subtype placed finished.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p09_two_predecessors_undo_to_the_actual_one

/// A refunded item of `type` on `where`'s turf, tracked for cleanup. `ignore` is an item the test itself put on the floor: it is no refund.
/datum/unit_test/dq_e0_proof/p09_two_predecessors_undo_to_the_actual_one/proc/find_refund(type, atom/where, obj/item/ignore)
	var/obj/item/found = null
	for(var/obj/item/candidate in get_turf(where))
		if(istype(candidate, type) && candidate != ignore)
			found = candidate
			break
	if(found)
		LAZYADD(allocated, found)
	return found

/datum/unit_test/dq_e0_proof/p09_two_predecessors_undo_to_the_actual_one/run_proof()
	var/mob/living/simple_mob/e0_fixture/actor = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil)
	var/obj/item/e0_fixture/board/board = allocate(/obj/item/e0_fixture/board)
	var/obj/item/e0_fixture/door_kit/kit = allocate(/obj/item/e0_fixture/door_kit)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	// The board path: frame, wired, boarded, finished, then back by the same tool.
	var/obj/e0_fixture/door_assembly/boarded_path = allocate(/obj/e0_fixture/door_assembly)
	test_record(actor, boarded_path, board)
	test_click(actor, boarded_path, coil)
	test_click(actor, boarded_path, board)
	test_click(actor, boarded_path, screwdriver)
	var/boarded_at_finish = built(boarded_path, STAGE_DOOR_BOARDED)
	var/wired_material = built_material(boarded_path, STAGE_DOOR_WIRED)
	test_click(actor, boarded_path, screwdriver) // from finished the same tool undoes
	var/boarded_after_undo = built(boarded_path, STAGE_DOOR_BOARDED)
	var/finished_after_undo = built(boarded_path, STAGE_DOOR_FINISHED)
	var/list/boarded_events = test_recorded()
	var/obj/item/e0_fixture/door_kit/kit_from_board_path = find_refund(/obj/item/e0_fixture/door_kit, boarded_path, kit)
	// The kit path: frame, wired, finished by the prefab kit, then back by the crowbar.
	var/obj/e0_fixture/door_assembly/kit_path = allocate(/obj/e0_fixture/door_assembly)
	test_record(actor, kit_path, kit)
	test_click(actor, kit_path, coil)
	test_click(actor, kit_path, kit)
	var/finished_by_kit = built(kit_path, STAGE_DOOR_FINISHED)
	var/boarded_on_kit_path = built(kit_path, STAGE_DOOR_BOARDED)
	test_click(actor, kit_path, crowbar)
	var/wired_after_undo = built(kit_path, STAGE_DOOR_WIRED)
	var/finished_after_kit_undo = built(kit_path, STAGE_DOOR_FINISHED)
	var/boarded_after_kit_undo = built(kit_path, STAGE_DOOR_BOARDED)
	var/list/kit_events = test_recorded()
	var/obj/item/e0_fixture/door_kit/refunded_kit = find_refund(/obj/item/e0_fixture/door_kit, kit_path)
	// A subtype placed finished: the history is seeded along the declared path, and an undo past the seed refunds nothing.
	var/obj/e0_fixture/door_assembly/finished/placed = allocate(/obj/e0_fixture/door_assembly/finished)
	var/placed_built = built(placed, STAGE_DOOR_FINISHED)
	var/placed_boarded = built(placed, STAGE_DOOR_BOARDED)
	var/list/logs = test_logs()
	E0_GATE
	TEST_ASSERT_EQUAL(boarded_at_finish, TRUE, "built(boarded) holds on the board path")
	TEST_ASSERT_EQUAL(wired_material, e0_var(coil, "material"), "built_material() is the material the wired stage actually took")
	TEST_ASSERT_EQUAL(boarded_after_undo, TRUE, "undoing finished on the board path returns to boarded")
	TEST_ASSERT_EQUAL(finished_after_undo, FALSE, "and finished is no longer built")
	TEST_ASSERT_NULL(kit_from_board_path, "the board stays in its slot: nothing is refunded when undoing the screwdriver edge")
	TEST_ASSERT_EQUAL(finished_by_kit, TRUE, "the kit path reaches finished")
	TEST_ASSERT_EQUAL(boarded_on_kit_path, FALSE, "a stage the instance never passed is not built")
	TEST_ASSERT_EQUAL(wired_after_undo, TRUE, "undoing the kit edge goes to wired, the actual predecessor, not boarded")
	TEST_ASSERT_EQUAL(finished_after_kit_undo, FALSE, "finished is gone")
	TEST_ASSERT_EQUAL(boarded_after_kit_undo, FALSE, "and boarded was never visited")
	TEST_ASSERT_NOTNULL(refunded_kit, "the ledger entry of the kit edge refunds one door kit")
	TEST_ASSERT(test_events_count(boarded_events, TEST_EVENT_TRANSFER) > 0, "the board path recorded its slot transfers")
	TEST_ASSERT(test_events_count(kit_events, TEST_EVENT_COMMIT) > 0, "the kit path recorded the resource commits its edges made")
	TEST_ASSERT_EQUAL(placed_built, TRUE, "a placed-finished assembly is finished")
	TEST_ASSERT_EQUAL(placed_boarded, TRUE, "and the declared via path seeds boarded into its history")
	TEST_ASSERT_NOTNULL(logs, "test_logs() returns the ledger lines")

// ---------------------------------------------------------------------------------------------------------------------
// Proof 10: a tracked setting with a schema clamps a bad UI write, and the generated UI type matches.
// Exercises: value schemas (X5, section 4). The pump of section 4 and the file build.sh ui-types writes.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e0_proof/p10_schema_clamps_and_types_match

/datum/unit_test/dq_e0_proof/p10_schema_clamps_and_types_match/run_proof()
	var/mob/living/simple_mob/e0_fixture/actor = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/e0_fixture/pump/P = allocate(/obj/e0_fixture/pump)
	var/datum/op_result/set_result = test_ui(actor, P, "set_pressure", list("pressure" = 99999))
	var/pressure = P.target_pressure
	var/list/logs = test_logs()
	var/clamp_logged = FALSE
	for(var/datum/test_log/line in logs)
		if(findtext(line.text, "clamp"))
			clamp_logged = TRUE
	var/schema_text = schema_range_text(/obj/e0_fixture/pump, "target_pressure")
	// The file build.sh ui-types writes: the doc comment on the field must equal the schema's own range text, and the type stays number.
	var/ts_path = "tgui/packages/tgui/interfaces/generated/E0Pump.d.ts"
	var/ts_text = fexists(ts_path) ? file2text(ts_path) : null
	if(isnull(ts_text))
		e0_pending(ENGINE_E5, "ui_shape to TypeScript generator: [ts_path] with a /** num 0..MAX_PUMP_PRESSURE step 1 */ doc comment on the field")
	var/ts_comment
	var/ts_type_is_number = FALSE
	if(ts_text)
		var/regex/doc_comment = regex(@"(?:/)\*\* ([^*]+?) \*/[\r\n\t ]*target_pressure\??: ([a-z]+)") // not opening with a slash: DM would read that as a delimited /pattern/flags
		if(doc_comment.Find(ts_text))
			ts_comment = doc_comment.group[1]
			ts_type_is_number = doc_comment.group[2] == "number"
	E0_GATE
	TEST_ASSERT_NOTNULL(set_result, "the press resolved")
	TEST_ASSERT_EQUAL(pressure, MAX_PUMP_PRESSURE, "99999 is clamped to the schema's ceiling, and the handler saw the clamped value")
	TEST_ASSERT(clamp_logged, "the clamp is logged")
	TEST_ASSERT_NOTNULL(schema_text, "the schema reports its own range text")
	TEST_ASSERT_EQUAL(ts_comment, schema_text, "the generated doc comment equals the schema's own range text")
	TEST_ASSERT(ts_type_is_number, "while the TypeScript type stays number")

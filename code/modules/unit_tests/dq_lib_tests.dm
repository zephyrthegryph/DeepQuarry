// The library capabilities of the rewrite (doc/rewrite/final_api.html, section 11 and section 16): reagent_container, interior, stackable, trait,
// natural_weapon and the examine and look entries. Every test drives the engine through the test driver (test_click, test_menu, test_answer,
// test_time, perform_op) on the fixtures of code/tests/library/fixtures.dm and reads what the world did, so a test fails when the capability does not
// do its job (an amount that is off by one, a reservation that leaks, a roll that is not made).

/datum/unit_test/dq_lib
	abstract_type = /datum/unit_test/dq_lib

/datum/unit_test/dq_lib/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_lib/proc/run_gate()
	return

/// A fixture actor with hands, and a reagent holder of its own for drinking and being injected.
/datum/unit_test/dq_lib/proc/actor()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	if(!M.reagents)
		M.create_reagents(60)
	return M

/// A container of `type` holding `amount` units of water.
/datum/unit_test/dq_lib/proc/filled(type, amount)
	var/atom/movable/C = allocate(type)
	if(amount > 0)
		C.reagents.add_reagent(REAGENT_ID_WATER, amount)
	return C

// ---------------------------------------------------------------------------------------------------------------------
// reagent_container: a pour is one transaction.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib/reagent_pour_moves_exactly_the_amount

/datum/unit_test/dq_lib/reagent_pour_moves_exactly_the_amount/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/flask/source = filled(/obj/item/lib_fixture/flask, 20)
	var/obj/item/lib_fixture/flask/sink = filled(/obj/item/lib_fixture/flask, 0)
	test_record(M, source, sink)
	var/datum/op_result/poured = test_click(M, sink, source)
	var/list/events = test_recorded()
	TEST_ASSERT_NOTNULL(poured, "a held container clicked on another resolves")
	TEST_ASSERT_EQUAL(poured.key, "reagent_container.pour", "to the pour op")
	TEST_ASSERT_EQUAL(poured.outcome, ACT_COMMITTED, "which commits")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 15, "the source gave exactly the default transfer amount (5)")
	TEST_ASSERT_EQUAL(sink.reagents.total_volume, 5, "and the sink took exactly it")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_RESERVE), 1, "one reservation is the engine's to track: the source's volume (it carries the sink's capacity hold)")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_COMMIT), 1, "committed together by the one reservation the engine tracks")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_RELEASE), 0, "and nothing was released")
	TEST_ASSERT_EQUAL(reagents_reserved(source, FALSE) + reagents_reserved(sink, TRUE), 0, "no hold outlives the op")

/datum/unit_test/dq_lib/reagent_pour_refuses_a_full_sink_before_anything_leaves

/datum/unit_test/dq_lib/reagent_pour_refuses_a_full_sink_before_anything_leaves/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/flask/source = filled(/obj/item/lib_fixture/flask, 20)
	var/obj/item/lib_fixture/flask/sink = filled(/obj/item/lib_fixture/flask, 30)
	test_record(M, source, sink)
	var/datum/op_result/refused = test_click(M, sink, source)
	var/list/events = test_recorded()
	TEST_ASSERT_NOTNULL(refused, "the click resolves")
	TEST_ASSERT_EQUAL(refused.outcome, ACT_REFUSED, "a full sink refuses")
	TEST_ASSERT_EQUAL(refused.reason, MSG(reagent_container/full), "with its reason")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 20, "nothing left the source")
	TEST_ASSERT_EQUAL(sink.reagents.total_volume, 30, "and the sink is unchanged")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_RESERVE), 0, "nothing was even reserved")

/// The transaction itself, outside an op: res_spend() is all or nothing, and what it spends is the sink's room, not the source's volume.
/datum/unit_test/dq_lib/reagent_transaction_is_all_or_nothing

/datum/unit_test/dq_lib/reagent_transaction_is_all_or_nothing/run_gate()
	var/obj/item/lib_fixture/flask/source = filled(/obj/item/lib_fixture/flask, 20)
	var/obj/item/lib_fixture/flask/almost_full = filled(/obj/item/lib_fixture/flask, 27)
	var/spent_into_full = res_spend(source, RES_REAGENTS, 10, null, source, almost_full)
	TEST_ASSERT_EQUAL(spent_into_full, 0, "10 units do not fit in 3 of room: the reservation is refused whole")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 20, "so the source lost nothing")
	TEST_ASSERT_EQUAL(almost_full.reagents.total_volume, 27, "and the sink gained nothing")
	TEST_ASSERT_EQUAL(reagents_reserved(source, FALSE) + reagents_reserved(almost_full, TRUE), 0, "and no hold is left behind")
	var/spent_in_room = res_spend(source, RES_REAGENTS, 3, null, source, almost_full)
	TEST_ASSERT_EQUAL(spent_in_room, 3, "3 units fit")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 17, "the source lost them")
	TEST_ASSERT_EQUAL(almost_full.reagents.total_volume, 30, "the sink took them, to the brim")

/// A syringe's injection waits; the target fills up during the wait; nothing was reserved, so the syringe keeps its contents.
/datum/unit_test/dq_lib/reagent_inject_rechecks_after_the_wait

/datum/unit_test/dq_lib/reagent_inject_rechecks_after_the_wait/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/patient = actor()
	var/obj/item/lib_fixture/syringe/S = filled(/obj/item/lib_fixture/syringe, 10)
	patient.reagents.maximum_volume = 20
	var/datum/op_result/injecting = test_click(M, patient, S)
	TEST_ASSERT_NOTNULL(injecting, "a syringe clicked on a mob resolves")
	TEST_ASSERT_EQUAL(injecting.key, "reagent_container.inject", "to the inject op")
	TEST_ASSERT_NULL(injecting.outcome, "extend() gave it a wait: it is pending")
	TEST_ASSERT_EQUAL(S.reagents.total_volume, 10, "nothing is spent while it waits")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(injecting.outcome, ACT_COMMITTED, "the wait ends and the injection commits")
	TEST_ASSERT_EQUAL(S.reagents.total_volume, 5, "the syringe gave its first transfer amount")
	TEST_ASSERT_EQUAL(patient.reagents.total_volume, 5, "and the patient has it")
	// the second injection: the patient fills up while it waits
	var/datum/op_result/second = test_click(M, patient, S)
	patient.reagents.add_reagent(REAGENT_ID_WATER, 15)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(second?.outcome, ACT_REFUSED, "a patient who filled up during the wait refuses the injection")
	TEST_ASSERT_EQUAL(second?.reason, MSG(reagent_container/full), "with the reason")
	TEST_ASSERT_EQUAL(S.reagents.total_volume, 5, "and the syringe kept what it had")

/datum/unit_test/dq_lib/reagent_lid_gates_the_ops

/datum/unit_test/dq_lib/reagent_lid_gates_the_ops/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/beaker/B = filled(/obj/item/lib_fixture/beaker, 40)
	var/obj/item/lib_fixture/flask/F = filled(/obj/item/lib_fixture/flask, 0)
	TEST_ASSERT_EQUAL(reagent_container_lid_open(B), FALSE, "a lidded container starts closed")
	var/datum/op_result/closed = test_click(M, F, B)
	TEST_ASSERT_EQUAL(closed?.outcome, ACT_REFUSED, "pouring from it is refused")
	TEST_ASSERT_EQUAL(closed?.reason, MSG(reagent_container/lid_closed), "because the lid is closed")
	TEST_ASSERT_EQUAL(B.reagents.total_volume, 40, "nothing moved")
	var/datum/op_result/opened = test_click(M, B, B)
	TEST_ASSERT_EQUAL(opened?.key, "reagent_container.lid", "used in hand it works the lid")
	TEST_ASSERT_EQUAL(reagent_container_lid_open(B), TRUE, "which is now open")
	var/datum/op_result/poured = test_click(M, F, B)
	TEST_ASSERT_EQUAL(poured?.outcome, ACT_COMMITTED, "and the same pour commits")
	TEST_ASSERT_EQUAL(F.reagents.total_volume, 5, "moving the default amount")
	var/obj/item/lib_fixture/flask/lidless = filled(/obj/item/lib_fixture/flask, 0)
	TEST_ASSERT_EQUAL(reagent_container_lid_open(lidless), TRUE, "a lidless container is open from the start")
	var/datum/op_result/no_lid_op = test_click(M, lidless, lidless)
	TEST_ASSERT(!no_lid_op || no_lid_op.key != "reagent_container.lid", "and has no lid op")
	var/datum/op_result/bare_hand = test_click(M, B, null)
	TEST_ASSERT(!bare_hand || bare_hand.key != "reagent_container.lid", "an empty hand on a container does not work its lid: it picks it up, as any item")
	for(var/obj/effect/temporary_effect/item_pickup_ghost/ghost in range(2, M))
		qdel(ghost) // the pickup animation a plain hand click on an item leaves behind

/datum/unit_test/dq_lib/reagent_transfer_amount_is_asked_and_checked

/datum/unit_test/dq_lib/reagent_transfer_amount_is_asked_and_checked/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/flask/source = filled(/obj/item/lib_fixture/flask, 30)
	var/obj/item/lib_fixture/flask/sink = filled(/obj/item/lib_fixture/flask, 0)
	var/datum/op_result/asking = test_menu(M, source, "reagent_container.set_amount")
	TEST_ASSERT_NOTNULL(asking, "the menu pick resolves")
	TEST_ASSERT_NULL(asking.outcome, "it waits for the number")
	var/datum/op_result/answered = test_answer(M, 10)
	TEST_ASSERT_EQUAL(answered?.outcome, ACT_COMMITTED, "a listed amount is accepted")
	test_click(M, sink, source)
	TEST_ASSERT_EQUAL(sink.reagents.total_volume, 10, "the next pour moves what was chosen")
	var/datum/op_result/asking_again = test_menu(M, source, "reagent_container.set_amount")
	var/datum/op_result/bad = test_answer(M, 7)
	TEST_ASSERT_NOTNULL(asking_again, "asked again")
	TEST_ASSERT_EQUAL(bad?.outcome, ACT_REFUSED, "an amount that is not listed is refused")
	TEST_ASSERT_EQUAL(bad?.reason, MSG(reagent_container/bad_amount), "with its reason")
	test_click(M, sink, source)
	TEST_ASSERT_EQUAL(sink.reagents.total_volume, 20, "and the chosen amount is unchanged (10 more)")
	// a bigger amount than the source holds moves what is there
	var/obj/item/lib_fixture/flask/small = filled(/obj/item/lib_fixture/flask, 4)
	var/obj/item/lib_fixture/flask/empty_sink = filled(/obj/item/lib_fixture/flask, 0)
	test_click(M, empty_sink, small)
	TEST_ASSERT_EQUAL(empty_sink.reagents.total_volume, 4, "a source with less than one transfer gives all it has")
	TEST_ASSERT_EQUAL(small.reagents.total_volume, 0, "and is empty")

/datum/unit_test/dq_lib/reagent_container_follows_configure

/datum/unit_test/dq_lib/reagent_container_follows_configure/run_gate()
	var/obj/item/lib_fixture/beaker/normal = allocate(/obj/item/lib_fixture/beaker)
	var/obj/item/lib_fixture/beaker/large/big = allocate(/obj/item/lib_fixture/beaker/large)
	TEST_ASSERT_EQUAL(normal.reagents.maximum_volume, 60, "the declared volume is the holder's")
	TEST_ASSERT_EQUAL(big.reagents.maximum_volume, 120, "configure(volume = 120) re-runs the body: the holder follows")
	var/datum/capability/lib/reagent_container/C = cap_of(big, CAP_REAGENT_CONTAINER)
	TEST_ASSERT(C?.lid, "and the other params are kept (the lid)")

/// fill, drink, splash and spray: the other four flows.
/datum/unit_test/dq_lib/reagent_other_flows

/datum/unit_test/dq_lib/reagent_other_flows/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	// fill: a flask draws from a tap, a closed tank of a declared type, by the tap's own amount (not its own)
	var/obj/lib_fixture/tap/tap = allocate(/obj/lib_fixture/tap)
	tap.reagents.add_reagent(REAGENT_ID_WATER, 50)
	var/obj/item/lib_fixture/flask/empty = filled(/obj/item/lib_fixture/flask, 0)
	var/datum/op_result/fill = test_click(M, tap, empty)
	TEST_ASSERT_EQUAL(fill?.key, "reagent_container.fill", "a held container on a tap is the fill op")
	TEST_ASSERT_EQUAL(empty.reagents.total_volume, 10, "it took the tap's amount")
	TEST_ASSERT_EQUAL(tap.reagents.total_volume, 40, "from the tap")
	var/obj/item/lib_fixture/flask/half = filled(/obj/item/lib_fixture/flask, 25)
	test_click(M, tap, half)
	TEST_ASSERT_EQUAL(half.reagents.total_volume, 30, "a flask with something in it draws only what fits")
	TEST_ASSERT_EQUAL(tap.reagents.total_volume, 35, "and the tap loses only that")
	// pour: an open tank of the same kind is poured into, not drawn from
	var/obj/lib_fixture/tank/tank = allocate(/obj/lib_fixture/tank)
	var/obj/item/lib_fixture/flask/pourer = filled(/obj/item/lib_fixture/flask, 20)
	var/datum/op_result/pour = test_click(M, tank, pourer)
	TEST_ASSERT_EQUAL(pour?.key, "reagent_container.pour", "a held container on an open tank is the pour op")
	// drink: a held container on yourself (a person with a mouth: it is swallowed)
	var/mob/living/carbon/human/drinker = allocate(/mob/living/carbon/human)
	var/obj/item/lib_fixture/flask/cup = filled(/obj/item/lib_fixture/flask, 12)
	var/before = drinker.ingested.total_volume
	var/datum/op_result/drink = test_click(drinker, drinker, cup, GESTURE_SELF)
	TEST_ASSERT_EQUAL(drink?.key, "reagent_container.drink", "a container with something in it clicked on yourself is drink")
	TEST_ASSERT_EQUAL(drinker.ingested.total_volume - before, 5, "the drinker has swallowed one transfer")
	TEST_ASSERT_EQUAL(cup.reagents.total_volume, 7, "from the cup")
	// splash: everything goes over the target and none of it is kept
	var/obj/item/lib_fixture/flask/bucket = filled(/obj/item/lib_fixture/flask, 25)
	var/obj/lib_fixture/dummy/target = allocate(/obj/lib_fixture/dummy)
	var/datum/op_result/splash = perform_op(M, target, "reagent_container.splash", bucket)
	TEST_ASSERT_EQUAL(splash?.outcome, ACT_COMMITTED, "a splash commits")
	TEST_ASSERT_EQUAL(bucket.reagents.total_volume, 0, "and throws everything")
	// spray: one transfer at a time, and a sprayer does not pour
	var/obj/item/lib_fixture/sprayer/sprayer = filled(/obj/item/lib_fixture/sprayer, 30)
	var/datum/op_result/spray = perform_op(M, target, "reagent_container.spray", sprayer)
	TEST_ASSERT_EQUAL(spray?.outcome, ACT_COMMITTED, "a spray commits")
	TEST_ASSERT_EQUAL(sprayer.reagents.total_volume, 25, "using one transfer (5)")
	var/has_pour = FALSE
	for(var/datum/centry/C as anything in table_of(sprayer).items)
		if(C.eff_key == "reagent_container.pour")
			has_pour = TRUE
	TEST_ASSERT(!has_pour, "a sprayer has no pour op")
	var/datum/op_result/speculative = perform_op(M, target, "reagent_container.pour", sprayer)
	TEST_ASSERT_NOTNULL(speculative, "calling an op nobody here has returns a result, not an error")
	TEST_ASSERT_EQUAL(speculative.outcome, ACT_REFUSED, "which is a refusal")
	TEST_ASSERT_EQUAL(speculative.reason, /datum/msg/op/unknown, "with the reason 'no such op'")
	TEST_ASSERT_EQUAL(sprayer.reagents.total_volume, 25, "and nothing was spent")

/// A setting that is the name of a var is read from the var: the volume, what it starts with, the lid it starts without, the amount and its range.
/datum/unit_test/dq_lib/reagent_settings_are_vars_of_the_type

/datum/unit_test/dq_lib/reagent_settings_are_vars_of_the_type/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/jug/stocked/jug = allocate(/obj/item/lib_fixture/jug/stocked)
	var/obj/item/lib_fixture/jug/small/small = allocate(/obj/item/lib_fixture/jug/small)
	TEST_ASSERT_EQUAL(jug.reagents.maximum_volume, 80, "the volume is the var's")
	TEST_ASSERT_EQUAL(jug.reagents.total_volume, 30, "what it starts with is the var's")
	TEST_ASSERT_EQUAL(reagent_container_lid_open(jug), TRUE, "a lidded container that starts open is open")
	TEST_ASSERT_EQUAL(small.reagents.maximum_volume, 25, "a subtype changes the volume on its var line")
	TEST_ASSERT_EQUAL(small.reagents.total_volume, 0, "and what it starts with")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(jug), 20, "the amount a transfer moves starts at the var's")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(small), 5, "and a subtype's")
	var/obj/item/lib_fixture/flask/sink = filled(/obj/item/lib_fixture/flask, 0)
	test_click(M, sink, jug)
	TEST_ASSERT_EQUAL(sink.reagents.total_volume, 20, "a click pours that much")
	// the range a person may choose: a whole number from the least to the most
	var/list/values = list(41, 1, 2, 40, 0)
	var/list/accepted = list(FALSE, FALSE, TRUE, TRUE, FALSE)
	for(var/i in 1 to length(values))
		var/value = values[i]
		var/wanted = accepted[i]
		test_menu(M, jug, "reagent_container.set_amount")
		var/datum/op_result/answered = test_answer(M, value)
		var/took = answered?.outcome == ACT_COMMITTED
		TEST_ASSERT_EQUAL(took, wanted, "an answer of [value] is accepted: [wanted]")

/// A container does not pour into or splash over what it is put on; a hostile click on a mob splashes it; a click on a mob feeds it after the wait.
/datum/unit_test/dq_lib/reagent_rests_on_things_and_feeds_after_a_wait

/datum/unit_test/dq_lib/reagent_rests_on_things_and_feeds_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human)
	var/obj/item/lib_fixture/jug/stocked/jug = allocate(/obj/item/lib_fixture/jug/stocked)
	var/obj/structure/table/table = allocate(/obj/structure/table)
	var/datum/op_result/onto_table = test_click(H, table, jug)
	TEST_ASSERT(!onto_table || !findtext(onto_table.key, "reagent_container."), "a click on a table is not a pour")
	TEST_ASSERT_EQUAL(jug.reagents.total_volume, 30, "and nothing left the jug")
	H.set_use_stance(I_HURT)
	var/datum/op_result/hostile_table = test_click(H, table, jug)
	TEST_ASSERT(!hostile_table || !findtext(hostile_table.key, "reagent_container."), "nor is a hostile one a splash")
	var/datum/op_result/hostile_person = test_click(H, patient, jug)
	TEST_ASSERT_EQUAL(hostile_person?.key, "reagent_container.splash", "a hostile click on a person splashes them")
	H.set_use_stance(I_HELP)
	jug.reagents.clear_reagents()
	jug.reagents.add_reagent(REAGENT_ID_WATER, 30)
	var/before = patient.ingested.total_volume
	var/datum/op_result/feeding = test_click(H, patient, jug)
	TEST_ASSERT_EQUAL(feeding?.key, "reagent_container.feed", "a click on another person feeds them")
	TEST_ASSERT_NULL(feeding?.outcome, "after a wait")
	TEST_ASSERT_EQUAL(patient.ingested.total_volume, before, "nothing is swallowed while it waits")
	test_time(3.5 SECONDS)
	TEST_ASSERT_EQUAL(feeding?.outcome, ACT_COMMITTED, "the wait ends and the feeding commits")
	TEST_ASSERT_EQUAL(patient.ingested.total_volume - before, 20, "the patient has swallowed one transfer")
	TEST_ASSERT_EQUAL(jug.reagents.total_volume, 10, "from the jug")
	own_turf_contents(get_turf(table))

// ---------------------------------------------------------------------------------------------------------------------
// interior: the escape.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib/interior_escape_waits_rolls_and_moves

/datum/unit_test/dq_lib/interior_escape_waits_rolls_and_moves/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/pod/pod = allocate(/obj/lib_fixture/pod)
	var/turf/outside = get_turf(pod)
	M.forceMove(pod)
	var/datum/op_result/escaping = test_click(M, pod, null)
	TEST_ASSERT_NOTNULL(escaping, "a click on the container from inside resolves")
	TEST_ASSERT_EQUAL(escaping.key, "interior.escape", "to the escape op")
	TEST_ASSERT_NULL(escaping.outcome, "which waits")
	TEST_ASSERT_EQUAL(M.loc, pod, "the actor is still inside while it waits")
	test_time(9 SECONDS)
	TEST_ASSERT_NULL(escaping.outcome, "still waiting a second before the end")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(escaping.outcome, ACT_COMMITTED, "the wait ends and the escape commits")
	TEST_ASSERT_EQUAL(escaping.rolled, TRUE, "the roll (100%) succeeded")
	TEST_ASSERT_EQUAL(M.loc, outside, "the actor is on the container's tile")
	// from the menu, the same op under the menu's origin
	M.forceMove(pod)
	var/datum/op_result/by_menu = test_menu(M, pod, "interior.escape")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(by_menu?.origin, ORIGIN_MENU, "picked from the context menu it runs with that origin")
	TEST_ASSERT_EQUAL(by_menu?.outcome, ACT_COMMITTED, "and commits")
	// from outside there is no escape
	var/datum/op_result/from_outside = test_click(M, pod, null)
	TEST_ASSERT(!from_outside || from_outside.key != "interior.escape", "outside, the escape is not the click's op")

/datum/unit_test/dq_lib/interior_escape_chance_is_rolled

/datum/unit_test/dq_lib/interior_escape_chance_is_rolled/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/pod/stubborn/stubborn = allocate(/obj/lib_fixture/pod/stubborn)
	M.forceMove(stubborn)
	test_rng(1)
	var/datum/op_result/failing = test_click(M, stubborn, null)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(failing?.outcome, ACT_COMMITTED, "a failed roll still ends committed (the struggle was made)")
	TEST_ASSERT_EQUAL(failing?.rolled, FALSE, "with the roll marked failed")
	TEST_ASSERT_EQUAL(M.loc, stubborn, "and the actor is still inside")
	TEST_ASSERT_EQUAL(test_rolls(), 1, "exactly one roll was drawn")
	// the chance named by a var of the holder
	var/obj/lib_fixture/pod/by_var/by_var = allocate(/obj/lib_fixture/pod/by_var)
	var/turf/outside = get_turf(by_var)
	by_var.chance_var = 0
	M.forceMove(by_var)
	var/datum/op_result/var_fail = test_click(M, by_var, null)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(var_fail?.rolled, FALSE, "escape_chance = nameof(var) reads the holder's var now (0%)")
	TEST_ASSERT_EQUAL(M.loc, by_var, "so the actor stays")
	by_var.chance_var = 100
	var/datum/op_result/var_ok = test_click(M, by_var, null)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(var_ok?.rolled, TRUE, "and 100% now")
	TEST_ASSERT_EQUAL(M.loc, outside, "so the actor is out")

// ---------------------------------------------------------------------------------------------------------------------
// stackable and the stack(T, n) + put_in() rule.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib/stackable_merge_moves_what_fits

/datum/unit_test/dq_lib/stackable_merge_moves_what_fits/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/sheets/held = allocate(/obj/item/lib_fixture/sheets)
	var/obj/item/lib_fixture/sheets/target = allocate(/obj/item/lib_fixture/sheets)
	held.amount = 6
	target.amount = 8
	var/datum/op_result/merged = test_click(M, target, held)
	TEST_ASSERT_EQUAL(merged?.key, "stackable.merge", "a stack clicked on a stack of the same type merges")
	TEST_ASSERT_EQUAL(merged?.outcome, ACT_COMMITTED, "and commits")
	TEST_ASSERT_EQUAL(target.amount, 10, "the target filled to its limit")
	TEST_ASSERT_EQUAL(held.amount, 4, "the held stack kept what did not fit (6 - 2)")
	var/datum/op_result/full = test_click(M, target, held)
	TEST_ASSERT_EQUAL(full?.outcome, ACT_REFUSED, "a full target refuses")
	TEST_ASSERT_EQUAL(full?.reason, MSG(stackable/full), "with its reason")
	TEST_ASSERT_EQUAL(held.amount, 4, "and nothing moved")
	var/datum/op_result/last = test_click(M, allocate(/obj/item/lib_fixture/sheets), held)
	TEST_ASSERT_EQUAL(last?.outcome, ACT_COMMITTED, "merging the rest into a stack of 1")
	TEST_ASSERT(QDELETED(held), "a held stack that gave all its units is used up")

/datum/unit_test/dq_lib/stackable_split_makes_a_new_stack

/datum/unit_test/dq_lib/stackable_split_makes_a_new_stack/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/lib_fixture/sheets/stack_item = allocate(/obj/item/lib_fixture/sheets)
	stack_item.amount = 8
	var/datum/op_result/asking = test_menu(M, stack_item, "stackable.split")
	TEST_ASSERT_NOTNULL(asking, "the menu pick resolves")
	var/datum/op_result/done = test_answer(M, 3)
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "a count inside the stack splits it")
	TEST_ASSERT_EQUAL(stack_item.amount, 5, "the stack kept the rest")
	var/pieces = 0
	var/turf/floor_turf = get_turf(stack_item)
	var/list/nearby = floor_turf.contents + M.contents
	for(var/obj/item/lib_fixture/sheets/other in nearby)
		if(other != stack_item)
			pieces += other.amount
	TEST_ASSERT_EQUAL(pieces, 3, "and exactly the split-off units are a new stack")
	for(var/obj/item/lib_fixture/sheets/leftover in nearby)
		if(leftover != stack_item)
			qdel(leftover)
	test_menu(M, stack_item, "stackable.split")
	var/datum/op_result/too_many = test_answer(M, 5)
	TEST_ASSERT_EQUAL(too_many?.outcome, ACT_REFUSED, "splitting off all of it is refused")
	TEST_ASSERT_EQUAL(too_many?.reason, MSG(stackable/bad_split), "with its reason")
	TEST_ASSERT_EQUAL(stack_item.amount, 5, "and nothing changed")

/// stack(T, n) with put_in(): the put splits off exactly n units and moves the split; the commit spends nothing further.
/datum/unit_test/dq_lib/stack_binding_with_put_in_splits_exactly_n

/datum/unit_test/dq_lib/stack_binding_with_put_in_splits_exactly_n/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e0_fixture/hopper/H = allocate(/obj/e0_fixture/hopper)
	var/obj/item/e0_fixture/sheets/pile = allocate(/obj/item/e0_fixture/sheets)
	pile.amount = 8
	var/datum/op_result/loading = test_click(M, H, pile)
	TEST_ASSERT_NOTNULL(loading, "the load op resolves")
	TEST_ASSERT_NULL(loading.outcome, "it waits")
	TEST_ASSERT_EQUAL(pile.amount, 8, "nothing is taken during the wait")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(loading.outcome, ACT_COMMITTED, "the load commits")
	TEST_ASSERT_EQUAL(pile.amount, 3, "the pile gave exactly E0_SHEETS_PER_LOAD (8 - 5): the commit spent nothing on top of the split")
	var/in_hopper = 0
	for(var/obj/item/e0_fixture/sheets/S in H)
		in_hopper += S.amount
	TEST_ASSERT_EQUAL(in_hopper, E0_SHEETS_PER_LOAD, "and the hopper holds the split, exactly n units")
	for(var/obj/item/e0_fixture/sheets/loaded in H)
		qdel(loaded)

// ---------------------------------------------------------------------------------------------------------------------
// trait.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib/trait_is_held_while_the_capability_is

/datum/unit_test/dq_lib/trait_is_held_while_the_capability_is/run_gate()
	var/obj/item/lib_fixture/hazmat/suit = allocate(/obj/item/lib_fixture/hazmat)
	TEST_ASSERT(has_trait(suit, TRAIT_RADIATION_PROTECTED_CLOTHING), "a type that declares trait() has it from init")
	var/list/lines = examine_collect(suit, null)
	var/hazmat_line = FALSE
	for(var/line in lines)
		if(findtext(line, "A hazmat patch is sewn on."))
			hazmat_line = TRUE
	TEST_ASSERT(hazmat_line, "and its examine line is collected")
	var/obj/item/lib_fixture/flask/plain = allocate(/obj/item/lib_fixture/flask)
	TEST_ASSERT(!has_trait(plain, TRAIT_RADIATION_PROTECTED_CLOTHING), "a type that does not has not")
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/activation/granted = grant(M, trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = "It hums."), source = plain)
	TEST_ASSERT_NOTNULL(granted, "a trait can be granted")
	TEST_ASSERT(has_trait(M, TRAIT_RADIATION_PROTECTED_CLOTHING), "and the holder has it")
	var/list/granted_lines = examine_collect(M, null)
	var/found = FALSE
	for(var/line in granted_lines)
		if(findtext(line, "It hums."))
			found = TRUE
	TEST_ASSERT(found, "its examine line shows on the grantee")
	revoke(M, trait(TRAIT_RADIATION_PROTECTED_CLOTHING), source = plain)
	TEST_ASSERT(!has_trait(M, TRAIT_RADIATION_PROTECTED_CLOTHING), "revoking takes it back")
	TEST_ASSERT_EQUAL(length(examine_collect(M, null)), 0, "with its line")

// ---------------------------------------------------------------------------------------------------------------------
// natural_weapon.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib/natural_weapon_bites_through_the_same_op

/datum/unit_test/dq_lib/natural_weapon_bites_through_the_same_op/run_gate()
	var/mob/living/simple_mob/lib_fixture_biter/biter = allocate(/mob/living/simple_mob/lib_fixture_biter)
	var/obj/lib_fixture/dummy/target = allocate(/obj/lib_fixture/dummy)
	var/before = target.get_integrity()
	var/datum/op_result/by_ai = perform_op(biter, target, "natural_weapon.attack", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(by_ai?.outcome, ACT_COMMITTED, "a mob with no hands bites through the op (AI origin): [reason_text(by_ai?.reason)]")
	TEST_ASSERT_EQUAL(before - target.get_integrity(), 10, "for exactly the declared damage")
	var/datum/op_result/cooling = perform_op(biter, target, "natural_weapon.attack", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(cooling?.outcome, ACT_REFUSED, "the cooldown refuses a second bite at once")
	TEST_ASSERT_EQUAL(cooling?.reason, /datum/msg/op/cooling_down, "with its reason")
	TEST_ASSERT_EQUAL(before - target.get_integrity(), 10, "and it did no damage")
	test_time(2 SECONDS)
	var/datum/op_result/again = perform_op(biter, target, "natural_weapon.attack", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(again?.outcome, ACT_COMMITTED, "once the cooldown is over it bites again: [reason_text(again?.reason)]")
	TEST_ASSERT_EQUAL(before - target.get_integrity(), 20, "the second bite landed")
	test_time(2 SECONDS)
	var/datum/op_result/by_self = perform_op(biter, biter, "natural_weapon.attack", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(by_self?.outcome, ACT_REFUSED, "the real natural weapon refuses a self attack")
	TEST_ASSERT_EQUAL(by_self?.reason, MSG(natural_weapon/self), "self attack retains its reason after the cooldown ends")
	// no hand ops: the mob has no hands, so a hand op of a machine is refused for want of a provider
	var/provider_kinds = 0
	for(var/datum/prov/P in providers_for(biter, null))
		provider_kinds |= P.aff()
	TEST_ASSERT(provider_kinds & AFF_ATTACK, "the mob's provider set has AFF_ATTACK")
	TEST_ASSERT(!(provider_kinds & AFF_MANIPULATE), "and no AFF_MANIPULATE: the bite is not a hand")

// ---------------------------------------------------------------------------------------------------------------------
// examine and look.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib/examine_lines_follow_their_conditions

/datum/unit_test/dq_lib/examine_lines_follow_their_conditions/run_gate()
	var/obj/lib_fixture/glow_box/box = allocate(/obj/lib_fixture/glow_box)
	var/list/dark = examine_collect(box, null)
	TEST_ASSERT_EQUAL(length(dark), 2, "two lines apply while it is dark: the fixed one and the computed one")
	TEST_ASSERT_EQUAL(dark[1], "It is a box.", "the fixed line first, in declaration order")
	TEST_ASSERT_EQUAL(dark[2], "A note says hello.", "then the handler's answer")
	box.set_lit(TRUE)
	var/list/lit = examine_collect(box, null)
	TEST_ASSERT_EQUAL(length(lit), 3, "a third line appears while the condition holds")
	TEST_ASSERT_EQUAL(lit[3], "It glows.", "the conditional line")
	box.shown_note = "A note says goodbye."
	TEST_ASSERT_EQUAL(examine_collect(box, null)[2], "A note says goodbye.", "a handler is asked every time")

/datum/unit_test/dq_lib/look_layers_follow_their_conditions

/datum/unit_test/dq_lib/look_layers_follow_their_conditions/run_gate()
	var/obj/lib_fixture/glow_box/box = allocate(/obj/lib_fixture/glow_box)
	TEST_ASSERT_EQUAL(jointext(look_layers_of(box), ","), "box", "while dark only the unconditional layer is drawn")
	box.set_lit(TRUE)
	TEST_ASSERT_EQUAL(jointext(look_layers_of(box), ","), "glow,box", "lit, the glow layer joins in declaration order")
	// a capability's layers: the beaker's lid and fill gauge
	var/obj/item/lib_fixture/beaker/B = filled(/obj/item/lib_fixture/beaker, 30)
	var/list/layers = look_layers_of(B)
	TEST_ASSERT(LOOK_LID in layers, "a closed lid is a layer")
	TEST_ASSERT(("[LOOK_FILL_PREFIX]2" in layers), "half full is fill step 2 of 4")
	cap_key_set(B, REAGENT_CONTAINER_LID_OPEN, TRUE)
	layers = look_layers_of(B)
	TEST_ASSERT(!(LOOK_LID in layers), "opened, the lid layer goes")
	var/obj/item/lib_fixture/beaker/empty = allocate(/obj/item/lib_fixture/beaker)
	TEST_ASSERT_EQUAL(length(look_layers_of(empty)), 1, "an empty beaker draws only its lid")
	var/list/lines = examine_collect(B, null)
	TEST_ASSERT_EQUAL(lines[1], "It contains 30 of 60 units.", "its examine line says how full it is")

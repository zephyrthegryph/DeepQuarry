// Behaviour pins for the timed actions of code/modules (worker W4), recorded on the legacy task_timed forms before they become ops with wait().
// Same helpers and same rules as dq_timed_pin_behaviour.dm: a conversion keeps every assertion, a difference is a documented class in
// doc/rewrite/intended_changes.md.

/datum/unit_test/dq_timed_pin_w4
	abstract_type = /datum/unit_test/dq_timed_pin_w4
	parent_type = /datum/unit_test/dq_timed_pin

/// A mob given a ckey in a test leaves an observer behind: remove it.
/datum/unit_test/dq_timed_pin_w4/proc/forget_ghosts()
	for(var/mob/observer/dead/G in world)
		qdel(G)

// ---- Dumbbell: an item in hand, refused while too hungry ----

/datum/unit_test/dq_timed_pin_w4/dumbbell_exercise

/datum/unit_test/dq_timed_pin_w4/dumbbell_exercise/run_pin()
	var/mob/living/carbon/human/user = person()
	user.nutrition = 400
	var/obj/item/entrepreneur/dumbbell/D = allocate(/obj/item/entrepreneur/dumbbell, run_loc_floor_bottom_left)
	user.put_in_active_hand(D)
	test_chat_clear()
	test_click(user, D, D)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	test_time(2 SECONDS)
	TEST_ASSERT(user.nutrition > 395, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(user.nutrition < 395 && user.nutrition > 385, "it costs ten nutrition")
	TEST_ASSERT(said(user, "You successfully perform"), "it says it finished")

/datum/unit_test/dq_timed_pin_w4/dumbbell_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/dumbbell_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	user.nutrition = 400
	var/obj/item/entrepreneur/dumbbell/D = allocate(/obj/item/entrepreneur/dumbbell, run_loc_floor_bottom_left)
	user.put_in_active_hand(D)
	test_click(user, D, D)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(user.nutrition > 395, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/dumbbell_cancel_on_drop

/datum/unit_test/dq_timed_pin_w4/dumbbell_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	user.nutrition = 400
	var/obj/item/entrepreneur/dumbbell/D = allocate(/obj/item/entrepreneur/dumbbell, run_loc_floor_bottom_left)
	user.put_in_active_hand(D)
	test_click(user, D, D)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	user.drop_from_inventory(D)
	test_time(5 SECONDS)
	TEST_ASSERT(user.nutrition > 395, "dropping it cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/dumbbell_too_hungry

/datum/unit_test/dq_timed_pin_w4/dumbbell_too_hungry/run_pin()
	var/mob/living/carbon/human/user = person()
	user.nutrition = 50
	var/obj/item/entrepreneur/dumbbell/D = allocate(/obj/item/entrepreneur/dumbbell, run_loc_floor_bottom_left)
	user.put_in_active_hand(D)
	test_chat_clear()
	test_click(user, D, D)
	TEST_ASSERT_NULL(running(user), "a hungry user starts nothing")
	TEST_ASSERT(said(user, "too hungry"), "and is told why")
	test_time(5 SECONDS)
	TEST_ASSERT(user.nutrition < 55, "and spends nothing")

// ---- Anomaly core: an anomaly releaser used on it ----

/datum/unit_test/dq_timed_pin_w4/anomaly_core_release

/datum/unit_test/dq_timed_pin_w4/anomaly_core_release/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/assembly/signaler/anomaly/flux/core = allocate(/obj/item/assembly/signaler/anomaly/flux, run_loc_floor_bottom_left)
	var/obj/item/anomaly_releaser/rel = allocate(/obj/item/anomaly_releaser, run_loc_floor_bottom_left)
	user.put_in_active_hand(rel)
	test_click(user, core, rel)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a releaser on a core starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(core) && !rel.used, "nothing happens before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(rel.used, "the releaser is used up")
	TEST_ASSERT(QDELETED(core), "the core is consumed")
	var/found = FALSE
	for(var/obj/effect/anomaly/anom in range(2, run_loc_floor_bottom_left))
		found = TRUE
		qdel(anom)
	TEST_ASSERT(found, "an anomaly is released")

/datum/unit_test/dq_timed_pin_w4/anomaly_core_release_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/anomaly_core_release_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/assembly/signaler/anomaly/flux/core = allocate(/obj/item/assembly/signaler/anomaly/flux, run_loc_floor_bottom_left)
	var/obj/item/anomaly_releaser/rel = allocate(/obj/item/anomaly_releaser, run_loc_floor_bottom_left)
	user.put_in_active_hand(rel)
	test_click(user, core, rel)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a releaser on a core starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!rel.used && !QDELETED(core), "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/anomaly_core_used_releaser

/datum/unit_test/dq_timed_pin_w4/anomaly_core_used_releaser/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/assembly/signaler/anomaly/flux/core = allocate(/obj/item/assembly/signaler/anomaly/flux, run_loc_floor_bottom_left)
	var/obj/item/anomaly_releaser/rel = allocate(/obj/item/anomaly_releaser, run_loc_floor_bottom_left)
	rel.used = TRUE
	user.put_in_active_hand(rel)
	test_click(user, core, rel)
	TEST_ASSERT_NULL(running(user), "a used releaser starts nothing")
	test_time(5 SECONDS)
	TEST_ASSERT(!QDELETED(core), "and the core stays")

// ---- Survey beacon: a survey scanner logs its readings ----

/datum/unit_test/dq_timed_pin_w4/survey_beacon_log

/datum/unit_test/dq_timed_pin_w4/survey_beacon_log/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/expedition_survey_beacon/B = allocate(/obj/structure/expedition_survey_beacon, run_loc_floor_bottom_left)
	var/obj/item/survey_scanner/S = allocate(/obj/item/survey_scanner, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	test_chat_clear()
	test_click(user, B, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a scanner on a beacon starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	TEST_ASSERT(said(user, "You begin logging"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.scanned, "not logged before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(B.scanned, "logged at the end")
	TEST_ASSERT(said(user, "Survey data logged"), "it says it finished")

/datum/unit_test/dq_timed_pin_w4/survey_beacon_cancel_on_drop

/datum/unit_test/dq_timed_pin_w4/survey_beacon_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/expedition_survey_beacon/B = allocate(/obj/structure/expedition_survey_beacon, run_loc_floor_bottom_left)
	var/obj/item/survey_scanner/S = allocate(/obj/item/survey_scanner, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	test_click(user, B, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a scanner on a beacon starts a timed action")
	user.drop_from_inventory(S)
	test_time(5 SECONDS)
	TEST_ASSERT(!B.scanned, "dropping the scanner cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/survey_beacon_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/survey_beacon_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/expedition_survey_beacon/B = allocate(/obj/structure/expedition_survey_beacon, run_loc_floor_bottom_left)
	var/obj/item/survey_scanner/S = allocate(/obj/item/survey_scanner, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	test_click(user, B, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a scanner on a beacon starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!B.scanned, "moving cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/survey_beacon_already_logged

/datum/unit_test/dq_timed_pin_w4/survey_beacon_already_logged/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/expedition_survey_beacon/B = allocate(/obj/structure/expedition_survey_beacon, run_loc_floor_bottom_left)
	var/obj/item/survey_scanner/S = allocate(/obj/item/survey_scanner, run_loc_floor_bottom_left)
	B.scanned = TRUE
	user.put_in_active_hand(S)
	test_chat_clear()
	test_click(user, B, S)
	TEST_ASSERT_NULL(running(user), "a logged beacon starts nothing")
	TEST_ASSERT(said(user, "already been logged"), "and says why")

// ---- Log: cut into planks with a sharp item (the time depends on the item) ----

/datum/unit_test/dq_timed_pin_w4/log_cut_planks

/datum/unit_test/dq_timed_pin_w4/log_cut_planks/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/stack/material/log/L = allocate(/obj/item/stack/material/log, run_loc_floor_bottom_left, 2)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	var/expected = round((3 SECONDS / max(K.force / 10, 1)) * K.toolspeed)
	TEST_ASSERT(expected > 2, "the knife makes a measurable time")
	test_chat_clear()
	test_click(user, L, K)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a knife on a log starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == expected, "it lasts as long as the knife's force and speed make it")
	test_time(expected - 1 SECONDS)
	TEST_ASSERT_EQUAL(L.get_amount(), 2, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(L.get_amount(), 1, "one log is used")
	TEST_ASSERT(said(user, "You cut up a log into planks"), "it says it finished")
	var/obj/item/stack/material/wood/planks = locate() in user.loc
	TEST_ASSERT(!isnull(planks) && planks.get_amount() == 2, "two planks are made")
	qdel(planks)

/datum/unit_test/dq_timed_pin_w4/log_cut_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/log_cut_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/stack/material/log/L = allocate(/obj/item/stack/material/log, run_loc_floor_bottom_left, 2)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	test_click(user, L, K)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a knife on a log starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(20 SECONDS)
	TEST_ASSERT_EQUAL(L.get_amount(), 2, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/log_blunt_item

/datum/unit_test/dq_timed_pin_w4/log_blunt_item/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/stack/material/log/L = allocate(/obj/item/stack/material/log, run_loc_floor_bottom_left, 2)
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	user.put_in_active_hand(P)
	test_click(user, L, P)
	TEST_ASSERT_NULL(running(user), "a pen starts nothing")
	test_time(20 SECONDS)
	TEST_ASSERT_EQUAL(L.get_amount(), 2, "and spends nothing")

// ---- The One Pizza: a knife cuts through it slowly ----

/datum/unit_test/dq_timed_pin_w4/pizza_slice

/datum/unit_test/dq_timed_pin_w4/pizza_slice/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/theonepizza/P = allocate(/obj/structure/theonepizza, run_loc_floor_bottom_left)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	test_chat_clear()
	test_click(user, P, K)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a knife on the pizza starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 15 SECONDS, "it lasts fifteen seconds")
	TEST_ASSERT(said(user, "You start to slowly cut through"), "it says it began")
	test_time(14 SECONDS)
	TEST_ASSERT(!QDELETED(P), "the pizza is whole before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(P), "the pizza is consumed at the end")
	TEST_ASSERT(said(user, "You successfully cut"), "it says it finished")
	var/slices = 0
	for(var/obj/item/reagent_containers/food/snacks/sliceable/pizza/S in run_loc_floor_bottom_left)
		slices++
		qdel(S)
	TEST_ASSERT_EQUAL(slices, 5, "five giant slices are made")

/datum/unit_test/dq_timed_pin_w4/pizza_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/pizza_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/theonepizza/P = allocate(/obj/structure/theonepizza, run_loc_floor_bottom_left)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	test_click(user, P, K)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a knife on the pizza starts a timed action")
	test_time(3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(20 SECONDS)
	TEST_ASSERT(!QDELETED(P), "moving cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/pizza_other_item

/datum/unit_test/dq_timed_pin_w4/pizza_other_item/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/theonepizza/P = allocate(/obj/structure/theonepizza, run_loc_floor_bottom_left)
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	user.put_in_active_hand(pen)
	test_click(user, P, pen)
	TEST_ASSERT_NULL(running(user), "a pen starts nothing")

// ---- Candy bowl: searched by hand, one searcher at a time ----

/datum/unit_test/dq_timed_pin_w4/candybowl_search

/datum/unit_test/dq_timed_pin_w4/candybowl_search/run_pin()
	var/mob/living/carbon/human/user = person()
	user.ckey = "pinsearcher"
	var/obj/structure/candybowl/B = allocate(/obj/structure/candybowl, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on the bowl starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 5 SECONDS, "it lasts five seconds")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(length(user.get_all_held_items()), 0, "nothing is taken before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(user.get_active_held_item()), "a sweet is in hand at the end")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w4/candybowl_one_searcher

/datum/unit_test/dq_timed_pin_w4/candybowl_one_searcher/run_pin()
	var/mob/living/carbon/human/one = person()
	var/mob/living/carbon/human/two = person()
	one.ckey = "pinsearcher"
	two.ckey = "pinsearchertwo"
	var/obj/structure/candybowl/B = allocate(/obj/structure/candybowl, run_loc_floor_bottom_left)
	test_click(one, B, null)
	TEST_ASSERT(!isnull(running(one)), "the first searcher is running")
	test_chat_clear()
	test_click(two, B, null)
	TEST_ASSERT_NULL(running(two), "the second searcher is refused")
	TEST_ASSERT(said(two, "already looking through"), "and is told why")
	test_time(6 SECONDS)
	TEST_ASSERT(!isnull(one.get_active_held_item()), "the first searcher gets a sweet")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w4/candybowl_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/candybowl_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	user.ckey = "pinsearcher"
	var/obj/structure/candybowl/B = allocate(/obj/structure/candybowl, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on the bowl starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(6 SECONDS)
	TEST_ASSERT_NULL(user.get_active_held_item(), "moving cancels: nothing is taken")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w4/candybowl_empty

/datum/unit_test/dq_timed_pin_w4/candybowl_empty/run_pin()
	var/mob/living/carbon/human/user = person()
	user.ckey = "pinsearcher"
	var/obj/structure/candybowl/B = allocate(/obj/structure/candybowl, run_loc_floor_bottom_left)
	B.has_candy = FALSE
	test_chat_clear()
	test_click(user, B, null)
	TEST_ASSERT_NULL(running(user), "an empty bowl starts nothing")
	TEST_ASSERT(said(user, "there is no candy"), "and says why")
	forget_ghosts()

// ---- Spirit board: a drink slid across it ----

/datum/unit_test/dq_timed_pin_w4/spirit_board_slide

/datum/unit_test/dq_timed_pin_w4/spirit_board_slide/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/entrepreneur/spirit_board/B = allocate(/obj/item/entrepreneur/spirit_board, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/drinks/glass2/G = allocate(/obj/item/reagent_containers/food/drinks/glass2, run_loc_floor_bottom_left)
	B.next_result = "Yes"
	user.put_in_active_hand(G)
	test_click(user, B, G)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a glass on the board starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(B.next_result, "Yes", "the chosen result stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(B.next_result, 0, "the chosen result is used up at the end")

/datum/unit_test/dq_timed_pin_w4/spirit_board_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/spirit_board_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/entrepreneur/spirit_board/B = allocate(/obj/item/entrepreneur/spirit_board, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/drinks/glass2/G = allocate(/obj/item/reagent_containers/food/drinks/glass2, run_loc_floor_bottom_left)
	B.next_result = "Yes"
	user.put_in_active_hand(G)
	test_click(user, B, G)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a glass on the board starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(B.next_result, "Yes", "moving cancels: the result stands")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/spirit_board_not_a_drink

/datum/unit_test/dq_timed_pin_w4/spirit_board_not_a_drink/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/entrepreneur/spirit_board/B = allocate(/obj/item/entrepreneur/spirit_board, run_loc_floor_bottom_left)
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	user.put_in_active_hand(pen)
	test_chat_clear()
	test_click(user, B, pen)
	TEST_ASSERT_NULL(running(user), "a pen starts nothing")
	TEST_ASSERT(said(user, "glass, bottle or cup"), "and the board says what it needs")

// ---- Diagnostic instruments: used on a patient ----

/datum/unit_test/dq_timed_pin_w4/thermometer_reading

/datum/unit_test/dq_timed_pin_w4/thermometer_reading/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/patient = person(get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/thermometer_medical/I = allocate(/obj/item/thermometer_medical, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	test_chat_clear()
	test_click(user, patient, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "an instrument on a patient starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	TEST_ASSERT(said(user, "You take"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT(!said(user, "Reading:"), "no reading before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "Reading:"), "the reading is told at the end")

/datum/unit_test/dq_timed_pin_w4/thermometer_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/thermometer_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/patient = person(get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/thermometer_medical/I = allocate(/obj/item/thermometer_medical, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	test_click(user, patient, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "an instrument on a patient starts a timed action")
	user.forceMove(get_step(user, SOUTH))
	test_chat_clear()
	test_time(5 SECONDS)
	TEST_ASSERT(!said(user, "Reading:"), "moving cancels: no reading")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/thermometer_cancel_on_patient_leaving

/datum/unit_test/dq_timed_pin_w4/thermometer_cancel_on_patient_leaving/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/patient = person(get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/thermometer_medical/I = allocate(/obj/item/thermometer_medical, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	test_click(user, patient, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "an instrument on a patient starts a timed action")
	patient.forceMove(get_step(patient, EAST))
	test_chat_clear()
	test_time(5 SECONDS)
	TEST_ASSERT(!said(user, "Reading:"), "the patient leaving cancels: no reading")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/bp_cuff_reading

/datum/unit_test/dq_timed_pin_w4/bp_cuff_reading/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/patient = person(get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/bp_cuff/I = allocate(/obj/item/bp_cuff, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	test_chat_clear()
	test_click(user, patient, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the cuff on a patient starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 12 SECONDS, "it lasts twelve seconds")
	TEST_ASSERT(said(user, "You wrap"), "it says it began")
	test_time(11 SECONDS)
	TEST_ASSERT(!said(user, "Reading:") && !said(user, "pulse to measure"), "no reading before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "Reading:") || said(user, "pulse to measure"), "the reading is told at the end")

/datum/unit_test/dq_timed_pin_w4/oximeter_reading

/datum/unit_test/dq_timed_pin_w4/oximeter_reading/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/patient = person(get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/pulse_oximeter/I = allocate(/obj/item/pulse_oximeter, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	test_chat_clear()
	test_click(user, patient, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the oximeter on a patient starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 4 SECONDS, "it lasts four seconds")
	TEST_ASSERT(said(user, "You clip"), "it says it began")
	test_time(3 SECONDS)
	TEST_ASSERT(!said(user, "Reading:") && !said(user, "No signal"), "no reading before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "Reading:") || said(user, "No signal"), "the reading is told at the end")

// ---- A fuel tank: rig an assembly to it, then detach it ----

/datum/unit_test/dq_timed_pin_w4/fueltank_rig_and_detach

/datum/unit_test/dq_timed_pin_w4/fueltank_rig_and_detach/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/fueltank/F = allocate(/obj/structure/reagent_dispensers/fueltank, run_loc_floor_bottom_left)
	var/obj/item/assembly_holder/H = allocate(/obj/item/assembly_holder, run_loc_floor_bottom_left)
	user.put_in_active_hand(H)
	test_chat_clear()
	test_click(user, F, H)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "an assembly on the tank starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 2 SECONDS, "it lasts two seconds")
	TEST_ASSERT(said(user, "You begin rigging"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT_NULL(F.rig, "nothing is rigged before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(F.rig, H, "the assembly is rigged at the end")
	TEST_ASSERT(said(user, "You rig"), "it says it finished")
	test_chat_clear()
	test_click(user, F, null)
	T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on a rigged tank starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 2 SECONDS, "detaching lasts two seconds")
	TEST_ASSERT(said(user, "You begin to detach"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(F.rig, H, "still rigged before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(F.rig, "detached at the end")
	TEST_ASSERT(said(user, "You detach"), "it says it finished")

/datum/unit_test/dq_timed_pin_w4/fueltank_rig_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/fueltank_rig_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/fueltank/F = allocate(/obj/structure/reagent_dispensers/fueltank, run_loc_floor_bottom_left)
	var/obj/item/assembly_holder/H = allocate(/obj/item/assembly_holder, run_loc_floor_bottom_left)
	user.put_in_active_hand(H)
	test_click(user, F, H)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "an assembly on the tank starts a timed action")
	user.forceMove(get_step(user, SOUTH))
	test_time(4 SECONDS)
	TEST_ASSERT_NULL(F.rig, "moving cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- A rocky outcrop: dug with a pickaxe ----

/datum/unit_test/dq_timed_pin_w4/outcrop_dig

/datum/unit_test/dq_timed_pin_w4/outcrop_dig/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/outcrop/O = allocate(/obj/structure/outcrop, run_loc_floor_bottom_left)
	var/obj/item/pickaxe/P = allocate(/obj/item/pickaxe, run_loc_floor_bottom_left)
	user.put_in_active_hand(P)
	test_chat_clear()
	test_click(user, O, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a pickaxe on an outcrop starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 4 SECONDS, "it lasts four seconds")
	TEST_ASSERT(said(user, "begins to hack away"), "it says it began")
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(O), "the outcrop stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(O), "the outcrop is gone at the end")
	TEST_ASSERT(said(user, "You have finished digging"), "it says it finished")
	var/ores = 0
	for(var/obj/item/ore/ore in run_loc_floor_bottom_left)
		ores++
		qdel(ore)
	TEST_ASSERT(ores > 0, "ore is left behind")

/datum/unit_test/dq_timed_pin_w4/outcrop_cancel_on_drop

/datum/unit_test/dq_timed_pin_w4/outcrop_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/outcrop/O = allocate(/obj/structure/outcrop, run_loc_floor_bottom_left)
	var/obj/item/pickaxe/P = allocate(/obj/item/pickaxe, run_loc_floor_bottom_left)
	user.put_in_active_hand(P)
	test_click(user, O, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a pickaxe on an outcrop starts a timed action")
	user.drop_from_inventory(P)
	test_time(6 SECONDS)
	TEST_ASSERT(!QDELETED(O), "dropping the pickaxe cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Shredded paper: burned with a lit lighter ----

/datum/unit_test/dq_timed_pin_w4/shredded_paper_burn

/datum/unit_test/dq_timed_pin_w4/shredded_paper_burn/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/shreddedp/S = allocate(/obj/item/shreddedp, run_loc_floor_bottom_left)
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter, run_loc_floor_bottom_left)
	L.set_lit(1)
	user.put_in_active_hand(L)
	test_chat_clear()
	test_click(user, S, L)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a lit lighter on shredded paper starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 2 SECONDS, "it lasts two seconds")
	TEST_ASSERT(said(user, "burning it slowly"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT(!QDELETED(S), "the paper is whole before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(S), "the paper is burned at the end")
	TEST_ASSERT(said(user, "You burn right through"), "it says it finished")
	for(var/obj/effect/decal/cleanable/ash/ash in run_loc_floor_bottom_left)
		qdel(ash)

/datum/unit_test/dq_timed_pin_w4/shredded_paper_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/shredded_paper_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/shreddedp/S = allocate(/obj/item/shreddedp, run_loc_floor_bottom_left)
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter, run_loc_floor_bottom_left)
	L.set_lit(1)
	user.put_in_active_hand(L)
	test_click(user, S, L)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a lit lighter on shredded paper starts a timed action")
	test_chat_clear()
	user.forceMove(get_step(user, SOUTH))
	test_time(4 SECONDS)
	TEST_ASSERT(!QDELETED(S), "moving cancels: the paper stays")
	TEST_ASSERT(said(user, "You must hold"), "and says to hold steady")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/shredded_paper_unlit

/datum/unit_test/dq_timed_pin_w4/shredded_paper_unlit/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/shreddedp/S = allocate(/obj/item/shreddedp, run_loc_floor_bottom_left)
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter, run_loc_floor_bottom_left)
	user.put_in_active_hand(L)
	test_chat_clear()
	test_click(user, S, L)
	TEST_ASSERT_NULL(running(user), "an unlit lighter starts nothing")
	TEST_ASSERT(said(user, "is not lit"), "and says why")

// ---- A rig module: mended with nanopaste ----

/datum/unit_test/dq_timed_pin_w4/rig_module_mend

/datum/unit_test/dq_timed_pin_w4/rig_module_mend/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/rig_module/M = allocate(/obj/item/rig_module, run_loc_floor_bottom_left)
	var/obj/item/stack/nanopaste/N = allocate(/obj/item/stack/nanopaste, run_loc_floor_bottom_left, 3)
	M.damage = 2
	user.put_in_active_hand(N)
	test_chat_clear()
	test_click(user, M, N)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "nanopaste on a damaged module starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	TEST_ASSERT(said(user, "You start mending"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT(M.damage == 2 && N.get_amount() == 3, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(M.damage, 0, "the module is mended")
	TEST_ASSERT_EQUAL(N.get_amount(), 2, "one unit is used")
	TEST_ASSERT(said(user, "You mend the damage"), "it says it finished")

/datum/unit_test/dq_timed_pin_w4/rig_module_mend_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/rig_module_mend_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/rig_module/M = allocate(/obj/item/rig_module, run_loc_floor_bottom_left)
	var/obj/item/stack/nanopaste/N = allocate(/obj/item/stack/nanopaste, run_loc_floor_bottom_left, 3)
	M.damage = 2
	user.put_in_active_hand(N)
	test_click(user, M, N)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "nanopaste on a damaged module starts a timed action")
	user.forceMove(get_step(user, SOUTH))
	test_time(5 SECONDS)
	TEST_ASSERT(M.damage == 2 && N.get_amount() == 3, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/rig_module_undamaged

/datum/unit_test/dq_timed_pin_w4/rig_module_undamaged/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/rig_module/M = allocate(/obj/item/rig_module, run_loc_floor_bottom_left)
	var/obj/item/stack/nanopaste/N = allocate(/obj/item/stack/nanopaste, run_loc_floor_bottom_left, 3)
	user.put_in_active_hand(N)
	test_chat_clear()
	test_click(user, M, N)
	TEST_ASSERT_NULL(running(user), "an undamaged module starts nothing")
	TEST_ASSERT(said(user, "no damage to mend"), "and says why")

// ---- A water cooler: a bottle screwed on, a cup dispenser attached ----

/datum/unit_test/dq_timed_pin_w4/cooler_bottle

/datum/unit_test/dq_timed_pin_w4/cooler_bottle/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/glass/cooler_bottle/B = allocate(/obj/item/reagent_containers/glass/cooler_bottle, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_chat_clear()
	test_click(user, C, B)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bottle on the cooler starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 2 SECONDS, "it lasts two seconds")
	TEST_ASSERT(said(user, "You start to screw the bottle"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT(!C.bottle, "no bottle before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(C.bottle, "the bottle is on at the end")
	TEST_ASSERT(said(user, "You screw the bottle"), "it says it finished")
	TEST_ASSERT(QDELETED(B), "the bottle item is used up")

/datum/unit_test/dq_timed_pin_w4/cooler_bottle_cancel_on_drop

/datum/unit_test/dq_timed_pin_w4/cooler_bottle_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/glass/cooler_bottle/B = allocate(/obj/item/reagent_containers/glass/cooler_bottle, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_click(user, C, B)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bottle on the cooler starts a timed action")
	user.drop_from_inventory(B)
	test_time(4 SECONDS)
	TEST_ASSERT(!C.bottle && !QDELETED(B), "dropping the bottle cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/cooler_bottle_refusals

/datum/unit_test/dq_timed_pin_w4/cooler_bottle_refusals/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/glass/cooler_bottle/B = allocate(/obj/item/reagent_containers/glass/cooler_bottle, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	C.set_anchored(FALSE)
	test_chat_clear()
	test_click(user, C, B)
	TEST_ASSERT_NULL(running(user), "an unbolted cooler starts nothing")
	TEST_ASSERT(said(user, "wrench down the cooler first"), "and says why")
	C.set_anchored(TRUE)
	C.set_bottle(TRUE)
	test_chat_clear()
	test_click(user, C, B)
	TEST_ASSERT_NULL(running(user), "a cooler with a bottle starts nothing")
	TEST_ASSERT(said(user, "already a bottle"), "and says why")

/datum/unit_test/dq_timed_pin_w4/cooler_cupholder

/datum/unit_test/dq_timed_pin_w4/cooler_cupholder/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	var/obj/item/stack/material/plastic/P = allocate(/obj/item/stack/material/plastic, run_loc_floor_bottom_left, 3)
	user.put_in_active_hand(P)
	test_chat_clear()
	test_click(user, C, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "plastic on the cooler starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 2 SECONDS, "it lasts two seconds")
	TEST_ASSERT(said(user, "You start to attach a cup dispenser"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT(!C.cupholder && P.get_amount() == 3, "nothing is done before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(C.cupholder, "the cup dispenser is on at the end")
	TEST_ASSERT_EQUAL(P.get_amount(), 2, "one sheet is used")
	TEST_ASSERT(said(user, "You attach a cup dispenser"), "it says it finished")

/datum/unit_test/dq_timed_pin_w4/cooler_cupholder_cancel_on_move

/datum/unit_test/dq_timed_pin_w4/cooler_cupholder_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	var/obj/item/stack/material/plastic/P = allocate(/obj/item/stack/material/plastic, run_loc_floor_bottom_left, 3)
	user.put_in_active_hand(P)
	test_click(user, C, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "plastic on the cooler starts a timed action")
	user.forceMove(get_step(user, SOUTH))
	test_time(4 SECONDS)
	TEST_ASSERT(!C.cupholder && P.get_amount() == 3, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w4/cooler_cupholder_refusals

/datum/unit_test/dq_timed_pin_w4/cooler_cupholder_refusals/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	var/obj/item/stack/material/plastic/P = allocate(/obj/item/stack/material/plastic, run_loc_floor_bottom_left, 3)
	user.put_in_active_hand(P)
	C.set_anchored(FALSE)
	test_chat_clear()
	test_click(user, C, P)
	TEST_ASSERT_NULL(running(user), "an unbolted cooler starts nothing")
	TEST_ASSERT(said(user, "wrench down the cooler first"), "and says why")
	C.set_anchored(TRUE)
	C.cupholder = 1
	test_chat_clear()
	test_click(user, C, P)
	TEST_ASSERT_NULL(running(user), "a cooler with a cup dispenser starts nothing")
	TEST_ASSERT(said(user, "already a cup dispenser"), "and says why")

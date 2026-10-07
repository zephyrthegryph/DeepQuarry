// Behaviour pins for the timed actions of code/modules (worker Y), recorded on the legacy task_timed forms before they become ops with wait().
// Same helpers and same rules as dq_timed_pin_behaviour.dm: a conversion keeps every assertion, a difference is a documented class in
// doc/rewrite/intended_changes.md.

/datum/unit_test/dq_timed_pin_w6
	abstract_type = /datum/unit_test/dq_timed_pin_w6
	parent_type = /datum/unit_test/dq_timed_pin

/// A mob that still has a ckey when it is deleted leaves an observer behind: take the ckeys off.
/datum/unit_test/dq_timed_pin_w6/proc/forget_ghosts()
	for(var/mob/living/carbon/human/H in range(3, run_loc_floor_bottom_left))
		H.ckey = null

/// Clicks `target` with `held` and checks that a timed action of `dur` starts (and says `start_text` when given). Returns the running action.
/datum/unit_test/dq_timed_pin_w6/proc/begin(mob/user, atom/target, obj/item/held, dur, start_text = null)
	test_chat_clear()
	test_click(user, target, held)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	if(!isnull(dur))
		TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == dur, "it lasts [dur] ticks")
	if(start_text)
		TEST_ASSERT(said(user, start_text), "it says it began")
	return T

/// The held-in-hand form: puts `I` in the active hand.
/datum/unit_test/dq_timed_pin_w6/proc/hold(mob/living/carbon/human/user, obj/item/I)
	user.put_in_active_hand(I)
	return I

// ---- Generated station: the upload terminal and the department control override (bare hand) ----

/datum/unit_test/dq_timed_pin_w6/upload_terminal

/datum/unit_test/dq_timed_pin_w6/upload_terminal/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/generated_station_upload_terminal/term = allocate(/obj/machinery/generated_station_upload_terminal, run_loc_floor_bottom_left)
	begin(user, term, null, 5 SECONDS, "You begin uploading")
	test_time(4 SECONDS)
	TEST_ASSERT(!term.uploaded, "nothing is uploaded before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(term.uploaded, "the payload is resident at the end")
	TEST_ASSERT_NULL(running(user), "nothing is left running")
	test_click(user, term, null)
	TEST_ASSERT_NULL(running(user), "an uploaded terminal starts nothing")

/datum/unit_test/dq_timed_pin_w6/upload_terminal_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/upload_terminal_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/generated_station_upload_terminal/term = allocate(/obj/machinery/generated_station_upload_terminal, run_loc_floor_bottom_left)
	var/datum/T = begin(user, term, null, 5 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(7 SECONDS)
	TEST_ASSERT(!term.uploaded, "moving cancels: nothing is uploaded")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/department_override

/datum/unit_test/dq_timed_pin_w6/department_override/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/generated_station_department_control/C = allocate(/obj/machinery/generated_station_department_control, run_loc_floor_bottom_left)
	begin(user, C, null, 3 SECONDS, "You begin overriding")
	test_time(2 SECONDS)
	TEST_ASSERT(!C.captured, "nothing is captured before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(C.captured, "the control is captured at the end")
	test_click(user, C, null)
	TEST_ASSERT_NULL(running(user), "a captured control starts nothing")

/datum/unit_test/dq_timed_pin_w6/department_override_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/department_override_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/generated_station_department_control/C = allocate(/obj/machinery/generated_station_department_control, run_loc_floor_bottom_left)
	var/datum/T = begin(user, C, null, 3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!C.captured, "moving cancels: nothing is captured")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Beehive: the assembly in hand and the screwdriver on a hive ----

/datum/unit_test/dq_timed_pin_w6/beehive_assemble

/datum/unit_test/dq_timed_pin_w6/beehive_assemble/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beehive_assembly/A = allocate(/obj/item/beehive_assembly, run_loc_floor_bottom_left)
	hold(user, A)
	begin(user, A, A, 3 SECONDS, "You start assembling")
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(A), "the assembly stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(A), "the assembly is used up")
	var/obj/machinery/beehive/H = locate(/obj/machinery/beehive) in run_loc_floor_bottom_left
	TEST_ASSERT(!isnull(H), "a beehive stands where the user is")
	TEST_ASSERT(said(user, "You construct a beehive"), "it says it finished")
	if(H)
		qdel(H)

/datum/unit_test/dq_timed_pin_w6/beehive_assemble_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/beehive_assemble_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beehive_assembly/A = allocate(/obj/item/beehive_assembly, run_loc_floor_bottom_left)
	hold(user, A)
	var/datum/T = begin(user, A, A, 3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!QDELETED(A), "moving cancels: the assembly stays")
	TEST_ASSERT(isnull(locate(/obj/machinery/beehive) in run_loc_floor_bottom_left), "and no hive is built")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/beehive_dismantle

/datum/unit_test/dq_timed_pin_w6/beehive_dismantle/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/beehive/H = allocate(/obj/machinery/beehive, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	hold(user, S)
	begin(user, H, S, null, "You start dismantling")
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(H), "the hive stands before the end")
	test_time(6 SECONDS)
	TEST_ASSERT(QDELETED(H), "the hive is taken apart")
	var/obj/item/beehive_assembly/A = locate(/obj/item/beehive_assembly) in run_loc_floor_bottom_left
	TEST_ASSERT(!isnull(A), "an assembly is left")
	if(A)
		qdel(A)

/datum/unit_test/dq_timed_pin_w6/beehive_dismantle_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/beehive_dismantle_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/beehive/H = allocate(/obj/machinery/beehive, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	hold(user, S)
	var/datum/T = begin(user, H, S, null)
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(H), "moving cancels: the hive stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Halloween box pile: rummaged by hand, one at a time ----

/datum/unit_test/dq_timed_pin_w6/boxpile_rummage

/datum/unit_test/dq_timed_pin_w6/boxpile_rummage/run_pin()
	var/mob/living/carbon/human/user = person()
	user.ckey = "pinrummager"
	var/obj/structure/boxpile/B = allocate(/obj/structure/boxpile, run_loc_floor_bottom_left)
	test_chat_clear()
	begin(user, B, null, 5 SECONDS)
	test_time(4 SECONDS)
	TEST_ASSERT(!LAZYACCESS(B.ckeys_that_took, "pinrummager"), "nothing is found before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(LAZYACCESS(B.ckeys_that_took, "pinrummager"), "a costume is found at the end")
	TEST_ASSERT(said(user, "found a costume"), "it says it finished")
	for(var/obj/item/storage/box/halloween/X in run_loc_floor_bottom_left)
		qdel(X)
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w6/boxpile_one_rummager

/datum/unit_test/dq_timed_pin_w6/boxpile_one_rummager/run_pin()
	var/mob/living/carbon/human/one = person()
	var/mob/living/carbon/human/two = person()
	one.ckey = "pinrummager"
	two.ckey = "pinrummagertwo"
	var/obj/structure/boxpile/B = allocate(/obj/structure/boxpile, run_loc_floor_bottom_left)
	test_click(one, B, null)
	TEST_ASSERT(!isnull(running(one)), "the first rummager is running")
	test_click(two, B, null)
	// Legacy: the pile is claimed, so the second rummager starts nothing. The converted op claims the pile the same way.
	TEST_ASSERT_NULL(running(two), "the second rummager starts nothing")
	test_time(6 SECONDS)
	TEST_ASSERT(LAZYACCESS(B.ckeys_that_took, "pinrummager"), "the first rummager finds a costume")
	for(var/obj/item/storage/box/halloween/X in run_loc_floor_bottom_left)
		qdel(X)
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w6/boxpile_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/boxpile_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	user.ckey = "pinrummager"
	var/obj/structure/boxpile/B = allocate(/obj/structure/boxpile, run_loc_floor_bottom_left)
	var/datum/T = begin(user, B, null, 5 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(7 SECONDS)
	TEST_ASSERT(!LAZYACCESS(B.ckeys_that_took, "pinrummager"), "moving cancels: nothing is found")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
	forget_ghosts()

// ---- Bluespace extraction beacon signaller: activated in hand ----

/datum/unit_test/dq_timed_pin_w6/fulton_core_deploy

/datum/unit_test/dq_timed_pin_w6/fulton_core_deploy/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/fulton_core/C = allocate(/obj/item/fulton_core, run_loc_floor_bottom_left)
	hold(user, C)
	begin(user, C, C, 1.5 SECONDS)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(C), "the core stands before the end")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(C), "the core is replaced at the end")
	var/obj/structure/extraction_point/P = locate(/obj/structure/extraction_point) // the successor may be handed to the hand slot the core left
	TEST_ASSERT(!isnull(P), "a beacon stands where the core was")
	if(P)
		qdel(P)

/datum/unit_test/dq_timed_pin_w6/fulton_core_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/fulton_core_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/fulton_core/C = allocate(/obj/item/fulton_core, run_loc_floor_bottom_left)
	hold(user, C)
	var/datum/T = begin(user, C, C, 1.5 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(C), "moving cancels: the core stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Trail blazer: knocked down by hand ----

/datum/unit_test/dq_timed_pin_w6/trailblazer_knock_down

/datum/unit_test/dq_timed_pin_w6/trailblazer_knock_down/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/trailblazer/B = allocate(/obj/structure/trailblazer, run_loc_floor_bottom_left)
	begin(user, B, null, 8 SECONDS)
	test_time(7 SECONDS)
	TEST_ASSERT(!QDELETED(B), "the blazer stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(B), "the blazer is knocked down")
	var/obj/item/stack/lightpole/P = locate(/obj/item/stack/lightpole) in run_loc_floor_bottom_left
	TEST_ASSERT(!isnull(P), "a pole is left")
	if(P)
		qdel(P)

/datum/unit_test/dq_timed_pin_w6/trailblazer_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/trailblazer_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/trailblazer/B = allocate(/obj/structure/trailblazer, run_loc_floor_bottom_left)
	var/datum/T = begin(user, B, null, 8 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(10 SECONDS)
	TEST_ASSERT(!QDELETED(B), "moving cancels: the blazer stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Event kit generic item (in hand) and structure (by hand): a delay before it turns on ----

/datum/unit_test/dq_timed_pin_w6/generic_item_delayed

/datum/unit_test/dq_timed_pin_w6/generic_item_delayed/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/generic_item/I = allocate(/obj/item/generic_item, run_loc_floor_bottom_left)
	I.delay_time = 3 SECONDS
	hold(user, I)
	begin(user, I, I, 3 SECONDS)
	test_time(2 SECONDS)
	TEST_ASSERT(!I.on, "it is off before the delay ends")
	test_time(2 SECONDS)
	TEST_ASSERT(I.on, "it is on after the delay")
	// Used again, it turns off after the same delay.
	begin(user, I, I, 3 SECONDS)
	test_time(4 SECONDS)
	TEST_ASSERT(!I.on, "it is off after the second delay")

/datum/unit_test/dq_timed_pin_w6/generic_item_instant

/datum/unit_test/dq_timed_pin_w6/generic_item_instant/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/generic_item/I = allocate(/obj/item/generic_item, run_loc_floor_bottom_left)
	hold(user, I)
	test_click(user, I, I)
	TEST_ASSERT(I.on, "without a delay it turns on at once")

/datum/unit_test/dq_timed_pin_w6/generic_item_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/generic_item_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/generic_item/I = allocate(/obj/item/generic_item, run_loc_floor_bottom_left)
	I.delay_time = 3 SECONDS
	hold(user, I)
	var/datum/T = begin(user, I, I, 3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!I.on, "moving cancels: it stays off")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/generic_structure_delayed

/datum/unit_test/dq_timed_pin_w6/generic_structure_delayed/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/generic_structure/S = allocate(/obj/structure/generic_structure, run_loc_floor_bottom_left)
	S.delay_time = 3 SECONDS
	begin(user, S, null, 3 SECONDS)
	test_time(2 SECONDS)
	TEST_ASSERT(!S.on, "it is off before the delay ends")
	test_time(2 SECONDS)
	// The legacy delayed_use() called attack_hand() again, which never reached the op: the structure stayed off. The converted op turns it on.
	// (doc/rewrite/intended_changes.md, "a legacy runtime that the conversion removes".)
	if(!hascall(S, "delayed_use"))
		TEST_ASSERT(S.on, "it is on after the delay")
		begin(user, S, null, 3 SECONDS)
		test_time(4 SECONDS)
		TEST_ASSERT(!S.on, "it is off after the second delay")

/datum/unit_test/dq_timed_pin_w6/generic_structure_instant

/datum/unit_test/dq_timed_pin_w6/generic_structure_instant/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/generic_structure/S = allocate(/obj/structure/generic_structure, run_loc_floor_bottom_left)
	test_click(user, S, null)
	TEST_ASSERT(S.on, "without a delay it turns on at once")

/datum/unit_test/dq_timed_pin_w6/generic_structure_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/generic_structure_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/generic_structure/S = allocate(/obj/structure/generic_structure, run_loc_floor_bottom_left)
	S.delay_time = 3 SECONDS
	var/datum/T = begin(user, S, null, 3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!S.on, "moving cancels: it stays off")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Fishing rod: cable to string it ----

/datum/unit_test/dq_timed_pin_w6/fishing_rod_string

/datum/unit_test/dq_timed_pin_w6/fishing_rod_string/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/fishing_rod/built/R = allocate(/obj/item/material/fishing_rod/built, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	hold(user, C)
	begin(user, R, C, null)
	test_time(9 SECONDS)
	TEST_ASSERT(!R.strung && C.get_amount() == 10, "nothing is spent before the shortest time")
	test_time(12 SECONDS)
	TEST_ASSERT(R.strung, "the rod is strung by the longest time")
	TEST_ASSERT_EQUAL(C.get_amount(), 5, "five lengths are used")
	TEST_ASSERT(said(user, "You string"), "it says it finished")

/datum/unit_test/dq_timed_pin_w6/fishing_rod_string_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/fishing_rod_string_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/fishing_rod/built/R = allocate(/obj/item/material/fishing_rod/built, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	hold(user, C)
	var/datum/T = begin(user, R, C, null)
	user.forceMove(get_step(user, EAST))
	test_time(22 SECONDS)
	TEST_ASSERT(!R.strung && C.get_amount() == 10, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/fishing_rod_string_short_of_cable

/datum/unit_test/dq_timed_pin_w6/fishing_rod_string_short_of_cable/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/fishing_rod/built/R = allocate(/obj/item/material/fishing_rod/built, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 3)
	hold(user, C)
	test_click(user, R, C)
	TEST_ASSERT_NULL(running(user), "too little cable starts nothing")
	test_time(22 SECONDS)
	TEST_ASSERT(!R.strung && C.get_amount() == 3, "and spends nothing")

// ---- Meteorite: broken apart with a pickaxe ----

/datum/unit_test/dq_timed_pin_w6/meteorite_break_apart

/datum/unit_test/dq_timed_pin_w6/meteorite_break_apart/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/meteorite/M = allocate(/obj/structure/meteorite, run_loc_floor_bottom_left)
	var/obj/item/pickaxe/P = allocate(/obj/item/pickaxe, run_loc_floor_bottom_left)
	hold(user, P)
	begin(user, M, P, P.digspeed * 3, "You start")
	test_time(P.digspeed * 3 - 1 SECOND)
	TEST_ASSERT(!QDELETED(M), "the meteorite stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(M), "the meteorite is broken apart")
	for(var/obj/item/ore/O in run_loc_floor_bottom_left)
		qdel(O)
	for(var/obj/machinery/artifact/X in run_loc_floor_bottom_left)
		qdel(X)

/datum/unit_test/dq_timed_pin_w6/meteorite_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/meteorite_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/meteorite/M = allocate(/obj/structure/meteorite, run_loc_floor_bottom_left)
	var/obj/item/pickaxe/P = allocate(/obj/item/pickaxe, run_loc_floor_bottom_left)
	hold(user, P)
	var/datum/T = begin(user, M, P, null)
	user.forceMove(get_step(user, EAST))
	test_time(P.digspeed * 3 + 2 SECONDS)
	TEST_ASSERT(!QDELETED(M), "moving cancels: the meteorite stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/meteorite_cancel_on_drop

/datum/unit_test/dq_timed_pin_w6/meteorite_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/meteorite/M = allocate(/obj/structure/meteorite, run_loc_floor_bottom_left)
	var/obj/item/pickaxe/P = allocate(/obj/item/pickaxe, run_loc_floor_bottom_left)
	hold(user, P)
	var/datum/T = begin(user, M, P, null)
	user.drop_from_inventory(P)
	test_time(P.digspeed * 3 + 2 SECONDS)
	TEST_ASSERT(!QDELETED(M), "dropping the pickaxe cancels: the meteorite stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Shield generator: its wires replaced with cable ----

/datum/unit_test/dq_timed_pin_w6/shieldgen_rewire

/datum/unit_test/dq_timed_pin_w6/shieldgen_rewire/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/shieldgen/G = allocate(/obj/machinery/shieldgen, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	G.malfunction = 1
	G.set_is_open(TRUE)
	hold(user, C)
	begin(user, G, C, 3 SECONDS, "You begin to replace the wires")
	test_time(2 SECONDS)
	TEST_ASSERT(G.malfunction && C.get_amount() == 10, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!G.malfunction, "the generator is repaired")
	TEST_ASSERT_EQUAL(C.get_amount(), 9, "one length is used")
	TEST_ASSERT(said(user, "You repair"), "it says it finished")

/datum/unit_test/dq_timed_pin_w6/shieldgen_rewire_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/shieldgen_rewire_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/shieldgen/G = allocate(/obj/machinery/shieldgen, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	G.malfunction = 1
	G.set_is_open(TRUE)
	hold(user, C)
	var/datum/T = begin(user, G, C, 3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(G.malfunction && C.get_amount() == 10, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/shieldgen_rewire_not_broken

/datum/unit_test/dq_timed_pin_w6/shieldgen_rewire_not_broken/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/shieldgen/G = allocate(/obj/machinery/shieldgen, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	G.set_is_open(TRUE)
	hold(user, C)
	test_click(user, G, C)
	TEST_ASSERT_NULL(running(user), "an intact generator starts nothing")

// ---- Microwave: the eject entry of its menu ----

/datum/unit_test/dq_timed_pin_w6/microwave_eject

/datum/unit_test/dq_timed_pin_w6/microwave_eject/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/microwave/M = allocate(/obj/machinery/microwave, run_loc_floor_bottom_left)
	test_chat_clear()
	test_menu(user, M, "microwave_verb_eject")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the menu entry starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 1 SECOND, "it lasts one second")
	TEST_ASSERT(said(user, "You try to open"), "it says it began")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!said(user, "You have opened"), "nothing is taken out before the end")
	test_time(1 SECOND)
	TEST_ASSERT(said(user, "You have opened"), "it says it finished")

/datum/unit_test/dq_timed_pin_w6/microwave_eject_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/microwave_eject_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/microwave/M = allocate(/obj/machinery/microwave, run_loc_floor_bottom_left)
	test_menu(user, M, "microwave_verb_eject")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the menu entry starts a timed action")
	test_chat_clear()
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!said(user, "You have opened"), "moving cancels: nothing is taken out")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Microscope: a sample inserted, then examined by hand ----

/datum/unit_test/dq_timed_pin_w6/microscope_examine

/datum/unit_test/dq_timed_pin_w6/microscope_examine/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/microscope/M = allocate(/obj/machinery/microscope, run_loc_floor_bottom_left)
	var/obj/item/forensics/swab/S = allocate(/obj/item/forensics/swab, run_loc_floor_bottom_left)
	hold(user, S)
	test_click(user, M, S)
	TEST_ASSERT(M.sample() == S, "the swab is in the microscope")
	begin(user, M, null, 2 SECONDS, "The microscope whirrs")
	test_time(1 SECOND)
	TEST_ASSERT(!said(user, "Printing findings"), "nothing is printed before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "Printing findings"), "it prints at the end")
	var/obj/item/paper/P = locate(/obj/item/paper) in run_loc_floor_bottom_left
	TEST_ASSERT(!isnull(P), "a report is printed")
	if(P)
		qdel(P)

/datum/unit_test/dq_timed_pin_w6/microscope_examine_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/microscope_examine_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/microscope/M = allocate(/obj/machinery/microscope, run_loc_floor_bottom_left)
	var/obj/item/forensics/swab/S = allocate(/obj/item/forensics/swab, run_loc_floor_bottom_left)
	hold(user, S)
	test_click(user, M, S)
	var/datum/T = begin(user, M, null, 2 SECONDS)
	test_chat_clear()
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!said(user, "Printing findings"), "moving cancels: nothing is printed")
	TEST_ASSERT(said(user, "You stop examining"), "it says it stopped")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- A book: carved with a knife or wirecutters ----

/datum/unit_test/dq_timed_pin_w6/book_carve_knife

/datum/unit_test/dq_timed_pin_w6/book_carve_knife/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/book/B = allocate(/obj/item/book, run_loc_floor_bottom_left)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	hold(user, K)
	begin(user, B, K, 3 SECONDS, "You begin to carve out")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.carved, "nothing is carved before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(B.carved, "the pages are carved out")
	TEST_ASSERT(said(user, "You carve out the pages"), "it says it finished")
	var/obj/item/shreddedp/P = locate(/obj/item/shreddedp) in run_loc_floor_bottom_left
	TEST_ASSERT(!isnull(P), "shredded paper is left")
	if(P)
		qdel(P)
	test_click(user, B, K)
	TEST_ASSERT_NULL(running(user), "a carved book starts nothing")

/datum/unit_test/dq_timed_pin_w6/book_carve_knife_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/book_carve_knife_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/book/B = allocate(/obj/item/book, run_loc_floor_bottom_left)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	hold(user, K)
	var/datum/T = begin(user, B, K, 3 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!B.carved, "moving cancels: nothing is carved")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/book_carve_wirecutters

/datum/unit_test/dq_timed_pin_w6/book_carve_wirecutters/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/book/B = allocate(/obj/item/book, run_loc_floor_bottom_left)
	var/obj/item/tool/wirecutters/W = allocate(/obj/item/tool/wirecutters, run_loc_floor_bottom_left)
	hold(user, W)
	// A legacy wirecutter_act() is not reached by the driver's click: it is called directly while it exists.
	test_chat_clear()
	if(hascall(B, "carve_pages"))
		call(B, "wirecutter_act")(user, W)
	else
		test_click(user, B, W)
	TEST_ASSERT(!isnull(running(user)), "wirecutters on the book start a timed action")
	TEST_ASSERT(said(user, "You begin to carve out"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.carved, "nothing is carved before the end")
	test_time(3 SECONDS)
	TEST_ASSERT(B.carved, "the pages are carved out")
	var/obj/item/shreddedp/P = locate(/obj/item/shreddedp) in run_loc_floor_bottom_left
	if(P)
		qdel(P)

// ---- Material furnace: the eject entry of its menu, with carbon loaded ----

/datum/unit_test/dq_timed_pin_w6/furnace_eject

/datum/unit_test/dq_timed_pin_w6/furnace_eject/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/material_furnace/F = allocate(/obj/machinery/material_furnace, run_loc_floor_bottom_left)
	var/obj/item/ore/coal/C = allocate(/obj/item/ore/coal, run_loc_floor_bottom_left)
	hold(user, C)
	test_click(user, F, C)
	TEST_ASSERT_EQUAL(LAZYLEN(F.carbon_feed), 1, "the coal is loaded")
	test_chat_clear()
	test_menu(user, F, "eject_contents")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the menu entry starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 1 SECOND, "it lasts one second")
	TEST_ASSERT(said(user, "You begin opening"), "it says it began")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(LAZYLEN(F.carbon_feed), 1, "nothing is unloaded before the end")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(LAZYLEN(F.carbon_feed), 0, "the charge is unloaded at the end")

/datum/unit_test/dq_timed_pin_w6/furnace_eject_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/furnace_eject_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/material_furnace/F = allocate(/obj/machinery/material_furnace, run_loc_floor_bottom_left)
	var/obj/item/ore/coal/C = allocate(/obj/item/ore/coal, run_loc_floor_bottom_left)
	hold(user, C)
	test_click(user, F, C)
	test_menu(user, F, "eject_contents")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the menu entry starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(LAZYLEN(F.carbon_feed), 1, "moving cancels: nothing is unloaded")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/furnace_eject_empty

/datum/unit_test/dq_timed_pin_w6/furnace_eject_empty/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/material_furnace/F = allocate(/obj/machinery/material_furnace, run_loc_floor_bottom_left)
	test_menu(user, F, "eject_contents")
	TEST_ASSERT_NULL(running(user), "an empty furnace starts nothing")

// ---- Candy bowl: a second search asks whether to reach in again (recorded on the converted form only: the legacy question was opened by a callback) ----

/datum/unit_test/dq_timed_pin_w6/candybowl_repeat_asks

/datum/unit_test/dq_timed_pin_w6/candybowl_repeat_asks/run_pin()
	var/mob/living/carbon/human/user = person()
	user.ckey = "pinrepeater"
	var/obj/structure/candybowl/B = allocate(/obj/structure/candybowl, run_loc_floor_bottom_left)
	test_click(user, B, null)
	test_time(6 SECONDS)
	var/obj/item/first = user.get_active_held_item()
	TEST_ASSERT(!isnull(first), "the first search gives a sweet")
	qdel(first)
	test_click(user, B, null)
	test_time(6 SECONDS)
	TEST_ASSERT_NULL(user.get_active_held_item(), "the second search gives nothing until it is answered")
	test_answer(user, "Leave it!")
	TEST_ASSERT_NULL(user.get_active_held_item(), "leaving it takes nothing")
	test_click(user, B, null)
	test_time(6 SECONDS)
	test_answer(user, "Reach in...")
	TEST_ASSERT(!isnull(user.get_active_held_item()) || !B.has_candy, "reaching in takes a sweet or empties the bowl")
	forget_ghosts()

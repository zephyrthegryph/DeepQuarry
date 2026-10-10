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

// ---- Round two: resuscitation kit (bag-valve mask, airway kit, decompression needle), trail light planting, the stardog's fur ----

/datum/unit_test/dq_timed_pin_w6/proc/patient_beside(mob/living/carbon/human/user)
	var/mob/living/carbon/human/patient = person(get_step(user, EAST))
	return patient

/datum/unit_test/dq_timed_pin_w6/bvm_squeeze

/datum/unit_test/dq_timed_pin_w6/bvm_squeeze/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/bag_valve_mask/B = allocate(/obj/item/bag_valve_mask, run_loc_floor_bottom_left)
	hold(user, B)
	begin(user, patient, B, 2 SECONDS, "start squeezing")
	test_time(1 SECOND)
	TEST_ASSERT(!said(user, "won't empty"), "nothing is said before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!said(user, "won't empty"), "an open airway takes the breaths")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w6/bvm_squeeze_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/bvm_squeeze_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/bag_valve_mask/B = allocate(/obj/item/bag_valve_mask, run_loc_floor_bottom_left)
	hold(user, B)
	var/datum/T = begin(user, patient, B, 2 SECONDS)
	user.forceMove(get_step(user, SOUTH))
	test_time(4 SECONDS)
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/bvm_squeeze_masked

/datum/unit_test/dq_timed_pin_w6/bvm_squeeze_masked/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/clothing/mask/gas/M = allocate(/obj/item/clothing/mask/gas, run_loc_floor_bottom_left)
	TEST_ASSERT(patient.equip_to_slot_if_possible(M, SLOT_ID_MASK, disable_warning = TRUE), "the mask goes on")
	var/obj/item/bag_valve_mask/B = allocate(/obj/item/bag_valve_mask, run_loc_floor_bottom_left)
	hold(user, B)
	test_chat_clear()
	test_click(user, patient, B)
	TEST_ASSERT_NULL(running(user), "a masked patient starts nothing")
	TEST_ASSERT(said(user, "can't get a seal"), "and the user is told why")

/datum/unit_test/dq_timed_pin_w6/airway_kit_clear

/datum/unit_test/dq_timed_pin_w6/airway_kit_clear/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = O_MOUTH
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/airway_kit/K = allocate(/obj/item/airway_kit, run_loc_floor_bottom_left)
	hold(user, K)
	begin(user, patient, K, 4 SECONDS, "start working")
	test_time(3 SECONDS)
	TEST_ASSERT(!said(user, "already clear"), "nothing is said before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "already clear"), "it says it finished")

/datum/unit_test/dq_timed_pin_w6/airway_kit_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/airway_kit_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = O_MOUTH
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/airway_kit/K = allocate(/obj/item/airway_kit, run_loc_floor_bottom_left)
	hold(user, K)
	var/datum/T = begin(user, patient, K, 4 SECONDS)
	user.forceMove(get_step(user, SOUTH))
	test_time(6 SECONDS)
	TEST_ASSERT(!said(user, "already clear"), "moving cancels: nothing is said")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/airway_kit_wrong_zone

/datum/unit_test/dq_timed_pin_w6/airway_kit_wrong_zone/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_TORSO
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/airway_kit/K = allocate(/obj/item/airway_kit, run_loc_floor_bottom_left)
	hold(user, K)
	test_chat_clear()
	test_click(user, patient, K)
	TEST_ASSERT_NULL(running(user), "aiming at the chest starts nothing")
	TEST_ASSERT(said(user, "Aim for"), "and the user is told where to aim")

/datum/unit_test/dq_timed_pin_w6/decompression_needle

/datum/unit_test/dq_timed_pin_w6/decompression_needle/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_TORSO
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/decompression_needle/N = allocate(/obj/item/decompression_needle, run_loc_floor_bottom_left)
	hold(user, N)
	begin(user, patient, N, 3 SECONDS, "You line")
	test_time(2 SECONDS)
	TEST_ASSERT(!N.used, "the needle is unused before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(N.used, "the needle is used at the end")
	TEST_ASSERT(said(user, "Nothing comes out"), "it says nothing was trapped")
	test_chat_clear()
	test_click(user, patient, N)
	TEST_ASSERT_NULL(running(user), "a used needle starts nothing")
	TEST_ASSERT(said(user, "already been used"), "and says why")

/datum/unit_test/dq_timed_pin_w6/decompression_needle_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/decompression_needle_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_TORSO
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/decompression_needle/N = allocate(/obj/item/decompression_needle, run_loc_floor_bottom_left)
	hold(user, N)
	var/datum/T = begin(user, patient, N, 3 SECONDS)
	user.forceMove(get_step(user, SOUTH))
	test_time(5 SECONDS)
	TEST_ASSERT(!N.used, "moving cancels: the needle is not used")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/decompression_needle_wrong_zone

/datum/unit_test/dq_timed_pin_w6/decompression_needle_wrong_zone/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_HEAD
	var/mob/living/carbon/human/patient = patient_beside(user)
	var/obj/item/decompression_needle/N = allocate(/obj/item/decompression_needle, run_loc_floor_bottom_left)
	hold(user, N)
	test_chat_clear()
	test_click(user, patient, N)
	TEST_ASSERT_NULL(running(user), "aiming at the head starts nothing")
	TEST_ASSERT(said(user, "Aim for"), "and the user is told where to aim")

// ---- Trail lights: planted in hand on snow ----

/datum/unit_test/dq_timed_pin_w6/lightpole_plant

/datum/unit_test/dq_timed_pin_w6/lightpole_plant/run_pin()
	var/turf/base = run_loc_floor_bottom_left
	var/turf/snow = get_step(base, NORTH)
	var/old_type = snow.type
	snow.ChangeTurf(/turf/simulated/floor/snow)
	snow = get_step(base, NORTH)
	var/mob/living/carbon/human/user = person(snow)
	var/obj/item/stack/lightpole/P = allocate(/obj/item/stack/lightpole, snow, 5)
	hold(user, P)
	begin(user, P, P, 8 SECONDS)
	test_time(7 SECONDS)
	TEST_ASSERT_EQUAL(P.get_amount(), 5, "nothing is spent before the end")
	TEST_ASSERT(isnull(locate(/obj/structure/trailblazer) in snow), "nothing is planted before the end")
	test_time(2 SECONDS)
	var/obj/structure/trailblazer/B = locate(/obj/structure/trailblazer) in snow
	TEST_ASSERT(!isnull(B), "a trail light stands at the end")
	TEST_ASSERT_EQUAL(P.get_amount(), 4, "one light is used")
	if(B)
		qdel(B)
	snow.ChangeTurf(old_type)

/datum/unit_test/dq_timed_pin_w6/lightpole_plant_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/lightpole_plant_cancel_on_move/run_pin()
	var/turf/base = run_loc_floor_bottom_left
	var/turf/snow = get_step(base, NORTH)
	var/old_type = snow.type
	snow.ChangeTurf(/turf/simulated/floor/snow)
	snow = get_step(base, NORTH)
	var/mob/living/carbon/human/user = person(snow)
	var/obj/item/stack/lightpole/P = allocate(/obj/item/stack/lightpole, snow, 5)
	hold(user, P)
	var/datum/T = begin(user, P, P, 8 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(P.get_amount(), 5, "moving cancels: nothing is spent")
	TEST_ASSERT(isnull(locate(/obj/structure/trailblazer) in snow), "and nothing is planted")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
	snow.ChangeTurf(old_type)

/datum/unit_test/dq_timed_pin_w6/lightpole_plant_on_floor

/datum/unit_test/dq_timed_pin_w6/lightpole_plant_on_floor/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/stack/lightpole/P = allocate(/obj/item/stack/lightpole, run_loc_floor_bottom_left, 5)
	hold(user, P)
	test_click(user, P, P)
	TEST_ASSERT_NULL(running(user), "a plain floor starts nothing")

// ---- The stardog's fur: pick someone out of it ----

/datum/unit_test/dq_timed_pin_w6/stardog_fur_pick

/datum/unit_test/dq_timed_pin_w6/stardog_fur_pick/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/fur_turf = get_step(T, NORTH)
	var/old_type = fur_turf.type
	fur_turf.ChangeTurf(/turf/simulated/floor/outdoors/fur)
	fur_turf = get_step(T, NORTH)
	var/mob/living/carbon/human/H = person(T)
	H.pickup_pref = TRUE
	H.pickup_active = TRUE
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, fur_turf)
	victim.enable_godmode()
	var/had_overmap = using_map.use_overmap
	using_map.use_overmap = FALSE
	var/mob/living/simple_mob/vore/overmap/stardog/test_fur/dog = allocate(/mob/living/simple_mob/vore/overmap/stardog/test_fur, get_step(T, EAST))
	using_map.use_overmap = had_overmap
	dog.invisibility = INVISIBILITY_NONE
	dog.in_fur += victim
	test_chat_clear()
	hci_click(H, dog, null)
	test_time(1 SECOND)
	hci_answer(H, victim)
	var/datum/R = running(H)
	TEST_ASSERT(!isnull(R), "the answer starts a timed action")
	TEST_ASSERT(isnull(declared_duration(R)) || declared_duration(R) == 3 SECONDS, "it lasts three seconds")
	TEST_ASSERT(said(victim, "reaches toward you"), "the one picked is told a hand is coming")
	test_time(2 SECONDS)
	TEST_ASSERT(victim.loc == fur_turf, "the one picked is still in the fur before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(victim.loc != fur_turf, "the one picked was lifted out of the fur")
	fur_turf.ChangeTurf(old_type)

/datum/unit_test/dq_timed_pin_w6/stardog_fur_pick_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/stardog_fur_pick_cancel_on_move/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/fur_turf = get_step(T, NORTH)
	var/old_type = fur_turf.type
	fur_turf.ChangeTurf(/turf/simulated/floor/outdoors/fur)
	fur_turf = get_step(T, NORTH)
	var/mob/living/carbon/human/H = person(T)
	H.pickup_pref = TRUE
	H.pickup_active = TRUE
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, fur_turf)
	victim.enable_godmode()
	var/had_overmap = using_map.use_overmap
	using_map.use_overmap = FALSE
	var/mob/living/simple_mob/vore/overmap/stardog/test_fur/dog = allocate(/mob/living/simple_mob/vore/overmap/stardog/test_fur, get_step(T, EAST))
	using_map.use_overmap = had_overmap
	dog.invisibility = INVISIBILITY_NONE
	dog.in_fur += victim
	hci_click(H, dog, null)
	test_time(1 SECOND)
	hci_answer(H, victim)
	var/datum/R = running(H)
	TEST_ASSERT(!isnull(R), "the answer starts a timed action")
	H.forceMove(get_step(H, SOUTH))
	test_time(5 SECONDS)
	TEST_ASSERT(victim.loc == fur_turf, "moving cancels: the one picked stays in the fur")
	TEST_ASSERT(was_cancelled(R, H), "the action ends cancelled")
	fur_turf.ChangeTurf(old_type)

// ---- Mobs at timed work of their own (AI-started): ants building, a mouse cloaking ----

/datum/unit_test/dq_timed_pin_w6/ant_builder_builds

/datum/unit_test/dq_timed_pin_w6/ant_builder_builds/run_pin()
	var/mob/living/simple_mob/animal/tyr/mineral_ants/builder/B = allocate(/mob/living/simple_mob/animal/tyr/mineral_ants/builder, run_loc_floor_bottom_left)
	B.build_type = /obj/effect/ant_structure/wall // the default is a random pick, and one of its entries (an ant hill) is not an ant_structure
	B.set_nutrition(150)
	var/turf/T = get_turf(B)
	TEST_ASSERT(B.build_tile(T), "the builder starts building")
	TEST_ASSERT(!isnull(running(B)), "and is at work")
	TEST_ASSERT(!B.build_tile(T), "a builder at work takes no second job")
	test_time(4 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/ant_structure) in T), "nothing is built before the end")
	TEST_ASSERT_EQUAL(B.nutrition, 150, "and nothing is spent")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/ant_structure) in T), "a structure stands at the end")
	TEST_ASSERT_EQUAL(B.nutrition, 120, "and thirty nutrition are spent")
	TEST_ASSERT_NULL(running(B), "and the builder is free again")
	for(var/obj/effect/ant_structure/S in T)
		qdel(S)

/datum/unit_test/dq_timed_pin_w6/ant_queen_builds

/datum/unit_test/dq_timed_pin_w6/ant_queen_builds/run_pin()
	var/mob/living/simple_mob/animal/tyr/mineral_ants/queen/Q = allocate(/mob/living/simple_mob/animal/tyr/mineral_ants/queen, run_loc_floor_bottom_left)
	Q.set_nutrition(630)
	var/turf/T = get_turf(Q)
	TEST_ASSERT(Q.build_tile(T), "the queen starts building")
	TEST_ASSERT(!isnull(running(Q)), "and is at work")
	test_time(4 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/spider/spiderling/antling) in T), "nothing is laid before the end")
	TEST_ASSERT_EQUAL(Q.nutrition, 630, "and nothing is spent")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/spider/spiderling/antling) in T), "an antling is laid at the end")
	TEST_ASSERT_EQUAL(Q.nutrition, 600, "and thirty nutrition are spent")
	for(var/obj/effect/spider/spiderling/antling/S in T)
		qdel(S)

/datum/unit_test/dq_timed_pin_w6/ant_builder_steps_aside

/datum/unit_test/dq_timed_pin_w6/ant_builder_steps_aside/run_pin()
	var/mob/living/simple_mob/animal/tyr/mineral_ants/builder/B = allocate(/mob/living/simple_mob/animal/tyr/mineral_ants/builder, run_loc_floor_bottom_left)
	B.set_nutrition(150)
	var/turf/T = get_turf(B)
	TEST_ASSERT(B.build_tile(T), "the builder starts building")
	B.forceMove(get_step(B, EAST))
	test_time(6 SECONDS)
	// The mob work only ended when the worker was more than a tile from the turf; an ai() op has no range keep (doc/rewrite/framework_gaps.md, K), so a worker
	// that strays further goes on as well. One step aside builds on the legacy form too.
	TEST_ASSERT(!isnull(locate(/obj/effect/ant_structure) in T), "a builder one tile away still builds")
	TEST_ASSERT_EQUAL(B.nutrition, 120, "and thirty nutrition are spent")
	for(var/obj/effect/ant_structure/S in T)
		qdel(S)

/datum/unit_test/dq_timed_pin_w6/ant_builder_too_hungry

/datum/unit_test/dq_timed_pin_w6/ant_builder_too_hungry/run_pin()
	var/mob/living/simple_mob/animal/tyr/mineral_ants/builder/B = allocate(/mob/living/simple_mob/animal/tyr/mineral_ants/builder, run_loc_floor_bottom_left)
	B.set_nutrition(50)
	TEST_ASSERT(!B.build_tile(get_turf(B)), "a hungry builder starts nothing")
	TEST_ASSERT_NULL(running(B), "and is not at work")

/datum/unit_test/dq_timed_pin_w6/mouse_cloaks

/datum/unit_test/dq_timed_pin_w6/mouse_cloaks/run_pin()
	var/mob/living/simple_mob/animal/space/mouse_army/stealth/M = allocate(/mob/living/simple_mob/animal/space/mouse_army/stealth, run_loc_floor_bottom_left)
	M.start_cloaking()
	TEST_ASSERT(!isnull(running(M)), "the mouse is at work")
	test_time(0.5 SECONDS)
	TEST_ASSERT(M.plane != CLOAKED_PLANE, "it is not yet on the cloaked plane")
	test_time(1 SECOND)
	TEST_ASSERT(M.plane == CLOAKED_PLANE, "it is on the cloaked plane at the end")
	TEST_ASSERT_NULL(running(M), "and is free again")

/datum/unit_test/dq_timed_pin_w6/mouse_cloak_dies

/datum/unit_test/dq_timed_pin_w6/mouse_cloak_dies/run_pin()
	var/mob/living/simple_mob/animal/space/mouse_army/stealth/M = allocate(/mob/living/simple_mob/animal/space/mouse_army/stealth, run_loc_floor_bottom_left)
	M.start_cloaking()
	TEST_ASSERT(!isnull(running(M)), "the mouse is at work")
	M.death()
	test_time(2 SECONDS)
	TEST_ASSERT(M.plane != CLOAKED_PLANE, "a mouse that dies never reaches the cloaked plane")
	TEST_ASSERT(!M.is_cloaked(), "and is not cloaked")

// ---- Round four: a welder on the sensors suite, a welder on graffiti, a wrench on a water cooler's jug ----

/// A lit welder with fuel, in the user's hand.
/datum/unit_test/dq_timed_pin_w6/proc/lit_welder(mob/living/carbon/human/user)
	var/obj/item/weldingtool/W = allocate(/obj/item/weldingtool, run_loc_floor_bottom_left)
	W.reagents.add_reagent(REAGENT_ID_FUEL, W.max_fuel)
	W.setWelding(TRUE)
	hold(user, W)
	return W

/// Clicks `target` with `tool` as a player does. A legacy *_act() override is not reached by the driver's click: it is called directly while the
/// op named `op_key` does not exist yet.
/datum/unit_test/dq_timed_pin_w6/proc/click_tool(mob/living/carbon/human/user, atom/target, obj/item/tool, op_key, act_proc)
	test_chat_clear()
	if(op_known_anywhere(user, target, tool, op_key))
		test_click(user, target, tool)
	else
		call(target, act_proc)(user, tool)

/datum/unit_test/dq_timed_pin_w6/sensors_weld

/datum/unit_test/dq_timed_pin_w6/sensors_weld/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/shipsensors/S = allocate(/obj/machinery/shipsensors, run_loc_floor_bottom_left)
	S.update_integrity(S.max_integrity - 100)
	var/obj/item/weldingtool/W = lit_welder(user)
	begin(user, S, W, 2 SECONDS, "You start repairing")
	test_time(1 SECOND)
	TEST_ASSERT(S.get_integrity() < S.max_integrity, "the sensors are still damaged before the end")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(S.get_integrity(), S.max_integrity, "the sensors are whole at the end")
	TEST_ASSERT(said(user, "You finish repairing"), "it says it finished")

/datum/unit_test/dq_timed_pin_w6/sensors_weld_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/sensors_weld_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/shipsensors/S = allocate(/obj/machinery/shipsensors, run_loc_floor_bottom_left)
	S.update_integrity(S.max_integrity - 100)
	var/obj/item/weldingtool/W = lit_welder(user)
	var/datum/T = begin(user, S, W, 2 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(4 SECONDS)
	TEST_ASSERT(S.get_integrity() < S.max_integrity, "moving cancels: the sensors stay damaged")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/sensors_weld_undamaged

/datum/unit_test/dq_timed_pin_w6/sensors_weld_undamaged/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/shipsensors/S = allocate(/obj/machinery/shipsensors, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = lit_welder(user)
	test_click(user, S, W)
	TEST_ASSERT_NULL(running(user), "undamaged sensors start nothing")

/datum/unit_test/dq_timed_pin_w6/graffiti_clear

/datum/unit_test/dq_timed_pin_w6/graffiti_clear/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/decal/writing/G = allocate(/obj/effect/decal/writing, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = lit_welder(user)
	click_tool(user, G, W, "clear_graffiti", "welder_act")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the welder starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 0.5 SECONDS, "it lasts half a second")
	TEST_ASSERT(!QDELETED(G), "the graffiti stands before the end")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(G), "the graffiti is cleared at the end")

/datum/unit_test/dq_timed_pin_w6/graffiti_clear_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/graffiti_clear_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/decal/writing/G = allocate(/obj/effect/decal/writing, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = lit_welder(user)
	click_tool(user, G, W, "clear_graffiti", "welder_act")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the welder starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(G), "moving cancels: the graffiti stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w6/graffiti_clear_welder_off

/datum/unit_test/dq_timed_pin_w6/graffiti_clear_welder_off/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/decal/writing/G = allocate(/obj/effect/decal/writing, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = allocate(/obj/item/weldingtool, run_loc_floor_bottom_left)
	hold(user, W)
	click_tool(user, G, W, "clear_graffiti", "welder_act")
	TEST_ASSERT_NULL(running(user), "a welder that is off starts nothing")
	TEST_ASSERT(!QDELETED(G), "and the graffiti stays")

/datum/unit_test/dq_timed_pin_w6/cooler_unfasten_jug

/datum/unit_test/dq_timed_pin_w6/cooler_unfasten_jug/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	C.set_bottle(TRUE)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	hold(user, W)
	click_tool(user, C, W, "unfasten_jug", "wrench_act")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the wrench starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 2 SECONDS, "it lasts two seconds")
	test_time(1 SECOND)
	TEST_ASSERT(C.bottle, "the jug is on before the end")
	test_time(1.5 SECONDS)
	TEST_ASSERT(!C.bottle, "the jug is off at the end")
	TEST_ASSERT(said(user, "You unfasten the jug"), "it says it finished")
	var/obj/item/reagent_containers/glass/cooler_bottle/J = locate(/obj/item/reagent_containers/glass/cooler_bottle) in run_loc_floor_bottom_left
	TEST_ASSERT(!isnull(J), "a jug is left on the floor")
	if(J)
		qdel(J)

/datum/unit_test/dq_timed_pin_w6/cooler_unfasten_jug_cancel_on_move

/datum/unit_test/dq_timed_pin_w6/cooler_unfasten_jug_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/reagent_dispensers/water_cooler/C = allocate(/obj/structure/reagent_dispensers/water_cooler, run_loc_floor_bottom_left)
	C.set_bottle(TRUE)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	hold(user, W)
	click_tool(user, C, W, "unfasten_jug", "wrench_act")
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the wrench starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(4 SECONDS)
	TEST_ASSERT(C.bottle, "moving cancels: the jug stays on")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

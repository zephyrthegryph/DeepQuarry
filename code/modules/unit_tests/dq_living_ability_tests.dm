// Living abilities (K23): the ops of living_abilities() (code/library/mob/living_abilities.dm) are declared in the one CAPABILITIES(/mob/living) block through
// a library proc, so a species or trait ability on any living mob resolves by key, waits, keeps what it keeps and runs its effect. Each test drives an ability
// the way its verb does (perform_op by key, an answer to its question, the kernel clock) and reads what the mob then has.

/datum/unit_test/dq_living_ability
	abstract_type = /datum/unit_test/dq_living_ability

/datum/unit_test/dq_living_ability/Run()
	test_driver_begin()
	exercise()
	test_driver_end()

/datum/unit_test/dq_living_ability/proc/exercise()
	return

/// The key of an ability the way its verb performs it.
/datum/unit_test/dq_living_ability/proc/use(mob/living/actor, key, list/with = null)
	return perform_op(actor, actor, key, null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = with)

/// A human that cannot be hurt by the test map's air while the clock runs.
/datum/unit_test/dq_living_ability/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// An ability of /mob/living resolves for a living mob and runs after its wait: the revert from a beast form.
/datum/unit_test/dq_living_ability/revert_beast_form_resolves

/datum/unit_test/dq_living_ability/revert_beast_form_resolves/exercise()
	var/mob/living/carbon/human/H = person()
	var/datum/op_result/result = use(H, "revert_beast_form")
	TEST_ASSERT_NOTNULL(result, "the op resolves")
	TEST_ASSERT(result.outcome != ACT_REFUSED, "a living mob is not refused its own ability")
	TEST_ASSERT_NULL(result.outcome, "the op waits")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the actor has a pending op")
	test_time(9 SECONDS)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "ten seconds are not over: [result.outcome] [result.reason] ")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "the wait ended")
	TEST_ASSERT_EQUAL(result.outcome, ACT_COMMITTED, "and the ability committed")

/// Walking away ends the wait and tells the others the form stopped shifting.
/datum/unit_test/dq_living_ability/revert_beast_form_cancels_on_move

/datum/unit_test/dq_living_ability/revert_beast_form_cancels_on_move/exercise()
	var/mob/living/carbon/human/H = person()
	use(H, "revert_beast_form")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "waiting")
	H.forceMove(get_step(get_turf(H), NORTH))
	test_time(1 SECOND)
	TEST_ASSERT_NULL(op_pending_of(H), "a move ended the wait")
	test_time(11 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "and nothing finished later")

/// The succubus bite carries its victim and its choice into the wait, and lands on the one still there.
/datum/unit_test/dq_living_ability/succubus_bite_injects_after_the_wait

/datum/unit_test/dq_living_ability/succubus_bite_injects_after_the_wait/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	var/datum/op_result/result = use(H, "succubus_bite", list("victim" = V, "choice" = "Numbing", "from" = V.loc))
	TEST_ASSERT_NOTNULL(result, "the op resolves")
	TEST_ASSERT_NULL(result.outcome, "the bite waits")
	test_time(29 SECONDS)
	TEST_ASSERT(!V.bloodstr.has_reagent(REAGENT_ID_NUMBING_FLUID), "nothing is injected before half a minute")
	test_time(2 SECONDS)
	TEST_ASSERT(V.bloodstr.has_reagent(REAGENT_ID_NUMBING_FLUID), "the chosen venom went in: [result.outcome] [result.reason] pend [!!op_pending_of(H)]")

/// A victim who got away before the bite is not bitten.
/datum/unit_test/dq_living_ability/succubus_bite_misses_a_victim_who_left

/datum/unit_test/dq_living_ability/succubus_bite_misses_a_victim_who_left/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	use(H, "succubus_bite", list("victim" = V, "choice" = "Numbing", "from" = V.loc))
	V.forceMove(get_step(get_turf(V), NORTH))
	test_time(31 SECONDS)
	TEST_ASSERT(!V.bloodstr.has_reagent(REAGENT_ID_NUMBING_FLUID), "a victim who is no longer there is not bitten")

/// Egg laying asks first, and the answer reaches the effect.
/datum/unit_test/dq_living_ability/egg_laying_asks_then_waits

/datum/unit_test/dq_living_ability/egg_laying_asks_then_waits/exercise()
	var/mob/living/carbon/human/H = person()
	H.eggs = 0
	var/datum/op_result/result = use(H, "egg_laying")
	TEST_ASSERT_NULL(result?.outcome, "the ability waits on its question")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(H), "it asks what to do")
	var/datum/op_result/waiting = test_answer(H, "Make a Egg")
	TEST_ASSERT_NULL(waiting?.outcome, "an answered question starts the wait")
	test_time(31 SECONDS)
	TEST_ASSERT_EQUAL(H.eggs, 1, "the egg was made: [waiting?.outcome] [waiting?.reason] pend [!!op_pending_of(H)]")

/// The rainbow ability keeps the one it was asked at: when they walk out of sight the charge ends and nothing fires.
/datum/unit_test/dq_living_ability/healing_rainbows_keeps_its_target

/datum/unit_test/dq_living_ability/healing_rainbows_keeps_its_target/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	var/datum/op_result/result = use(H, "healing_rainbows")
	TEST_ASSERT_NULL(result?.outcome, "the ability waits on its question")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(H), "it asks whom")
	test_answer(H, V)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the charge runs")
	V.forceMove(get_step(get_turf(V), NORTH))
	test_time(1 SECOND)
	TEST_ASSERT_NULL(op_pending_of(H), "the one asked at moved: the charge ended")

// ---- The abilities of the human block: what a prompt chose comes with the call ----

/// A hand game reads its partner and the winner from the call, and ends with the players cancelling when the one who started walks off.
/datum/unit_test/dq_living_ability/hand_game_runs_and_cancels

/datum/unit_test/dq_living_ability/hand_game_runs_and_cancels/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/P = person(get_step(get_turf(H), NORTH))
	var/datum/op_result/result = use(H, "game_thumbwars", list("partner" = P, "from" = P.loc))
	TEST_ASSERT_NULL(result?.outcome, "the thumb war takes its five seconds")
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(result.outcome, ACT_COMMITTED, "and then it is played")
	var/datum/op_result/second = use(H, "game_armwrestle", list("partner" = P, "from" = P.loc, "competition" = H))
	TEST_ASSERT_NOTNULL(op_pending_of(H), "an arm wrestle waits")
	H.forceMove(get_step(get_turf(H), WEST))
	test_time(1 SECOND)
	TEST_ASSERT_NULL(op_pending_of(H), "the one who started walked off: it is over")
	TEST_ASSERT(second.outcome != ACT_COMMITTED, "and it was not played")

/// Popping a joint back is the subject's op performed by someone else, who has to stay beside them.
/datum/unit_test/dq_living_ability/relocate_joint_works_on_another

/datum/unit_test/dq_living_ability/relocate_joint_works_on_another/exercise()
	var/mob/living/carbon/human/S = person()
	var/mob/living/carbon/human/U = person(get_step(get_turf(S), NORTH))
	var/obj/item/organ/external/limb = S.organs_by_name[BP_L_ARM]
	limb.dislocate()
	TEST_ASSERT(limb.dislocated > 0, "the arm is out of its joint")
	var/datum/op_result/result = perform_op(U, S, "relocate_joint", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("limb" = limb))
	TEST_ASSERT_NULL(result?.outcome, "the relocation takes its three seconds")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(result.outcome, ACT_COMMITTED, "it was done")
	TEST_ASSERT_EQUAL(limb.dislocated, 0, "the joint is back in")

/// A drain through a grab runs one stage a lap and ends when a stage says so.
/datum/unit_test/dq_living_ability/grab_drain_runs_stage_by_stage

/datum/unit_test/dq_living_ability/grab_drain_runs_stage_by_stage/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	H.zone_sel = allocate(/atom/movable/screen/zone_sel) // a hud-less human has none, and a grab's step reads the aimed zone
	var/obj/item/grab/G = new /obj/item/grab(H, V)
	H.put_in_active_hand(G)
	G.state = GRAB_NECK
	GLOB.grab_drain_test_stages = list()
	H.grab_drain_step(V, G, 1, TYPE_PROC_REF(/mob/living/carbon/human, grab_drain_test_stage), GRAB_NECK, "draining")
	TEST_ASSERT_EQUAL(length(GLOB.grab_drain_test_stages), 1, "the first stage ran at once")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the hold goes on")
	test_time(5.5 SECONDS)
	TEST_ASSERT_EQUAL(length(GLOB.grab_drain_test_stages), 2, "a lap later the second stage ran")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(length(GLOB.grab_drain_test_stages), 3, "and the third")
	TEST_ASSERT_NULL(op_pending_of(H), "the third said it was done")
	TEST_ASSERT_EQUAL(jointext(GLOB.grab_drain_test_stages, ","), "1,2,3", "in order")

/// The stages the test drain has run.
GLOBAL_LIST_EMPTY(grab_drain_test_stages)

/mob/living/carbon/human/proc/grab_drain_test_stage(mob/living/carbon/human/T, stage)
	GLOB.grab_drain_test_stages += stage
	return stage >= 3 ? 0 : stage

/// Butchering is two ops in a row: a lap per cut of meat, then the butchering, and nobody else works on the carcass meanwhile.
/datum/unit_test/dq_living_ability/harvest_cuts_every_piece_then_butchers

/datum/unit_test/dq_living_ability/harvest_cuts_every_piece_then_butchers/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/simple_mob/e0_fixture/carcass = allocate(/mob/living/simple_mob/e0_fixture, get_step(get_turf(H), NORTH))
	carcass.meat_type = /obj/item/reagent_containers/food/snacks/meat
	carcass.meat_amount = 2
	carcass.name_the_meat = FALSE
	carcass.gib_on_butchery = FALSE
	carcass.mob_size = MOB_SMALL // a cut takes half a second per ten of size
	carcass.stat = DEAD
	carcass.harvest(H, null)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the first cut is under way")
	TEST_ASSERT(op_claimed(carcass), "nobody else may work on the carcass")
	test_time(0.6 SECONDS)
	TEST_ASSERT_EQUAL(carcass.meat_amount, 1, "a lap later one cut was made")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "and the next is under way")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(carcass.meat_amount, 0, "the second cut was made")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the butchering follows the last cut")
	test_time(2.1 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "and it ends")
	var/meat = 0
	for(var/obj/item/reagent_containers/food/snacks/meat/M in get_turf(carcass))
		meat++
		own(M)
	for(var/obj/effect/decal/cleanable/blood/splatter/S in get_turf(carcass))
		own(S)
	TEST_ASSERT_EQUAL(meat, 2, "both pieces lie on the carcass's tile")

/// A spin turns a quarter every lap, however long it was asked to go on, and holds nothing of the one spinning.
/datum/unit_test/dq_living_ability/spin_turns_a_quarter_a_lap

/datum/unit_test/dq_living_ability/spin_turns_a_quarter_a_lap/exercise()
	var/mob/living/carbon/human/H = person()
	H.set_dir(NORTH)
	H.spin(1 SECOND, 0.2 SECONDS)
	test_time(0.3 SECONDS)
	TEST_ASSERT_EQUAL(H.dir, EAST, "the first quarter turn")
	test_time(0.2 SECONDS)
	TEST_ASSERT_EQUAL(H.dir, SOUTH, "the second")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(H.dir, EAST, "five quarters in all: it ends facing east")
	TEST_ASSERT_NULL(op_pending_of(H), "and it is over")
	H.spin(0.1 SECONDS, 0.2 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "a spin shorter than one turn starts nothing")

/// A protean power is an op of the power datum (the actor is the protean): folding into the control cluster waits two seconds, and walking off breaks it.
/datum/unit_test/dq_living_ability/protean_power_op_runs_on_the_power

/datum/unit_test/dq_living_ability/protean_power_op_runs_on_the_power/exercise()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	H.enable_godmode()
	var/datum/forms/protean/F = H.get_protean_forms()
	TEST_ASSERT(!F.in_rig(), "it starts outside its cluster")
	TEST_ASSERT(H.activate_protean_power(/datum/protean_power/hardsuit), "the power can be used")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the condensing waits")
	TEST_ASSERT(!F.in_rig(), "and has not happened yet")
	test_time(2.5 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "it ended")
	TEST_ASSERT(F.in_rig(), "and the protean is folded into its cluster")

/datum/unit_test/dq_living_ability/protean_power_op_breaks_when_moved

/datum/unit_test/dq_living_ability/protean_power_op_breaks_when_moved/exercise()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	H.enable_godmode()
	var/datum/forms/protean/F = H.get_protean_forms()
	H.activate_protean_power(/datum/protean_power/hardsuit)
	H.forceMove(get_step(get_turf(H), NORTH))
	test_time(2.5 SECONDS)
	TEST_ASSERT(!F.in_rig(), "walking off stopped the condensing")
	TEST_ASSERT_NULL(op_pending_of(H), "nothing is pending")

/// A micro inside a pair of shoes on the floor climbs out after five seconds: the op is the shoes', the actor is the one inside.
/datum/unit_test/dq_living_ability/micro_climbs_out_of_shoes

/datum/unit_test/dq_living_ability/micro_climbs_out_of_shoes/exercise()
	var/turf/floor = run_loc_floor_bottom_left
	var/obj/item/clothing/shoes/boots = allocate(/obj/item/clothing/shoes, floor)
	var/mob/living/carbon/human/micro = person(floor)
	micro.forceMove(boots)
	boots.container_resist(micro)
	TEST_ASSERT_NOTNULL(op_pending_of(micro), "the climb is under way")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(micro.loc, boots, "still inside after four seconds")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(micro.loc, floor, "out on the floor after five")
	TEST_ASSERT_NULL(op_pending_of(micro), "and it is over")

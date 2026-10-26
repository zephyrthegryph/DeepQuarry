// Behavioural checks of the dx-review-1 conversions (open_request() to asks() steps, refusals to needs()): the answer reaches the effect,
// a refusal shows its reason, and what the old effect did before or around its question still happens.

/// The advanced pinpointer's mode question switches the pinpointer off when it opens, before it is answered, as the old verb did.
/datum/unit_test/dx_followup_pinpointer_off_before_answer/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/pinpointer/advpinpointer/pin = allocate(/obj/item/pinpointer/advpinpointer, T)
	TEST_ASSERT(user.put_in_active_hand(pin), "the pinpointer is carried")
	pin.set_active(TRUE)
	pin.mode = 1
	test_driver_begin()
	test_prompts_reset()
	var/datum/op_result/waiting = test_menu(user, pin, "advpinpointer_toggle_mode_effect")
	TEST_ASSERT_NULL(waiting?.outcome, "the mode toggle waits on its question")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "one question is open")
	TEST_ASSERT(!pin.active, "the pinpointer is already off while the question is open")
	TEST_ASSERT_EQUAL(pin.mode, 1, "the mode itself waits for the answer")
	var/datum/op_result/done = test_answer(user, "Disk Recovery")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the answer commits the op")
	TEST_ASSERT_EQUAL(pin.mode, 0, "the answered mode is applied")
	GLOB.test_prompts = null
	test_driver_end()

/// A pen labels a carried tape through a question; on a tape that is not carried the click is used up without asking (it does not fall through).
/datum/unit_test/dx_followup_tape_label_answer_and_swallow/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/rectape/tape = allocate(/obj/item/rectape, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(user.put_in_active_hand(pen), "the pen is in hand")
	test_driver_begin()
	test_prompts_reset()
	var/datum/op_result/loose = perform_op(user, tape, "item", pen, ORIGIN_CLICK, user.click_authority())
	TEST_ASSERT_EQUAL(loose?.outcome, ACT_COMMITTED, "the pen on a tape that is not carried is used up")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "and asks nothing")
	TEST_ASSERT_EQUAL(tape.name, initial(tape.name), "the tape is unchanged")
	TEST_ASSERT(user.put_in_inactive_hand(tape), "the tape is carried")
	var/datum/op_result/waiting = perform_op(user, tape, "item", pen, ORIGIN_CLICK, user.click_authority())
	TEST_ASSERT_NULL(waiting?.outcome, "the carried tape asks for its label")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "one question is open")
	var/datum/op_result/done = test_answer(user, "Mixtape")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the answer commits the op")
	TEST_ASSERT_EQUAL(tape.name, "tape - 'Mixtape'", "the answered label is applied")
	GLOB.test_prompts = null
	test_driver_end()

/// A rolling paper refuses a plant that is not dried with its reason, told to the one who tried.
/datum/unit_test/dx_followup_rolling_paper_refusal_reason/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/reagent_containers/rollingpaper/paper = allocate(/obj/item/reagent_containers/rollingpaper, T)
	var/obj/item/reagent_containers/food/snacks/donut/plain/snack = allocate(/obj/item/reagent_containers/food/snacks/donut/plain, T)
	test_driver_begin()
	test_chat_clear()
	var/datum/op_result/refused = perform_op(user, paper, "add", snack, ORIGIN_CLICK, user.click_authority())
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a food that is not a dried plant is refused")
	TEST_ASSERT(findtext(jointext(test_chat_of(user), " / "), "must be dried"), "the refusal tells why")
	test_driver_end()

/// Milking a venomous creature twice in a row: the second try is refused, the milker is told why and onlookers see the failed attempt.
/datum/unit_test/dx_followup_venom_milking_onlooker_message/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/onlooker = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/animal/giant_spider/lurker/spider = allocate(/mob/living/simple_mob/animal/giant_spider/lurker, T)
	var/obj/item/reagent_containers/glass/beaker/vessel = allocate(/obj/item/reagent_containers/glass/beaker, T)
	TEST_ASSERT(user.put_in_active_hand(vessel), "the beaker is in hand")
	cap_key_set(vessel, REAGENT_CONTAINER_LID_OPEN, FALSE) // milking wants the lid closed
	var/milk_key = "glass_container" + ".milk" // a capability's op is keyed capability.op; its entries are built at runtime, which the static key check cannot see
	test_driver_begin()
	var/datum/op_result/first = perform_op(user, spider, milk_key, vessel, ORIGIN_CLICK, user.click_authority())
	TEST_ASSERT_EQUAL(first?.outcome, ACT_COMMITTED, "the first milking succeeds")
	test_chat_clear()
	var/datum/op_result/second = perform_op(user, spider, milk_key, vessel, ORIGIN_CLICK, user.click_authority())
	TEST_ASSERT_EQUAL(second?.outcome, ACT_REFUSED, "the second milking is refused")
	TEST_ASSERT(findtext(jointext(test_chat_of(user), " / "), "too recently"), "the milker is told why")
	TEST_ASSERT(findtext(jointext(test_chat_of(onlooker), " / "), "attempts to express venom"), "an onlooker sees the failed attempt")
	test_driver_end()

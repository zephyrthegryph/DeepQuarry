// Native versions of the three old-production-proved casino prompt flows.
/datum/unit_test/dq_silicon/casino_wheel_use_flow

/datum/unit_test/dq_silicon/casino_wheel_use_flow/run_gate()
	set_global("test_prompts", list())
	var/turf/T = test_floor()
	var/obj/machinery/wheel_of_fortune/W = allocate(/obj/machinery/wheel_of_fortune, T)
	var/mob/living/silicon/ai/AI = make_ai(get_step(T, EAST))
	var/mob/living/silicon/robot/R = make_borg(get_step(T, EAST))
	var/original = W.interval
	test_menu(AI, W, "wheel_use")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "an actual AI is not admitted to the wheel question")
	test_menu(R, W, "wheel_use")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual borg opens the wheel choice")
	var/datum/prompt/choice/choice = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(choice.answerer, R, "the actual borg owns the question")
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Set the interval"), "the choice resumes the real nested interval flow")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "the selected branch opens exactly one numeric question")
	var/datum/prompt/number/number = GLOB.test_prompts[2]
	TEST_ASSERT_EQUAL(number.answerer, R, "the nested question keeps the same borg")
	TEST_ASSERT_EQUAL(W.interval, original, "the first answer does not commit the interval")
	TEST_ASSERT_NULL(test_prompt_answer(number, 37), "the actual numeric answer is accepted")
	TEST_ASSERT_EQUAL(W.interval, 37, "the actual callback commits the chosen interval")
	test_menu(R, W, "wheel_use")
	choice = GLOB.test_prompts[3]
	TEST_ASSERT_EQUAL(test_prompt_answer(choice, null, TRUE), "no answer", "the wheel question can be cancelled")
	TEST_ASSERT_EQUAL(W.interval, 37, "cancellation keeps the previously committed interval")
	test_menu(R, W, "wheel_use")
	choice = GLOB.test_prompts[4]
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Spin the Wheel! (Not Lottery)"), "the disabled-spin choice reaches its actual refusal")
	TEST_ASSERT(!work_busy(W), "a disabled public spin does not start wheel work")
	TEST_ASSERT_EQUAL(W.interval, 37, "the disabled-spin branch leaves interval state unchanged")

/datum/unit_test/dq_silicon/casino_wheel_interval_flow

/datum/unit_test/dq_silicon/casino_wheel_interval_flow/run_gate()
	set_global("test_prompts", list())
	var/turf/T = test_floor()
	var/obj/machinery/wheel_of_fortune/W = allocate(/obj/machinery/wheel_of_fortune, T)
	var/mob/living/silicon/ai/AI = make_ai(get_step(T, EAST))
	var/mob/living/silicon/robot/R = make_borg(get_step(T, EAST))
	var/original = W.interval
	test_menu(AI, W, "wheel_setinterval")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "the actual AI cannot open the interval question")
	test_menu(R, W, "wheel_setinterval")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual borg opens the independent interval question")
	var/datum/prompt/number/number = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(number.answerer, R, "the independent question retains its actor")
	TEST_ASSERT_NULL(test_prompt_answer(number, 0), "the request admits the answer before the real interval range check")
	TEST_ASSERT_EQUAL(W.interval, original, "an invalid interval never changes the machine")
	test_menu(R, W, "wheel_setinterval")
	number = GLOB.test_prompts[2]
	TEST_ASSERT_EQUAL(test_prompt_answer(number, null, TRUE), "no answer", "the independent question can be cancelled")
	TEST_ASSERT_EQUAL(W.interval, original, "cancel does not change interval state")
	test_menu(R, W, "wheel_setinterval")
	number = GLOB.test_prompts[3]
	TEST_ASSERT_NULL(test_prompt_answer(number, 1000), "the inclusive upper boundary is accepted")
	TEST_ASSERT_EQUAL(W.interval, 1000, "the real independent callback commits its boundary answer")

/datum/unit_test/dq_silicon/casino_prize_price_flow

/datum/unit_test/dq_silicon/casino_prize_price_flow/run_gate()
	set_global("test_prompts", list())
	var/turf/T = test_floor()
	var/obj/machinery/casinosentientprize_handler/P = allocate(/obj/machinery/casinosentientprize_handler, T)
	var/mob/living/silicon/ai/AI = make_ai(get_step(T, EAST))
	var/mob/living/silicon/robot/R = make_borg(get_step(T, EAST))
	var/original = P.casinosentientprize_price
	P.setprice(AI)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "the actual AI is not admitted to prize pricing")
	var/datum/op_result/result = P.setprice(R)
	TEST_ASSERT_NOTNULL(result, "the actual script entry returns the pending operation result")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual borg opens the price question")
	var/datum/prompt/number/number = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(number.answerer, R, "the actual borg owns its price question")
	TEST_ASSERT_NULL(test_prompt_answer(number, 1001), "the numeric request accepts transport before native requirement evaluation")
	TEST_ASSERT_EQUAL(result.outcome, ACT_REFUSED, "the invalid price closes the pending operation")
	TEST_ASSERT_EQUAL(reason_text(result.reason), "Invalid price.", "the native requirement preserves the old visible refusal")
	TEST_ASSERT(QDELETED(number) || !number.is_open(), "the invalid price closes its actual question, as before")
	TEST_ASSERT_EQUAL(P.casinosentientprize_price, original, "a rejected price does not change machine state")
	P.setprice(R)
	number = GLOB.test_prompts[2]
	TEST_ASSERT_EQUAL(test_prompt_answer(number, null, TRUE), "no answer", "price cancellation reaches the actual request")
	TEST_ASSERT_EQUAL(P.casinosentientprize_price, original, "price cancellation preserves state")
	P.setprice(R)
	number = GLOB.test_prompts[3]
	TEST_ASSERT_NULL(test_prompt_answer(number, 1), "the inclusive lower boundary is accepted")
	TEST_ASSERT_EQUAL(P.casinosentientprize_price, 1, "the real callback commits the accepted price")

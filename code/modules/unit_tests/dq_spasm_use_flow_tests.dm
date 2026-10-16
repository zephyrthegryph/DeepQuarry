// New native branch coverage; old per-type AI/borg menu pins were captured separately.
/datum/unit_test/dq_silicon/casino_spasm_use_flow

/datum/unit_test/dq_silicon/casino_spasm_use_flow/run_gate()
	set_global("test_prompts", list())
	var/turf/T = test_floor()
	var/obj/machinery/casinosentientprize_handler/P = allocate(/obj/machinery/casinosentientprize_handler, T)
	P.set_casinosentientprize_sale("enabled")
	var/mob/living/silicon/ai/AI = make_ai(get_step(T, EAST))
	var/mob/living/silicon/robot/R = make_borg(get_step(T, EAST))
	var/obj/item/clothing/accessory/collar/casinosentientprize/first = allocate(/obj/item/clothing/accessory/collar/casinosentientprize, T)
	var/obj/item/clothing/accessory/collar/casinosentientprize/second = allocate(/obj/item/clothing/accessory/collar/casinosentientprize, T)
	rel_add(P, nameof(P.collar_list), first)
	rel_add(P, nameof(P.collar_list), second)
	test_menu(AI, P, "spasm_use")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "the actual AI opens no SPASM operator question")
	test_menu(R, P, "spasm_use")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual borg opens the real SPASM choice")
	var/datum/prompt/choice/choice = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(choice.answerer, R, "the real question retains its borg actor")
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Select Prize"), "the actual first answer reaches the collar question")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "selection opens exactly one second question")
	var/datum/prompt/choice/collars = GLOB.test_prompts[2]
	TEST_ASSERT_EQUAL(collars.answerer, R, "the collar question retains the actual actor")
	TEST_ASSERT(first in collars.choices && second in collars.choices, "the question offers both exact real registry members")
	TEST_ASSERT_NULL(P.selected_collar, "opening the collar question makes no selection")
	TEST_ASSERT_NULL(test_prompt_answer(collars, first), "the real collar answer completes its actual flow")
	TEST_ASSERT_EQUAL(P.selected_collar, first, "the terminal stores exactly the chosen real collar")
	test_menu(R, P, "spasm_use")
	choice = GLOB.test_prompts[3]
	test_prompt_answer(choice, "Select Prize")
	collars = GLOB.test_prompts[4]
	TEST_ASSERT_EQUAL(test_prompt_answer(collars, null, TRUE), "no answer", "cancelling the real second question ends selection")
	TEST_ASSERT_EQUAL(P.selected_collar, first, "cancelled selection preserves the existing exact collar")
	test_menu(R, P, "spasm_use")
	choice = GLOB.test_prompts[5]
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Show selected Prize"), "the actual information branch completes without another question")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 5, "showing an existing collar opens no extra question")
	TEST_ASSERT_EQUAL(P.selected_collar, first, "information output never changes the chosen collar")
	qdel(first)
	test_menu(R, P, "spasm_use")
	choice = GLOB.test_prompts[6]
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Show selected Prize"), "the real missing-collar branch completes safely")
	TEST_ASSERT_NULL(P.selected_collar, "a deleted real collar does not survive as a selected relation")
	TEST_ASSERT_EQUAL(length(P.collar_list), 1, "the live registry retains only its independent second collar")
	test_menu(R, P, "spasm_use")
	choice = GLOB.test_prompts[7]
	TEST_ASSERT_NULL(R.client, "this real test borg deliberately has no client; no fake client identity is supplied")
	TEST_ASSERT_NULL(test_prompt_answer(choice, "Become Prize (Please examine yourself first)"), "the real clientless registration branch returns without confirmation")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 7, "a clientless actor receives no registration questions")
	TEST_ASSERT_EQUAL(length(P.collar_list), 1, "clientless registration creates no collar")
	TEST_ASSERT(!length(P.sentientprizes_ckeys_list), "clientless registration adds no player identity")

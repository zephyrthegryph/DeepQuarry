/// Real supply prompts retain their actor through every answer and subsequent choice.
/datum/unit_test/om/interim_talisman_supply_actor/run_om(list/made)
	sched.test_prompts = list()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/talisman/supply/source = allocate(/obj/item/paper/talisman/supply, T)
	TEST_ASSERT(actor.put_in_active_hand(source), "the actual supply talisman is held by its supplied actor")
	TEST_ASSERT_EQUAL(source.uses, 5, "the actual supply talisman starts with five uses")
	source.supply(null, actor)
	for(var/index = 1, index <= 5, index++)
		TEST_ASSERT_EQUAL(length(sched.test_prompts), index, "each remaining use produces exactly one actual choice prompt")
		var/datum/om/prompt/choice/carried_item/ask = sched.test_prompts[index]
		made += ask
		TEST_ASSERT_EQUAL(ask.peek("answerer"), actor, "the actual choice prompt belongs to the original supplied actor")
		TEST_ASSERT_EQUAL(ask.peek("receiver"), source, "the actual choice callback targets the original supply talisman")
		var/choice
		for(var/label in ask.choices)
			if(ask.choices[label] == "runestun")
				choice = label
				break
		TEST_ASSERT(choice, "the actual rune choices include the selected stun talisman")
		TEST_ASSERT_NULL(om_prompt_answer(ask, choice), "the actual typed answer creates the selected rune product")
		var/product_count = 0
		for(var/obj/item/paper/talisman/product in contents_of(T))
			if(product.imbue == "runestun")
				product_count++
		TEST_ASSERT_EQUAL(product_count, index, "each actual answer creates exactly one additional selected talisman")
		if(index < 5)
			TEST_ASSERT_EQUAL(source.uses, 5 - index, "each successful answer consumes exactly one actual supply use")
			TEST_ASSERT_EQUAL(actor.get_active_hand(), source, "the surviving supply remains in its actor's actual hand")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(source), "the actual supply talisman is deleted after its fifth use")
	TEST_ASSERT_NULL(actor.get_active_hand(), "exhausting the supply vacates its actual hand")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 5, "exhaustion creates no sixth prompt")

/datum/unit_test/om/interim_talisman_supply_released/run_om(list/made)
	sched.test_prompts = list()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/talisman/supply/source = allocate(/obj/item/paper/talisman/supply, T)
	TEST_ASSERT(actor.put_in_active_hand(source), "the actual supply is held when its choice opens")
	source.supply(null, actor)
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the actual supply creates its typed choice")
	var/datum/om/prompt/choice/carried_item/ask = sched.test_prompts[1]
	made += ask
	var/choice
	for(var/label in ask.choices)
		if(ask.choices[label] == "runestun")
			choice = label
			break
	TEST_ASSERT(choice, "the actual prompt includes the selected rune")
	TEST_ASSERT(actor.unEquip(source), "the actor actually releases the supply before answering")
	TEST_ASSERT_NOTNULL(om_prompt_answer(ask, choice), "the real carried-item guard refuses a released supply")
	TEST_ASSERT_EQUAL(source.uses, 5, "the actual refusal consumes no supply uses")
	TEST_ASSERT(!QDELETED(source), "refusal preserves the released supply")
	var/product_count = 0
	for(var/obj/item/paper/talisman/product in contents_of(T))
		if(product.imbue == "runestun")
			product_count++
	TEST_ASSERT_EQUAL(product_count, 0, "refusal creates no selected talisman")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "refusal starts no subsequent supply prompt")

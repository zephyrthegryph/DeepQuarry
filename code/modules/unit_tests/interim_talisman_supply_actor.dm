/// Real supply prompts retain their actor through every answer and subsequent choice.
/datum/unit_test/interim_talisman_supply_actor/Run()
	test_driver_begin()
	exercise_supply()
	test_driver_end()

/datum/unit_test/interim_talisman_supply_actor/proc/exercise_supply()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/obj/item/paper/talisman/supply/source = allocate(/obj/item/paper/talisman/supply, T)
	TEST_ASSERT(actor.put_in_active_hand(source), "the actual supply talisman is held by its supplied actor")
	TEST_ASSERT_EQUAL(source.uses, 5, "the actual supply talisman starts with five uses")
	source.supply(null, actor)
	for(var/index = 1, index <= 5, index++)
		var/datum/prompt/choice/talisman_chant/ask = SSrequests.open_for(actor)
		TEST_ASSERT(istype(ask), "each remaining use produces its actual native choice prompt")
		TEST_ASSERT_EQUAL(ask.answerer, actor, "the actual choice prompt belongs to the original supplied actor")
		TEST_ASSERT_EQUAL(ask.owner, source, "the actual choice callback targets the original supply talisman")
		var/choice
		for(var/label in ask.choices)
			if(ask.choices[label] == "runestun")
				choice = label
				break
		TEST_ASSERT(choice, "the actual rune choices include the selected stun talisman")
		test_answer(actor, choice)
		test_time(0.1 SECONDS)
		own_turf_contents(T)
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
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "exhaustion creates no sixth prompt")

/datum/unit_test/interim_talisman_supply_released/Run()
	test_driver_begin()
	exercise_release()
	test_driver_end()

/datum/unit_test/interim_talisman_supply_released/proc/exercise_release()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/obj/item/paper/talisman/supply/source = allocate(/obj/item/paper/talisman/supply, T)
	TEST_ASSERT(actor.put_in_active_hand(source), "the actual supply is held when its choice opens")
	source.supply(null, actor)
	var/datum/prompt/choice/talisman_chant/ask = SSrequests.open_for(actor)
	TEST_ASSERT(istype(ask), "the actual supply creates its native choice")
	var/choice
	for(var/label in ask.choices)
		if(ask.choices[label] == "runestun")
			choice = label
			break
	TEST_ASSERT(choice, "the actual prompt includes the selected rune")
	TEST_ASSERT(actor.unEquip(source), "the actor actually releases the supply before answering")
	test_answer(actor, choice)
	test_time(0.1 SECONDS)
	own_turf_contents(T)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the real carried-item refusal closes the native request")
	TEST_ASSERT_EQUAL(source.uses, 5, "the actual refusal consumes no supply uses")
	TEST_ASSERT(!QDELETED(source), "refusal preserves the released supply")
	var/product_count = 0
	for(var/obj/item/paper/talisman/product in contents_of(T))
		if(product.imbue == "runestun")
			product_count++
	TEST_ASSERT_EQUAL(product_count, 0, "refusal creates no selected talisman")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "refusal starts no subsequent supply prompt")

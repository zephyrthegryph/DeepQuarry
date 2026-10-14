/// Four actual native law-module inputs configure their original carried source without uploading any laws.
/datum/unit_test/round2_ai_module_configuration
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_ai_module_configuration/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/list/modules = list(/obj/item/aiModule/safeguard, /obj/item/aiModule/oneHuman, /obj/item/aiModule/freeformcore, /obj/item/aiModule/syndicate)
	var/completed = 0
	for(var/module_type in modules)
		var/obj/item/aiModule/module = allocate(module_type, T)
		TEST_ASSERT_EQUAL(configured_value(module), "", "real original module starts unconfigured")
		TEST_ASSERT(user.put_in_active_hand(module), "actual actor holds original module")
		test_click(user, module, module)
		test_time(1 SECOND)
		var/datum/prompt/text/ai_module/question = SSrequests.open_for(user)
		TEST_ASSERT(istype(question), "actual native self-input opens law configuration text")
		if(istype(module, /obj/item/aiModule/safeguard))
			TEST_ASSERT_EQUAL(question.default, user.name, "real safeguard default snapshots actual actor name")
		if(istype(module, /obj/item/aiModule/oneHuman))
			TEST_ASSERT_EQUAL(question.default, user.real_name, "real one-human default snapshots actual actor identity")
		var/turf/answer_location = get_turf(user) == T ? get_step(T, EAST) : T
		TEST_ASSERT_NOTNULL(answer_location, "real carried request has another location for its actor")
		user.forceMove(answer_location)
		TEST_ASSERT_EQUAL(get_turf(module), answer_location, "actual actor movement moves the original carried module")
		var/answer = "Round2 configured law"
		test_answer(user, answer)
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(configured_value(module), answer, "real native answer changes original module configuration")
		TEST_ASSERT(findtext(module.desc, answer), "real native answer updates player-visible module description")
		TEST_ASSERT_EQUAL(user.get_active_hand(), module, "real configuration preserves exact original source hand")
		TEST_ASSERT_EQUAL(module.loc, user, "real configuration preserves original physical carrier")
		if(istype(module, /obj/item/aiModule/safeguard))
			test_click(user, module, module)
			test_time(1 SECOND)
			question = SSrequests.open_for(user)
			TEST_ASSERT(istype(question), "real configured module opens a fresh request")
			TEST_ASSERT(user.unEquip(module), "actual original module is released before answer")
			test_answer(user, "Must not replace original")
			test_time(1 SECOND)
			TEST_ASSERT_EQUAL(configured_value(module), answer, "answer rechecks actual carried source and refuses released module")
			TEST_ASSERT(findtext(module.desc, answer), "released-source refusal preserves prior visible description")
			TEST_ASSERT(user.put_in_active_hand(module), "actual actor picks original configured module up again")
			test_click(user, module, module)
			test_time(1 SECOND)
			question = SSrequests.open_for(user)
			TEST_ASSERT(istype(question), "real picked-up source opens request after refusal")
			test_answer(user, null, REQ_CANCELLED)
			test_time(1 SECOND)
			TEST_ASSERT_EQUAL(configured_value(module), answer, "actual request cancellation preserves prior configuration")
			TEST_ASSERT_NULL(SSrequests.open_for(user), "actual cancelled request closes")
		TEST_ASSERT(user.unEquip(module), "actual actor releases completed original module")
		completed++
	TEST_ASSERT_EQUAL(completed, 4, "all four actual native configuration families were exercised")

/datum/unit_test/round2_ai_module_configuration/proc/configured_value(obj/item/aiModule/module)
	if(istype(module, /obj/item/aiModule/safeguard))
		var/obj/item/aiModule/safeguard/board = module
		return board.targetName
	if(istype(module, /obj/item/aiModule/oneHuman))
		var/obj/item/aiModule/oneHuman/board = module
		return board.targetName
	if(istype(module, /obj/item/aiModule/freeformcore))
		var/obj/item/aiModule/freeformcore/board = module
		return board.newFreeFormLaw
	if(istype(module, /obj/item/aiModule/syndicate))
		var/obj/item/aiModule/syndicate/board = module
		return board.newFreeFormLaw
	return null

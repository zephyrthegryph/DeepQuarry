/// Real held bedsheet cutting respects release refusal before creating any rags.
/datum/unit_test/interim_bedsheet_cut
	var/sticky = FALSE

/datum/unit_test/interim_bedsheet_cut/sticky
	sticky = TRUE

/datum/unit_test/interim_bedsheet_cut/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/bedsheet/sheet = allocate(/obj/item/bedsheet, T)
	TEST_ASSERT(user.put_in_active_hand(sheet), "the actual bedsheet starts held")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/reagent_containers/glass/rag)), 0, "the floor starts without cut rags")
	if(sticky)
		add_trait(sheet, TRAIT_NODROP, "interim_bedsheet_cut")
		TEST_ASSERT(sheet.loc.release_refusal(sheet, user), "the actual sticky sheet refuses release")
		TEST_ASSERT_EQUAL(sheet.cut_into_rags(user), FALSE, "actual cutting refuses to consume the sticky sheet")
		own_turf_contents(T)
		TEST_ASSERT(!QDELETED(sheet), "refused cutting preserves the original bedsheet")
		TEST_ASSERT_EQUAL(user.get_active_hand(), sheet, "refused cutting preserves the original hand slot")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/reagent_containers/glass/rag)), 0, "refused cutting creates no duplicate rags")
		remove_trait(sheet, TRAIT_NODROP, "interim_bedsheet_cut")
	else
		TEST_ASSERT_EQUAL(sheet.cut_into_rags(user), TRUE, "actual cutting reports successful consumption")
		own_turf_contents(T)
		TEST_ASSERT(QDELETED(sheet), "successful actual cutting consumes the original sheet")
		TEST_ASSERT_NULL(user.get_active_hand(), "successful cutting vacates the sheet's original hand")
		var/list/rags = contents_of(T, /obj/item/reagent_containers/glass/rag)
		TEST_ASSERT(length(rags) >= 2 && length(rags) <= 5, "actual cutting returns its declared two-to-five rag quantity")
		for(var/obj/item/reagent_containers/glass/rag/rag as anything in rags)
			TEST_ASSERT_EQUAL(rag.loc, T, "every real returned rag stays on the original floor")

/// Actual sign unfastening and typed refastening preserve metadata and honor cancellation/refusal.
/datum/unit_test/interim_sign_refasten
	var/sticky = FALSE
	var/cancel = FALSE

/datum/unit_test/interim_sign_refasten/sticky
	sticky = TRUE

/datum/unit_test/interim_sign_refasten/cancel
	cancel = TRUE

/datum/unit_test/interim_sign_refasten/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/sign/science/original = allocate(/obj/structure/sign/science, T)
	var/original_name = original.name
	var/original_desc = original.desc
	var/original_state = original.icon_state
	original.unfasten(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(original), "actual unfastening consumes the original wall sign")
	var/obj/item/sign/sign = locate_within(T, /obj/item/sign)
	TEST_ASSERT(sign, "actual unfastening returns its portable sign")
	TEST_ASSERT_EQUAL(sign.original_type, /obj/structure/sign/science, "the portable sign records its real original type")
	TEST_ASSERT(user.put_in_active_hand(sign), "the portable sign starts in the actor's active hand")
	var/obj/item/tool/screwdriver/tool = allocate(/obj/item/tool/screwdriver, T)
	TEST_ASSERT(user.put_in_inactive_hand(tool), "the actual screwdriver occupies the other hand")
	test_click(user, sign, tool) // the screwdriver on a portable sign asks for a direction
	if(sticky)
		add_trait(sign, TRAIT_NODROP, "interim_sign_refasten")
		TEST_ASSERT(sign.loc.release_refusal(sign, user), "the actual portable sign refuses release")
	test_answer(user, cancel ? "Cancel" : "East")
	own_turf_contents(T)
	if(sticky || cancel)
		TEST_ASSERT(!QDELETED(sign), "refusal or cancellation preserves the original portable sign")
		TEST_ASSERT_EQUAL(user.get_active_hand(), sign, "refusal or cancellation preserves the original sign hand slot")
		TEST_ASSERT_NULL(locate_within(T, /obj/structure/sign/science), "refusal or cancellation creates no duplicate wall sign")
		if(sticky)
			remove_trait(sign, TRAIT_NODROP, "interim_sign_refasten")
	else
		TEST_ASSERT(QDELETED(sign), "successful typed refastening consumes the portable sign")
		TEST_ASSERT_NULL(user.get_active_hand(), "successful refastening vacates the portable sign's original hand")
		var/obj/structure/sign/science/restored = locate_within(T, /obj/structure/sign/science)
		TEST_ASSERT(restored, "actual refastening restores the real original sign type")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/sign/science)), 1, "refastening creates exactly one restored wall sign")
		TEST_ASSERT_EQUAL(restored.name, original_name, "actual refastening preserves the original sign name")
		TEST_ASSERT_EQUAL(restored.desc, original_desc, "actual refastening preserves the original description")
		TEST_ASSERT_EQUAL(restored.icon_state, original_state, "actual refastening preserves the original sign appearance")
		TEST_ASSERT_EQUAL(restored.pixel_x, 32, "the actual East answer sets the wall offset")
		TEST_ASSERT_EQUAL(restored.pixel_y, 0, "the actual East answer does not add a vertical offset")
	TEST_ASSERT_EQUAL(user.get_inactive_hand(), tool, "every outcome preserves the original screwdriver hand slot")

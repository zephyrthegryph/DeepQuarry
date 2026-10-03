/// Real drop_from_sky timing must retain the falling source until impact, then injure its real victim and consume only the illusion.
/datum/unit_test/om/interim_illusionary_fall_cleanup
	var/with_victim = TRUE

/datum/unit_test/om/interim_illusionary_fall_cleanup/empty
	with_victim = FALSE

/datum/unit_test/om/interim_illusionary_fall_cleanup/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/victim
	if(with_victim)
		victim = allocate(/mob/living/carbon/human, T)
		made += victim
		TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "The real landing victim starts without physical injuries")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	made += pen
	if(victim)
		TEST_ASSERT(victim.put_in_active_hand(pen), "The actual landing victim holds its original real pen")
	var/list/before = turf_contents_of_type(T, /obj/effect/illusionary_fall)
	drop_from_sky(T, /obj/effect/illusionary_fall, FALSE)
	own_turf_contents(T)
	var/list/created = turf_contents_of_type(T, /obj/effect/illusionary_fall) - before
	TEST_ASSERT_EQUAL(length(created), 1, "The actual sky-drop path creates exactly one real illusionary falling source")
	var/obj/effect/illusionary_fall/falling = created[1]
	made += falling
	TEST_ASSERT(falling && !QDELETED(falling), "The real source starts alive before its actual landing deadline")
	TEST_ASSERT_EQUAL(falling.loc, T, "The actual dropping source stays on its original landing floor")
	TEST_ASSERT(text2num(falling.icon_state) >= 1 && text2num(falling.icon_state) <= 33, "The actual constructor retains its original random illusion sprite range")
	scheduler_advance((0.6 SECONDS) / (1 SECOND))
	TEST_ASSERT(!QDELETED(falling), "The real falling source survives until its original seven-tenths-second impact")
	if(victim)
		TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "Actual sky dropping does not injure its original victim before impact")
	scheduler_advance((0.2 SECONDS) / (1 SECOND))
	TEST_ASSERT(QDELETED(falling), "The actual timed impact consumes the original falling illusion")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/effect/illusionary_fall)), length(before), "Actual landing leaves no additional illusionary source on its original floor")
	TEST_ASSERT(!QDELETED(pen), "Actual illusionary landing preserves the original real pen")
	if(victim)
		TEST_ASSERT(victim.injury_load(INJURY_CATEGORY_PHYSICAL) > 0, "The actual impact applies real physical injury to its original victim")
		TEST_ASSERT(!QDELETED(victim) && victim.loc == T, "Actual impact preserves the original victim and landing floor")
		TEST_ASSERT_EQUAL(victim.get_active_hand(), pen, "Actual illusionary impact preserves the victim's original held pen")
	else
		TEST_ASSERT_EQUAL(pen.loc, T, "Actual empty-floor impact preserves the original pen on its floor")

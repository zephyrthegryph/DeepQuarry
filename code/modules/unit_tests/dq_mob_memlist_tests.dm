// Mob memory-list audit (doc/rewrite/memory_lists_audit.md, "Pass 3 (mob memlists)"):
// a fresh mob should own none of the lazy-list vars converted this pass.
// These assert the negative — a regression that makes one of these eager
// again shows up as a failing TEST_ASSERT_NULL here, not just a bigger
// boot_memory number.

/datum/unit_test/dq_mob_memlist_human_lazy_lists_null

/datum/unit_test/dq_mob_memlist_human_lazy_lists_null/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_NULL(H.logging, "a fresh human owns no logging list")
	TEST_ASSERT_NULL(H.grabbed_by, "a fresh human owns no grabbed_by list")
	TEST_ASSERT_NULL(H.active_genes, "a fresh human owns no active_genes list")
	TEST_ASSERT_NULL(H.modifiers, "a fresh human owns no modifiers list")
	TEST_ASSERT_NULL(H.temp_language_sources, "a fresh human owns no temp_language_sources list")
	TEST_ASSERT_NULL(H.temp_languages, "a fresh human owns no temp_languages list")
	TEST_ASSERT_NULL(H.custom_heat, "a fresh human owns no custom_heat list")
	TEST_ASSERT_NULL(H.custom_cold, "a fresh human owns no custom_cold list")
	TEST_ASSERT_NULL(H.worn_clothing, "a fresh human owns no worn_clothing list")
	TEST_ASSERT_NULL(H.all_underwear, "a fresh human owns no all_underwear list")
	TEST_ASSERT_NULL(H.flavor_texts, "a fresh human owns no flavor_texts list")
	TEST_ASSERT_NULL(H.trait_injection_reagents, "a fresh human owns no trait_injection_reagents list")

/datum/unit_test/dq_mob_memlist_simple_mob_lazy_lists_null

/datum/unit_test/dq_mob_memlist_simple_mob_lazy_lists_null/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)

	TEST_ASSERT_NULL(M.logging, "a fresh simple_mob owns no logging list")
	TEST_ASSERT_NULL(M.grabbed_by, "a fresh simple_mob owns no grabbed_by list")
	TEST_ASSERT_NULL(M.modifiers, "a fresh simple_mob owns no modifiers list")
	TEST_ASSERT_NULL(M.friends, "a fresh simple_mob owns no friends list")

	// attacktext/friendly/loot_list/myid_access are per-subtype constant tables:
	// shared via shared_type_list() in Initialize(), so they may be non-null,
	// but two mice of the same type must reference the SAME list.
	var/mob/living/simple_mob/animal/passive/mouse/M2 = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	if(M.attacktext || M2.attacktext)
		TEST_ASSERT_EQUAL(M.attacktext, M2.attacktext, "same-type mice share one attacktext list")
	if(M.friendly || M2.friendly)
		TEST_ASSERT_EQUAL(M.friendly, M2.friendly, "same-type mice share one friendly list")
	if(M.loot_list || M2.loot_list)
		TEST_ASSERT_EQUAL(M.loot_list, M2.loot_list, "same-type mice share one loot_list")
	if(M.myid_access || M2.myid_access)
		TEST_ASSERT_EQUAL(M.myid_access, M2.myid_access, "same-type mice share one myid_access list")

/datum/unit_test/dq_mob_memlist_robot_lazy_lists_null

/datum/unit_test/dq_mob_memlist_robot_lazy_lists_null/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)

	TEST_ASSERT_NULL(R.logging, "a fresh robot owns no logging list")
	TEST_ASSERT_NULL(R.grabbed_by, "a fresh robot owns no grabbed_by list")
	TEST_ASSERT_NULL(R.modifiers, "a fresh robot owns no modifiers list")
	TEST_ASSERT_NULL(R.robotdecal_on, "a fresh robot owns no robotdecal_on list")
	TEST_ASSERT_NULL(R.sprite_extra_customization, "a fresh robot owns no sprite_extra_customization list")

	// req_access is a per-type constant table (var/static/list): every robot
	// of the same type must reference the exact same list object.
	var/mob/living/silicon/robot/R2 = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT_EQUAL(R.req_access, R2.req_access, "same-type robots share one req_access list")

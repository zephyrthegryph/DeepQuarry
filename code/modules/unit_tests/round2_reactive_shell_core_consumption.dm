/// The actual core-install click must consume the original ingredient before replacing the original shell.
/datum/unit_test/round2_reactive_shell_core_consumption
	parent_type = /datum/unit_test/dq_p2_engine
	var/refuse_core = TRUE
	var/core_anomaly_type = /obj/effect/anomaly/grav
	var/expected_armour_type = /obj/item/clothing/suit/armor/reactive/repulse

/datum/unit_test/round2_reactive_shell_core_consumption/allowed
	refuse_core = FALSE

/datum/unit_test/round2_reactive_shell_core_consumption/allowed/fallback
	core_anomaly_type = /obj/effect/anomaly
	expected_armour_type = /obj/item/clothing/suit/armor/reactive/stealth

/datum/unit_test/round2_reactive_shell_core_consumption/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/suit/armor/reactive_armor_shell/shell = allocate(/obj/item/clothing/suit/armor/reactive_armor_shell, T)
	var/obj/item/assembly/signaler/anomaly/core = allocate(/obj/item/assembly/signaler/anomaly, T)
	set_var(core, nameof(core.anomaly_type), core_anomaly_type)
	TEST_ASSERT_EQUAL(core.anomaly_type, core_anomaly_type, "actual core carries the selected anomaly identity")
	TEST_ASSERT_EQUAL(shell.type, /obj/item/clothing/suit/armor/reactive_armor_shell, "actual target is an unconverted original shell")
	TEST_ASSERT(user.put_in_active_hand(core), "actor holds exact original anomaly core")
	if(refuse_core)
		add_trait(core, TRAIT_NODROP, "round2_reactive_core")
		TEST_ASSERT(user.release_refusal(core, user), "real inventory refuses exact sticky core release")
	else
		TEST_ASSERT_NULL(user.release_refusal(core, user), "real inventory allows exact core release")
	input_submit(new /datum/input_event/click(user, shell, null, null, "left=1"))
	test_time(1 SECOND)
	var/product_count = 0
	var/obj/item/clothing/suit/armor/reactive/product
	for(var/obj/item/clothing/suit/armor/reactive/built in T)
		product_count++
		product = own(built)
	for(var/obj/item/clothing/suit/armor/reactive/built in user)
		product_count++
		product = own(built)
	if(refuse_core)
		TEST_ASSERT_EQUAL(product_count, 0, "refused original core grants no armour on floor or in either hand")
		TEST_ASSERT(!QDELETED(shell), "refused installation preserves exact original shell alive")
		TEST_ASSERT_EQUAL(shell.loc, T, "refused installation preserves original shell location")
		TEST_ASSERT(!QDELETED(core), "refused installation preserves exact original core alive")
		TEST_ASSERT_EQUAL(user.get_active_hand(), core, "refused installation preserves exact source hand")
		TEST_ASSERT_EQUAL(core.loc, user, "refused installation preserves original core inventory containment")
	else
		TEST_ASSERT(QDELETED(core), "allowed installation consumes exact original anomaly core")
		TEST_ASSERT_NULL(user.get_active_hand(), "allowed original consumption clears source hand")
		TEST_ASSERT(QDELETED(shell), "allowed installation replaces exact original shell")
		TEST_ASSERT_EQUAL(product_count, 1, "allowed core produces exactly one actual armour successor")
		TEST_ASSERT_EQUAL(product?.type, expected_armour_type, "actual core identity selects the exact original mapping or fallback")
		TEST_ASSERT_EQUAL(product?.loc, T, "actual successor replaces original floor shell position")

// These old below-/obj item aliases were exercised by the real forced-baton '*' plan.
// Keep their actual0/1/2 negative appearance checks after native COW migration.
/datum/unit_test/dq_look_native_item_alias_parity
/datum/unit_test/dq_look_native_item_alias_parity/proc/check_aliases(list/aliases)
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/item/melee/robotic/baton/A = allocate(/obj/item/melee/robotic/baton, test_floor())
	var/obj/item/melee/robotic/baton/B = allocate(/obj/item/melee/robotic/baton, test_floor())
	TEST_ASSERT(!QDELETED(A) && !QDELETED(B), "the actual full-scan family constructs real standalone batons")
	dq_look_settle()
	var/base = jointext(dq_look_pin_lines(A), "\n")
	TEST_ASSERT_EQUAL(jointext(dq_look_pin_lines(B), "\n"), base, "the actual peer starts with the same appearance")
	for(var/alias in aliases)
		TEST_ASSERT(!(alias in A.vars), "[alias] has a native home, not a fake physical shadow")
		var/list/address = type_trait_field_for_var(A, alias)
		TEST_ASSERT(address && length(address) == 2, "the actual registered [alias] route resolves")
		var/kind = address[1]
		var/field = address[2]
		var/datum/entry_engine/type_trait/E = type_trait_engine(kind)
		TEST_ASSERT_EQUAL(E.base_type, /obj/item, "this narrow cohort's native schema preserves the proven below-root declaration scope")
		var/original = type_trait_of(A, kind).vars[field]
		var/peer_original = type_trait_of(B, kind).vars[field]
		for(var/value in list(0, 1, 2))
			set_trait(A, kind, field, value)
			dq_look_settle()
			TEST_ASSERT_EQUAL(type_trait_of(A, kind).vars[field], value, "[alias]=[value] reaches the real native policy")
			TEST_ASSERT_EQUAL(type_trait_of(B, kind).vars[field], peer_original, "[alias]=[value] cannot modify the peer's shared defaults")
			TEST_ASSERT_EQUAL(jointext(dq_look_pin_lines(A), "\n"), base, "[alias]=[value] retains the old no-appearance-change outcome on the real forced family")
			TEST_ASSERT_EQUAL(jointext(dq_look_pin_lines(B), "\n"), base, "[alias]=[value] does not redraw the peer differently")
			set_trait(A, kind, field, original)
			dq_look_settle()
			TEST_ASSERT_EQUAL(type_trait_of(A, kind).vars[field], original, "[alias] restores the exact old native value")
			TEST_ASSERT_EQUAL(jointext(dq_look_pin_lines(A), "\n"), base, "restoring [alias] preserves actual repeated-draw parity")

/datum/unit_test/dq_look_native_item_alias_parity/Run()
	check_aliases(list("climbing_delay", "no_attack_log", "no_random_knockdown", "preserve_item"))

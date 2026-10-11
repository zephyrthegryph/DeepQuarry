// By-name writes of trait fields (doc/rewrite/proposals/base_vars.md, "Tooling"): a map edit or an admin VV edit naming a var that left the base
// type for a trait block goes to the holder's own copy of the trait through set_trait(), and the trait's key is published.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/obj/machinery/dq_trait_write_probe
	use_power = USE_POWER_IDLE

CAPABILITIES(/obj/machinery/dq_trait_write_probe)
	configure(uses_power(idle = 10, active = 100, channel = EQUIP))

/// A map edit of `active_power_usage` (the Southern Cross omni mixer's 7500) sets the machine's own active draw.
/datum/unit_test/dq_type_trait_map_edit

/datum/unit_test/dq_type_trait_map_edit/Run()
	var/obj/machinery/dq_trait_write_probe/M = allocate(/obj/machinery/dq_trait_write_probe)
	world.preloader_setup(list("active_power_usage" = 7500), /obj/machinery/dq_trait_write_probe)
	world.preloader_load(M)
	TEST_ASSERT_EQUAL(power_of(M).active, 7500, "the map edit wrote the machine's active draw")
	TEST_ASSERT_EQUAL(power_of_type(M.type).active, 100, "the type's shared trait is untouched")
	TEST_ASSERT_EQUAL(power_of(M).idle, 10, "the fields the edit does not name are inherited")

/// VV lists `@kind.field` and writes it (and an old var name) through set_trait().
/datum/unit_test/dq_type_trait_vv_edit

/datum/unit_test/dq_type_trait_vv_edit/Run()
	var/obj/machinery/dq_trait_write_probe/M = allocate(/obj/machinery/dq_trait_write_probe)
	var/list/fields = type_trait_fields_of(M)
	TEST_ASSERT_EQUAL(fields["@[ENTRY_USES_POWER].active"], 100, "VV lists the trait field with its value")
	TEST_ASSERT(isnull(fields["@[ENTRY_USES_POWER].kind"]), "the trait datum's own vars are not fields")
	TEST_ASSERT(M.vv_edit_var("@[ENTRY_USES_POWER].idle", 25), "the VV edit of a trait field is accepted")
	TEST_ASSERT_EQUAL(power_of(M).idle, 25, "and written to the machine's own copy")
	TEST_ASSERT(vars_write(M, "power_channel", LIGHT), "vars_write routes an old var name to its trait field")
	TEST_ASSERT_EQUAL(power_of(M).channel, LIGHT, "and writes it")
	TEST_ASSERT_EQUAL(power_of_type(M.type).idle, 10, "the type's shared trait is untouched")
	TEST_ASSERT(!M.vv_edit_var("@[ENTRY_USES_POWER].no_such_field", 1), "an unknown field is refused")

#endif

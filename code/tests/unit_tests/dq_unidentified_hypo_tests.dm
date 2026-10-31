/// An unidentified hypospray starts with its identity hidden: it carries an identification datum that knows nothing yet, and shows its
/// unidentified name instead of its true one.
/datum/unit_test/dq_unidentified_hypo_starts_hidden/Run()
	var/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified/hypo = allocate(/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(hypo.identity, "the unidentified hypospray made its identification datum")
	TEST_ASSERT(istype(hypo.identity, /datum/identification/hypo), "of the hypospray kind")
	TEST_ASSERT_EQUAL(hypo.identity.identified, IDENTITY_UNKNOWN, "it starts unidentified")
	TEST_ASSERT(hypo.name != hypo.identity.true_name, "it shows its unidentified name ([hypo.name]), not its true one ([hypo.identity.true_name])")
	var/obj/item/reagent_containers/hypospray/autoinjector/bonemed/known = allocate(/obj/item/reagent_containers/hypospray/autoinjector/bonemed, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(known.identity, "the ordinary one is not hidden")

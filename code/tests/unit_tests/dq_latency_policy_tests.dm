// Type metadata registry: declarations are readable without an instance and inherit through the real parent_type chain.

/datum/type_metadata_registry/register_test_defaults()
	register(/obj/item/dq_containment_test/hooked, TYPE_META_SLOT_HOOKS, TRUE)
	register(/obj/item/dq_destroy_transaction_content_probe, TYPE_META_SLOT_HOOKS, TRUE)
	register(/obj/item/dq_destroy_transaction_mind_probe, TYPE_META_SLOT_HOOKS, TRUE)

GLOBAL_VAR_INIT(dq_type_metadata_constructed, 0)

/obj/dq_type_metadata_probe
/obj/dq_type_metadata_probe/Initialize(mapload)
	. = ..()
	GLOB.dq_type_metadata_constructed++
/obj/dq_type_metadata_probe/sub
/obj/dq_type_metadata_probe/sub/leaf
/obj/dq_type_metadata_redirect
	parent_type = /obj/dq_type_metadata_probe

/datum/unit_test/dq_type_metadata_inheritance/Run()
	set_global("dq_type_metadata_constructed", 0)
	var/datum/type_metadata_registry/R = allocate(/datum/type_metadata_registry)
	R.register(/obj/dq_type_metadata_probe, TYPE_META_SLOT_HOOKS, TRUE)
	R.register(/obj/dq_type_metadata_probe/sub, TYPE_META_SLOT_HOOKS, FALSE)
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_probe, TYPE_META_SLOT_HOOKS, FALSE), TRUE, "An explicit type declaration is readable without an instance")
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_probe/sub/leaf, TYPE_META_SLOT_HOOKS, TRUE), FALSE, "An explicit false subtype declaration overrides its true ancestor")
	TEST_ASSERT_EQUAL(R.value(/obj/dq_type_metadata_redirect, TYPE_META_SLOT_HOOKS, FALSE), TRUE, "Inheritance follows actual parent_type rather than path prefixes")
	TEST_ASSERT_EQUAL(R.value(/obj, TYPE_META_SLOT_HOOKS, FALSE), FALSE, "An undeclared type uses the supplied default")
	TEST_ASSERT_EQUAL(GLOB.dq_type_metadata_constructed, 0, "Dry type queries never allocate or initialize a content prototype")

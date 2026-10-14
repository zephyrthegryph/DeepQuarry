/// Observe the existing ownership-release callback without changing construction or disposal.
/datum/artifact_master/interim2_configured_temperature
	make_effects = list(/datum/artifact_effect/temperature)
	var/releases = 0
	var/datum/artifact_effect/released_effect
	var/datum/released_owner

/datum/artifact_master/interim2_configured_temperature/on_owned_release(var_name, datum/child)
	. = ..()
	if(var_name == nameof(my_effects))
		releases++
		released_effect = child
		released_owner = owner_of(child)

/// The real configured setup rejects a temperature effect on a turf and preserves the same canonical effect on a wrench.
/datum/unit_test/interim2_artifact_configured_effect_rejection/Run()
	var/turf/T = test_floor()
	TEST_ASSERT_NULL(T.artifact_master, "The actual fixture turf must not already own anomalous state")
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/datum/artifact_master/interim2_configured_temperature/rejected = allocate(/datum/artifact_master/interim2_configured_temperature, T)
	TEST_ASSERT_EQUAL(T.artifact_master, rejected, "The actual turf must own the original configured artifact master")
	TEST_ASSERT_EQUAL(rejected.releases, 1, "Actual configured rejection must release exactly one constructed effect through its owner")
	var/datum/artifact_effect/temperature/original = rejected.released_effect
	TEST_ASSERT(istype(original), "Actual configured rejection must report the exact canonical temperature effect it constructed")
	TEST_ASSERT_NULL(rejected.released_owner, "Actual release removes the exact effect from its owner list before invoking the observer")
	TEST_ASSERT(QDELETED(original), "Actual configured rejection must dispose of that exact original incompatible effect")
	TEST_ASSERT_NULL(owner_of(original), "Disposal must clear the exact rejected effect's ownership stamp")
	TEST_ASSERT_EQUAL(length(rejected.my_effects), 0, "The actual rejected master must retain no incompatible effect")
	var/datum/artifact_master/interim2_configured_temperature/control = allocate(/datum/artifact_master/interim2_configured_temperature, wrench)
	TEST_ASSERT_EQUAL(wrench.artifact_master, control, "The compatible actual wrench must own its original master")
	TEST_ASSERT_EQUAL(control.releases, 0, "Actual compatible construction must not reject its original effect")
	TEST_ASSERT_EQUAL(length(control.my_effects), 1, "The compatible actual holder must retain exactly one configured effect")
	var/datum/artifact_effect/temperature/compatible = control.my_effects[1]
	TEST_ASSERT(istype(compatible) && compatible != original, "The compatible holder must construct a distinct actual canonical effect")
	TEST_ASSERT(!QDELETED(compatible), "The exact compatible original effect must remain alive")
	TEST_ASSERT_EQUAL(owner_of(compatible), control, "The compatible master must own its exact original effect")
	TEST_ASSERT_EQUAL(compatible.get_master_holder(), wrench, "The compatible original effect must resolve the actual wrench through its real master relation")
	TEST_ASSERT(!compatible.activated, "The canonical temperature effect must preserve its real inactive starting configuration")
	qdel(rejected)
	TEST_ASSERT_NULL(T.artifact_master, "Disposing the test's anomalous state must restore the original real turf")
	TEST_ASSERT(!QDELETED(compatible), "Independent rejected-master teardown must preserve the exact compatible effect")
	qdel(control)
	TEST_ASSERT(QDELETED(compatible), "Actual compatible-master teardown must dispose of its exact original owned effect")
	TEST_ASSERT(!QDELETED(wrench), "Artifact-state teardown must preserve the original compatible wrench")
	TEST_ASSERT_NULL(wrench.artifact_master, "The original wrench must forget its disposed anomalous state")

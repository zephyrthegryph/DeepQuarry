/// Actual camera reset disposes its owned child through the owner accessor and preserves other pairings.
/datum/unit_test/interim_camera_bug_reset_ownership
	parent_type = /datum/unit_test/dq_p2_reagents
	var/bug_type = /obj/item/camerabug
	var/camera_type = /obj/machinery/camera/bug
	var/network_id = NETWORK_SECURITY

/datum/unit_test/interim_camera_bug_reset_ownership/spy
	bug_type = /obj/item/camerabug/spy
	camera_type = /obj/machinery/camera/bug/spy
	network_id = NETWORK_MERCENARY

/datum/unit_test/interim_camera_bug_reset_ownership/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = rc_actor(T)
	var/obj/item/camerabug/bug = allocate(bug_type, T)
	var/obj/item/camerabug/control = allocate(bug_type, T)
	var/obj/item/bug_monitor/monitor = allocate(/obj/item/bug_monitor, T)
	var/obj/machinery/camera/bug/original = bug.camera
	var/obj/machinery/camera/bug/control_camera = control.camera
	TEST_ASSERT(istype(original) && istype(control_camera), "Both actual constructors must create real camera children")
	own(original)
	own(control_camera)
	TEST_ASSERT_EQUAL(original.type, camera_type, "The actual child must have its canonical variant camera type")
	TEST_ASSERT_EQUAL(owner_of(original), bug, "The exact original camera must belong to the actual bug")
	TEST_ASSERT_EQUAL(original.loc, bug, "The original child must occupy the actual bug")
	TEST_ASSERT((network_id in original.network), "The actual variant must preserve its declared network")
	TEST_ASSERT(actor.put_in_active_hand(monitor), "The actor must actually hold the pairing monitor")
	TEST_ASSERT(test_op_handler(bug, "interaction_pair", actor, monitor), "The actual pairing entry must accept the original bug")
	TEST_ASSERT(test_op_handler(control, "interaction_pair", actor, monitor), "The actual pairing entry must accept the independent bug")
	TEST_ASSERT_EQUAL(bug.linkedmonitor(), monitor, "Actual pairing must link the original bug to the exact monitor")
	var/list/paired = monitor.paired_cameras()
	TEST_ASSERT_EQUAL(length(paired), 2, "The real monitor must hold both original camera relations")
	TEST_ASSERT((original in paired) && (control_camera in paired), "Actual pairing must retain both exact child identities")
	actor.drop_item()
	TEST_ASSERT(actor.put_in_active_hand(bug), "The actor must actually hold the original bug for reset")
	bug.camerabug_reset_effect(actor)
	TEST_ASSERT(QDELETED(original), "Actual reset must dispose of the exact original child")
	TEST_ASSERT_NULL(owner_of(original), "Reset must clear the disposed original's owner stamp")
	TEST_ASSERT_NULL(bug.linkedmonitor(), "Actual reset must clear the original bug's monitor relation")
	var/obj/machinery/camera/bug/replacement = bug.camera
	TEST_ASSERT(istype(replacement) && !QDELETED(replacement), "Reset must construct a live actual replacement child")
	own(replacement)
	TEST_ASSERT(replacement != original, "Reset must create a distinct child identity")
	TEST_ASSERT_EQUAL(replacement.type, camera_type, "Reset must preserve the exact variant camera type")
	TEST_ASSERT_EQUAL(owner_of(replacement), bug, "The replacement must be adopted by the exact original bug")
	TEST_ASSERT_EQUAL(replacement.loc, bug, "The replacement must physically occupy the original bug")
	TEST_ASSERT((network_id in replacement.network), "Reset must preserve the variant's real network")
	paired = monitor.paired_cameras()
	TEST_ASSERT_EQUAL(length(paired), 1, "Reset must remove only the original bug's pairing")
	TEST_ASSERT_EQUAL(paired[1], control_camera, "Reset must preserve the exact independent camera pairing")
	TEST_ASSERT_EQUAL(control.linkedmonitor(), monitor, "Reset must preserve the independent bug's exact monitor")
	TEST_ASSERT_EQUAL(owner_of(control_camera), control, "Reset must preserve the independent camera owner")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), bug, "Reset must preserve the exact actual held bug")
	bug.camerabug_reset_effect(actor)
	TEST_ASSERT(QDELETED(replacement), "An unpaired second reset must dispose of its exact prior child")
	var/obj/machinery/camera/bug/final_camera = bug.camera
	TEST_ASSERT(istype(final_camera) && !QDELETED(final_camera), "Second reset must construct another actual live child")
	own(final_camera)
	TEST_ASSERT_EQUAL(final_camera.type, camera_type, "Second reset must preserve canonical camera type")
	TEST_ASSERT_EQUAL(owner_of(final_camera), bug, "Second reset must retain correct child ownership")
	TEST_ASSERT_EQUAL(final_camera.loc, bug, "Second reset must retain correct child containment")
	paired = monitor.paired_cameras()
	TEST_ASSERT_EQUAL(length(paired), 1, "Unpaired reset must not add an unrequested pairing")
	TEST_ASSERT_EQUAL(paired[1], control_camera, "Unpaired reset must leave independent pairing unchanged")

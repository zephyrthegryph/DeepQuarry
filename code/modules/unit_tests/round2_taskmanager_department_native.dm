#define ROUND2_TASK_BRIDGE "Bridge"
#define ROUND2_TASK_SECURITY "Security"
#define ROUND2_TASK_ENGINEERING "Engineering"

/// Actual native department choices reset genuine source progress, including after an adjacent drop.
/datum/unit_test/round2_taskmanager_department_native
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_taskmanager_department_native/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/obj/item/taskmanager/manager = allocate(/obj/item/taskmanager, T)
	TEST_ASSERT_EQUAL(manager.mode, ROUND2_TASK_BRIDGE, "actual constructor begins with Bridge selected")
	TEST_ASSERT(user.put_in_active_hand(manager), "actual actor holds original taskmanager")
	var/completed = 0
	for(var/department in list(ROUND2_TASK_SECURITY, ROUND2_TASK_ENGINEERING))
		// A valid existing-progress fixture: this canonical type is on the source's department scan tables.
		manager.set_scancount(1)
		manager.set_scanreq(9)
		LAZYADD(manager.scanned, /obj/item/geiger)
		TEST_ASSERT_EQUAL(manager.scancount, 1, "source has nonzero progress before the real choice")
		TEST_ASSERT_EQUAL(LAZYLEN(manager.scanned), 1, "source has an actual recorded scanned type before reset")
		test_click(user, manager, manager)
		test_time(1 SECOND)
		var/datum/prompt/choice/request = SSrequests.open_for(user)
		TEST_ASSERT(istype(request), "actual self click opens native department request")
		TEST_ASSERT(request.radial && request.tooltips, "real request retains radial tooltips")
		TEST_ASSERT_EQUAL(request.anchor, manager, "actual ring is anchored to original device")
		TEST_ASSERT_EQUAL(request.timeout, REQUEST_DEFAULT_TIMEOUT, "department choice keeps original unlimited timeout (a request given no timeout gets the default, framework_gaps.md E2)")
		TEST_ASSERT_EQUAL(length(request.choices), 6, "actual choice offers all six original departments")
		TEST_ASSERT(department in request.choices, "actual offered department is a canonical accepted choice")
		if(department == ROUND2_TASK_ENGINEERING)
			TEST_ASSERT(user.unEquip(manager), "actor drops the original source while its request is open")
			TEST_ASSERT_EQUAL(manager.loc, T, "original source remains on exact adjacent fixture floor")
			TEST_ASSERT(user.Adjacent(manager), "dropped original remains genuinely adjacent")
		test_answer(user, department)
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(manager.mode, department, "real answer changes original source to exact chosen department")
		TEST_ASSERT_EQUAL(manager.scancount, 0, "real department change clears existing scan progress")
		TEST_ASSERT_EQUAL(LAZYLEN(manager.scanned), 0, "real department change clears actual recorded scan types")
		TEST_ASSERT(manager.scanreq >= 3 && manager.scanreq <= 9 && manager.scanreq == round(manager.scanreq), "real callback installs an integer quota within original randomized bounds")
		TEST_ASSERT_NULL(SSrequests.open_for(user), "accepted native request closes")
		TEST_ASSERT(!QDELETED(manager), "actual department change preserves original item identity")
		if(department == ROUND2_TASK_SECURITY)
			TEST_ASSERT_EQUAL(user.get_active_hand(), manager, "held choice preserves original source hand")
		else
			TEST_ASSERT_EQUAL(manager.loc, T, "dropped-adjacent answer preserves original floor position")
		completed++
	TEST_ASSERT_EQUAL(completed, 2, "held and dropped-adjacent actual answer paths both completed")

#undef ROUND2_TASK_BRIDGE
#undef ROUND2_TASK_SECURITY
#undef ROUND2_TASK_ENGINEERING

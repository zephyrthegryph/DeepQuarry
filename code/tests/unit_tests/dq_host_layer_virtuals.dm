// The virtuals code/host declares and content implements: dispatch reaches content's body.
/datum/unit_test/dq_host_key_name_mind
/datum/unit_test/dq_host_clickcross_is_content

/datum/unit_test/dq_host_key_name_mind/Run()
	var/datum/mind/M = new("somekey")
	set_var(M, nameof(M.name), "Fallback")
	TEST_ASSERT_EQUAL(key_name(M), "somekey\[DC\]/(Fallback)", "A mind prints its key and name through key_name_fields()")
	var/datum/plain = new
	TEST_ASSERT_EQUAL(copytext(key_name(plain), 1, 2), "\[", "Any other datum takes the catch-all")
	qdel(plain)

/datum/unit_test/dq_host_clickcross_is_content/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/window/W = allocate(/obj/structure/window/reinforced/full, T)
	TEST_ASSERT(!T.ClickCross(NORTH, FALSE), "A dense full window on the turf blocks reach: content's ClickCross runs, not the host's stub")

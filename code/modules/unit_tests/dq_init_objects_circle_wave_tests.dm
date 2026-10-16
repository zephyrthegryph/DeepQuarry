/datum/unit_test/dq_init_objects_circle_wave

/// Map variables are installed before the real Initialize transaction, not through a new production param.
/datum/unit_test/dq_init_objects_circle_wave/proc/mapped_wave(type, matrix/birth_transform, scale_x = DEFAULT_ICON_SCALE_X, scale_y = DEFAULT_ICON_SCALE_Y, rotation = DEFAULT_ICON_ROTATION, birth_alpha = 255)
	SSatoms.map_loader_begin("dq_circle_wave_context")
	var/obj/effect/temp_visual/circle_wave/V = new type(test_floor())
	set_var(V, nameof(V.transform), birth_transform)
	set_var(V, nameof(V.icon_scale_x), scale_x)
	set_var(V, nameof(V.icon_scale_y), scale_y)
	set_var(V, nameof(V.icon_rotation), rotation)
	set_var(V, nameof(V.alpha), birth_alpha)
	SSatoms.map_loader_stop("dq_circle_wave_context")
	own(V)
	SSatoms.InitializeAtoms(list(V))
	return V

/datum/unit_test/dq_init_objects_circle_wave/proc/check_matrix(matrix/actual, matrix/expected)
	TEST_ASSERT(actual && expected, "constructor leaves real matrices to compare")
	TEST_ASSERT_EQUAL(actual.a, expected.a, "actual horizontal scale/rotation component")
	TEST_ASSERT_EQUAL(actual.b, expected.b, "actual horizontal rotation component")
	TEST_ASSERT_EQUAL(actual.c, expected.c, "actual horizontal translation component")
	TEST_ASSERT_EQUAL(actual.d, expected.d, "actual vertical rotation component")
	TEST_ASSERT_EQUAL(actual.e, expected.e, "actual vertical scale/rotation component")
	TEST_ASSERT_EQUAL(actual.f, expected.f, "actual vertical translation component")

/datum/unit_test/dq_init_objects_circle_wave/proc/check_parent_visual(obj/effect/temp_visual/circle_wave/V, expected_alpha)
	var/emissive_count = 0
	for(var/entry in V.overlays)
		var/image/I = entry
		if(I.plane != PLANE_EMISSIVE)
			continue
		emissive_count++
		TEST_ASSERT_EQUAL(I.icon, V.icon, "the actual movable-parent emissive snapshot uses the circle icon")
		TEST_ASSERT_EQUAL(I.icon_state, V.icon_state, "the parent captures the actual circle state")
		TEST_ASSERT_EQUAL(I.alpha, expected_alpha, "the parent captures pre-animation map alpha, not the animation target")
		TEST_ASSERT_EQUAL(I.color, GLOB.em_block_color, "the parent uses its real generic emissive color")
	TEST_ASSERT_EQUAL(emissive_count, 1, "exactly one real generic emissive overlay survives construction")
	TEST_ASSERT_EQUAL(length(V.filters), 7, "all seven actual wibbly filters were installed")
	for(var/i in 1 to 7)
		TEST_ASSERT(V.get_filter("wibbly-[i]"), "the actual named wave filter [i] exists")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(V), 1, "no extra framework timers were introduced by animations or filters")

/datum/unit_test/dq_init_objects_circle_wave/Run()
	dq_init_objects_fixture_scope()
	// Null, a zero matrix and an unrelated custom transform are all intentionally overwritten.
	var/list/transforms = list(null, matrix(0, 0, 0, 0, 0, 0), matrix(4, 1, 13, 2, 5, 17))
	for(var/matrix/birth_transform as anything in transforms)
		var/obj/effect/temp_visual/circle_wave/V = mapped_wave(/obj/effect/temp_visual/circle_wave, birth_transform)
		check_matrix(V.transform, matrix().Scale(0.1))
		check_parent_visual(V, 255)
		qdel(V)
		TEST_ASSERT_EQUAL(time_scheduler().timer_count(V), 0, "deleted wave retains no scheduled native calls")

/datum/unit_test/dq_init_objects_circle_wave/parent_transform_and_lifetime

/datum/unit_test/dq_init_objects_circle_wave/parent_transform_and_lifetime/Run()
	dq_init_objects_fixture_scope()
	var/obj/effect/temp_visual/circle_wave/V = mapped_wave(/obj/effect/temp_visual/circle_wave, matrix(4, 1, 13, 2, 5, 17), 2, 3, 90, 0)
	var/matrix/parent_result = matrix()
	parent_result.Scale(2, 3)
	parent_result.Turn(90)
	check_matrix(V.transform, parent_result)
	check_parent_visual(V, 0)
	test_time(V.duration + 1 SECOND)
	TEST_ASSERT(QDELETED(V), "the actual native lifetime expires the wave")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(V), 0, "expiry leaves no native timer behind")
	var/obj/effect/temp_visual/circle_wave/void_conduit/long_wave = mapped_wave(/obj/effect/temp_visual/circle_wave/void_conduit, null, birth_alpha = 17)
	check_matrix(long_wave.transform, matrix().Scale(0.1))
	check_parent_visual(long_wave, 17)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(long_wave), "the real long-lived subtype does not inherit the short default lifetime")
	qdel(long_wave)
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(long_wave), 0, "early destruction cancels the long subtype's remaining lifetime")

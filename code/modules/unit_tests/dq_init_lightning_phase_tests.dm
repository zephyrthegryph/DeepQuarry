// Real mapped construction proves the same parent snapshots and native lifetime.
/datum/unit_test/dq_init_lightning_phase

/datum/unit_test/dq_init_lightning_phase/Run()
	dq_init_objects_fixture_scope()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	for(var/birth_alpha in list(0, 17, 255))
		SSatoms.map_loader_begin("dq_lightning_phase")
		var/obj/effect/temporary_effect/lightning_strike/L = new(test_floor())
		set_var(L, nameof(L.alpha), birth_alpha)
		set_var(L, nameof(L.time_to_die), 2 SECONDS)
		SSatoms.map_loader_stop("dq_lightning_phase")
		own(L)
		SSatoms.InitializeAtoms(list(L))
		TEST_ASSERT(!QDELETED(L), "real mapped lightning survives initialization")
		TEST_ASSERT_EQUAL(L.alpha, birth_alpha, "queued fade preserves the actual constructor alpha before host animation advances")
		TEST_ASSERT(L.icon_state in list("lightning_strike1", "lightning_strike2"), "native roll still selects one actual lightning state")
		var/parent_overlays = 0
		for(var/entry in L.overlays)
			var/image/I = entry
			if(I.plane != PLANE_EMISSIVE)
				continue
			parent_overlays++
			TEST_ASSERT_EQUAL(I.alpha, birth_alpha, "movable-parent snapshot captures the original map alpha")
			TEST_ASSERT_EQUAL(I.icon_state, L.icon_state, "the parent snapshots the same final native sprite roll")
		TEST_ASSERT_EQUAL(parent_overlays, 1, "one actual generic emissive parent overlay remains")
		TEST_ASSERT_EQUAL(time_scheduler().timer_count(L), 1, "native lifetime is the only framework timer")
		test_time(1.9 SECONDS)
		TEST_ASSERT(!QDELETED(L), "mapped lifetime is not shortened to fade duration")
		test_time(0.2 SECONDS)
		TEST_ASSERT(QDELETED(L), "the original native lifetime deletes the real strike")
		TEST_ASSERT_EQUAL(time_scheduler().timer_count(L), 0, "destruction leaves no native timer")

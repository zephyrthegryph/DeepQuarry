// A real destroy consequence queues another explosion during capture cleanup.
/obj/dq_look_destroy_blast
/obj/dq_look_destroy_blast/on_destroy(force)
	explosion(get_turf(src), 0, 0, 3)
	return ..()

/datum/unit_test/dq_look_cleanup_large_explosion
/datum/unit_test/dq_look_cleanup_large_explosion/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/saved_ticklimit = Kernel.current_ticklimit
	explosion(T, 3, 4, 5)
	Kernel.current_ticklimit = -1
	try
		for(var/i in 1 to 50)
			if(!SSexplosions.has_work())
				break
			SSexplosions.explosion_step(0)
		TEST_ASSERT(SSexplosions.has_work(), "a real multi-turf explosion demonstrably outlives the old fifty spent-budget steps")
		dq_look_reset(T)
		TEST_ASSERT_EQUAL(Kernel.current_ticklimit, -1, "cleanup restores its caller's exact spent budget")
	catch(var/exception/fault)
		Kernel.current_ticklimit = saved_ticklimit
		throw fault
	Kernel.current_ticklimit = saved_ticklimit
	TEST_ASSERT(!SSexplosions.has_work(), "the actual larger explosion epoch completely finished")
	TEST_ASSERT(!SScontracts.is_contract_batching(), "real explosion completion closed its contract batch")
	for(var/turf/B as anything in block_turfs(test_block))
		TEST_ASSERT_EQUAL(B.type, /turf/simulated/floor/tiled/steel, "every actual test floor, not only the epicenter, is restored")
	TEST_ASSERT_EQUAL(test_floor().type, /turf/simulated/floor/tiled/steel, "the next subject receives a real floor")

/datum/unit_test/dq_look_cleanup_destroy_explosion
/datum/unit_test/dq_look_cleanup_destroy_explosion/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/obj/dq_look_destroy_blast/O = allocate(/obj/dq_look_destroy_blast, T)
	TEST_ASSERT(!SSexplosions.has_work(), "no blast is queued before the fixture's actual destroy consequence")
	dq_look_reset(T)
	TEST_ASSERT(QDELETED(O), "cleanup actually destroyed the real subject")
	TEST_ASSERT(!SSexplosions.has_work(), "the blast queued by actual qdel was resolved before releasing the block")
	for(var/turf/B as anything in block_turfs(test_block))
		TEST_ASSERT_EQUAL(B.type, /turf/simulated/floor/tiled/steel, "qdel cascades cannot destroy a floor after restoration")
		for(var/obj/effect/expl_particles/P in B)
			TEST_FAIL("actual explosion particle survived the completed cleanup")
	TEST_ASSERT_EQUAL(test_floor().type, /turf/simulated/floor/tiled/steel, "the next subject's real base floor survives the qdel cascade")

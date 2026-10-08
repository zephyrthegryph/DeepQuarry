// The shadekin smite frees its target when the shadekin dies, without waiting for the fallback timer (code/modules/admin/verbs/smite.dm).

/datum/unit_test/dq_smite_shadekin_death_frees_target

/datum/unit_test/dq_smite_shadekin_death_frees_target/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/shadekin/shadekin = allocate(/mob/living/simple_mob/shadekin/blue, T)
	target.set_transforming(TRUE)
	shadekin_smite_step(shadekin, target, null, 1)
	TEST_ASSERT(after_pending(target, "shadekin_smite_release"), "the smite arms its fallback release")
	shadekin.death()
	test_time(1)
	TEST_ASSERT(!target.transforming, "the shadekin's death freed the target at once")
	TEST_ASSERT(!after_pending(target, "shadekin_smite_release"), "and the fallback timer is spent")

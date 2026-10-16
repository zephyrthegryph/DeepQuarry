// Metric signature state follows its body and invalidates the real domains.
/datum/unit_test/dq_medical_metric_home
/datum/unit_test/dq_medical_metric_home/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_NOTNULL(H.body, "the real human owns its condition body")
	H.dq_refresh_metric_dirty_state()
	TEST_ASSERT_EQUAL(H.body.dq_last_neural_load, H.injury_load(INJURY_CATEGORY_NEURAL), "the body's cursor records the actual neural metric")
	TEST_ASSERT_EQUAL(H.body.dq_last_radiation, H.radiation, "the body's cursor records actual radiation")
	TEST_ASSERT_EQUAL(H.body.dq_last_bodytemperature, H.body_temperature(), "the body's cursor records actual body temperature")
	H.body.dirty &= ~BODY_DIRTY_METRICS
	H.dq_refresh_metric_dirty_state()
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_METRICS), "an unchanged signature does not spuriously wake the metric domain")
	var/other_before = other.body.dq_last_bodytemperature
	H.body.dq_last_bodytemperature = -1
	H.dq_refresh_metric_dirty_state()
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_METRICS, "a changed signature invalidates the body's actual metric domain")
	TEST_ASSERT_EQUAL(other.body.dq_last_bodytemperature, other_before, "another body's signature is unchanged by this body's refresh")

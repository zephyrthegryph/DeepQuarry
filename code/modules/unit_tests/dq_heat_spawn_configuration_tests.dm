/mob/dq_heat_spawn_probe
CAPABILITIES(/mob/dq_heat_spawn_probe)
	configure(heat_spawn(temperature = 280))

// Force the actual native-null branch through the existing heat-body provider interface.
/mob/dq_heat_spawn_probe/no_native/mob_heat_body()
	return null

/mob/living/carbon/human/dq_heat_spawn_probe
CAPABILITIES(/mob/living/carbon/human/dq_heat_spawn_probe)
	configure(heat_spawn(temperature = 285))

/datum/unit_test/dq_heat_spawn_configuration
/datum/unit_test/dq_heat_spawn_configuration/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/mob/dq_heat_spawn_probe/A = allocate(/mob/dq_heat_spawn_probe, test_floor())
	var/mob/dq_heat_spawn_probe/B = allocate(/mob/dq_heat_spawn_probe, test_floor())
	TEST_ASSERT_NULL(A.heat_body, "A bodyless real mob does not eagerly allocate native heat")
	TEST_ASSERT(vars_write(A, "bodytemperature", 250), "The historical map field routes to the native COW spawn config")
	TEST_ASSERT_NULL(A.heat_body, "A configuration edit preserves lazy native allocation")
	TEST_ASSERT_EQUAL(heat_spawn_of_type(A.type).temperature, 280, "Compiled type defaults are independent of map/VV holder overrides")
	TEST_ASSERT(abs(A.body_temperature() - 250) < 0.001, "The real native body starts at the holder's configured temperature")
	TEST_ASSERT_NOTNULL(A.heat_body, "The first actual temperature read creates native state")
	TEST_ASSERT(abs(B.body_temperature() - 280) < 0.001, "A peer retains its native type starting temperature")
	var/native_handle = A.heat_body
	TEST_ASSERT(A.vv_edit_var("@heat_spawn.temperature", 260), "The real admin editor updates spawn/fallback configuration")
	TEST_ASSERT_EQUAL(A.heat_body, native_handle, "Admin configuration does not replace the live native heat body")
	TEST_ASSERT(abs(A.body_temperature() - 250) < 0.001, "A live native temperature remains authoritative after config editing")
	A.set_bodytemperature(-20)
	TEST_ASSERT(abs(A.body_temperature() - TCMB) < 0.001, "The existing real setter preserves its absolute cold clamp")
	TEST_ASSERT_EQUAL(heat_spawn_of(A).temperature, 260, "Native heat mutation does not rewrite spawn configuration")
	var/mob/dq_heat_spawn_probe/no_native/N = allocate(/mob/dq_heat_spawn_probe/no_native, test_floor())
	TEST_ASSERT(vars_write(N, "bodytemperature", 230), "The native-null subject receives an actual holder override")
	TEST_ASSERT_EQUAL(N.body_temperature(), 230, "An absent native body uses holder configuration, not the compiled type default")
	TEST_ASSERT_NULL(N.heat_body, "The forced null provider does not invent a fake native handle")

/datum/unit_test/dq_heat_spawn_artifact_restoration
/datum/unit_test/dq_heat_spawn_artifact_restoration/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/mob/living/carbon/human/dq_heat_spawn_probe/H = allocate(/mob/living/carbon/human/dq_heat_spawn_probe, test_floor())
	var/area/A = get_area(H)
	defer_cleanup(A, TYPE_PROC_REF(/area, set_flags), A.flags)
	A.set_flags(A.flags & ~AREA_FORBID_EVENTS)
	TEST_ASSERT_EQUAL(GetAnomalySusceptibility(H), 1, "The actual unprotected human permits a guaranteed artifact effect")
	TEST_ASSERT(vars_write(H, "bodytemperature", 240), "The human's holder-specific spawn override is changed")
	H.set_bodytemperature(200)
	var/datum/artifact_effect/health/E = allocate(/datum/artifact_effect/health)
	set_var(E, nameof(E.health_type), initial(E.health_type))
	E.DoEffectTouch(H)
	TEST_ASSERT(abs(H.body_temperature() - 285) < 0.001, "The real healing artifact restores the compiled type default, not holder override240")
	TEST_ASSERT_EQUAL(heat_spawn_of(H).temperature, 240, "Artifact restoration does not mutate the holder's separate spawn configuration")
	TEST_ASSERT_EQUAL(heat_spawn_of_type(H.type).temperature, 285, "The declared cold-human type default remains immutable")

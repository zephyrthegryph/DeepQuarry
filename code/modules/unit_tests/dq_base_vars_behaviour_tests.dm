// Behaviour state lives only on instances which use it; type defaults remain shared.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_base_vars_behaviours
	abstract_type = /datum/unit_test/dq_base_vars_behaviours



/datum/unit_test/dq_base_vars_behaviours

	abstract_type = /datum/unit_test/dq_base_vars_behaviours



/datum/unit_test/dq_base_vars_behaviours/light_source/Run()

	var/turf/start = run_loc_floor_bottom_left

	var/turf/next = get_step(start, EAST)

	var/obj/item/paper/P = allocate(/obj/item/paper, start)

	TEST_ASSERT(!P.is_blocking_light(), "ordinary items do not supply opacity")

	P.start_blocking_light()

	TEST_ASSERT(P.is_blocking_light() && (P in start.opacity_sources), "starting registers the actual movable")

	P.forceMove(next)

	TEST_ASSERT(!(P in start.opacity_sources) && (P in next.opacity_sources), "movement transfers the actual opacity source")

	P.stop_blocking_light()

	TEST_ASSERT(!P.is_blocking_light() && !(P in next.opacity_sources), "stopping clears state and source")

	TEST_ASSERT_NULL(sparse_get(P, blocks_light), "the stopped flag no longer consumes a sparse slot")



/datum/unit_test/dq_base_vars_behaviours/omen_merge/Run()

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	H.add_omen(incidents_left = 2, luck_mod = 4, damage_mod = 6, evil = FALSE, safe_disposals = FALSE, vorish = FALSE)

	TEST_ASSERT(!H.omen_is_evil(), "a non-evil omen overrides the default true")

	H.add_omen(incidents_left = 3, luck_mod = 2, damage_mod = 4, evil = TRUE, safe_disposals = TRUE, vorish = TRUE)

	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_incidents, INFINITY), 3, "the weaker longer omen replaces the incident budget")

	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_luck, 1), 5, "luck merges by the original half-strength rule")

	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_damage, 1), 8, "damage merges by the original half-strength rule")

	TEST_ASSERT(H.omen_is_evil() && sparse_get_or(H, omen_safe_disposals, FALSE) && sparse_get_or(H, omen_vorish, TRUE), "special modifiers accumulate")

	H.omen_consume()

	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_incidents, INFINITY), 2, "consuming an incident decrements the real budget")

	H.remove_omen()

	TEST_ASSERT(!H.has_omen(), "removing revokes the capability")

	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_incidents, INFINITY), 2, "revoking retains historical state until the next omen")



/datum/unit_test/dq_base_vars_behaviours/footstep_overrides/Run()

	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human)

	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human)

	TEST_ASSERT_EQUAL(footstep_settings_of(first).sound_type, FOOTSTEP_MOB_SHOE, "carbon types inherit their declared shoe sounds")

	TEST_ASSERT_EQUAL(footstep_settings_of(first).volume, 1, "carbon types inherit their declared volume")

	first.enable_footsteps(FOOTSTEP_MOB_CLAW, 0.5, -4, TRUE)

	TEST_ASSERT_EQUAL(footstep_settings_of(first).sound_type, FOOTSTEP_MOB_CLAW, "enabling selects the actual sound type")

	TEST_ASSERT_EQUAL(footstep_settings_of(first).volume, 0.5, "enabling overrides only this holder")

	TEST_ASSERT_EQUAL(footstep_settings_of(second).volume, 1, "a peer retains the shared type defaults")

	first.disable_footsteps()

	TEST_ASSERT_EQUAL(footstep_settings_of(first).volume, 0.5, "revocation retains the configured sound settings")

	first.enable_footsteps()

	TEST_ASSERT_EQUAL(footstep_settings_of(first).volume, 0.1, "the next enable uses its explicit API defaults")



/datum/unit_test/dq_base_vars_behaviours/slosh_counter/Run()

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	var/before = sparse_get_or(H, slosh_steps, 0)

	TEST_ASSERT_EQUAL(H.slosh_next_step(), before, "the first increment returns the actual old count")

	TEST_ASSERT_EQUAL(H.slosh_next_step(), before + 1, "postfix semantics advance exactly once")

	H.enable_slosh()

	revoke(H, /datum/capability/slosh, H)

	TEST_ASSERT_EQUAL(H.slosh_next_step(), before + 2, "capability removal retains the per-mob counter")



/datum/unit_test/dq_base_vars_behaviours/sale_profile/Run()

	var/obj/item/paper/manifest/M = allocate(/obj/item/paper/manifest)

	TEST_ASSERT_EQUAL(sale_profile_of(M).path, /datum/sellable/manifest, "manifest types declare their real valuation profile")

	M.make_sellable()

	TEST_ASSERT_EQUAL(sale_profile_of(M).path, /datum/sellable/manifest, "the first profile still wins over later calls")

	var/obj/item/paper/P = allocate(/obj/item/paper)

	P.make_sellable(/datum/sellable/manifest)

	TEST_ASSERT_EQUAL(sale_profile_of(P).path, /datum/sellable/manifest, "a runtime-selected profile is kept on this holder")

	var/obj/item/paper/untouched = allocate(/obj/item/paper)

	TEST_ASSERT_NULL(sale_profile_of(untouched).path, "a peer does not inherit another holder's runtime profile")



/datum/unit_test/dq_base_vars_behaviours/burning_record_lifetime/Run()

	var/obj/item/paper/P = allocate(/obj/item/paper)

	TEST_ASSERT_NULL(P.burning_state(), "ordinary objects allocate no fire record")

	var/datum/record/burning/state = P.burning_state(TRUE)

	TEST_ASSERT_NOTNULL(state, "the first fire allocates one real record")

	TEST_ASSERT_EQUAL(link_get(state, LK_BURNING_HOLDER), P, "the native reciprocal end identifies its holder")

	TEST_ASSERT_EQUAL(P.burning_state(TRUE), state, "repeated access preserves the same retained record")

	qdel(P)

	TEST_ASSERT(QDELETED(state), "destroying the holder deletes its linked fire record")



/datum/unit_test/dq_base_vars_behaviours/radiation_countdown/Run()

	test_driver_begin()

	test_time(1 SECONDS)

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	var/datum/radiation_pulse_information/pulse = allocate(/datum/radiation_pulse_information)

	pulse.minimum_exposure_time = 3 SECONDS

	TEST_ASSERT_EQUAL(H.radiation_countdown_check(pulse), 0, "a fresh mob has no exposure countdown")

	H.radiation_countdown_start(5 SECONDS)

	TEST_ASSERT_EQUAL(H.radiation_countdown_check(pulse), CANCEL_IRRADIATION, "a live countdown refuses before its shortest minimum")

	test_time(3 SECONDS)

	TEST_ASSERT_EQUAL(H.radiation_countdown_check(pulse), SKIP_MINIMUM_EXPOSURE_TIME_CHECK, "the shortest observed minimum permits irradiation")

	test_time(10 SECONDS)

	TEST_ASSERT_EQUAL(H.radiation_countdown_check(pulse), 0, "the keyed cleanup expires the actual countdown")

	TEST_ASSERT_NULL(sparse_get(H, rad_countdown_started), "the expired countdown frees its sparse start")

	test_driver_end()



#endif

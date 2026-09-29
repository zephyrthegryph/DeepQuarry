// climb() (code/datums/capabilities/library/climb.dm).

/obj/cap_fixture/climbable/capabilities()
	. = ..()
	. += climb(delay = 2 SECONDS)

/// Made climbable by its own Initialize(): the capability leaves it as it is.
/obj/cap_fixture/climbable/preset/Initialize(mapload)
	make_climbable(delay = 1 SECOND, vaulting = TRUE)
	return ..()

/datum/unit_test/dx_cap_climb

/datum/unit_test/dx_cap_climb/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/climbable/F = allocate(/obj/cap_fixture/climbable, T)

	TEST_ASSERT_EQUAL(F.climbable_type, /datum/om/behaviour/climbable, "made climbable at init")
	TEST_ASSERT_EQUAL(F.climbable_delay, 2 SECONDS, "with the capability's delay")
	TEST_ASSERT(has_trait(F, TRAIT_CLIMBABLE), "the behaviour is attached")

	var/datum/interaction/capability/E = dx_cap_entry(F, "Climb")
	TEST_ASSERT_NOTNULL(E, "climb() offers its entry")
	TEST_ASSERT_NULL(E.default_action, "Menu only")
	TEST_ASSERT_NULL(E.why_not(H, F, null), "climbable")
	TEST_ASSERT(E.perform(H, F, null), "the entry starts the climb")

	F.unmake_climbable()
	TEST_ASSERT_EQUAL(E.why_not(H, F, null), "it can't be climbed", "refused once it isn't climbable")

	var/obj/cap_fixture/climbable/preset/P = allocate(/obj/cap_fixture/climbable/preset, T)
	TEST_ASSERT_EQUAL(P.climbable_delay, 1 SECOND, "an object already climbable keeps its own settings")
	TEST_ASSERT(P.climbable_vaulting, "and its vaulting")

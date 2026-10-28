#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// sets_off() run for real (code/library/transformations/transformation_effects.dm): each stock effect is set off by a fixture rule of the
// spawns() test regime and its result is looked for in the world. The explosion is the tiny one (an amount of 2 or less is sparks and a bang, no blast).

/transformation/dq_spawn/foam

CAPABILITIES(/transformation/dq_spawn/foam)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUM, 1)), made = 12, effects = sets_off(XFORM_FX_FOAM, variant = 0, clears = TRUE)))

/transformation/dq_spawn/smoke

CAPABILITIES(/transformation/dq_spawn/smoke)
	configure(transformation(takes = list(reagent(REAGENT_ID_ALUMINIUM, 1)), made = 12, effects = sets_off(XFORM_FX_SMOKE, clears = TRUE)))

/transformation/dq_spawn/pulse

CAPABILITIES(/transformation/dq_spawn/pulse)
	configure(transformation(takes = list(reagent(REAGENT_ID_COPPER, 1)), made = 24, effects = sets_off(XFORM_FX_EMP, divisors = list(24, 12, 12, 12), clears = TRUE)))

/transformation/dq_spawn/bang

CAPABILITIES(/transformation/dq_spawn/bang)
	configure(transformation(takes = list(reagent(REAGENT_ID_LEAD, 1)), made = 2, effects = sets_off(XFORM_FX_EXPLOSION, divisor = 1)))

/transformation/dq_spawn/aura

CAPABILITIES(/transformation/dq_spawn/aura)
	configure(transformation(takes = list(reagent(REAGENT_ID_LITHIUM, 1)), made = 1, effects = sets_off(XFORM_FX_AREA, range = 1, body_effect = /datum/body_effect/entangled, lasts = 4 SECONDS)))

/// An item that notes the pulse.
/obj/item/dq_emp_probe
	var/pulsed = 0

/obj/item/dq_emp_probe/emp_act(severity)
	pulsed++
	return ..()

/datum/unit_test/dq_xform_sets_off_foam
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_foam/Run()
	var/turf/T = test_floor()
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_SODIUM, 1, safety = 1)
	xform_settle_reagents(H)
	var/obj/effect/effect/foam/F = locate(/obj/effect/effect/foam) in T
	TEST_ASSERT_NOTNULL(F, "the foam rule made foam where the vessel is")
	TEST_ASSERT_EQUAL(H.total_volume, 0, "a foam from a non-living vessel empties it")
	qdel(F)

/datum/unit_test/dq_xform_sets_off_smoke
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_smoke/Run()
	var/turf/T = test_floor()
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_ALUMINIUM, 1, safety = 1)
	xform_settle_reagents(H)
	test_time(1 SECOND)
	var/found = 0
	for(var/obj/effect/effect/smoke/chem/S in range(6, T))
		found++
		qdel(S)
	TEST_ASSERT(found > 0, "the smoke rule made a chemical smoke cloud")
	TEST_ASSERT_EQUAL(H.total_volume, 0, "a smoke from a non-living vessel empties it")

/datum/unit_test/dq_xform_sets_off_emp
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_emp/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_emp_probe/near = allocate(/obj/item/dq_emp_probe, T)
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_COPPER, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(near.pulsed > 0, "the pulse reached an item on the vessel's tile")
	TEST_ASSERT_EQUAL(H.total_volume, 0, "a pulse from a non-living vessel empties it")

/datum/unit_test/dq_xform_sets_off_explosion
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_explosion/Run()
	var/turf/T = test_floor()
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_LEAD, 1, safety = 1)
	xform_settle_reagents(H)
	var/sparks = 0
	for(var/obj/effect/effect/sparks/S in range(3, T))
		sparks++
		qdel(S)
	TEST_ASSERT(sparks > 0, "the tiny explosion went off as sparks")
	TEST_ASSERT_EQUAL(H.total_volume, 0, "an explosion in a non-living vessel empties it before it goes off")

/datum/unit_test/dq_xform_sets_off_area
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_area/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/near = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/far = allocate(/mob/living/carbon/human, locate(T.x + 3, T.y, T.z))
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_LITHIUM, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(near.has_body_effect(/datum/body_effect/entangled), "a mob within range gets the body effect")
	TEST_ASSERT(!far.has_body_effect(/datum/body_effect/entangled), "a mob out of range does not")

#endif

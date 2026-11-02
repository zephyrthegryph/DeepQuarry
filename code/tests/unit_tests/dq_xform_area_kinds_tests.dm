#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// The area kinds of sets_off() and the rule's `spends` (code/library/transformations/transformation_effects.dm, transformation_settle.dm), set off for
// real by fixture rules of the spawns() test regime. They replaced the bespoke chemical tails: flash powder and the rainbow, pink and nightmare extracts
// (XFORM_FX_WAVE), every slime extract's use (spends).

/// Weakened on the vessel's tile and the next, stunned two or three tiles out, nothing past that.
/transformation/dq_spawn/wave_bands

CAPABILITIES(/transformation/dq_spawn/wave_bands)
	configure(transformation(takes = list(reagent(REAGENT_ID_PHOSPHORUS, 1)), made = 1, effects = sets_off(kind = XFORM_FX_WAVE, range = 5, mob_type = /mob/living/carbon/human,
		statuses = list(list(1, STAT_WEAKENED, 15), list(3, STAT_STUNNED, 5)))))

/// Mends and a line told to every mob in range.
/transformation/dq_spawn/wave_mend

CAPABILITIES(/transformation/dq_spawn/wave_mend)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 1)), made = 1, effects = sets_off(kind = XFORM_FX_WAVE, range = 2, tell_each = "dq wave",
		mends = list(TREAT_TISSUE_REPAIR), mend_amount = 25)))

/// Lingering poison on every mob in range.
/transformation/dq_spawn/wave_poison

CAPABILITIES(/transformation/dq_spawn/wave_poison)
	configure(transformation(takes = list(reagent(REAGENT_ID_ETHANOL, 1)), made = 1, effects = sets_off(kind = XFORM_FX_WAVE, range = 2, poison = list(2, 3 MINUTES))))

/// Spends a use of the subject each step.
/transformation/dq_spawn/spend_one

CAPABILITIES(/transformation/dq_spawn/spend_one)
	configure(transformation(takes = list(reagent(REAGENT_ID_SULFUR, 1)), made = 1, spends = "uses"))

/// Spends every use left.
/transformation/dq_spawn/spend_all

CAPABILITIES(/transformation/dq_spawn/spend_all)
	configure(transformation(takes = list(reagent(REAGENT_ID_URANIUM, 1)), made = 1, spends = "uses", spends_all = TRUE))

/// A subject with uses, as a slime extract has; its setter notes each call.
/obj/item/dq_spend_probe
	var/uses = 3
	var/set_calls = 0

/obj/item/dq_spend_probe/proc/spend_uses(amount)
	set_calls++
	uses = amount

/// A cold snap and a heat wave of the thermal kind.
/transformation/dq_spawn/snap_cold

CAPABILITIES(/transformation/dq_spawn/snap_cold)
	configure(transformation(takes = list(reagent(REAGENT_ID_GLYCEROL, 1)), made = 1, effects = sets_off(kind = XFORM_FX_THERMAL, direction = THERMAL_COLD, joules = -1000)))

/transformation/dq_spawn/snap_heat

CAPABILITIES(/transformation/dq_spawn/snap_heat)
	configure(transformation(takes = list(reagent(REAGENT_ID_AMMONIA, 1)), made = 1, effects = sets_off(kind = XFORM_FX_THERMAL, direction = THERMAL_HEAT, temperature = T0C + 60, joules = 1000)))

/// Mobs next to the vessel are thrown up to 6 tiles away.
/transformation/dq_spawn/scatter

CAPABILITIES(/transformation/dq_spawn/scatter)
	configure(transformation(takes = list(reagent(REAGENT_ID_DIETHYLAMINE, 1)), made = 1, effects = sets_off(kind = XFORM_FX_SCATTER, range = 0, distance = 6)))

/// The floors around the vessel made wet.
/transformation/dq_spawn/slick

CAPABILITIES(/transformation/dq_spawn/slick)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 1)), made = 1, effects = sets_off(kind = XFORM_FX_SLICK, range = 1)))

/datum/unit_test/dq_xform_wave_statuses_by_distance
	boot_needs = list()

/datum/unit_test/dq_xform_wave_statuses_by_distance/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/near = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/mid = allocate(/mob/living/carbon/human, locate(T.x + 2, T.y, T.z))
	var/mob/living/carbon/human/far = allocate(/mob/living/carbon/human, locate(T.x + 4, T.y, T.z))
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_PHOSPHORUS, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(near.has_status(STAT_WEAKENED), "a mob on the vessel's tile is weakened (the first band)")
	TEST_ASSERT(!near.has_status(STAT_STUNNED), "and only the first band that covers it applies")
	TEST_ASSERT(mid.has_status(STAT_STUNNED), "a mob two tiles out is stunned (the second band)")
	TEST_ASSERT(!mid.has_status(STAT_WEAKENED), "and not weakened")
	TEST_ASSERT(!far.has_status(STAT_STUNNED) && !far.has_status(STAT_WEAKENED), "a mob past every band is left alone")

/datum/unit_test/dq_xform_wave_mend_and_poison
	boot_needs = list()

/datum/unit_test/dq_xform_wave_mend_and_poison/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/near = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/far = allocate(/mob/living/carbon/human, locate(T.x + 4, T.y, T.z))
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_ETHANOL, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(near.has_affliction(/datum/affliction/venom/lingering_poison), "a mob in range is poisoned")
	TEST_ASSERT(!far.has_affliction(/datum/affliction/venom/lingering_poison), "a mob out of range is not")
	// The mend wave reaches a mob in range and tells it so; a run without a fault is what the boot and the test runner check.
	var/datum/reagents/dq_spawn_fixture/H2 = dq_spawn_holder(T)
	H2.add_reagent(REAGENT_ID_SUGAR, 1, safety = 1)
	xform_settle_reagents(H2)
	TEST_ASSERT_EQUAL(H2.total_volume, 0, "the mend rule went")

/datum/unit_test/dq_xform_spends_uses
	boot_needs = list()

/datum/unit_test/dq_xform_spends_uses/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_spend_probe/P = allocate(/obj/item/dq_spend_probe, T)
	var/datum/reagents/dq_spawn_fixture/H = new(1000, P)
	own(H)
	H.add_reagent(REAGENT_ID_SULFUR, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(P.uses, 2, "a step spent one use")
	TEST_ASSERT_EQUAL(P.set_calls, 1, "through the subject's spend_uses()")
	H.add_reagent(REAGENT_ID_URANIUM, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(P.uses, 0, "spends_all spent every use left")

/// A real slime extract: a reaction spends its one use and it goes inert, so the same reagent does nothing more.
/datum/unit_test/dq_xform_slime_extract_goes_inert
	boot_needs = list()

/datum/unit_test/dq_xform_slime_extract_goes_inert/Run()
	var/obj/item/slime_extract/grey/E = allocate(/obj/item/slime_extract/grey, test_floor())
	TEST_ASSERT_EQUAL(E.uses, 1, "a fresh extract has one use")
	E.reagents.add_reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT_EQUAL(E.uses, 0, "the reaction spent it")
	TEST_ASSERT(findtext(E.name, "inert"), "and the extract went inert ([E.name])")

/// A cold snap chills an unprotected body toward 50 K; a heat wave warms it toward the wave's temperature (it used to chill it too).
/datum/unit_test/dq_xform_thermal_cold_and_heat
	boot_needs = list()

/datum/unit_test/dq_xform_thermal_cold_and_heat/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/near = allocate(/mob/living/carbon/human, T)
	var/before = near.body_temperature()
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_GLYCEROL, 1, safety = 1)
	xform_settle_reagents(H)
	var/chilled = near.body_temperature()
	TEST_ASSERT(chilled < before, "the cold snap chilled the body ([before] -> [chilled])")
	var/datum/reagents/dq_spawn_fixture/H2 = dq_spawn_holder(T)
	H2.add_reagent(REAGENT_ID_AMMONIA, 1, safety = 1)
	xform_settle_reagents(H2)
	var/warmed = near.body_temperature()
	TEST_ASSERT(warmed > chilled, "the heat wave warmed it ([chilled] -> [warmed])")
	TEST_ASSERT(warmed <= T0C + 60, "never past the wave's own temperature ([warmed])")
	near.set_bodytemperature(before)

/// A scatter throws the mob on the vessel's tile somewhere within its distance.
/datum/unit_test/dq_xform_scatter_moves_mobs
	boot_needs = list()

/datum/unit_test/dq_xform_scatter_moves_mobs/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/near = allocate(/mob/living/carbon/human, T)
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_DIETHYLAMINE, 1, safety = 1)
	xform_settle_reagents(H)
	var/turf/landed = get_turf(near)
	TEST_ASSERT_NOTNULL(landed, "the mob landed on a turf")
	TEST_ASSERT(get_dist(landed, T) <= 6, "within the scatter's distance ([get_dist(landed, T)])")
	for(var/obj/effect/effect/sparks/S in range(7, T))
		qdel(S)

/// A slick wets the simulated floors in range.
/datum/unit_test/dq_xform_slick_wets_floors
	boot_needs = list()

/datum/unit_test/dq_xform_slick_wets_floors/Run()
	var/turf/simulated/T = test_floor()
	TEST_ASSERT(istype(T), "the test floor is simulated")
	if(!istype(T))
		return
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_MILK, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(T.wet, TURFSLIP_WET, "the vessel's floor is wet")
	for(var/turf/simulated/W in trange(1, T))
		W.set_wet(TURFSLIP_DRY)

#endif

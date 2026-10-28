#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// sets_off() run for real (code/library/transformations/transformation_effects.dm): each stock effect is set off by a fixture rule of the
// spawns() test regime and its result is looked for in the world. The explosion is the tiny one (an amount of 2 or less is sparks and a bang, no blast).

/transformation/dq_spawn/foam

CAPABILITIES(/transformation/dq_spawn/foam)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUM, 1)), made = 12, effects = sets_off(kind = XFORM_FX_FOAM, variant = 0, clears = TRUE)))

/transformation/dq_spawn/smoke

CAPABILITIES(/transformation/dq_spawn/smoke)
	configure(transformation(takes = list(reagent(REAGENT_ID_ALUMINIUM, 1)), made = 12, effects = sets_off(kind = XFORM_FX_SMOKE, clears = TRUE)))

/transformation/dq_spawn/pulse

CAPABILITIES(/transformation/dq_spawn/pulse)
	configure(transformation(takes = list(reagent(REAGENT_ID_COPPER, 1)), made = 24, effects = sets_off(kind = XFORM_FX_EMP, divisors = list(24, 12, 12, 12), clears = TRUE)))

/transformation/dq_spawn/bang

CAPABILITIES(/transformation/dq_spawn/bang)
	configure(transformation(takes = list(reagent(REAGENT_ID_LEAD, 1)), made = 2, effects = sets_off(kind = XFORM_FX_EXPLOSION, divisor = 1)))

/transformation/dq_spawn/aura

CAPABILITIES(/transformation/dq_spawn/aura)
	configure(transformation(takes = list(reagent(REAGENT_ID_LITHIUM, 1)), made = 1, effects = sets_off(kind = XFORM_FX_AREA, range = 1, body_effect = /datum/body_effect/entangled, lasts = 4 SECONDS)))

/// The subjects the delayed fixture handler was called on.
GLOBAL_LIST_EMPTY(dq_later_log)

/proc/dq_later_probe(atom/subject)
	GLOB.dq_later_log += subject

/transformation/dq_spawn/later

CAPABILITIES(/transformation/dq_spawn/later)
	configure(transformation(takes = list(reagent(REAGENT_ID_CARBON, 1)), made = 1, effects = sets_off(kind = XFORM_FX_LATER, delay = 2 SECONDS, handler = GLOBAL_PROC_REF(dq_later_probe), chance = 100)))

/transformation/dq_spawn/never

CAPABILITIES(/transformation/dq_spawn/never)
	configure(transformation(takes = list(reagent(REAGENT_ID_SILICON, 1)), made = 1, effects = list(sets_off(kind = XFORM_FX_LATER, delay = 1 SECOND, handler = GLOBAL_PROC_REF(dq_later_probe), chance = 0), sets_off(kind = XFORM_FX_BLAST, blast = list(-1, list(-1, -1), -1, -1)))))

/transformation/dq_spawn/frosty

CAPABILITIES(/transformation/dq_spawn/frosty)
	configure(transformation(takes = list(reagent(REAGENT_ID_POTASSIUM, 1)), made = 1, effects = sets_off(kind = XFORM_FX_FROST, amount = 3, chance = 100)))

/transformation/dq_spawn/timed_pulse

CAPABILITIES(/transformation/dq_spawn/timed_pulse)
	configure(transformation(takes = list(reagent(REAGENT_ID_NITROGEN, 1)), made = 1, effects = sets_off(kind = XFORM_FX_EMP, delay = 1 SECOND, ranges = list(1, 1, 1, 1))))

/transformation/dq_spawn/shove

CAPABILITIES(/transformation/dq_spawn/shove)
	configure(transformation(takes = list(reagent(REAGENT_ID_RADIUM, 2)), made = 1, effects = sets_off(kind = XFORM_FX_GRAVITY, direction = GRAVITY_PUSH, range = 2)))

/transformation/dq_spawn/soothe

CAPABILITIES(/transformation/dq_spawn/soothe)
	configure(transformation(takes = list(reagent(REAGENT_ID_PHORON, 1)), made = 1, effects = sets_off(kind = XFORM_FX_MOOD, mood = MOOD_CALM)))

/transformation/dq_spawn/rile

CAPABILITIES(/transformation/dq_spawn/rile)
	configure(transformation(takes = list(reagent(REAGENT_ID_HYDROGEN, 1)), made = 1, effects = sets_off(kind = XFORM_FX_MOOD, mood = MOOD_ENRAGE)))

/transformation/dq_spawn/ignite

CAPABILITIES(/transformation/dq_spawn/ignite)
	configure(transformation(takes = list(reagent(REAGENT_ID_OXYGEN, 1)), made = 4, effects = sets_off(kind = XFORM_FX_BURN, gases = list(GAS_VOLATILE_FUEL = 1), scale_by_made = TRUE, temperature = 500, range = 0, floors_only = TRUE)))

/transformation/dq_spawn/dose

CAPABILITIES(/transformation/dq_spawn/dose)
	configure(transformation(takes = list(reagent(REAGENT_ID_IRON, 1)), made = 1, effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_PICKY, symptoms = list(/datum/viral_trait/sneeze))))

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

/datum/unit_test/dq_xform_sets_off_later_chance_blast
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_later_chance_blast/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	GLOB.dq_later_log.Cut()
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	var/obj/B = H.my_atom
	H.add_reagent(REAGENT_ID_CARBON, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(GLOB.dq_later_log), 0, "the handler waits for its delay")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(length(GLOB.dq_later_log), 1, "the handler ran once on the subject after the delay")
	TEST_ASSERT_EQUAL(GLOB.dq_later_log[1], B, "and it was called on the vessel")
	GLOB.dq_later_log.Cut()
	// chance = 0 never goes; the empty blast beside it (all -1) is rolled and does nothing.
	var/datum/reagents/dq_spawn_fixture/H2 = dq_spawn_holder(T)
	H2.add_reagent(REAGENT_ID_SILICON, 1, safety = 1)
	xform_settle_reagents(H2)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(length(GLOB.dq_later_log), 0, "a row with chance 0 never goes")
	var/datum/reagents/dq_spawn_fixture/H3 = dq_spawn_holder(T)
	H3.add_reagent(REAGENT_ID_POTASSIUM, 1, safety = 1)
	xform_settle_reagents(H3)
	var/frost = 0
	for(var/obj/effect/effect/smoke/elemental/frost/F in range(8, T))
		frost++
		qdel(F)
	TEST_ASSERT(frost > 0, "the frost row made a frost cloud")
	GLOB.dq_later_log.Cut()
	test_driver_end()

/datum/unit_test/dq_xform_sets_off_timed_emp
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_timed_emp/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/item/dq_emp_probe/near = allocate(/obj/item/dq_emp_probe, T)
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_NITROGEN, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(near.pulsed, 0, "a fixed-range pulse with a delay waits")
	test_time(2 SECONDS)
	TEST_ASSERT(near.pulsed > 0, "and goes off after the delay with its fixed ranges")
	test_driver_end()

/datum/unit_test/dq_xform_sets_off_gravity_push
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_gravity_push/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/turf/side = locate(T.x + 1, T.y, T.z)
	var/obj/item/dq_emp_probe/loose = allocate(/obj/item/dq_emp_probe, side)
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_RADIUM, 2, safety = 1)
	xform_settle_reagents(H)
	var/datum/thrownthing/flight = loose.throwing
	TEST_ASSERT_NOTNULL(flight, "the rule threw the loose item")
	var/steps = 0
	while(!QDELETED(flight) && steps++ < 100)
		// world.time is frozen inside a test; a throw's pace is measured from its start_time, so age it one server tick per slot.
		flight.start_time -= world.tick_lag
		test_time(1)
	TEST_ASSERT(QDELETED(flight), "the throw never landed")
	TEST_ASSERT(get_dist(loose, T) > get_dist(side, T), "the item landed further from the vessel than it started")
	test_driver_end()

/datum/unit_test/dq_xform_sets_off_mood
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_mood/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/slime/xenobio/slime = allocate(/mob/living/simple_mob/slime/xenobio, T)
	slime.apply_body_effect(/datum/body_effect/berserk, 5 MINUTES)
	TEST_ASSERT(slime.has_body_effect(/datum/body_effect/berserk), "the slime starts berserk")
	var/saved_luminosity = T.luminosity
	T.luminosity = 3 // view() sees only lit turfs
	var/datum/reagents/dq_spawn_fixture/calm = dq_spawn_holder(T)
	calm.add_reagent(REAGENT_ID_PHORON, 1, safety = 1)
	xform_settle_reagents(calm)
	var/calmed = !slime.has_body_effect(/datum/body_effect/berserk)
	var/datum/reagents/dq_spawn_fixture/rile = dq_spawn_holder(T)
	rile.add_reagent(REAGENT_ID_HYDROGEN, 1, safety = 1)
	xform_settle_reagents(rile)
	var/riled = slime.has_body_effect(/datum/body_effect/berserk)
	T.luminosity = saved_luminosity
	TEST_ASSERT(calmed, "a calm mood takes the berserk off a slime in view")
	TEST_ASSERT(riled, "an enraged mood puts it back")

/datum/unit_test/dq_xform_sets_off_burn
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_burn/Run()
	var/turf/T = dq_containment_floor()
	TEST_ASSERT_NOTNULL(T, "a clean floor to burn on")
	var/datum/gas_mixture/air = T.return_air()
	var/before = air.get_moles(GAS_VOLATILE_FUEL)
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_OXYGEN, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(T.return_air().get_moles(GAS_VOLATILE_FUEL) > before, "the burn rule put fuel on the vessel's tile, scaled by what the step made")

/datum/unit_test/dq_xform_sets_off_contagion
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_contagion/Run()
	set_global(nameof(GLOB.archive_diseases), list())
	var/turf/T = test_floor()
	var/datum/affliction/contagion/engineered/strain = allocate(/datum/affliction/contagion/engineered, FALSE)
	var/datum/viral_trait/sneeze/prototype = dq_proto(/datum/viral_trait/sneeze)
	TEST_ASSERT(!strain.HasSymptom(prototype), "the strain starts without the symptom")
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_BLOOD, 5, safety = 1)
	var/datum/reagent/blood/B = locate_in_list(H.reagent_list, /datum/reagent/blood)
	TEST_ASSERT_NOTNULL(B, "the vessel holds blood")
	B.data = list("viruses" = list(strain))
	H.add_reagent(REAGENT_ID_IRON, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(strain.HasSymptom(prototype), "the picky evolve added the one symptom it was given")

#endif

// The chem vapour layer (code/world/systems/chem_vapour.dm): vapour of a reagent that is not an atmos gas, from a boil with no condenser, spreads over the tiles the air
// reaches, condenses, is breathed in, burns when flammable, and is bounded.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Empties the layer and restores its bound (a test's clean-up).
/proc/dq_cv_cleanup()
	SSchem_vapour.clear_all()
	SSchem_vapour.max_tiles = VAPOUR_MAX_TILES

/// A clean layer for the test, put back at its end.
/datum/unit_test/proc/dq_cv_begin()
	dq_cv_cleanup()
	defer_cleanup(null, GLOBAL_PROC_REF(dq_cv_cleanup))

/// Runs the layer's step `times` times, to the end of each pass.
/datum/unit_test/proc/dq_cv_steps(times)
	for(var/i in 1 to times)
		for(var/attempt in 1 to 50)
			if(SSchem_vapour.vapour_step(VAPOUR_STEP_SECONDS) != STEP_YIELD)
				break

/// Units of vapour in the whole layer.
/datum/unit_test/proc/dq_cv_total()
	. = 0
	for(var/key in SSchem_vapour.cells)
		var/datum/vapour_cell/cell = SSchem_vapour.cells[key]
		. += cell.total()

/// A reagent with no atmos gas boiling on a plate with no condenser goes into the layer on the plate's tile.
/datum/unit_test/dq_chem_vapour_appears_when_unmapped_boils

/datum/unit_test/dq_chem_vapour_appears_when_unmapped_boils/Run()
	dq_cv_begin()
	var/turf/open/T = dq_cg_floor()
	var/obj/machinery/chem_hot_plate/P = dq_cg_plate(T, REAGENT_ID_ETHANOL, 30)
	TEST_ASSERT_EQUAL(chem_vapour_tiles(), 0, "no vapour to begin with")
	P.set_dial(T0C + 150)
	P.switch_element(null, TRUE)
	test_time(30 SECONDS)
	TEST_ASSERT(P.held_container.reagents.get_reagent_amount(REAGENT_ID_ETHANOL) < 30, "the ethanol boiled")
	TEST_ASSERT(chem_vapour_tiles() > 0, "its vapour is in the layer")
	TEST_ASSERT(dq_cv_total() > 1, "and the layer holds units of it ([dq_cv_total()])")

/// A condenser next to the plate still catches the vapour first: the layer stays empty.
/datum/unit_test/dq_chem_vapour_condenser_first

/datum/unit_test/dq_chem_vapour_condenser_first/Run()
	dq_cv_begin()
	var/turf/open/T = dq_cg_floor()
	var/obj/machinery/chem_hot_plate/P = dq_cg_plate(T, REAGENT_ID_ETHANOL, 30)
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, T)
	C.set_anchored(TRUE)
	C.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/catch = allocate(/obj/item/reagent_containers/glass/beaker/large, T)
	move_into(C, nameof(C.held_container), catch)
	P.set_dial(T0C + 150)
	P.switch_element(null, TRUE)
	test_time(30 SECONDS)
	TEST_ASSERT(catch.reagents.get_reagent_amount(REAGENT_ID_ETHANOL) > 1, "the condenser collected the vapour")
	TEST_ASSERT_EQUAL(chem_vapour_tiles(), 0, "none of it reached the layer")

/// Vapour spreads to the tiles the air reaches, no further in a step, and is gone in time.
/datum/unit_test/dq_chem_vapour_diffuses_and_decays

/datum/unit_test/dq_chem_vapour_diffuses_and_decays/Run()
	dq_cv_begin()
	var/turf/open/T = dq_cg_floor()
	TEST_ASSERT_EQUAL(chem_vapour_add(T, REAGENT_ID_ETHANOL, 40, T0C + 100), 40, "the layer took the vapour")
	TEST_ASSERT_EQUAL(chem_vapour_tiles(), 1, "one tile holds it")
	dq_cv_steps(1)
	var/list/reach = vg_atmos_adjacent_turfs(T)
	TEST_ASSERT(chem_vapour_tiles() > 1, "it spread to its neighbours ([chem_vapour_tiles()] tiles)")
	for(var/key in SSchem_vapour.cells)
		var/datum/vapour_cell/cell = SSchem_vapour.cells[key]
		var/turf/where = locate(cell.x, cell.y, cell.z)
		TEST_ASSERT(where == T || (where in reach), "[where] is a tile the air reaches from [T]")
	TEST_ASSERT(dq_cv_total() <= 40, "nothing was made ([dq_cv_total()])")
	var/early = dq_cv_total()
	dq_cv_steps(80)
	TEST_ASSERT(dq_cv_total() < early / 4, "it condenses away over time ([early] -> [dq_cv_total()])")
	dq_cv_steps(300)
	TEST_ASSERT_EQUAL(chem_vapour_tiles(), 0, "and the layer empties below its epsilon")

/// A wall blocks it: a floor beside a wall never gives the wall tile vapour.
/datum/unit_test/dq_chem_vapour_blocked_by_wall

/datum/unit_test/dq_chem_vapour_blocked_by_wall/Run()
	dq_cv_begin()
	var/turf/open/T
	var/turf/wall
	for(var/turf/simulated/floor/F in world)
		for(var/direction in GLOB.cardinal)
			var/turf/N = get_step(F, direction)
			if(istype(N, /turf/simulated/wall))
				T = F
				wall = N
				break
		if(T)
			break
	TEST_ASSERT_NOTNULL(T, "a floor beside a wall on the test map")
	dq_atmos_test_snapshot_air(T)
	chem_vapour_add(T, REAGENT_ID_ETHANOL, 60, T0C + 100)
	dq_cv_steps(6)
	TEST_ASSERT(chem_vapour_tiles() > 1, "it spread")
	TEST_ASSERT_EQUAL(chem_vapour_total_at(wall), 0, "but none of it is in the wall")
	TEST_ASSERT(!(wall in vg_atmos_adjacent_turfs(T)), "the air does not reach the wall from the floor")

/// Vapour on a breather's tile goes into its blood, and a lot of it tints the view.
/datum/unit_test/dq_chem_vapour_is_inhaled

/datum/unit_test/dq_chem_vapour_is_inhaled/Run()
	dq_cv_begin()
	var/turf/open/T = dq_cg_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NOTNULL(H.bloodstr, "the human has a bloodstream")
	chem_vapour_add(T, REAGENT_ID_ETHANOL, 30, T0C + 30)
	var/before = dq_cv_total()
	H.life_breathing_inhale_vapour()
	TEST_ASSERT(H.bloodstr.get_reagent_amount(REAGENT_ID_ETHANOL) > 0.1, "a breath of vapour reached the blood ([H.bloodstr.get_reagent_amount(REAGENT_ID_ETHANOL)]u)")
	TEST_ASSERT(dq_cv_total() < before, "and came out of the layer")
	TEST_ASSERT_NOTNULL(LAZYACCESS(H.screens, "chem_vapour"), "a lot of vapour tints the view")
	SSchem_vapour.clear_all()
	H.life_breathing_inhale_vapour()
	TEST_ASSERT_NULL(LAZYACCESS(H.screens, "chem_vapour"), "the tint goes with the vapour")

/// The layer is bounded: a tile cap with merging, and a cap on one tile.
/datum/unit_test/dq_chem_vapour_is_bounded

/datum/unit_test/dq_chem_vapour_is_bounded/Run()
	dq_cv_begin()
	SSchem_vapour.max_tiles = 3
	var/turf/open/T = dq_cg_floor()
	var/list/floors = list()
	for(var/turf/simulated/floor/F in world)
		floors += F
		if(length(floors) >= 12)
			break
	for(var/turf/F as anything in floors)
		chem_vapour_add(F, REAGENT_ID_ETHANOL, 5, T0C + 100)
	TEST_ASSERT(chem_vapour_tiles() <= 3, "never more tiles than the cap ([chem_vapour_tiles()])")
	var/refused = chem_vapour_refused()
	dq_cv_steps(5)
	TEST_ASSERT(chem_vapour_tiles() <= 3, "the spread respects it too ([chem_vapour_tiles()])")
	SSchem_vapour.clear_all()
	SSchem_vapour.max_tiles = VAPOUR_MAX_TILES
	var/taken = chem_vapour_add(T, REAGENT_ID_ETHANOL, VAPOUR_TILE_MAX_UNITS * 4, T0C + 100)
	TEST_ASSERT(taken <= VAPOUR_TILE_MAX_UNITS, "one tile holds at most [VAPOUR_TILE_MAX_UNITS]u (took [taken])")
	TEST_ASSERT(chem_vapour_refused() > refused, "the rest is counted as refused")

/// Flammable vapour ignites from a hotspot and burns; one that is not flammable does not.
/datum/unit_test/dq_chem_vapour_ignites

/datum/unit_test/dq_chem_vapour_ignites/Run()
	dq_cv_begin()
	var/turf/open/T = dq_cg_floor()
	var/datum/gas_mixture/air = T.turf_air()
	chem_vapour_add(T, REAGENT_ID_SUGAR, 10, T0C + 30)
	chem_vapour_add(T, REAGENT_ID_ETHANOL, 10, T0C + 30)
	TEST_ASSERT(!chem_vapour_ignite_at(T, T0C + 200), "a warm spot does not light it")
	var/kelvin = air.return_temperature()
	T.hotspot_expose(1000, 100)
	TEST_ASSERT(chem_vapour_total_at(T) < 11, "the ethanol vapour burned ([chem_vapour_total_at(T)]u left)")
	TEST_ASSERT(chem_vapour_total_at(T) > 9, "the sugar vapour did not")
	TEST_ASSERT(air.return_temperature() > kelvin, "the fire warmed the air ([kelvin] -> [air.return_temperature()] K)")

#endif

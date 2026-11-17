// Ice, the ice machine and baths (code/domains/world_model/reagents/freezing.dm, code/content/reagents/machinery/ice_machine.dm,
// code/content/reagents/purification/nesting.dm) and the hot plate that only heats (code/content/reagents/machinery/hot_plate.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// `seconds` of the world in steps of `step`: the native heat system (a bath's coupling to its inner container and to the room), the temperature sensing and the kernel's
/// timers (the machines' own work).
/datum/unit_test/proc/dq_ice_run(seconds, step = 5)
	for(var/block in 1 to round(seconds / step))
		heat_test_world_seconds(step)
		dq_sense_test_deliver()
		test_time(step * (1 SECOND))

/// A basin of `ice` units of ice and `water` of water at 0 C (a bath), on the kernel test clock.
/datum/unit_test/proc/dq_ice_bath(ice, water)
	var/obj/item/reagent_containers/glass/basin/bath = allocate(/obj/item/reagent_containers/glass/basin, test_floor())
	if(ice)
		bath.reagents.add_reagent(REAGENT_ID_ICE, ice, safety = 1)
	if(water)
		bath.reagents.add_reagent(REAGENT_ID_WATER, water, safety = 1)
	bath.inherit_heat(T0C)
	return bath

/// A small beaker of `water` units of water at room temperature stood in `bath` (the nesting the op does: the container goes in and both get kept heat bodies).
/datum/unit_test/proc/dq_ice_inner(obj/item/reagent_containers/glass/bath, water)
	var/obj/item/reagent_containers/glass/beaker/inner = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	inner.reagents.add_reagent(REAGENT_ID_WATER, water, safety = 1)
	TEST_ASSERT_NULL(bath.nest_refusal(inner), "[inner] may stand in [bath]")
	var/inner_temperature = inner.get_temperature()
	TEST_ASSERT(move_into(bath, nameof(bath.nested), inner), "[inner] went into [bath]")
	bath.nest_couple(inner_temperature)
	return inner

/// Melting takes the latent heat out of the container and freezing puts it back, unit for unit.
/datum/unit_test/dq_ice_phase_change_carries_latent_heat

/datum/unit_test/dq_ice_phase_change_carries_latent_heat/Run()
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.reagents.add_reagent(REAGENT_ID_WATER, 60, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_ICE, 10, safety = 1)
	B.inherit_heat(T0C + 5)
	var/before = B.get_temperature()
	var/capacity = B.thermal_properties()[THERMAL_CAPACITY]
	var/melted = B.reagents.phase_step()
	TEST_ASSERT(melted > 0, "ice in a 5 C beaker melts")
	TEST_ASSERT(melted <= 10.001, "no more melts than there is ice ([melted])")
	var/removed = capacity * (before - B.get_temperature())
	TEST_ASSERT(abs(removed - melted * ICE_MELT_LATENT_HEAT) < 0.05 * melted * ICE_MELT_LATENT_HEAT + 1, "melting [round(melted, 0.01)]u took [round(removed)] J out of the beaker, not [round(melted * ICE_MELT_LATENT_HEAT)] J")
	TEST_ASSERT_EQUAL(round(B.reagents.get_reagent_amount(REAGENT_ID_WATER) + B.reagents.get_reagent_amount(REAGENT_ID_ICE), 0.01), 70, "no volume is lost in a melt")
	// Water below 0 C freezes and warms the beaker back toward 0 C by the latent heat.
	var/obj/item/reagent_containers/glass/beaker/large/C = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	C.reagents.add_reagent(REAGENT_ID_WATER, 60, safety = 1)
	C.inherit_heat(T0C - 5)
	var/cold = C.get_temperature()
	var/cold_capacity = C.thermal_properties()[THERMAL_CAPACITY]
	var/frozen = C.reagents.phase_step()
	TEST_ASSERT(frozen > 0, "water at -5 C freezes")
	var/given = cold_capacity * (C.get_temperature() - cold)
	TEST_ASSERT(abs(given - frozen * ICE_MELT_LATENT_HEAT) < 0.05 * frozen * ICE_MELT_LATENT_HEAT + 1, "freezing [round(frozen, 0.01)]u gave [round(given)] J to the beaker")
	TEST_ASSERT(C.get_temperature() <= T0C + 0.5, "freezing does not warm it much past 0 C ([C.get_temperature() - T0C])")
	TEST_ASSERT(C.reagents.get_reagent_amount(REAGENT_ID_ICE) > 0, "and there is ice")
	// Ice and water at 0 C stay as they are.
	var/obj/item/reagent_containers/glass/beaker/large/D = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	D.reagents.add_reagent(REAGENT_ID_WATER, 30, safety = 1)
	D.reagents.add_reagent(REAGENT_ID_ICE, 30, safety = 1)
	D.inherit_heat(T0C)
	TEST_ASSERT_EQUAL(D.reagents.phase_step(), 0, "ice and water at 0 C change nothing")

/// The ice machine freezes a container of water in about a minute and a half, draws power while it runs, and switches itself off when it is done.
/datum/unit_test/dq_ice_machine_makes_ice

/datum/unit_test/dq_ice_machine_makes_ice/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/machinery/chem_ice_machine/M = allocate(/obj/machinery/chem_ice_machine, test_floor())
	M.set_anchored(TRUE)
	M.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.reagents.add_reagent(REAGENT_ID_WATER, 60, safety = 1)
	move_into(M, nameof(M.held_container), B)
	M.switch_coil(null, TRUE)
	TEST_ASSERT(M.running, "the coil runs")
	TEST_ASSERT_EQUAL(M.use_power, USE_POWER_ACTIVE, "and draws its active power")
	test_time(20 SECONDS)
	TEST_ASSERT(B.get_temperature() < T20C - 3, "it chills the water ([B.get_temperature() - T0C] C)")
	TEST_ASSERT(findtext(M.maptext, "ice"), "the readout shows the ice ([M.maptext])")
	test_time(180 SECONDS)
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_ICE) >= 59, "the water is ice ([B.reagents.get_reagents()])")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_WATER) < 0.5, "with no water left")
	TEST_ASSERT(B.get_temperature() <= ICE_MACHINE_TEMP + 1, "at the setpoint ([B.get_temperature() - T0C] C)")
	TEST_ASSERT(!M.running, "the machine switched itself off")
	TEST_ASSERT_EQUAL(M.use_power, USE_POWER_IDLE, "and draws only its idle power")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(findtext(jointext(M.examine(H), " "), "ice"), "examining it shows the ice")

/// It chills nothing without power.
/datum/unit_test/dq_ice_machine_needs_power

/datum/unit_test/dq_ice_machine_needs_power/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/machinery/chem_ice_machine/M = allocate(/obj/machinery/chem_ice_machine, test_floor())
	M.set_anchored(TRUE)
	M.set_powered(FALSE)
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.reagents.add_reagent(REAGENT_ID_WATER, 60, safety = 1)
	move_into(M, nameof(M.held_container), B)
	M.switch_coil(null, TRUE)
	test_time(60 SECONDS)
	TEST_ASSERT(!M.running, "an unpowered machine does not switch on")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_ICE) < 0.5, "and makes no ice")

/// A bath of ice and water stays at 0 C while any ice is left, chills the small container standing in it, and warms back once the ice is gone.
/datum/unit_test/dq_ice_bath_holds_zero_until_the_ice_is_gone

/datum/unit_test/dq_ice_bath_holds_zero_until_the_ice_is_gone/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/item/reagent_containers/glass/basin/bath = dq_ice_bath(100, 40)
	var/obj/item/reagent_containers/glass/beaker/inner = dq_ice_inner(bath, 40)
	TEST_ASSERT(abs(inner.get_temperature() - T20C) < 1, "the inner beaker starts at room temperature")
	var/start_ice = bath.reagents.get_reagent_amount(REAGENT_ID_ICE)
	for(var/block in 1 to 40)
		dq_ice_run(5)
		if(bath.reagents.get_reagent_amount(REAGENT_ID_ICE) > 1)
			TEST_ASSERT(abs(bath.get_temperature() - T0C) < 1.5, "the bath holds near 0 C while ice remains ([round(bath.get_temperature() - T0C, 0.1)] C, [round(bath.reagents.get_reagent_amount(REAGENT_ID_ICE), 0.1)]u ice)")
	TEST_ASSERT(inner.get_temperature() < T0C + 4, "the inner beaker is chilled to [round(inner.get_temperature() - T0C, 0.1)] C")
	TEST_ASSERT(bath.reagents.get_reagent_amount(REAGENT_ID_ICE) < start_ice - 10, "the heat it took melted the ice ([round(bath.reagents.get_reagent_amount(REAGENT_ID_ICE), 0.1)]u left of [start_ice])")
	// With almost no ice the heat of the inner beaker finishes it and the bath warms.
	var/obj/item/reagent_containers/glass/basin/small_bath = dq_ice_bath(3, 100)
	var/obj/item/reagent_containers/glass/beaker/warm = dq_ice_inner(small_bath, 40)
	dq_ice_run(300)
	TEST_ASSERT(small_bath.reagents.get_reagent_amount(REAGENT_ID_ICE) < 0.1, "the ice is gone")
	TEST_ASSERT(small_bath.get_temperature() > T0C + 2, "and the bath warmed ([round(small_bath.get_temperature() - T0C, 0.1)] C)")
	TEST_ASSERT(warm.get_temperature() < T20C - 1 && warm.get_temperature() > T0C, "the inner beaker is between ([round(warm.get_temperature() - T0C, 0.1)] C)")

/// A warm water bath on the hot plate heats the small container standing in it, through the bath; the plate shows both temperatures.
/datum/unit_test/dq_ice_warm_bath_on_the_plate_heats_the_inner_beaker

/datum/unit_test/dq_ice_warm_bath_on_the_plate_heats_the_inner_beaker/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_anchored(TRUE)
	P.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/basin/bath = allocate(/obj/item/reagent_containers/glass/basin, test_floor())
	bath.reagents.add_reagent(REAGENT_ID_WATER, 100, safety = 1)
	var/obj/item/reagent_containers/glass/beaker/inner = dq_ice_inner(bath, 30)
	move_into(P, nameof(P.held_container), bath)
	P.set_dial(T0C + 60)
	P.switch_element(null, TRUE)
	dq_ice_run(30)
	TEST_ASSERT(bath.get_temperature() > inner.get_temperature(), "the bath is warmer than the inner beaker ([round(bath.get_temperature() - T0C)] C against [round(inner.get_temperature() - T0C)] C)")
	dq_ice_run(240)
	TEST_ASSERT(inner.get_temperature() > T0C + 45, "the inner beaker was heated through the bath to [round(inner.get_temperature() - T0C, 0.1)] C")
	TEST_ASSERT(inner.get_temperature() <= bath.get_temperature() + 0.5, "and not past the bath ([round(bath.get_temperature() - T0C, 0.1)] C)")
	TEST_ASSERT(bath.get_temperature() <= T0C + 60.5, "the bath is not past the dial")
	TEST_ASSERT(findtext(P.maptext, "(") && findtext(P.maptext, "/60C"), "the readout shows both ([P.maptext])")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(findtext(jointext(P.examine(H), " "), "stands in it"), "examining the plate shows the inner beaker")

/// The plate only heats: the dial has a floor at room temperature and a container hotter than the dial is left to cool on its own.
/datum/unit_test/dq_ice_hot_plate_no_longer_cools

/datum/unit_test/dq_ice_hot_plate_no_longer_cools/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_anchored(TRUE)
	P.set_powered(TRUE)
	P.set_dial(T0C + 5)
	TEST_ASSERT(P.target_temp >= HOT_PLATE_MIN_TEMP, "the dial does not go below room temperature ([P.target_temp - T0C] C)")
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	B.inherit_heat(T0C + 40)
	move_into(P, nameof(P.held_container), B)
	P.switch_element(null, TRUE)
	var/start = B.get_temperature()
	for(var/second in 1 to 60)
		P.heat_step(1)
	TEST_ASSERT(B.get_temperature() >= start - 0.01, "a plate dialled below the beaker does not cool it ([round(start - T0C, 0.1)] -> [round(B.get_temperature() - T0C, 0.1)] C)")
	var/obj/item/reagent_containers/glass/beaker/large/C = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	C.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	C.inherit_heat(T0C + 2)
	P.remove_container(null)
	move_into(P, nameof(P.held_container), C)
	for(var/second in 1 to 60)
		P.heat_step(1)
	TEST_ASSERT(C.get_temperature() >= T0C + 2 - 0.01, "and a cold one is not chilled either")

/// A small container stands in a larger open one, only one, only a smaller one, comes out again, and a pour into the bath goes into the bath.
/datum/unit_test/dq_p2_reagents/dq_ice_nesting_rules_and_removal

/datum/unit_test/dq_p2_reagents/dq_ice_nesting_rules_and_removal/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/large/outer = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	var/obj/item/reagent_containers/glass/beaker/inner = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, outer, inner, I_GRAB)
	TEST_ASSERT_EQUAL(outer.nested, inner, "a smaller beaker clicked in a grab stance stands in the large one ([rc_last_click?.reason])")
	TEST_ASSERT_EQUAL(inner.loc, outer, "inside it")
	TEST_ASSERT_EQUAL(outer.reagents.total_volume, 0, "and was not poured into it")
	TEST_ASSERT_EQUAL(inner.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "nor emptied")
	TEST_ASSERT_NOTNULL(inner.heat_body, "the inner beaker has a heat body")
	TEST_ASSERT_NOTNULL(outer.heat_body, "and so has the bath")
	var/obj/item/reagent_containers/glass/beaker/second = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, outer, second, I_GRAB)
	TEST_ASSERT_EQUAL(outer.nested, inner, "only one container stands in it")
	TEST_ASSERT_NULL(second.bath_of(), "the second is not in the bath")
	// Only a smaller one: a large beaker does not go in a large beaker, nor in a small one.
	var/obj/item/reagent_containers/glass/beaker/large/other = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 10)
	var/obj/item/reagent_containers/glass/beaker/small_outer = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, small_outer, other, I_GRAB)
	TEST_ASSERT_NULL(small_outer.nested, "a larger container does not stand in a smaller one")
	var/obj/item/reagent_containers/glass/beaker/large/empty_large = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	var/obj/item/reagent_containers/glass/beaker/large/same = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 10)
	rc_click(H, empty_large, same, I_GRAB)
	TEST_ASSERT_NULL(empty_large.nested, "nor one of the same size")
	// A basin takes a large beaker.
	var/obj/item/reagent_containers/glass/basin/basin = rc_filled(/obj/item/reagent_containers/glass/basin, 0)
	var/obj/item/reagent_containers/glass/beaker/large/big = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 5)
	rc_click(H, basin, big, I_GRAB)
	TEST_ASSERT_EQUAL(basin.nested, big, "a large beaker stands in a basin")
	// It comes out again, into the hand.
	test_menu(H, outer, "glass_nesting.remove_nested")
	rc_settle()
	TEST_ASSERT_NULL(outer.nested, "taking it out empties the bath")
	TEST_ASSERT(inner.loc == H || inner.loc == H.loc, "the beaker is in the hands or at the feet of the person")
	TEST_ASSERT_NULL(inner.bath_of(), "and no longer in the bath")
	TEST_ASSERT_EQUAL(inner.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "with what it held")

/// A pour from a held container stays a pour whatever stands in the bath: it goes into the outer container's liquid, never the inner, in any stance.
/datum/unit_test/dq_p2_reagents/dq_ice_pour_into_a_bath_goes_to_the_outer_container

/datum/unit_test/dq_p2_reagents/dq_ice_pour_into_a_bath_goes_to_the_outer_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/large/outer = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 20)
	var/obj/item/reagent_containers/glass/beaker/inner = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, outer, inner, I_GRAB)
	TEST_ASSERT_EQUAL(outer.nested, inner, "the inner beaker stands in the bath")
	var/obj/item/reagent_containers/glass/beaker/jug = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, outer, jug, I_HELP)
	TEST_ASSERT_EQUAL(outer.reagents.get_reagent_amount(REAGENT_ID_WATER), 30, "a pour goes into the bath")
	TEST_ASSERT_EQUAL(inner.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "and not into the inner beaker")
	TEST_ASSERT_EQUAL(outer.nested, inner, "which is still standing in it")
	// A held container clicked on a bath that cannot take it in a grab stance is poured too.
	rc_click(H, outer, jug, I_GRAB)
	TEST_ASSERT_EQUAL(outer.reagents.get_reagent_amount(REAGENT_ID_WATER), 40, "a grab click on a bath that is taken pours")
	TEST_ASSERT_EQUAL(inner.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "still not into the inner beaker")
	// An empty bath is poured into in the other stances, not nested in.
	var/obj/item/reagent_containers/glass/beaker/large/empty_bath = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	var/obj/item/reagent_containers/glass/beaker/pourer = rc_filled(/obj/item/reagent_containers/glass/beaker, 20)
	rc_click(H, empty_bath, pourer, I_HELP)
	TEST_ASSERT_NULL(empty_bath.nested, "a help click is a pour")
	TEST_ASSERT_EQUAL(empty_bath.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "ten units went in")
	// A container is never a solid dropped in the bath.
	TEST_ASSERT_EQUAL(length(empty_bath.solids), 0, "no container lies in it as a solid")

/// The real path to the nitrating mix: an ice machine freezes a bath, the beaker of nitric and sulphuric acid stands in it, and the acids chill into the mixing band and
/// make the mix. At room temperature they stay apart (the dissolved-acid nitration is theirs to run).
/datum/unit_test/dq_p2_reagents/dq_chem_nitrating_mix_is_made_in_an_ice_bath

/datum/unit_test/dq_p2_reagents/dq_chem_nitrating_mix_is_made_in_an_ice_bath/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_ice_machine/M = allocate(/obj/machinery/chem_ice_machine, run_loc_floor_bottom_left)
	M.set_anchored(TRUE)
	M.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/large/tray = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 120)
	move_into(M, nameof(M.held_container), tray)
	M.switch_coil(null, TRUE)
	test_time(300 SECONDS)
	TEST_ASSERT(tray.reagents.get_reagent_amount(REAGENT_ID_ICE) >= 110, "the ice machine made ice ([tray.reagents.get_reagents()] at [round(tray.get_temperature() - T0C, 0.1)] C)")
	M.remove_container(H)
	// The ice is poured into a basin of water: the cold comes with it and makes it a bath of ice and water.
	var/obj/item/reagent_containers/glass/basin/bath = rc_filled(/obj/item/reagent_containers/glass/basin, 40)
	tray.set_amount_per_transfer_from_this(120)
	rc_click(H, bath, tray, I_HELP, FALSE)
	TEST_ASSERT(bath.reagents.get_reagent_amount(REAGENT_ID_ICE) > 5, "ice went into the basin ([bath.reagents.get_reagents()])")
	TEST_ASSERT(bath.get_temperature() < T0C + 1, "and the basin is at [round(bath.get_temperature() - T0C, 0.1)] C")
	var/obj/item/reagent_containers/glass/beaker/inner = allocate(/obj/item/reagent_containers/glass/beaker, run_loc_floor_bottom_left)
	inner.reagents.add_reagent(REAGENT_ID_NITRICACID, 20, safety = 1)
	inner.reagents.add_reagent(REAGENT_ID_SACID, 20, safety = 1)
	inner.reagents.handle_reactions()
	TEST_ASSERT_EQUAL(inner.reagents.get_reagent_amount(REAGENT_ID_NITRATINGMIX), 0, "the acids stay apart at room temperature")
	rc_click(H, bath, inner, I_GRAB)
	TEST_ASSERT_EQUAL(bath.nested, inner, "the beaker of acids stands in the bath")
	for(var/block in 1 to 40)
		heat_test_world_seconds(5)
		dq_sense_test_deliver()
		test_time(5 SECONDS)
		if(inner.get_temperature() <= T0C + 12 && inner.reagents.get_reagent_amount(REAGENT_ID_NITRATINGMIX) > 0)
			break
	TEST_ASSERT(inner.get_temperature() <= T0C + 12, "the bath chilled the acids to [round(inner.get_temperature() - T0C, 0.1)] C")
	TEST_ASSERT(inner.reagents.get_reagent_amount(REAGENT_ID_NITRATINGMIX) > 0, "and the chilled acids made the nitrating mix: [inner.reagents.get_reagents()]")

/// What is poured brings its temperature: ice poured into room-temperature water drops the mix toward 0 C, taking latent heat out of it as the ice melts.
/datum/unit_test/dq_ice_pouring_ice_cools_the_water

/datum/unit_test/dq_ice_pouring_ice_cools_the_water/Run()
	var/obj/item/reagent_containers/glass/beaker/large/source = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	source.reagents.add_reagent(REAGENT_ID_ICE, 60, safety = 1)
	source.inherit_heat(T0C - 10)
	var/obj/item/reagent_containers/glass/beaker/large/target = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	target.reagents.add_reagent(REAGENT_ID_WATER, 60, safety = 1)
	TEST_ASSERT(abs(target.get_temperature() - T20C) < 1, "the water is at room temperature")
	source.reagents.trans_to_holder(target.reagents, 60)
	TEST_ASSERT(target.get_temperature() < T20C - 5, "the mix dropped to [round(target.get_temperature() - T0C, 0.1)] C")
	TEST_ASSERT(target.get_temperature() >= T0C - 0.5, "and not far below 0 C")
	TEST_ASSERT(abs(source.get_temperature() - (T0C - 10)) < 0.5, "the beaker it came from is as cold as it was")

/// Hot liquid poured into a cold beaker warms it to the heat-capacity-weighted mix of the two.
/datum/unit_test/dq_ice_pouring_hot_liquid_warms_a_cold_beaker

/datum/unit_test/dq_ice_pouring_hot_liquid_warms_a_cold_beaker/Run()
	var/obj/item/reagent_containers/glass/beaker/large/source = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	source.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	source.inherit_heat(T0C + 80)
	var/obj/item/reagent_containers/glass/beaker/large/target = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	target.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	target.inherit_heat(T0C + 5)
	var/own_capacity = target.thermal_properties()[THERMAL_CAPACITY]
	var/carried = 40 * REAGENT_SPECIFIC_HEAT_WATER
	var/expected = ((own_capacity * (T0C + 5)) + (carried * (T0C + 80))) / (own_capacity + carried)
	source.reagents.trans_to_holder(target.reagents, 40)
	TEST_ASSERT(target.get_temperature() > T0C + 8, "the cold beaker warmed to [round(target.get_temperature() - T0C, 0.1)] C")
	TEST_ASSERT(abs(target.get_temperature() - expected) < 1, "to the weighted mix ([round(target.get_temperature() - T0C, 0.1)] C, expected [round(expected - T0C, 0.1)] C)")
	TEST_ASSERT(target.get_temperature() < T0C + 80, "and not to the temperature of what was poured")

/// The other ways a reagent moves between holders carry the heat too: a reagent drawn out by id, or by type, brings the temperature of the holder it came from.
/datum/unit_test/dq_ice_draws_carry_heat

/datum/unit_test/dq_ice_draws_carry_heat/proc/hot_source()
	var/obj/item/reagent_containers/glass/beaker/large/source = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	source.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	source.reagents.add_reagent(REAGENT_ID_SUGAR, 20, safety = 1)
	source.inherit_heat(T0C + 80)
	return source

/datum/unit_test/dq_ice_draws_carry_heat/proc/cold_target()
	var/obj/item/reagent_containers/glass/beaker/large/target = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	target.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	target.inherit_heat(T0C + 5)
	return target

/datum/unit_test/dq_ice_draws_carry_heat/Run()
	var/obj/item/reagent_containers/glass/beaker/large/source = hot_source()
	var/obj/item/reagent_containers/glass/beaker/large/target = cold_target()
	TEST_ASSERT(source.reagents.trans_id_to(target, REAGENT_ID_WATER, 30), "30u of water moved by id")
	TEST_ASSERT(target.get_temperature() > T0C + 8, "poured by id, the hot water warmed the cold beaker to [round(target.get_temperature() - T0C, 0.1)] C")
	TEST_ASSERT(target.get_temperature() < T0C + 80, "and not to the temperature of what was poured")
	TEST_ASSERT(abs(source.get_temperature() - (T0C + 80)) < 0.5, "the beaker it came from stayed as hot as it was")

	var/obj/item/reagent_containers/glass/beaker/large/other_target = cold_target()
	TEST_ASSERT(source.reagents.trans_type_to(other_target, REAGENT_ID_SUGAR, 15), "15u of sugar moved by type")
	TEST_ASSERT(other_target.get_temperature() > T0C + 5.5, "moved by type, the hot sugar warmed the cold beaker to [round(other_target.get_temperature() - T0C, 0.1)] C")

	var/datum/reagents/portion = source.reagents.draw_portion(REAGENT_ID_WATER, 5)
	TEST_ASSERT_NOTNULL(portion, "a portion was drawn")
	TEST_ASSERT(abs(portion.content_temperature() - (T0C + 80)) < 0.5, "the portion carries the temperature of the holder it was drawn from ([round(portion.content_temperature() - T0C, 0.1)] C)")
	qdel(portion)


#endif

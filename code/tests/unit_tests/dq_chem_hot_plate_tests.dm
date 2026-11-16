// The hot plate heats on its own clock while it is on (nobody has to stay beside it), boiling is limited by the heat delivered, and a beaker's reactions follow
// its real temperature.

/// A bolted, powered plate with a large beaker of `units` water on it, on the kernel test clock.
/datum/unit_test/proc/dq_hp_plate(units = 60)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_anchored(TRUE)
	P.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.reagents.add_reagent(REAGENT_ID_WATER, units, safety = 1)
	move_into(P, nameof(P.held_container), B)
	return P

/// Seconds the plate takes to boil its beaker dry at `celsius` (null: not within `limit`).
/datum/unit_test/proc/dq_hp_dry_time(celsius, units = 60, limit = 300)
	var/obj/machinery/chem_hot_plate/P = dq_hp_plate(units)
	var/obj/item/reagent_containers/glass/beaker/B = P.held_container
	P.set_dial(T0C + celsius)
	P.switch_element(null, TRUE)
	for(var/second in 1 to limit)
		test_time(1 SECOND)
		if(B.reagents.get_reagent_amount(REAGENT_ID_WATER) <= 0.01)
			return second
	return null

/// The plate's own timer does the heating and boiling: no actor is involved after the switch.
/datum/unit_test/dq_hp_heats_without_an_actor

/datum/unit_test/dq_hp_heats_without_an_actor/Run()
	var/obj/machinery/chem_hot_plate/P = dq_hp_plate()
	var/obj/item/reagent_containers/glass/beaker/B = P.held_container
	var/start = B.get_temperature()
	P.set_dial(T0C + 130)
	P.switch_element(null, TRUE)
	test_time(2 SECONDS)
	var/early = B.get_temperature()
	TEST_ASSERT(early > start + 1 && early < T0C + 130, "it warms over seconds, not at once ([start] -> [early] K)")
	test_time(300 SECONDS)
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_WATER) < 60, "the plate's own timer boiled water: [B.reagents.get_reagent_amount(REAGENT_ID_WATER)]u at [B.get_temperature() - T0C] C")

/// 60 u of water on a plate set well above 100 C boils dry in about half a minute to a minute.
/datum/unit_test/dq_hp_boil_off_time

/datum/unit_test/dq_hp_boil_off_time/Run()
	var/dry = dq_hp_dry_time(150)
	TEST_ASSERT_NOTNULL(dry, "60u of water boils dry at a 150 C dial")
	TEST_ASSERT(dry >= 25 && dry <= 70, "and takes 25-70 s ([dry] s)")

/// A hotter dial delivers more heat and boils faster; one just above the boiling point is slow.
/datum/unit_test/dq_hp_hotter_dial_boils_faster

/datum/unit_test/dq_hp_hotter_dial_boils_faster/Run()
	var/fast = dq_hp_dry_time(300)
	var/middle = dq_hp_dry_time(150)
	var/slow = dq_hp_dry_time(105, limit = 120)
	TEST_ASSERT_NOTNULL(fast, "a 300 C dial boils the beaker dry")
	TEST_ASSERT_NOTNULL(middle, "a 150 C dial boils the beaker dry")
	TEST_ASSERT(fast < middle, "300 C is faster than 150 C ([fast] s against [middle] s)")
	TEST_ASSERT(isnull(slow) || slow > middle * 2, "105 C is much slower than 150 C ([slow] s against [middle] s)")

/// While water remains the liquid is held at its boiling point, however high the dial.
/datum/unit_test/dq_hp_liquid_held_at_boiling_point

/datum/unit_test/dq_hp_liquid_held_at_boiling_point/Run()
	var/obj/machinery/chem_hot_plate/P = dq_hp_plate()
	var/obj/item/reagent_containers/glass/beaker/B = P.held_container
	P.set_dial(T0C + 250)
	P.switch_element(null, TRUE)
	test_time(20 SECONDS)
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_WATER) > 0, "there is water left to hold ([B.reagents.get_reagent_amount(REAGENT_ID_WATER)]u)")
	TEST_ASSERT(B.get_temperature() < T0C + 102, "the liquid does not pass its boiling point ([B.get_temperature() - T0C] C)")

/// Off the plate the beaker keeps cooling on its own.
/datum/unit_test/dq_hp_beaker_cools_off_the_plate

/datum/unit_test/dq_hp_beaker_cools_off_the_plate/Run()
	var/obj/machinery/chem_hot_plate/P = dq_hp_plate(20)
	var/obj/item/reagent_containers/glass/beaker/B = P.held_container
	P.set_dial(T0C + 80)
	P.switch_element(null, TRUE)
	test_time(60 SECONDS)
	var/hot = B.get_temperature()
	TEST_ASSERT(hot > T0C + 60, "the beaker is hot ([hot - T0C] C)")
	P.switch_element(null, FALSE)
	P.remove_container(null)
	heat_test_world_seconds(600) // the native world: the beaker's coupling to the room
	TEST_ASSERT(B.get_temperature() < hot - 1, "taken off the plate it cools ([hot - T0C] -> [B.get_temperature() - T0C] C)")

/// A beaker's reactions follow its temperature through the heat system: nothing steps them.
/datum/unit_test/dq_hp_reaction_follows_temperature

/datum/unit_test/dq_hp_reaction_follows_temperature/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	dq_pur_fill_for(B, /transformation/chem/instant/lipozine, 10, -10)
	dq_sense_test_deliver()
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_LIPOZINE), 0, "too cold: nothing reacted")
	dq_pur_set_temp(B, 25)
	heat_test_world_seconds(1)
	dq_sense_test_deliver()
	test_time(2 SECONDS)
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_LIPOZINE) > 0, "warmed into the band the reaction runs by itself ([B.get_temperature()] K, watch [B.reaction_watch ? "yes" : "no"], heard [SSsense.records_heard])")

/// The plate's readout and examine text show the beaker's temperature and the dial.
/datum/unit_test/dq_hp_shows_the_temperature

/datum/unit_test/dq_hp_shows_the_temperature/Run()
	var/obj/machinery/chem_hot_plate/P = dq_hp_plate(20)
	P.set_dial(T0C + 90)
	P.switch_element(null, TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT(findtext(P.maptext, "/90C"), "the readout shows the dial ([P.maptext])")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(findtext(jointext(P.examine(H), " "), "90 C"), "examining it shows the dial")

/// The readout keeps following a hot beaker after the element is switched off, and clears when the beaker is taken off.
/datum/unit_test/dq_hp_readout_follows_cooling_beaker

/datum/unit_test/dq_hp_readout_follows_cooling_beaker/Run()
	var/obj/machinery/chem_hot_plate/P = dq_hp_plate(20)
	P.set_dial(T0C + 90)
	P.switch_element(null, TRUE)
	test_time(60 SECONDS)
	P.switch_element(null, FALSE)
	test_time(2 SECONDS)
	var/first = P.maptext
	TEST_ASSERT(length(first), "the readout is still up with the element off ([first])")
	for(var/block in 1 to 30)
		heat_test_world_seconds(10)
		test_time(10 SECONDS)
	TEST_ASSERT(length(P.maptext) && P.maptext != first, "and it follows the cooling beaker ([first] -> [P.maptext])")
	P.remove_container(null)
	P.update_readout()
	TEST_ASSERT_EQUAL(P.maptext, "", "taking the beaker off clears it")

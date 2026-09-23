// H3 (doc/rewrite/temperature.md §4-5): items, reagents, fire and burning on
// heat bodies and rules. The generated threshold tests (dq_rule_thresholds)
// also cover every declared heat rule at its level; these check the rest.

/obj/item/dq_h3_still
	name = "test still"
	w_class = ITEMSIZE_SMALL

/obj/item/dq_h3_still/Initialize(mapload)
	. = ..()
	create_reagents(100, /datum/reagents/distilling)

/// Counts fire_act() calls: hotspots must not make any.
/obj/item/dq_h3_fire_probe
	name = "fire probe"
	w_class = ITEMSIZE_SMALL
	var/fire_acts = 0

/obj/item/dq_h3_fire_probe/fire_act(exposed_temperature, exposed_volume)
	fire_acts++
	return ..()

/// Puts the test floor's air back at room temperature (burning test objects heat it).
/proc/dq_h3_cool_floor(turf/open/T)
	T.air?.set_temperature(T20C)

/// wait_for_condition() helper: TRUE once A is warmer than `start`.
/proc/dq_h3_probe_warmer_than(atom/A, start)
	return A.get_temperature() > start

/// A fire needs oxygen; the test map's floor has little. Returns the air to restore.
/proc/dq_h3_oxygenate(turf/open/T)
	var/datum/gas_mixture/saved = new
	saved.copy_from(T.air)
	T.air.set_moles(GAS_O2, 20)
	return saved

/// Heat energy of `things`' bodies above 0 K: capacity x temperature.
/proc/dq_h3_energy(list/things)
	. = 0
	for(var/atom/A as anything in things)
		var/list/properties = A.thermal_properties()
		. += properties[THERMAL_CAPACITY] * A.get_temperature()

// ---- Ignition and melting, each at its threshold ----

/datum/unit_test/dq_h3_ignition_at_threshold

/datum/unit_test/dq_h3_ignition_at_threshold/Run()
	dq_h3_cool_floor(test_floor())
	var/datum/gas_mixture/restore = dq_h3_oxygenate(test_floor())
	var/obj/item/paper/paper = allocate(/obj/item/paper, test_floor())
	var/ignition = PROPERTY(paper, PROP_IGNITION_POINT)
	dq_rule_test_write(paper, PROP_TEMPERATURE, ignition - 1)
	dq_rx_flush()
	TEST_ASSERT(!(paper.resistance_flags & ON_FIRE), "a kelvin below its ignition point it does not burn")
	dq_rule_test_write(paper, PROP_TEMPERATURE, ignition + 1)
	dq_rx_flush()
	TEST_ASSERT(paper.resistance_flags & ON_FIRE, "a kelvin above it, the ignition rule lights it")

	// Heated at rest past its ignition point (its surroundings got hot while
	// nothing watched it): the rule fires as soon as it gets a heat body.
	var/turf/open/T = test_floor()
	var/datum/gas_mixture/saved = new
	saved.copy_from(T.air)
	var/obj/item/paper/late = allocate(/obj/item/paper, T)
	T.air.set_temperature(ignition + 100)
	late.add_heat(1)
	T.air.copy_from(saved)
	TEST_ASSERT(late.resistance_flags & ON_FIRE, "a first heat body above the ignition point lights it")
	paper.extinguish()
	late.extinguish()
	T.air.copy_from(restore)

/datum/unit_test/dq_h3_melting_at_threshold

/datum/unit_test/dq_h3_melting_at_threshold/Run()
	dq_h3_cool_floor(test_floor())
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/glass/cooler_bottle/bottle = allocate(/obj/item/reagent_containers/glass/cooler_bottle, T)
	var/melting = PROPERTY(bottle, PROP_MELTING_POINT)
	TEST_ASSERT(melting > T20C, "the bottle's melting point comes from its plastic")
	dq_rule_test_write(bottle, PROP_TEMPERATURE, melting - 1)
	dq_rx_flush()
	TEST_ASSERT(!QDELETED(bottle), "a kelvin below its melting point it keeps its shape")
	dq_rule_test_write(bottle, PROP_TEMPERATURE, melting + 1)
	dq_rx_flush()
	TEST_ASSERT(QDELETED(bottle), "a kelvin above, it melts")
	for(var/obj/effect/decal/cleanable/molten_item/goo in T)
		qdel(goo)
	// The bottle's release dumped its excess heat into the shared floor;
	// reset it so the window's own heat body starts at room temperature.
	// Otherwise its baseline rule check already reads "above the melting
	// point" before the write below, so the write is never seen as a
	// crossing and the overheating rule never fires.
	dq_h3_cool_floor(T)

	// Structures overheat instead: a damage stream while above the limit.
	var/obj/structure/window/basic/window = allocate(/obj/structure/window/basic, T)
	var/limit = PROPERTY(window, PROP_MELTING_POINT)
	TEST_ASSERT_EQUAL(limit, window.maximal_heat, "a window's heat limit is its maximal_heat")
	dq_rule_test_write(window, PROP_TEMPERATURE, limit + 50)
	var/datum/component/overheating/hot
	// A heavily loaded reactor can take a few frames to subscribe and fire on
	// a freshly created heat body; poll instead of assuming two flushes land.
	for(var/i in 1 to 10)
		dq_rx_flush()
		hot = window.GetComponent(/datum/component/overheating)
		if(hot || QDELETED(window))
			break
	TEST_ASSERT(hot, "above it the window overheats")
	var/before = window.get_integrity()
	hot.process(1)
	TEST_ASSERT(window.get_integrity() < before, "and takes thermal damage through the pipeline")
	dq_rule_test_write(window, PROP_TEMPERATURE, limit - 50)
	dq_rx_flush()
	TEST_ASSERT_NULL(window.GetComponent(/datum/component/overheating), "cooled below it, the stream stops")

// ---- Reagents ----

/datum/unit_test/dq_h3_reagent_reaction_at_temperature

/datum/unit_test/dq_h3_reagent_reaction_at_temperature/Run()
	dq_h3_cool_floor(test_floor())
	var/obj/item/dq_h3_still/still = allocate(/obj/item/dq_h3_still, test_floor())
	var/datum/reagents/distilling/holder = still.reagents
	// Hold the still at 300 K, off the room (beer distils at exactly room temperature).
	still.create_heat_body(TRUE)
	vg_heat_body_couple(still.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
	vg_heat_body_set_temperature(still.heat_body, 300)
	var/water_capacity = 10 * REAGENT_SPECIFIC_HEAT_WATER
	holder.add_reagent(REAGENT_ID_WATER, 10)
	TEST_ASSERT(abs(holder.heat_capacity() - water_capacity) < 0.01, "a holder's heat capacity is its reagents' specific heats")
	holder.add_reagent(REAGENT_ID_NUTRIMENT, 10)
	holder.add_reagent(REAGENT_ID_SUGAR, 10)
	TEST_ASSERT(!isnull(holder.heat_set_watch), "a distilling holder watches its reactions' temperatures with a ThresholdSet")
	TEST_ASSERT(!holder.has_reagent(REAGENT_ID_ETHANOL), "no ethanol at 300 K")
	// Ethanol distils between T20C + 30 and T20C + 40.
	vg_heat_body_set_temperature(still.heat_body, T20C + 35)
	dq_rx_flush()
	TEST_ASSERT(holder.has_reagent(REAGENT_ID_ETHANOL), "crossing into the reaction's range runs it, from the ThresholdSet crossing")

// ---- Cooking: an appliance heating its contents conserves energy ----

/datum/unit_test/dq_h3_appliance_energy

/datum/unit_test/dq_h3_appliance_energy/Run()
	dq_h3_cool_floor(test_floor())
	var/obj/machinery/appliance/cooker/oven/oven = allocate(/obj/machinery/appliance/cooker/oven, test_floor())
	STOP_MACHINE_PROCESSING(oven)
	oven.set_heating(TRUE)
	TEST_ASSERT(!isnull(oven.heat_body), "a heating cooker is a heat body")
	// Isolate it from the room so every joule stays in the oven and its contents.
	vg_heat_body_couple(oven.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
	var/list/things = list(oven)
	for(var/datum/cooking_item/CI as anything in oven.cooking_objs)
		TEST_ASSERT(!isnull(CI.container.heat_body), "its containers are coupled to it")
		things += CI.container
	// The heat source adds energy.
	vg_heat_debug_run_frames(1)
	var/start = dq_h3_energy(things)
	vg_heat_debug_run_frames(5)
	TEST_ASSERT(dq_h3_energy(things) - start >= oven.heating_power * 4, "the heat source put at least four seconds of power in")
	// With the source off, the hot oven heats its contents and no joule is
	// made or lost: the isolated oven plus contents keep their energy.
	vg_heat_body_power(oven.heat_body, 0)
	vg_heat_body_set_temperature(oven.heat_body, oven.optimal_temp)
	vg_heat_debug_run_frames(1)
	start = dq_h3_energy(things)
	var/contents_start = dq_h3_energy(things - oven)
	vg_heat_debug_run_frames(10)
	var/moved = dq_h3_energy(things - oven) - contents_start
	var/drift = abs(dq_h3_energy(things) - start)
	TEST_ASSERT(moved > 0, "the oven heated its contents")
	TEST_ASSERT(drift <= moved * 0.01, "energy is conserved: [moved] J moved to the contents, total changed by [drift] J")
	oven.set_heating(FALSE)

// ---- Burning ends on fuel, oxygen or cooling ----

/datum/unit_test/dq_h3_burning_ends

/datum/unit_test/dq_h3_burning_ends/Run()
	dq_h3_cool_floor(test_floor())
	var/turf/open/T = test_floor()
	var/datum/gas_mixture/air = T.return_air()
	var/datum/gas_mixture/saved = dq_h3_oxygenate(T)

	// Fuel: the damage stream burns it; it goes out when none is left.
	var/obj/item/paper/fuelled = allocate(/obj/item/paper, T)
	fuelled.rule_ignite()
	var/datum/component/burning/burn = fuelled.GetComponent(/datum/component/burning)
	TEST_ASSERT(burn, "ignited")
	TEST_ASSERT(!isnull(fuelled.heat_body), "burning is a heat source on the object's body")
	var/integrity = fuelled.get_integrity()
	var/oxygen = air.get_moles(GAS_O2)
	burn.process(1)
	TEST_ASSERT(fuelled.get_integrity() < integrity, "a second of burning is an integrity damage stream")
	TEST_ASSERT(air.get_moles(GAS_O2) < oxygen, "and uses the tile's oxygen")
	burn.fuel = 1
	burn.process(1)
	TEST_ASSERT_EQUAL(burn.ended_by, BURN_ENDED_FUEL, "it goes out when the fuel runs out")
	TEST_ASSERT(!(fuelled.resistance_flags & ON_FIRE), "and is no longer on fire")

	// Oxygen.
	var/obj/item/paper/smothered = allocate(/obj/item/paper, T)
	smothered.rule_ignite()
	burn = smothered.GetComponent(/datum/component/burning)
	air.set_moles(GAS_O2, 0)
	burn.process(1)
	air.set_moles(GAS_O2, 20)
	TEST_ASSERT_EQUAL(burn.ended_by, BURN_ENDED_OXYGEN, "it goes out without oxygen")

	// Cooling below its ignition point less the margin.
	var/obj/item/paper/doused = allocate(/obj/item/paper, T)
	doused.rule_ignite()
	burn = doused.GetComponent(/datum/component/burning)
	vg_heat_body_set_temperature(doused.heat_body, T20C)
	dq_rx_flush()
	TEST_ASSERT_EQUAL(burn.ended_by, BURN_ENDED_COOLED, "it goes out when it cools, from a heat watch")
	air.copy_from(saved)
	air.set_temperature(T20C)

// ---- Hotspots heat a tile's items through their heat nodes ----

/datum/unit_test/dq_h3_hotspot_heats_items

/datum/unit_test/dq_h3_hotspot_heats_items/Run()
	dq_h3_cool_floor(test_floor())
	var/turf/open/T = test_floor()
	var/datum/gas_mixture/saved = new
	saved.copy_from(T.air)
	var/obj/item/dq_h3_fire_probe/probe = allocate(/obj/item/dq_h3_fire_probe, T)

	T.air.set_moles(/datum/gas/oxygen, 300)
	T.air.set_moles(/datum/gas/plasma, 100)
	T.air.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 100)
	T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 500, CELL_VOLUME, TRUE)
	var/obj/effect/hotspot/hotspot = T.active_hotspot
	TEST_ASSERT(hotspot, "the tile burns")
	TEST_ASSERT_EQUAL(probe.heat_fire_turf, T, "the hotspot coupled the item to the burning gas")
	TEST_ASSERT(!isnull(probe.heat_body), "through its heat body")
	var/start = probe.get_temperature()
	// Was a fixed vg_heat_debug_run_frames(3): that assumed 3 frames is always
	// enough for the heat domain to measurably warm the probe, which held only
	// by accident when this test ran on a floor left warm by a previous test
	// sharing the same turf. On a genuinely isolated, cold floor, wait for the
	// actual condition instead of guessing a frame count.
	var/heated = wait_for_condition(
		CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(dq_h3_probe_warmer_than), probe, start),
		CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(vg_heat_debug_run_frames), 1),
		30,
	)
	TEST_ASSERT(heated, "the heat domain heats it")
	hotspot.perform_exposure()
	TEST_ASSERT_EQUAL(probe.fire_acts, 0, "without a fire_act() call per SSair fire")
	qdel(hotspot)
	TEST_ASSERT_NULL(probe.heat_fire_turf, "the fire going out uncouples it")

	for(var/obj/effect/hotspot/other in range(2, T))
		qdel(other)
	for(var/turf/open/near in range(2, T))
		if(near != T && near.air)
			near.air.set_moles(/datum/gas/plasma, 0)
	T.air.copy_from(saved)

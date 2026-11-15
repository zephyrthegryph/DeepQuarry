// Purification (code/content/reagents/purification/, hot_plate.dm, condenser.dm, code/domains/world_model/reagents/chem_temperature.dm, boiling.dm): the temperature a
// recipe runs at decides how clean its product is, a hot plate heats a beaker toward a dial, a container above a boiling point loses the reagent (a condenser
// catches it), a funnel with a filter takes contaminants out of a pour, a catalyst widens a recipe's ideal band, neutralisation consumes residues, and no
// machine takes a contaminant out of a mixture on its own.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A beaker on the test floor.
/datum/unit_test/proc/dq_pur_beaker(type = /obj/item/reagent_containers/glass/beaker/large)
	return allocate(type, test_floor())

/// Puts the container (and so its contents) at `celsius`.
/datum/unit_test/proc/dq_pur_set_temp(obj/item/reagent_containers/B, celsius)
	B.inherit_heat(T0C + celsius)

/// A holder of the rule's reactants, `scale` times its minimum each, in a container at `celsius` (null: room temperature), not yet reacted.
/datum/unit_test/proc/dq_pur_fill_for(obj/item/reagent_containers/B, rule_type, scale = 10, celsius = null)
	var/datum/xform/X = xform_of(rule_type)
	for(var/id in X.reagent_takes)
		B.reagents.add_reagent(id, X.reagent_takes[id] * scale, safety = 1)
	if(!isnull(celsius))
		dq_pur_set_temp(B, celsius)
	return X

/datum/unit_test/proc/dq_pur_near(a, b, tolerance = 0.01)
	return abs(a - b) <= tolerance

/// The mixture with the contaminants a pour should filter: stock and one of each class.
/datum/unit_test/proc/dq_pur_dirty_source(stock = 50, each = 5)
	var/obj/item/reagent_containers/glass/beaker/bluespace/source = allocate(/obj/item/reagent_containers/glass/beaker/bluespace, test_floor())
	source.reagents.add_reagent(REAGENT_ID_DEXALIN, stock, safety = 1)
	for(var/id in list(REAGENT_ID_CONTAMINANT_INERT_FILLER, REAGENT_ID_CONTAMINANT_OILY_RESIDUE, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, REAGENT_ID_CONTAMINANT_HEAVY_METAL, REAGENT_ID_CONTAMINANT_SULFUR, REAGENT_ID_CONTAMINANT_REACTIVE, REAGENT_ID_CONTAMINANT_BIOLOGICAL))
		source.reagents.add_reagent(id, each, safety = 1)
	return source

/// The contaminant classes of dq_pur_dirty_source().
/datum/unit_test/proc/dq_pur_classes()
	return list(REAGENT_ID_CONTAMINANT_INERT_FILLER, REAGENT_ID_CONTAMINANT_OILY_RESIDUE, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, REAGENT_ID_CONTAMINANT_HEAVY_METAL, REAGENT_ID_CONTAMINANT_SULFUR, REAGENT_ID_CONTAMINANT_REACTIVE, REAGENT_ID_CONTAMINANT_BIOLOGICAL)

/// A funnel with `filter` in it, fitted on a fresh beaker (the slots filled the way the ops fill them).
/datum/unit_test/proc/dq_pur_funnelled_beaker(obj/item/chem_filter/filter)
	var/obj/item/reagent_containers/glass/beaker/bluespace/target = allocate(/obj/item/reagent_containers/glass/beaker/bluespace, test_floor())
	var/obj/item/chem_funnel/funnel = allocate(/obj/item/chem_funnel, test_floor())
	if(filter)
		TEST_ASSERT(move_into(funnel, nameof(funnel.filter), filter), "the filter went into the funnel")
	TEST_ASSERT(move_into(target, nameof(target.funnel), funnel), "the funnel went on the beaker")
	return target

/// A material for the filters and catalysts: registered under `name` with the given stats, removed by dq_pur_forget_material().
/datum/unit_test/proc/dq_pur_material(name, porosity = 0, catalysis = 0, antimicrobial = 0)
	var/datum/material/M = new /datum/material/processed_alloy
	M.set_name(name)
	M.set_display_name(name)
	M.reagent_porosity = porosity
	M.catalytic_activity = catalysis
	M.antimicrobial_activity = antimicrobial
	GLOB.name_to_material[name] = M
	return M

/datum/unit_test/proc/dq_pur_forget_material(name)
	GLOB.name_to_material -= name

// ---- the hot plate ----

/datum/unit_test/dq_pur_hot_plate_heats_toward_target

/datum/unit_test/dq_pur_hot_plate_heats_toward_target/Run()
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	B.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	TEST_ASSERT(move_into(P, nameof(P.held_container), B), "the beaker stands on the plate")
	var/start = B.get_temperature()
	TEST_ASSERT(start > T0C && start < T0C + 40, "a beaker starts at room temperature ([start] K)")
	P.set_dial(T0C + 80)
	TEST_ASSERT(dq_pur_near(P.target_temp, T0C + 80, 0.01), "the dial reads 80 C")
	P.heat_step(1)
	TEST_ASSERT(dq_pur_near(B.get_temperature(), start, 0.01), "an element that is off heats nothing")
	P.switch_element(null, TRUE)
	TEST_ASSERT(P.heating, "the element is on")
	TEST_ASSERT_EQUAL(P.use_power, USE_POWER_ACTIVE, "and it draws its active power")
	P.heat_step(1)
	var/after_one = B.get_temperature()
	TEST_ASSERT(after_one > start + 0.5, "one second warms the beaker ([start] -> [after_one])")
	TEST_ASSERT(after_one < T0C + 80, "but not to the dial: it approaches it over seconds")
	var/previous = after_one
	for(var/second in 1 to 60)
		P.heat_step(1)
		TEST_ASSERT(B.get_temperature() >= previous - 0.001 && B.get_temperature() <= T0C + 80.5, "it never overshoots the dial")
		previous = B.get_temperature()
	TEST_ASSERT(dq_pur_near(B.get_temperature(), T0C + 80, 1), "and reaches it ([B.get_temperature() - T0C] C)")
	P.switch_element(null, FALSE)
	TEST_ASSERT_EQUAL(P.use_power, USE_POWER_IDLE, "switched off it draws its idle power")
	var/off_temp = B.get_temperature()
	P.heat_step(1)
	TEST_ASSERT(dq_pur_near(B.get_temperature(), off_temp, 0.01), "and heats nothing again")
	P.set_dial(T0C + 9999)
	TEST_ASSERT(P.target_temp <= HOT_PLATE_MAX_TEMP, "the dial has a top")

/// The ops: a beaker clicked onto a plate stands on it and a second is refused.
/datum/unit_test/dq_p2_reagents/dq_pur_hot_plate_takes_one_container

/datum/unit_test/dq_p2_reagents/dq_pur_hot_plate_takes_one_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, P, B)
	TEST_ASSERT_EQUAL(P.held_container, B, "the beaker is on the plate")
	var/obj/item/reagent_containers/glass/beaker/B2 = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, P, B2)
	TEST_ASSERT_EQUAL(P.held_container, B, "a second one is not taken")
	TEST_ASSERT_EQUAL(B2.loc, H, "and stays in hand")

// ---- reaction temperature ----

/datum/unit_test/dq_pur_every_recipe_has_a_band

/datum/unit_test/dq_pur_every_recipe_has_a_band/Run()
	var/checked = 0
	for(var/datum/xform/X as anything in dq_chem_rules())
		if(X.regime != REGIME_INSTANT)
			continue
		var/list/band = reaction_temperature_profile(X.rule_type)
		TEST_ASSERT_NOTNULL(band, "[X.rule_type] has a temperature band")
		TEST_ASSERT(band[1] < band[2] && band[2] < band[3] && band[3] < band[4], "[X.rule_type] has a range around a narrower ideal band")
		TEST_ASSERT(!isnull(GLOB.reaction_temperature_classes[reaction_temperature_class(X.rule_type)]), "[X.rule_type] is filed under a class that exists")
		checked++
	TEST_ASSERT(checked > 100, "the instant recipes were checked ([checked])")
	TEST_ASSERT_EQUAL(reaction_temperature_class(/transformation/chem/instant/anticonvulsant), REACTION_TEMP_GENTLE, "a plain medicine is gentle")
	TEST_ASSERT_EQUAL(reaction_temperature_class(/transformation/chem/instant/drinks/grapejuice), REACTION_TEMP_AMBIENT, "a bar drink is ambient")
	TEST_ASSERT_EQUAL(reaction_temperature_class(/transformation/chem/instant/hydride), REACTION_TEMP_HOT, "a hydride is hot")
	TEST_ASSERT_EQUAL(reaction_temperature_class(/transformation/chem/instant/explosion_potassium), REACTION_TEMP_VIOLENT, "an explosive is violent")
	var/list/gentle = GLOB.reaction_temperature_classes[REACTION_TEMP_GENTLE]
	var/list/hot = GLOB.reaction_temperature_classes[REACTION_TEMP_HOT]
	var/list/violent = GLOB.reaction_temperature_classes[REACTION_TEMP_VIOLENT]
	TEST_ASSERT(gentle[2] <= T20C && T20C <= gentle[3], "room temperature is inside the gentle ideal band")
	TEST_ASSERT(hot[2] > gentle[3] && violent[2] > hot[2], "harsher classes are hotter")

/// Inside the ideal band: clean product, nothing else.
/datum/unit_test/dq_pur_reaction_clean_in_the_ideal_band

/datum/unit_test/dq_pur_reaction_clean_in_the_ideal_band/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	var/datum/xform/X = dq_pur_fill_for(B, /transformation/chem/instant/anticonvulsant, 10, 25)
	TEST_ASSERT_EQUAL(B.reagents.reaction_temperature_state(X)[1], REACTION_TEMP_STATE_IDEAL, "25 C is inside the ideal band")
	B.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_ANTICONVULSANT), 30), "ten reaction units made 30u of product")
	TEST_ASSERT_EQUAL(B.reagents.contaminant_volume(), 0, "and not a unit of contaminant")
	TEST_ASSERT_EQUAL(B.reagents.grade(), GRADE_REAGENT, "Reagent grade")

/// Inside the range but off the band: product and contaminants, scaled by the distance; too cold leaves organic residue, too hot a reactive impurity and a loss.
/datum/unit_test/dq_pur_reaction_off_ideal_makes_contaminants

/datum/unit_test/dq_pur_reaction_off_ideal_makes_contaminants/Run()
	var/obj/item/reagent_containers/glass/beaker/cold = dq_pur_beaker()
	dq_pur_fill_for(cold, /transformation/chem/instant/anticonvulsant, 10, 5)
	cold.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(cold.reagents.get_reagent_amount(REAGENT_ID_ANTICONVULSANT), 30), "a cold run still makes all the product")
	var/residue = cold.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE)
	TEST_ASSERT(residue > 1, "too cold leaves organic residue ([residue]u)")
	TEST_ASSERT_EQUAL(cold.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_REACTIVE), 0, "and no reactive impurity")
	TEST_ASSERT(cold.reagents.purity() < 1 && cold.reagents.grade() < GRADE_REAGENT, "so the batch is no longer Reagent grade")
	// Colder is dirtier.
	var/obj/item/reagent_containers/glass/beaker/colder = dq_pur_beaker()
	dq_pur_fill_for(colder, /transformation/chem/instant/anticonvulsant, 10, 1)
	colder.reagents.handle_reactions()
	TEST_ASSERT(colder.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE) > residue, "the further from the band, the more residue")
	var/obj/item/reagent_containers/glass/beaker/hot = dq_pur_beaker()
	dq_pur_fill_for(hot, /transformation/chem/instant/anticonvulsant, 10, 60)
	hot.reagents.handle_reactions()
	var/impurity = hot.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_REACTIVE)
	var/product = hot.reagents.get_reagent_amount(REAGENT_ID_ANTICONVULSANT)
	TEST_ASSERT(impurity > 1, "too hot leaves a reactive impurity ([impurity]u)")
	TEST_ASSERT(product < 30 && product > 20, "and burns off some of the product ([product]u of 30)")
	TEST_ASSERT_EQUAL(hot.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE), 0, "but leaves no organic residue")

/// Outside the working range: nothing happens.
/datum/unit_test/dq_pur_reaction_refused_out_of_range

/datum/unit_test/dq_pur_reaction_refused_out_of_range/Run()
	var/obj/item/reagent_containers/glass/beaker/freezing = dq_pur_beaker()
	var/datum/xform/X = dq_pur_fill_for(freezing, /transformation/chem/instant/anticonvulsant, 10, -20)
	freezing.reagents.handle_reactions()
	TEST_ASSERT_EQUAL(freezing.reagents.get_reagent_amount(REAGENT_ID_ANTICONVULSANT), 0, "too cold: no product")
	TEST_ASSERT(dq_pur_near(freezing.reagents.get_reagent_amount(REAGENT_ID_SUGAR), 10), "the reactants are untouched")
	TEST_ASSERT_EQUAL(freezing.reagents.reaction_temperature_state(X)[1], REACTION_TEMP_STATE_OUT, "-20 C is outside the range")
	var/obj/item/reagent_containers/glass/beaker/boiling = dq_pur_beaker()
	dq_pur_fill_for(boiling, /transformation/chem/instant/anticonvulsant, 10, 120)
	boiling.reagents.handle_reactions()
	TEST_ASSERT_EQUAL(boiling.reagents.get_reagent_amount(REAGENT_ID_ANTICONVULSANT), 0, "too hot: no product either")
	// And warmed into the range it goes.
	dq_pur_set_temp(freezing, 25)
	freezing.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(freezing.reagents.get_reagent_amount(REAGENT_ID_ANTICONVULSANT), 30), "back in the band the mixture reacts at once")

/// A harsh recipe needs a hot plate; a bar drink does not.
/datum/unit_test/dq_pur_harsh_needs_heat_and_drinks_do_not

/datum/unit_test/dq_pur_harsh_needs_heat_and_drinks_do_not/Run()
	var/obj/item/reagent_containers/glass/beaker/room = dq_pur_beaker()
	dq_pur_fill_for(room, /transformation/chem/instant/pacid, 5)
	room.reagents.handle_reactions()
	TEST_ASSERT_EQUAL(room.reagents.get_reagent_amount(REAGENT_ID_PACID), 0, "polytrinic acid does not form at room temperature")
	dq_pur_set_temp(room, 95)
	room.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(room.reagents.get_reagent_amount(REAGENT_ID_PACID), 15), "at 95 C it does: ideal band, 15u from 5 reaction units")
	TEST_ASSERT_EQUAL(room.reagents.contaminant_volume(), 0, "and clean")
	var/obj/item/reagent_containers/glass/beaker/bar = dq_pur_beaker()
	dq_pur_fill_for(bar, /transformation/chem/instant/drinks/grapejuice, 5)
	bar.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(bar.reagents.get_reagent_amount(REAGENT_ID_GRAPEJUICE), 15), "a bar drink mixes at room temperature")
	TEST_ASSERT_EQUAL(bar.reagents.contaminant_volume(), 0, "with no contaminant")
	var/obj/item/reagent_containers/glass/beaker/chilled = dq_pur_beaker()
	dq_pur_fill_for(chilled, /transformation/chem/instant/drinks/grapejuice, 5, 2)
	chilled.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(chilled.reagents.get_reagent_amount(REAGENT_ID_GRAPEJUICE), 15), "and from a cold tap")
	TEST_ASSERT_EQUAL(chilled.reagents.contaminant_volume(), 0, "still clean")

/// A holder that is not a loose container (a mob's blood, a machine's buffer) is not gated.
/datum/unit_test/dq_pur_only_loose_containers_are_gated

/datum/unit_test/dq_pur_only_loose_containers_are_gated/Run()
	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, test_floor())
	var/datum/xform/X = xform_of(/transformation/chem/instant/pacid)
	TEST_ASSERT(!M.reagents.temperature_gated(), "a machine's buffer is not gated")
	TEST_ASSERT_NULL(M.reagents.reaction_temperature_state(X), "so a recipe has no temperature in it")
	TEST_ASSERT(M.reagents.reaction_temperature_ok(X), "and is never refused for it")
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	TEST_ASSERT(B.reagents.temperature_gated(), "a beaker is")

/// A solid catalyst belongs to the processes that run on one: a sheet in the beaker lowers their band (it does not widen any other recipe's), and no sheet, no route.
/datum/unit_test/dq_p2_reagents/dq_pur_solid_catalyst_lowers_a_process_band

/datum/unit_test/dq_p2_reagents/dq_pur_solid_catalyst_lowers_a_process_band/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, run_loc_floor_bottom_left)
	B.reagents.add_reagent(REAGENT_ID_ETHANOL, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_OXYGEN, 10, safety = 1)
	dq_pur_set_temp(B, 40)
	var/datum/chem_route/route = GLOB.chem_routes["oxidise:ethanol:solid_metal>contaminant_organic_residue"]
	TEST_ASSERT_NOTNULL(route, "oxidising ethanol on a solid metal is a generated route")
	var/datum/xform/X = dq_route_rule(route)
	TEST_ASSERT(!xform_matches(X, B.reagents), "with no sheet the route does not hold")
	TEST_ASSERT_NULL(B.reagents.solid_catalyst(), "there is no solid catalyst")
	var/obj/item/stack/material/exotic_feedstock/sheets = allocate(/obj/item/stack/material/exotic_feedstock, run_loc_floor_bottom_left)
	sheets.set_stack_material(MAT_ETCHING_CERAMIC)
	sheets.set_amount(3)
	TEST_ASSERT(sheets.material.catalytic_activity > 0, "etching ceramic is catalytic")
	var/material_name = sheets.material.name
	rc_click(H, B, sheets)
	TEST_ASSERT_NOTNULL(B.catalyst, "the sheet went into the beaker")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 2, "one sheet of three")
	TEST_ASSERT_EQUAL(B.catalyst.material.name, material_name, "of the material")
	TEST_ASSERT(dq_pur_near(B.catalyst_activity(), sheets.material.catalytic_activity), "its activity is the beaker's")
	var/list/solid = B.reagents.solid_catalyst()
	TEST_ASSERT_EQUAL(solid[1], B.catalyst_kind(), "its kind is the beaker's")
	var/list/lowered = route.band_in(B.reagents)
	TEST_ASSERT(dq_pur_near(route.band_base[2] - lowered[2], solid[2] * CHEM_SOLID_REDUCTION_PER_POINT, 0.01), "the band came down by the activity")
	// Poisoned by sulfur: the activity and the reduction go.
	B.reagents.add_reagent(REAGENT_ID_CONTAMINANT_SULFUR, 2, safety = 1)
	var/list/poisoned = B.reagents.solid_catalyst()
	TEST_ASSERT(poisoned[2] < solid[2], "sulfur poisons the sheet")
	// A sheet that is no catalyst is refused.
	var/obj/item/reagent_containers/glass/beaker/large/plain = allocate(/obj/item/reagent_containers/glass/beaker/large, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/plate = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left)
	rc_click(H, plain, plate)
	TEST_ASSERT_NULL(plain.catalyst, "a steel sheet is not a catalyst")

// ---- boiling ----

/datum/unit_test/dq_pur_boiling_follows_the_boiling_point

/datum/unit_test/dq_pur_boiling_follows_the_boiling_point/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	B.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_ETHANOL, 20, safety = 1)
	var/datum/reagent/water = B.reagents.get_reagent(REAGENT_ID_WATER)
	TEST_ASSERT(dq_pur_near(water.boiling_point_k(), T0C + 100, 0.01), "water boils at 100 C")
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent(REAGENT_ID_ETHANOL).boiling_point_k(), T0C + 78.4, 0.01), "ethanol at 78.4 C")
	var/list/cool = B.reagents.boil_step(5)
	TEST_ASSERT_EQUAL(length(cool), 0, "nothing boils at room temperature")
	dq_pur_set_temp(B, 90)
	var/list/warm = B.reagents.boil_step(1)
	TEST_ASSERT_NOTNULL(warm[REAGENT_ID_ETHANOL], "at 90 C the ethanol boils")
	TEST_ASSERT_NULL(warm[REAGENT_ID_WATER], "and the water does not")
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 40), "so the water is all there")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_ETHANOL) < 20, "the ethanol is less")
	dq_pur_set_temp(B, 115)
	var/water_before = B.reagents.get_reagent_amount(REAGENT_ID_WATER)
	var/list/hot = B.reagents.boil_step(1)
	TEST_ASSERT_NOTNULL(hot[REAGENT_ID_WATER], "at 115 C the water boils")
	var/lost = water_before - B.reagents.get_reagent_amount(REAGENT_ID_WATER)
	TEST_ASSERT(lost > 0.1 && lost < water_before / 2, "gradually: [lost]u of [water_before]u in a second")
	TEST_ASSERT(dq_pur_near(hot[REAGENT_ID_WATER][1], lost), "the vapour is what was lost")
	TEST_ASSERT(B.get_temperature() < T0C + 115, "and the vapour carried heat away")
	// Every reagent has a boiling point; a contaminant that is a salt or a metal effectively never boils.
	for(var/id in SSchemistry.ready().chemical_reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
		TEST_ASSERT(R.boiling_point_k() > 0, "[id] has a boiling point")
	TEST_ASSERT(contaminant_def(REAGENT_ID_CONTAMINANT_HEAVY_METAL).boiling_point_k() >= BOILING_POINT_NEVER, "heavy metals never boil")
	TEST_ASSERT(contaminant_def(REAGENT_ID_CONTAMINANT_SALTS).boiling_point_k() >= BOILING_POINT_NEVER, "salts never boil")
	TEST_ASSERT(contaminant_def(REAGENT_ID_CONTAMINANT_REACTIVE).boiling_point_k() < T0C + 100, "a reactive impurity boils off below water")

/// A hot plate boils its container's water away above 100 C and not below.
/datum/unit_test/dq_pur_hot_plate_boils_above_the_boiling_point

/datum/unit_test/dq_pur_hot_plate_boils_above_the_boiling_point/Run()
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	B.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	move_into(P, nameof(P.held_container), B)
	P.set_dial(T0C + 80)
	P.switch_element(null, TRUE)
	for(var/second in 1 to 90)
		P.heat_step(1)
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 40), "held at 80 C no water is lost")
	P.set_dial(T0C + 140)
	for(var/second in 1 to 120)
		P.heat_step(1)
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_WATER) < 40, "set to 140 C the water boils away")
	TEST_ASSERT(B.get_temperature() > T0C + 100, "the beaker is above 100 C ([B.get_temperature() - T0C])")

// ---- the condenser ----

/datum/unit_test/dq_pur_condenser_collects_the_vapour

/datum/unit_test/dq_pur_condenser_collects_the_vapour/Run()
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_powered(TRUE)
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, test_floor())
	C.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/flask = dq_pur_beaker()
	flask.reagents.add_reagent(REAGENT_ID_WATER, 40, safety = 1)
	flask.reagents.add_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 4, safety = 1)
	var/obj/item/reagent_containers/glass/beaker/receiver = dq_pur_beaker()
	move_into(P, nameof(P.held_container), flask)
	move_into(C, nameof(C.held_container), receiver)
	dq_pur_set_temp(flask, 112)
	P.set_dial(T0C + 120)
	P.switch_element(null, TRUE)
	for(var/second in 1 to 10)
		P.heat_step(1)
	var/distillate = receiver.reagents.get_reagent_amount(REAGENT_ID_WATER)
	TEST_ASSERT(distillate > 1, "the condenser collected the boiled water ([distillate]u)")
	TEST_ASSERT(dq_pur_near(distillate + flask.reagents.get_reagent_amount(REAGENT_ID_WATER), 40, 0.05), "every unit that left the flask is in the receiver")
	TEST_ASSERT_EQUAL(receiver.reagents.contaminant_volume(), 0, "the heavy metals stayed behind: the distillate is pure")
	TEST_ASSERT(dq_pur_near(flask.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 4), "in the flask")
	TEST_ASSERT_EQUAL(receiver.reagents.grade(), GRADE_REAGENT, "Reagent grade distillate from a Crude-ish flask")

/// A condenser without power takes nothing, and neither does one with no container.
/datum/unit_test/dq_pur_condenser_needs_power_and_a_container

/datum/unit_test/dq_pur_condenser_needs_power_and_a_container/Run()
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, test_floor())
	var/list/vapour = list(REAGENT_ID_WATER = list(5, null))
	C.set_powered(TRUE)
	TEST_ASSERT(!C.collect(vapour), "with no container there is nothing to collect into")
	var/obj/item/reagent_containers/glass/beaker/receiver = dq_pur_beaker()
	move_into(C, nameof(C.held_container), receiver)
	C.set_powered(FALSE)
	TEST_ASSERT(!C.collect(vapour), "unpowered it collects nothing")
	TEST_ASSERT_EQUAL(receiver.reagents.total_volume, 0, "the receiver is empty")
	C.set_powered(TRUE)
	TEST_ASSERT(C.collect(vapour), "powered it does")
	TEST_ASSERT(dq_pur_near(receiver.reagents.get_reagent_amount(REAGENT_ID_WATER), 5), "5u of water")

// ---- funnel and filters ----

/// The funnel and the filter go where the ops put them, through real clicks.
/datum/unit_test/dq_p2_reagents/dq_pur_funnel_and_filter_ops

/datum/unit_test/dq_p2_reagents/dq_pur_funnel_and_filter_ops/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	var/obj/item/chem_funnel/F = allocate(/obj/item/chem_funnel, run_loc_floor_bottom_left)
	var/obj/item/chem_filter/paper/P = allocate(/obj/item/chem_filter/paper, run_loc_floor_bottom_left)
	rc_click(H, F, P)
	TEST_ASSERT_EQUAL(F.filter, P, "a filter clicked onto the funnel goes in it")
	rc_click(H, B, F)
	TEST_ASSERT_EQUAL(B.funnel, F, "the funnel clicked onto a beaker fits on it")
	TEST_ASSERT_EQUAL(B.funnel_filter(), P, "and the beaker pours through the paper")
	var/obj/item/chem_funnel/F2 = allocate(/obj/item/chem_funnel, run_loc_floor_bottom_left)
	rc_click(H, B, F2)
	TEST_ASSERT_EQUAL(B.funnel, F, "a second funnel is not taken")
	// The funnel comes off with its filter, and the beaker pours straight again.
	var/datum/act/op/stub = new
	stub.actor = H
	B.funnel_removed(stub)
	TEST_ASSERT_NULL(B.funnel, "the funnel is off")
	TEST_ASSERT_NULL(B.funnel_filter(), "and the beaker is unfiltered")

/// Without a funnel nothing is filtered; with one and no filter nothing is either.
/datum/unit_test/dq_pur_no_filter_no_filtering

/datum/unit_test/dq_pur_no_filter_no_filtering/Run()
	var/obj/item/reagent_containers/glass/beaker/bluespace/source = dq_pur_dirty_source()
	var/obj/item/reagent_containers/glass/beaker/bluespace/plain = dq_pur_beaker(/obj/item/reagent_containers/glass/beaker/bluespace)
	source.reagents.trans_to_holder(plain.reagents, 1000)
	TEST_ASSERT(dq_pur_near(plain.reagents.contaminant_volume(), 35), "an unfunnelled pour carries every contaminant (35u)")
	var/obj/item/reagent_containers/glass/beaker/bluespace/empty_funnel = dq_pur_funnelled_beaker(null)
	var/obj/item/reagent_containers/glass/beaker/bluespace/source2 = dq_pur_dirty_source()
	source2.reagents.trans_to_holder(empty_funnel.reagents, 1000)
	TEST_ASSERT(dq_pur_near(empty_funnel.reagents.contaminant_volume(), 35), "a funnel with no filter carries every contaminant too")

/datum/unit_test/dq_pur_paper_filter_takes_the_particulate

/datum/unit_test/dq_pur_paper_filter_takes_the_particulate/Run()
	var/obj/item/chem_filter/paper/F = allocate(/obj/item/chem_filter/paper, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/target = dq_pur_funnelled_beaker(F)
	var/obj/item/reagent_containers/glass/beaker/bluespace/source = dq_pur_dirty_source()
	source.reagents.trans_to_holder(target.reagents, 1000)
	TEST_ASSERT(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER) < 1, "the paper took most of the particulate ([target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER)]u of 5)")
	for(var/id in list(REAGENT_ID_CONTAMINANT_OILY_RESIDUE, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, REAGENT_ID_CONTAMINANT_HEAVY_METAL, REAGENT_ID_CONTAMINANT_SULFUR, REAGENT_ID_CONTAMINANT_REACTIVE, REAGENT_ID_CONTAMINANT_BIOLOGICAL))
		TEST_ASSERT(dq_pur_near(target.reagents.get_reagent_amount(id), 5), "paper takes no [id]")
	var/stock = target.reagents.get_reagent_amount(REAGENT_ID_DEXALIN)
	TEST_ASSERT(stock < 50 && stock > 48, "a little of the product stayed in the paper ([stock]u of 50)")
	TEST_ASSERT(F.used > 0 && F.freshness() < 1, "and the filter is used")

/datum/unit_test/dq_pur_charcoal_filter_takes_oils_and_residue

/datum/unit_test/dq_pur_charcoal_filter_takes_oils_and_residue/Run()
	var/obj/item/chem_filter/charcoal/F = allocate(/obj/item/chem_filter/charcoal, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/target = dq_pur_funnelled_beaker(F)
	var/obj/item/reagent_containers/glass/beaker/bluespace/source = dq_pur_dirty_source()
	var/dirty_purity = source.reagents.purity()
	source.reagents.trans_to_holder(target.reagents, 1000)
	TEST_ASSERT(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_OILY_RESIDUE) < 1, "oily residue is mostly gone")
	TEST_ASSERT(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE) < 1.5, "and organic residue")
	TEST_ASSERT(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_BIOLOGICAL) < 1.5, "and endotoxin, which is organic too")
	for(var/id in list(REAGENT_ID_CONTAMINANT_INERT_FILLER, REAGENT_ID_CONTAMINANT_HEAVY_METAL, REAGENT_ID_CONTAMINANT_SULFUR, REAGENT_ID_CONTAMINANT_REACTIVE))
		TEST_ASSERT(dq_pur_near(target.reagents.get_reagent_amount(id), 5), "charcoal takes no [id]")
	TEST_ASSERT(target.reagents.purity() > dirty_purity, "the mixture is purer than it was")

/// A filter has a capacity: it works less as it fills and a full one passes everything.
/datum/unit_test/dq_pur_filters_saturate

/datum/unit_test/dq_pur_filters_saturate/Run()
	var/obj/item/chem_filter/paper/F = allocate(/obj/item/chem_filter/paper, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/target = dq_pur_funnelled_beaker(F)
	TEST_ASSERT(dq_pur_near(F.freshness(), 1), "fresh")
	var/obj/item/reagent_containers/glass/beaker/bluespace/first = dq_pur_dirty_source(50, 5)
	first.reagents.trans_to_holder(target.reagents, 1000)
	var/caught_fresh = 5 - target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER)
	F.used = F.capacity / 2
	var/before = target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER)
	var/obj/item/reagent_containers/glass/beaker/bluespace/second = dq_pur_dirty_source(50, 5)
	second.reagents.trans_to_holder(target.reagents, 1000)
	var/caught_half = 5 - (target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER) - before)
	TEST_ASSERT(caught_half < caught_fresh * 0.75, "half full it takes less ([caught_half]u against [caught_fresh]u fresh)")
	F.used = F.capacity
	TEST_ASSERT(dq_pur_near(F.freshness(), 0), "full")
	before = target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER)
	var/stock_before = target.reagents.get_reagent_amount(REAGENT_ID_DEXALIN)
	var/obj/item/reagent_containers/glass/beaker/bluespace/third = dq_pur_dirty_source(50, 5)
	third.reagents.trans_to_holder(target.reagents, 1000)
	TEST_ASSERT(dq_pur_near(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER) - before, 5), "a full filter passes all 5u of the particulate")
	TEST_ASSERT(dq_pur_near(target.reagents.get_reagent_amount(REAGENT_ID_DEXALIN) - stock_before, 50), "and keeps none of the product")

/// The sorbent filter: sorption takes heavy metals, oils and sulfur; catalytic activity reactive impurity and sulfur; antimicrobial activity endotoxin; and
/// the better the stat the more it takes.
/datum/unit_test/dq_pur_sorbent_filter_follows_the_material

/datum/unit_test/dq_pur_sorbent_filter_follows_the_material/Run()
	dq_pur_material("dq_pur_sponge", porosity = 25)
	dq_pur_material("dq_pur_half_sponge", porosity = 12.5)
	dq_pur_material("dq_pur_catalyst", catalysis = 100)
	dq_pur_material("dq_pur_silver", antimicrobial = 100)
	dq_pur_material("dq_pur_bare")
	var/list/left = list()
	for(var/name in list("dq_pur_sponge", "dq_pur_half_sponge", "dq_pur_catalyst", "dq_pur_silver", "dq_pur_bare"))
		var/obj/item/chem_filter/sorbent/F = allocate(/obj/item/chem_filter/sorbent, test_floor(), name)
		var/obj/item/reagent_containers/glass/beaker/bluespace/target = dq_pur_funnelled_beaker(F)
		var/obj/item/reagent_containers/glass/beaker/bluespace/source = dq_pur_dirty_source()
		source.reagents.trans_to_holder(target.reagents, 1000)
		var/list/amounts = list()
		for(var/id in dq_pur_classes())
			amounts[id] = target.reagents.get_reagent_amount(id)
		left[name] = amounts
	dq_pur_forget_material("dq_pur_sponge")
	dq_pur_forget_material("dq_pur_half_sponge")
	dq_pur_forget_material("dq_pur_catalyst")
	dq_pur_forget_material("dq_pur_silver")
	dq_pur_forget_material("dq_pur_bare")
	var/list/sponge = left["dq_pur_sponge"]
	var/list/half = left["dq_pur_half_sponge"]
	var/list/catalyst = left["dq_pur_catalyst"]
	var/list/silver = left["dq_pur_silver"]
	var/list/bare = left["dq_pur_bare"]
	for(var/id in dq_pur_classes())
		TEST_ASSERT(dq_pur_near(bare[id], 5), "a filter of a material with no stats takes no [id]")
	// Sorption: heavy metals, oils, sulfur.
	for(var/id in list(REAGENT_ID_CONTAMINANT_HEAVY_METAL, REAGENT_ID_CONTAMINANT_OILY_RESIDUE, REAGENT_ID_CONTAMINANT_SULFUR))
		TEST_ASSERT(sponge[id] < 1, "a sponge takes [id] ([sponge[id]]u left of 5)")
		TEST_ASSERT(half[id] > sponge[id] + 0.5 && half[id] < 5, "half the sorption takes less of [id] ([half[id]] against [sponge[id]])")
	for(var/id in list(REAGENT_ID_CONTAMINANT_BIOLOGICAL, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, REAGENT_ID_CONTAMINANT_INERT_FILLER))
		TEST_ASSERT(dq_pur_near(sponge[id], 5), "a sponge does not take [id]")
	TEST_ASSERT(sponge[REAGENT_ID_CONTAMINANT_REACTIVE] < 1, "but being ion exchange it takes the ionic reactive impurity")
	// Catalytic activity: reactive impurity and sulfur.
	TEST_ASSERT(catalyst[REAGENT_ID_CONTAMINANT_REACTIVE] < 1, "a catalytic filter takes the reactive impurity")
	TEST_ASSERT(catalyst[REAGENT_ID_CONTAMINANT_SULFUR] < 1, "and sulfur")
	TEST_ASSERT(dq_pur_near(catalyst[REAGENT_ID_CONTAMINANT_HEAVY_METAL], 5), "but not heavy metals")
	// Antimicrobial activity: endotoxin.
	TEST_ASSERT(silver[REAGENT_ID_CONTAMINANT_BIOLOGICAL] < 1, "an antimicrobial filter takes endotoxin")
	TEST_ASSERT(dq_pur_near(silver[REAGENT_ID_CONTAMINANT_REACTIVE], 5), "and not the reactive impurity")

/// A paper filter lined with a sheet makes a sorbent filter of the sheet's material, through the click.
/datum/unit_test/dq_p2_reagents/dq_pur_sorbent_filter_made_from_a_sheet

/datum/unit_test/dq_p2_reagents/dq_pur_sorbent_filter_made_from_a_sheet/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/chem_filter/paper/P = allocate(/obj/item/chem_filter/paper, run_loc_floor_bottom_left)
	var/obj/item/stack/material/exotic_feedstock/sheets = allocate(/obj/item/stack/material/exotic_feedstock, run_loc_floor_bottom_left)
	sheets.set_stack_material(MAT_RIFT_GLASS)
	sheets.set_amount(2)
	rc_click(H, P, sheets)
	TEST_ASSERT_EQUAL(sheets.get_amount(), 1, "the filter used one sheet")
	TEST_ASSERT(QDELETED(P), "the paper blank is used up")
	var/obj/item/chem_filter/sorbent/made = locate() in H
	if(!made)
		made = locate() in run_loc_floor_bottom_left
	TEST_ASSERT_NOTNULL(made, "a sorbent filter was made")
	TEST_ASSERT_EQUAL(made.material_name, sheets.material.name, "of the sheet's material")
	TEST_ASSERT(made.sorption() > 0.5, "with the rift glass's sorption")
	TEST_ASSERT(made.capacity > 40, "and a capacity that grows with it")
	rc_extra = list(made)

// ---- neutralisation ----

/datum/unit_test/dq_pur_neutralisation

/datum/unit_test/dq_pur_neutralisation/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_pur_beaker()
	B.reagents.add_reagent(REAGENT_ID_DEXALIN, 30, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE, 4, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_LYE, 4, safety = 1)
	B.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ACID_RESIDUE), 0), "the acid residue is neutralised")
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_LYE), 0), "the lye is spent")
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 4), "into salts")
	TEST_ASSERT(dq_pur_near(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 4), "and water")
	var/obj/item/reagent_containers/glass/beaker/too_little = dq_pur_beaker()
	too_little.reagents.add_reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE, 6, safety = 1)
	too_little.reagents.add_reagent(REAGENT_ID_AMMONIA, 2, safety = 1)
	too_little.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(too_little.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ACID_RESIDUE), 4), "2u of ammonia neutralises 2u of acid residue and leaves 4u")
	var/obj/item/reagent_containers/glass/beaker/base = dq_pur_beaker()
	base.reagents.add_reagent(REAGENT_ID_DEXALIN, 30, safety = 1)
	base.reagents.add_reagent(REAGENT_ID_CONTAMINANT_BASE_RESIDUE, 3, safety = 1)
	base.reagents.add_reagent(REAGENT_ID_SACID, 3, safety = 1)
	base.reagents.handle_reactions()
	TEST_ASSERT(dq_pur_near(base.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_BASE_RESIDUE), 0), "base residue is neutralised by an acid")
	TEST_ASSERT(dq_pur_near(base.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 3), "into salts")
	TEST_ASSERT(dq_pur_near(base.reagents.get_reagent_amount(REAGENT_ID_WATER), 3), "and water")
	// The reactive residue is gone: the mixture no longer burns.
	TEST_ASSERT_EQUAL(base.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_BASE_RESIDUE), 0, "nothing reactive is left")

// ---- the loopholes ----

/// Drawing a reagent out of a mixture carries its share of the contaminants; a contaminant is never drawn on its own.
/datum/unit_test/dq_pur_picking_a_reagent_carries_the_contaminants

/datum/unit_test/dq_pur_picking_a_reagent_carries_the_contaminants/Run()
	var/obj/item/reagent_containers/glass/beaker/bluespace/source = dq_pur_dirty_source(40, 4)
	var/obj/item/reagent_containers/glass/beaker/bluespace/target = dq_pur_beaker(/obj/item/reagent_containers/glass/beaker/bluespace)
	var/purity = source.reagents.purity()
	var/moved = source.reagents.trans_id_to(target, REAGENT_ID_DEXALIN, 20)
	TEST_ASSERT(moved > 0, "the stock moved")
	TEST_ASSERT(dq_pur_near(target.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 20), "20u of it")
	TEST_ASSERT(dq_pur_near(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2), "with half the heavy metals (half of the stock moved)")
	TEST_ASSERT(dq_pur_near(target.reagents.purity(), purity, 0.001), "so picking a reagent by id did not purify it")
	TEST_ASSERT(dq_pur_near(source.reagents.purity(), purity, 0.001), "nor dirty what stayed")
	// A contaminant cannot be separated out.
	var/before = source.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS)
	TEST_ASSERT_NULL(source.reagents.trans_id_to(target, REAGENT_ID_CONTAMINANT_HEAVY_METAL, 2), "trans_id_to refuses a contaminant")
	TEST_ASSERT_NULL(source.reagents.trans_type_to(target, REAGENT_ID_CONTAMINANT_HEAVY_METAL, 2), "and so does trans_type_to")
	TEST_ASSERT(dq_pur_near(source.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2), "nothing left the mixture")
	TEST_ASSERT(dq_pur_near(source.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), before), "not even a trace")
	// Isolating a reagent keeps the contaminants (and cannot isolate one).
	var/obj/item/reagent_containers/glass/beaker/bluespace/mixed = dq_pur_dirty_source(40, 4)
	mixed.reagents.add_reagent(REAGENT_ID_ANTITOXIN, 10, safety = 1)
	var/contaminants = mixed.reagents.contaminant_volume()
	mixed.reagents.isolate_reagent(REAGENT_ID_DEXALIN)
	TEST_ASSERT(dq_pur_near(mixed.reagents.get_reagent_amount(REAGENT_ID_ANTITOXIN), 0), "isolating threw the other stock away")
	TEST_ASSERT(dq_pur_near(mixed.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 40), "kept the one asked for")
	TEST_ASSERT(dq_pur_near(mixed.reagents.contaminant_volume(), contaminants), "and every contaminant")
	mixed.reagents.isolate_reagent(REAGENT_ID_CONTAMINANT_SALTS)
	TEST_ASSERT(dq_pur_near(mixed.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 40), "isolating a contaminant does nothing")

/// The chem master and the dispenser cannot discard or move a contaminant on its own, and what they move of a stock reagent carries its share.
/datum/unit_test/dq_pur_machines_cannot_strip_contaminants

/datum/unit_test/dq_pur_machines_cannot_strip_contaminants/Run()
	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/B = dq_pur_dirty_source(40, 4)
	move_into(M, nameof(M.beaker), B)
	var/datum/act/op/stub = new
	M.ui_act_add(stub, 10, REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	TEST_ASSERT_EQUAL(M.reagents.total_volume, 0, "the chem master will not load a contaminant by itself")
	M.ui_act_add(stub, 20, REAGENT_ID_DEXALIN)
	TEST_ASSERT(dq_pur_near(M.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 20), "it loads stock")
	TEST_ASSERT(dq_pur_near(M.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2), "with the contaminants that go with it")
	var/volume = M.reagents.total_volume
	M.ui_act_remove(stub, 1, REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	TEST_ASSERT(dq_pur_near(M.reagents.total_volume, volume), "it will not discard one either")
	M.ui_act_remove(stub, 1, REAGENT_ID_CONTAMINANT_SULFUR)
	TEST_ASSERT(dq_pur_near(M.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SULFUR), 2), "the buffer still holds all its sulfur")
	// The dispenser.
	var/obj/machinery/chemical_dispenser/ert/D = allocate(/obj/machinery/chemical_dispenser/ert, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/vessel = dq_pur_dirty_source(40, 4)
	move_into(D, nameof(D.container), vessel)
	D.ui_act_remove(stub, 4, REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	TEST_ASSERT(dq_pur_near(vessel.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 4), "the dispenser will not remove a contaminant")
	D.ui_act_remove(stub, -1, REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	TEST_ASSERT(dq_pur_near(vessel.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 40), "and isolating a contaminant does nothing")
	D.ui_act_remove(stub, -1, REAGENT_ID_DEXALIN)
	TEST_ASSERT(dq_pur_near(vessel.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SULFUR), 4), "isolating the stock keeps the contaminants")
	TEST_ASSERT(vessel.reagents.purity() < 0.9, "so it is still the same dirty mixture")

/// Refilling a cartridge from a pure supply is mixing: the contaminants stay, so the purity is the mixture's and never above what was poured in.
/datum/unit_test/dq_pur_refilling_a_cartridge_is_only_mixing

/datum/unit_test/dq_pur_refilling_a_cartridge_is_only_mixing/Run()
	var/obj/item/reagent_containers/chem_disp_cartridge/C = dq_contam_cartridge()
	var/purity = C.reagents.purity()
	C.reagents.remove_any(200)
	var/contaminants_left = C.reagents.contaminant_volume()
	var/obj/item/reagent_containers/glass/beaker/bluespace/canister = allocate(/obj/item/reagent_containers/glass/beaker/bluespace, test_floor())
	canister.reagents.add_reagent(REAGENT_ID_DEXALIN, 150, safety = 1)
	TEST_ASSERT_EQUAL(canister.reagents.purity(), 1, "the canister is pure")
	canister.reagents.trans_to_holder(C.reagents, 150)
	TEST_ASSERT(dq_pur_near(C.reagents.contaminant_volume(), contaminants_left, 0.001), "pouring pure stock in removed no contaminant")
	TEST_ASSERT(C.reagents.purity() >= purity - 0.001, "the mixture is as pure as pouring in 150u of pure stock makes it")
	TEST_ASSERT(C.reagents.purity() <= 1, "and no purer than the canister")
	// Taking it out through the dispenser path and putting it back is the same mixture.
	var/datum/reagents/H = new /datum/reagents(1000)
	C.dispense_to_holder(H, 50)
	TEST_ASSERT(dq_pur_near(H.purity(), C.reagents.purity(), 0.01), "what a cartridge dispenses has the purity of what is in it")

// ---- the book ----

/datum/unit_test/dq_pur_book_lists_the_methods

/datum/unit_test/dq_pur_book_lists_the_methods/Run()
	var/obj/item/book/dq_medical_reference/book = allocate(/obj/item/book/dq_medical_reference)
	var/list/purity = book._dq_book_purity()
	TEST_ASSERT(length(purity["methods"]) >= 5, "the book lists the methods")
	TEST_ASSERT_EQUAL(length(purity["temperature_classes"]), length(GLOB.reaction_temperature_classes), "every temperature class")
	var/found_acid = FALSE
	for(var/list/row in purity["recipe_temperatures"])
		TEST_ASSERT(row["ideal_low"] < row["ideal_high"], "[row["name"]] has a band")
		if(row["id"] == REAGENT_ID_PACID)
			found_acid = TRUE
			TEST_ASSERT(row["ideal_low"] > 40, "and polytrinic acid wants a hot plate")
	TEST_ASSERT(found_acid, "the recipes that need heat are listed")
	var/found_water = FALSE
	var/found_metal = FALSE
	for(var/list/row in purity["boiling_points"])
		if(row["id"] == REAGENT_ID_WATER)
			found_water = TRUE
			TEST_ASSERT(dq_pur_near(row["celsius"], 100, 0.2), "water is 100 C")
		if(row["id"] == REAGENT_ID_CONTAMINANT_HEAVY_METAL)
			found_metal = TRUE
			TEST_ASSERT(row["never"], "heavy metals never boil")
	TEST_ASSERT(found_water && found_metal, "boiling points are listed")

#endif

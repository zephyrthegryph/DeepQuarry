// A declared (instant) recipe wins a reactant it shares with a generated route, so one whose inputs are a subset of a route's inputs and catalysts would stand in
// that route's way: the nitrating mix once ate the sulphuric acid of every dissolved-acid nitration, the caustic digest the lye of every dissolved-base
// hydrolysis, space cleaner the ammonia of the bicaridine chain. The check builds each route's own beaker at its ideal band and asks the settle what holds.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// What stands in the way of `R` in a beaker holding exactly what it takes (and its catalysts), a few times over, at the middle of its ideal band: null when no declared
/// recipe holds there and none fires in the settle, else a line naming the recipe or what the beaker holds.
/datum/unit_test/proc/dq_chem_hijack_of(datum/chem_route/R)
	var/celsius = dq_chem_ideal_celsius(R)
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker(celsius)
	for(var/take_id in R.takes)
		B.reagents.add_reagent(take_id, R.takes[take_id] * 4, safety = 1)
	for(var/catalyst_id in R.catalysts)
		B.reagents.add_reagent(catalyst_id, R.catalysts[catalyst_id] * 4, safety = 1)
	var/list/lookup = xform_bucket_table(MEDIUM_REAGENTS, REGIME_INSTANT)
	var/list/eligible = list()
	for(var/datum/reagent/held as anything in B.reagents.reagent_list)
		if(lookup[held.id])
			eligible |= lookup[held.id]
	var/result
	for(var/datum/xform/X as anything in eligible)
		if(!X.route_id && xform_matches(X, B.reagents))
			result = "[R.id] at [round(celsius)] C is stood in the way of by the recipe [X.rule_type]"
			break
	qdel(B)
	if(result)
		return result
	// And the real settle: a declared recipe that fires there took what the route needed.
	var/obj/item/reagent_containers/glass/beaker/settled = dq_blk_beaker(celsius)
	for(var/take_id in R.takes)
		settled.reagents.add_reagent(take_id, R.takes[take_id] * 4, safety = 1)
	for(var/catalyst_id in R.catalysts)
		settled.reagents.add_reagent(catalyst_id, R.catalysts[catalyst_id] * 4, safety = 1)
	for(var/datum/xform/X as anything in xform_settle_reagents(settled.reagents))
		if(!X.route_id)
			result = "[R.id] at [round(celsius)] C: the recipe [X.rule_type] fired in the settle"
			break
	qdel(settled)
	return result

/// Every route that makes a chemical, in a beaker holding exactly its inputs at its ideal band, meets no declared recipe and none fires in the settle.
/datum/unit_test/dq_chem_no_recipe_hijacks_sweep
	tier = TEST_TIER_EXHAUSTIVE
	is_sweep_test = TRUE

/// The routes this run checks.
/datum/unit_test/dq_chem_no_recipe_hijacks_sweep/proc/routes_to_check()
	return dq_chem_plain_product_routes()

/datum/unit_test/dq_chem_no_recipe_hijacks_sweep/Run()
	var/list/failures = list()
	var/ran = 0
	for(var/datum/chem_route/R as anything in routes_to_check())
		ran++
		var/failure = dq_chem_hijack_of(R)
		if(failure)
			failures += failure
	log_world("CHEM TEST: hijack check ran [ran] routes, [length(failures)] stood in the way of: [jointext(failures, "\n")]")
	TEST_ASSERT(ran > 40, "routes were run ([ran])")
	TEST_ASSERT(!length(failures), "[length(failures)] route(s) are stood in the way of by an instant recipe: [jointext(failures.Copy(1, min(length(failures), 12) + 1), " || ")]")

/// Normal tier: the routes of the families the hijacks were found in (nitration, hydrolysis, ammonia, fluorine, salicylic acid) and a thin slice of the rest.
/datum/unit_test/dq_chem_no_recipe_hijacks_sweep/representative
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_chem_no_recipe_hijacks_sweep/representative/routes_to_check()
	var/list/found = list()
	var/seen = 0
	for(var/datum/chem_route/R as anything in dq_chem_plain_product_routes())
		if(!findtext(R.id, "salicyl") && !findtext(R.id, "nitrate:") && !findtext(R.id, "hydrolyse:") && !findtext(R.id, "ammonia") && !findtext(R.id, "fluorine") && (++seen % 25))
			continue
		found += R
	return found

/// The declared reagent rule with this id, or null.
/datum/unit_test/proc/dq_chem_declared_rule(rule_id)
	for(var/datum/xform/X as anything in GLOB.xform_rules)
		if(X.medium == MEDIUM_REAGENTS && !X.route_id && X.id == rule_id)
			return X
	return null

/// A recipe never makes more than it takes: the virus food and its colonies, the distilled hydrogen and the biomass once multiplied what went in.
/datum/unit_test/dq_chem_recipes_do_not_create_mass

/datum/unit_test/dq_chem_recipes_do_not_create_mass/Run()
	var/checked = 0
	for(var/rule_id in list(REAGENT_ID_VIRUSFOOD, REAGENT_ID_MEATCOLONY, REAGENT_ID_PLANTCOLONY, "distill_hydrogen", "distill_oxygen", "distill_biomass"))
		var/datum/xform/X = dq_chem_declared_rule(rule_id)
		if(!X)
			continue
		var/took = 0
		for(var/take_id in X.reagent_takes)
			took += X.reagent_takes[take_id]
		var/made = X.result_amount
		for(var/list/byproduct as anything in X.byproducts)
			made += byproduct[2]
		TEST_ASSERT(made <= took + 0.001, "[rule_id] makes [made]u from [took]u")
		checked++
	TEST_ASSERT(checked >= 5, "the recipes were found ([checked])")

/// No route takes lye apart: the instant recipe composes it from sodium, hydrogen and oxygen at three units for three, so a route that decomposes one lye into
/// more units grows it without bound (sodium and oxygen from lye, then lye from them and a little hydrogen).
/datum/unit_test/dq_chem_no_electrolysis_loop_grows_lye

/datum/unit_test/dq_chem_no_electrolysis_loop_grows_lye/Run()
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		if(R.process_id != CHEM_PROCESS_ELECTROLYSE)
			continue
		TEST_ASSERT(!(REAGENT_ID_LYE in R.takes), "[route_id] takes lye apart")

/// A product with a generated route has no hand-written recipe of its own beside it (peridaxon once made twelve from four on top of its three routes).
/datum/unit_test/dq_chem_routed_products_have_no_hand_recipe

/datum/unit_test/dq_chem_routed_products_have_no_hand_recipe/Run()
	for(var/product_id in list(REAGENT_ID_PERIDAXON))
		var/routed = 0
		for(var/route_id in GLOB.chem_routes)
			var/datum/chem_route/R = GLOB.chem_routes[route_id]
			if(R.matched && (product_id in R.products))
				routed++
		TEST_ASSERT(routed > 0, "[product_id] has a generated route")
		for(var/datum/xform/X as anything in GLOB.xform_rules)
			TEST_ASSERT(!(X.medium == MEDIUM_REAGENTS && !X.route_id && X.result == product_id), "[product_id] is also made by the hand recipe [X.rule_type]")

#endif

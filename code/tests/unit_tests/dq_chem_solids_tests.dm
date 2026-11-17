// Solids in a beaker (code/content/reagents/purification/solids.dm): any small item goes in, dissolves when the liquid can dissolve it, or works as a solid catalyst.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A small item whose material the test sets.
/obj/item/dq_solid_probe
	name = "probe"
	w_class = ITEMSIZE_SMALL

/// A probe made of the materials in the list (material name => share of a sheet).
/datum/unit_test/dq_p2_reagents/proc/solids_probe(list/mix)
	var/obj/item/dq_solid_probe/probe = allocate(/obj/item/dq_solid_probe, run_loc_floor_bottom_left)
	var/list/amounts = list()
	for(var/name in mix)
		amounts[name] = SHEET_MATERIAL_AMOUNT * mix[name]
	probe.set_material_mix(amounts)
	return probe

/// A beaker that does not react by itself (so what dissolves can be read), holding `water` units of water.
/datum/unit_test/dq_p2_reagents/proc/solids_beaker(water = 0)
	var/obj/item/reagent_containers/glass/beaker/noreact/B = allocate(/obj/item/reagent_containers/glass/beaker/noreact, run_loc_floor_bottom_left)
	if(water > 0)
		B.reagents.add_reagent(REAGENT_ID_WATER, water, safety = 1)
	return B

/// Soap in water dissolves over time into its feedstock, and takes the solid out of the glass.
/datum/unit_test/dq_p2_reagents/solids_soap_dissolves_in_water_over_time

/datum/unit_test/dq_p2_reagents/solids_soap_dissolves_in_water_over_time/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/noreact/B = solids_beaker(30)
	var/obj/item/soap/soap = allocate(/obj/item/soap, run_loc_floor_bottom_left)
	var/list/feed = solid_feedstock(soap)
	TEST_ASSERT(length(feed) > 0, "soap has a feedstock")
	rc_click(H, B, soap)
	TEST_ASSERT_EQUAL(length(B.solids), 1, "the soap went into the beaker")
	TEST_ASSERT(B.solid_dissolving(soap), "water dissolves it")
	B.solids_step(10)
	var/progress = B.solid_progress(soap)
	TEST_ASSERT(progress > 0 && progress < 1, "ten seconds in it is part way ([progress])")
	TEST_ASSERT(!QDELETED(soap) && length(B.solids), "and still there")
	B.solids_step(CHEM_SOLID_STEP_MAX)
	B.solids_step(CHEM_SOLID_STEP_MAX)
	TEST_ASSERT(QDELETED(soap), "a minute on it is gone")
	TEST_ASSERT_EQUAL(length(B.solids), 0, "from the glass")
	var/total = 0
	for(var/id in feed)
		TEST_ASSERT(abs(B.reagents.get_reagent_amount(id) - feed[id]) < 0.01, "[id] came out as the grinder makes it")
		total += feed[id]
	TEST_ASSERT(abs(B.reagents.total_volume - (30 + total)) < 0.1, "the glass holds the water and the feedstock, no more")

/// A steel item does not dissolve in water but does in an acid, which it uses up some of; hot dissolves it faster.
/datum/unit_test/dq_p2_reagents/solids_steel_needs_an_acid

/datum/unit_test/dq_p2_reagents/solids_steel_needs_an_acid/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/noreact/B = solids_beaker(20)
	var/obj/item/dq_solid_probe/steel = solids_probe(list(MAT_STEEL = 1))
	rc_click(H, B, steel)
	TEST_ASSERT_EQUAL(length(B.solids), 1, "the steel item went in")
	TEST_ASSERT(!B.solid_dissolving(steel), "water does not dissolve it")
	B.solids_step(CHEM_SOLID_STEP_MAX)
	B.solids_step(CHEM_SOLID_STEP_MAX)
	B.solids_step(CHEM_SOLID_STEP_MAX)
	TEST_ASSERT(!QDELETED(steel) && length(B.solids), "it is still whole after minutes in water")
	B.reagents.add_reagent(REAGENT_ID_SACID, 20, safety = 1)
	TEST_ASSERT(B.solid_dissolving(steel), "an acid does")
	B.solids_step(10)
	var/slow = B.solid_progress(steel)
	TEST_ASSERT(slow > 0 && slow < 1, "part way after ten seconds ([slow])")
	B.solids_step(CHEM_SOLID_STEP_MAX)
	B.solids_step(CHEM_SOLID_STEP_MAX)
	B.solids_step(CHEM_SOLID_STEP_MAX)
	TEST_ASSERT(QDELETED(steel), "and gone after a while")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_IRON) > 0, "into iron")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_SACID) < 20, "using up some of the acid")
	// The heat speeds it up: the same item at 80 C is further along after two seconds against its ten.
	var/obj/item/reagent_containers/glass/beaker/noreact/hot = solids_beaker(0)
	hot.reagents.add_reagent(REAGENT_ID_SACID, 20, safety = 1)
	var/obj/item/dq_solid_probe/other = solids_probe(list(MAT_STEEL = 1))
	TEST_ASSERT(move_into(hot, nameof(hot.solids), other), "a second steel item went into the hot beaker")
	hot.inherit_heat(T0C + 80)
	hot.solids_step(2)
	TEST_ASSERT(hot.solid_progress(other) > slow, "hot acid works faster")

/// A solid that does not dissolve, made of a catalytic material, is the catalyst; the item need not be a sheet. Its activity is weighted by the share it is of the item.
/datum/unit_test/dq_p2_reagents/solids_a_catalytic_item_catalyses_a_route

/datum/unit_test/dq_p2_reagents/solids_a_catalytic_item_catalyses_a_route/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, run_loc_floor_bottom_left)
	B.reagents.add_reagent(REAGENT_ID_ETHANOL, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_OXYGEN, 10, safety = 1)
	B.inherit_heat(T0C + 40)
	var/datum/chem_route/route = GLOB.chem_routes["oxidise:ethanol:solid_metal>contaminant_organic_residue"]
	var/datum/xform/X = dq_route_rule(route)
	TEST_ASSERT(!xform_matches(X, B.reagents), "with nothing in the glass the route does not hold")
	TEST_ASSERT_NULL(B.reagents.solid_catalyst(), "there is no solid catalyst")
	var/obj/item/dq_solid_probe/part = solids_probe(list(MAT_TUNGSTEN = 0.5, MAT_STEEL = 0.5))
	rc_click(H, B, part)
	TEST_ASSERT_EQUAL(length(B.solids), 1, "the part went in")
	TEST_ASSERT_EQUAL(B.catalyst_kind(), CHEM_CATALYST_SOLID_REFRACTORY, "its dominant catalytic material is tungsten")
	var/datum/material/tungsten = get_material_by_name(MAT_TUNGSTEN)
	TEST_ASSERT(abs(B.catalyst_activity() - tungsten.trait(MT_CATALYTIC) * 0.5) < 0.01, "half of it: half the activity ([B.catalyst_activity()])")
	TEST_ASSERT_NOTNULL(B.reagents.solid_catalyst(), "the mixture sees a solid catalyst")
	TEST_ASSERT(route.solid_runs(B.catalyst_kind()), "the route runs on that kind")
	var/list/lowered = route.band_in(B.reagents)
	TEST_ASSERT(abs((route.band_base[2] - lowered[2]) - B.reagents.solid_catalyst()[2] * CHEM_SOLID_REDUCTION_PER_POINT) < 0.01, "and its band came down by the activity")
	// The strongest of several works.
	var/obj/item/dq_solid_probe/whole = solids_probe(list(MAT_TUNGSTEN = 1))
	TEST_ASSERT(move_into(B, nameof(B.solids), whole), "a whole tungsten part went in too")
	TEST_ASSERT(abs(B.catalyst_activity() - tungsten.trait(MT_CATALYTIC)) < 0.01, "the strongest of them is the catalyst")

/// A tungsten sheet still works as it did: dropped in, it is the refractory catalyst, one sheet of the stack, and no acid dissolves it.
/datum/unit_test/dq_p2_reagents/solids_a_tungsten_sheet_still_works

/datum/unit_test/dq_p2_reagents/solids_a_tungsten_sheet_still_works/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, run_loc_floor_bottom_left)
	B.reagents.add_reagent(REAGENT_ID_SACID, 20, safety = 1)
	var/obj/item/stack/material/tungsten/sheets = allocate(/obj/item/stack/material/tungsten, run_loc_floor_bottom_left, 3)
	rc_click(H, B, sheets)
	TEST_ASSERT_EQUAL(sheets.get_amount(), 2, "one sheet of three went in")
	TEST_ASSERT_EQUAL(length(B.solids), 1, "as a solid")
	var/datum/material/tungsten = get_material_by_name(MAT_TUNGSTEN)
	TEST_ASSERT_EQUAL(B.catalyst_kind(), CHEM_CATALYST_SOLID_REFRACTORY, "a refractory catalyst")
	TEST_ASSERT(abs(B.catalyst_activity() - tungsten.trait(MT_CATALYTIC)) < 0.01, "of the material's activity")
	B.solids_step(CHEM_SOLID_STEP_MAX)
	TEST_ASSERT_EQUAL(length(B.solids), 1, "an acid does not dissolve it")

/// One take-out op returns every solid, whole.
/datum/unit_test/dq_p2_reagents/solids_take_out_returns_all_of_them

/datum/unit_test/dq_p2_reagents/solids_take_out_returns_all_of_them/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/noreact/B = solids_beaker(10)
	var/obj/item/soap/soap = allocate(/obj/item/soap, run_loc_floor_bottom_left)
	var/obj/item/dq_solid_probe/steel = solids_probe(list(MAT_STEEL = 1))
	var/obj/item/dq_solid_probe/tungsten = solids_probe(list(MAT_TUNGSTEN = 1))
	rc_click(H, B, soap)
	rc_click(H, B, steel)
	rc_click(H, B, tungsten)
	TEST_ASSERT_EQUAL(length(B.solids), 3, "three solids lie in it")
	var/obj/item/dq_solid_probe/fourth = solids_probe(list(MAT_STEEL = 1))
	rc_click(H, B, fourth)
	TEST_ASSERT_EQUAL(length(B.solids), 3, "a fourth does not fit")
	test_menu(H, B, "glass_purification.remove_solids")
	rc_settle()
	TEST_ASSERT_EQUAL(length(B.solids), 0, "the glass is empty of solids")
	TEST_ASSERT(!QDELETED(soap) && !QDELETED(steel) && !QDELETED(tungsten), "and all three came out whole")
	TEST_ASSERT(soap.loc == H || soap.loc == H.loc, "into the hands or at the feet of the person")

/// A reagent container is poured, never dropped in as a solid; a funnel is fitted.
/datum/unit_test/dq_p2_reagents/solids_a_reagent_container_is_still_poured

/datum/unit_test/dq_p2_reagents/solids_a_reagent_container_is_still_poured/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/target = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	var/obj/item/reagent_containers/glass/beaker/source = rc_filled(/obj/item/reagent_containers/glass/beaker, 20)
	rc_click(H, target, source)
	TEST_ASSERT_EQUAL(length(target.solids), 0, "a beaker is not a solid")
	TEST_ASSERT(target.reagents.total_volume > 0, "it was poured into the other")
	var/obj/item/chem_funnel/funnel = allocate(/obj/item/chem_funnel, run_loc_floor_bottom_left)
	rc_click(H, target, funnel)
	TEST_ASSERT_EQUAL(length(target.solids), 0, "a funnel is not a solid")
	TEST_ASSERT_EQUAL(target.funnel, funnel, "it is fitted")

#endif

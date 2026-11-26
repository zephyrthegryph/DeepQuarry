// Stage 4 of the chemistry and materials redesign (doc/rewrite/proposals/chemistry_redesign.md sections 9 and 10): feedstock from any item, rolled traces, one vocabulary for
// the traces of a melt and the contaminants of a beaker, ore refining to a floor, the polymers, tungsten as the refractory catalyst, the generic spray bottle.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// What a grinder puts in a large holder for `thing`: reagent id => units.
/proc/dq_feed_ground(obj/item/thing, turf/T)
	var/obj/box = new /obj(T)
	var/datum/reagents/R = new /datum/reagents(5000, box)
	box.reagents = R
	thing.forceMove(box)
	var/list/held = list(thing)
	grind_items_to_reagents(held, R)
	. = list()
	for(var/datum/reagent/part as anything in R.reagent_list)
		.[part.id] = part.volume
	qdel(box)

/// The units in a reagent list that are not contaminants.
/proc/dq_feed_stock_total(list/ground)
	. = 0
	for(var/id in ground)
		if(!contaminant_def(id))
			. += ground[id]

// ---- rolled traces ----

/// A source's roll is deterministic for the round seed and the lot, carries the signature always, and differs between lots and between rounds.
/datum/unit_test/dq_trace_rolls_are_per_round_and_per_lot
	boot_needs = list()

/datum/unit_test/dq_trace_rolls_are_per_round_and_per_lot/Run()
	var/old_seed = GLOB.round_seed
	rolls_fix_seed(4401)
	var/list/station = trace_roll(MAT_IRON)
	TEST_ASSERT_EQUAL(contaminants_text(station), contaminants_text(trace_roll(MAT_IRON)), "station stock is one roll for the round")
	TEST_ASSERT(station[REAGENT_ID_CONTAMINANT_SULFUR] >= 0.8 && station[REAGENT_ID_CONTAMINANT_SULFUR] <= 1.2, "iron always carries its signature, sulfur ([station[REAGENT_ID_CONTAMINANT_SULFUR]])")
	var/list/texts = list()
	for(var/lot_name in list("vein 1:2:3 hematite", "vein 1:5:9 hematite", "vein 2:0:0 hematite", "shipment 31", "shipment 32", "site a", "site b", "site c", "site d", "site e"))
		var/list/lot = trace_roll(MAT_IRON, TRACE_SCOPE_LOT, lot_name)
		TEST_ASSERT(lot[REAGENT_ID_CONTAMINANT_SULFUR] > 0, "[lot_name] carries the signature")
		TEST_ASSERT_EQUAL(contaminants_text(lot), contaminants_text(trace_roll(MAT_IRON, TRACE_SCOPE_LOT, lot_name)), "[lot_name] rolls the same every time")
		texts[contaminants_text(lot)] = TRUE
	TEST_ASSERT(length(texts) >= 4, "different lots carry different traces ([length(texts)] distinct of 10)")
	var/before = ""
	var/after = ""
	for(var/source_id in list(MAT_IRON, MAT_COPPER, MAT_LEAD, MAT_SILVER, MAT_TIN, MAT_TITANIUM))
		before += contaminants_text(trace_roll(source_id, TRACE_SCOPE_LOT, "vein 1:2:3"))
	rolls_fix_seed(4402)
	for(var/source_id in list(MAT_IRON, MAT_COPPER, MAT_LEAD, MAT_SILVER, MAT_TIN, MAT_TITANIUM))
		after += contaminants_text(trace_roll(source_id, TRACE_SCOPE_LOT, "vein 1:2:3"))
	TEST_ASSERT_NOTEQUAL(before, after, "a new round seed rolls new traces")
	rolls_fix_seed(old_seed)

/// Every extra shuts or taxes a route and never makes a chemical impossible: what a source can carry is only what the standard separations can bring down.
/datum/unit_test/dq_trace_pools_never_make_a_chemical_impossible
	boot_needs = list()

/datum/unit_test/dq_trace_pools_never_make_a_chemical_impossible/Run()
	TEST_ASSERT(length(GLOB.trace_sources) >= 15, "the sources are declared ([length(GLOB.trace_sources)])")
	TEST_ASSERT_NOTNULL(GLOB.trace_sources[TRACE_SOURCE_DEFAULT], "there is a default source")
	for(var/source_id in GLOB.trace_sources)
		var/datum/trace_source/source = GLOB.trace_sources[source_id]
		var/list/carried = list()
		for(var/id in source.signature)
			carried += id
		for(var/id in source.extras)
			carried += id
		for(var/id in carried)
			var/datum/reagent/contaminant/C = contaminant_def(id)
			TEST_ASSERT_NOTNULL(C, "[source_id] carries [id], a contaminant reagent")
			TEST_ASSERT(C.source_weight > 0, "[source_id] carries [id], which a source can carry (nothing that only a process makes)")
			TEST_ASSERT(C.filter_floor <= 0.02, "[source_id] carries [id], which a filter can take down to a trace")
			TEST_ASSERT(GLOB.trace_route_taxes[id], "[id] has its route tax written down, for the assay")
		TEST_ASSERT(source.extras_max <= max(length(source.extras), source.extras_max > 0 ? 1 : 0), "[source_id] never asks for more extras than its pool holds")

/// A trace of a melt and a contaminant of a beaker are one thing, both ways.
/datum/unit_test/dq_trace_vocabulary_is_one_both_ways
	boot_needs = list()

/datum/unit_test/dq_trace_vocabulary_is_one_both_ways/Run()
	var/mapped = 0
	for(var/trace_id in GLOB.material_traces)
		var/datum/material_trace/trace = GLOB.material_traces[trace_id]
		if(trace.contaminant)
			mapped++
			TEST_ASSERT_NOTNULL(contaminant_def(trace.contaminant), "[trace_id] is the contaminant [trace.contaminant]")
			TEST_ASSERT_EQUAL(material_trace_of_contaminant(trace.contaminant), trace_id, "[trace.contaminant] maps back to [trace_id]")
			TEST_ASSERT_EQUAL(contaminant_of_material_trace(trace_id), trace.contaminant, "[trace_id] maps to [trace.contaminant]")
		for(var/absorbed_id in trace.absorbs)
			TEST_ASSERT(contaminant_def(absorbed_id) || SSchemistry.ready().chemical_reagents[absorbed_id], "[trace_id] takes up [absorbed_id], a contaminant or a real reagent")
	TEST_ASSERT(mapped >= 8, "most traces are a contaminant of the chemistry ([mapped])")
	// The traces a stock material's source can roll all land in a melt: nothing a lot carries is lost on the way into the metal.
	for(var/source_id in GLOB.trace_sources)
		if(!get_material_by_name(source_id))
			continue
		var/datum/trace_source/source = GLOB.trace_sources[source_id]
		var/list/carried = list()
		for(var/id in source.signature)
			carried += id
		for(var/id in source.extras)
			carried += id
		for(var/id in carried)
			TEST_ASSERT(material_trace_of_contaminant(id) || melt_trace_of(id), "[source_id]'s [id] becomes something in a melt")

/// A reagent poured into a melt is a trace, a part of one, a vapour or slag: never an inert residue.
/datum/unit_test/dq_melt_reagents_become_traces
	boot_needs = list()

/datum/unit_test/dq_melt_reagents_become_traces/Run()
	var/list/melt = melt_trace_of(REAGENT_ID_SULFUR)
	TEST_ASSERT_EQUAL(melt[1], "sulfur", "sulfur is sulfur in a melt")
	melt = melt_trace_of(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	TEST_ASSERT_EQUAL(melt[1], "lead", "heavy metals are lead in a melt")
	melt = melt_trace_of(REAGENT_ID_CONTAMINANT_SULFUR)
	TEST_ASSERT_EQUAL(melt[1], "sulfur", "the contaminant sulfur is the trace sulfur")
	melt = melt_trace_of(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE)
	TEST_ASSERT_EQUAL(melt[1], "carbon", "organic residue is carbon in a melt")
	melt = melt_trace_of(REAGENT_ID_CONTAMINANT_OILY_RESIDUE)
	TEST_ASSERT_EQUAL(melt[1], "carbon", "oily residue chars to carbon")
	TEST_ASSERT(melt[2] > 0 && melt[2] < 1, "and part of it burns off")
	melt = melt_trace_of(REAGENT_ID_CONTAMINANT_PEROXIDE)
	TEST_ASSERT_EQUAL(melt[1], "oxygen", "peroxide is oxide inclusions")
	melt = melt_trace_of(REAGENT_ID_HYDROCHLORIC)
	TEST_ASSERT_EQUAL(melt[1], "hydrogen", "hydrochloric acid left in a beaker takes up as dissolved hydrogen")
	melt = melt_trace_of(REAGENT_ID_ETHANOL)
	TEST_ASSERT_EQUAL(melt[1], "carbon", "an organic chars to carbon")
	TEST_ASSERT_NULL(melt_trace_of(REAGENT_ID_WATER), "water is a vapour in a melt")
	melt = melt_trace_of(REAGENT_ID_SODAASH)
	TEST_ASSERT_EQUAL(melt[1], "slag", "what does not boil and is no trace is slag")
	var/datum/material_trace/slag = GLOB.material_traces["slag"]
	TEST_ASSERT(length(slag.effects), "and slag does something to the card")

/// Each refining step takes its traces down to a floor and no lower; a trace already below it is left; a step that is no refining one does nothing.
/datum/unit_test/dq_refining_takes_traces_to_a_floor
	boot_needs = list()

/datum/unit_test/dq_refining_takes_traces_to_a_floor/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 10)
	batch.add_substance("sulfur", 0.5, 0)
	batch.add_substance("oxygen", 0.4, 0)
	batch.add_substance("lead", 0.3, 0)
	batch.add_substance("slag", 0.2, 0)
	batch.add_substance("hydrogen", 0.2, 0)
	TEST_ASSERT(batch.refine_by_process(CHEM_PROCESS_OXIDISE) > 0, "a roast takes sulfur out")
	TEST_ASSERT(dq_feed_near(batch.composition["sulfur"], 0.015), "down to the roast's floor, not to nothing ([batch.composition["sulfur"]])")
	TEST_ASSERT(dq_feed_near(batch.composition["oxygen"], 0.4), "and leaves what it does not act on")
	batch.refine_by_process(CHEM_PROCESS_REDUCE)
	TEST_ASSERT(dq_feed_near(batch.composition["oxygen"], 0.012), "smelting takes the oxide down to its floor ([batch.composition["oxygen"]])")
	batch.refine_by_process(CHEM_PROCESS_DISPLACE)
	TEST_ASSERT(dq_feed_near(batch.composition["slag"], 0.01), "a flux skims the slag to its floor ([batch.composition["slag"]])")
	TEST_ASSERT(dq_feed_near(batch.composition["lead"], 0.3), "and leaves the lead")
	batch.refine_by_process(CHEM_PROCESS_ELECTROLYSE)
	TEST_ASSERT(dq_feed_near(batch.composition["lead"], 0.003), "electrorefining takes the lead down to its floor ([batch.composition["lead"]])")
	var/sulfur = batch.composition["sulfur"]
	batch.refine_by_process(CHEM_PROCESS_OXIDISE)
	TEST_ASSERT(dq_feed_near(batch.composition["sulfur"], sulfur), "a second roast takes nothing more")
	TEST_ASSERT(!batch.refine_by_process(CHEM_PROCESS_NEUTRALISE), "neutralising is no refining step")
	batch.strip_traces(FALSE)
	TEST_ASSERT(dq_feed_near(batch.composition["hydrogen"], 0.004), "a vacuum degasses the dissolved hydrogen to its floor ([batch.composition["hydrogen"]])")
	qdel(batch)

/proc/dq_feed_near(value, expected, tolerance = 0.0005)
	return isnum(value) && abs(value - expected) <= tolerance

/// A stack's traces are its source's: the signature always, an assay reads them, and they come out of a grinder as the contaminants they are.
/datum/unit_test/dq_trace_stack_is_rolled_from_its_source
	boot_needs = list()

/datum/unit_test/dq_trace_stack_is_rolled_from_its_source/Run()
	var/turf/floor = test_floor()
	var/obj/item/stack/material/steel/station = allocate(/obj/item/stack/material/steel, floor, 10)
	station.ensure_traces()
	TEST_ASSERT(station.trace_amounts["sulfur"] > 0, "steel always carries its signature, sulfur")
	TEST_ASSERT(!station.assayed, "and it is hidden until it is assayed")
	var/list/lines = station.assay(null)
	TEST_ASSERT(length(lines) && findtext(jointext(lines, ";"), "sulfur"), "the assay reads it ([jointext(lines, "; ")])")
	var/obj/item/stack/material/steel/lot_stack = allocate(/obj/item/stack/material/steel, floor, 10)
	lot_stack.lot_key = "vein 1:1:1 hematite"
	lot_stack.ensure_traces()
	TEST_ASSERT(lot_stack.trace_amounts["sulfur"] > 0, "a lot of steel carries the signature too")
	TEST_ASSERT(lot_stack.trace_amounts["sulfur"] > station.trace_amounts["sulfur"] * 0.9, "and a lot is dirtier than station stock")
	// A grinder gives the sheets' feedstock and the traces they carry, as contaminant reagents.
	var/obj/item/stack/material/steel/grindable = allocate(/obj/item/stack/material/steel, floor, 5)
	var/list/ground = dq_feed_ground(grindable, floor)
	TEST_ASSERT(ground[REAGENT_ID_IRON] > 0, "the sheets ground to iron")
	TEST_ASSERT(ground[REAGENT_ID_CONTAMINANT_SULFUR] > 0, "and the sulfur in them came out as sulfur compounds ([contaminants_text(ground)])")

/// An ore carries its vein's traces: a lot of its own, hidden until ground or smelted.
/datum/unit_test/dq_trace_ore_carries_its_vein
	boot_needs = list()

/datum/unit_test/dq_trace_ore_carries_its_vein/Run()
	var/turf/floor = test_floor()
	var/obj/item/ore/iron/ore = allocate(/obj/item/ore/iron, floor)
	TEST_ASSERT(istext(ore.lot_key) && findtext(ore.lot_key, "vein"), "an ore is a lot, named for its vein ([ore.lot_key])")
	TEST_ASSERT_EQUAL(ore.trace_source_id(), MAT_IRON, "hematite is rolled as iron")
	var/list/ground = dq_feed_ground(ore, floor)
	TEST_ASSERT(ground[REAGENT_ID_IRON] > 0, "ground, it gives its metal")
	TEST_ASSERT(ground[REAGENT_ID_CONTAMINANT_SULFUR] > 0, "and its signature ([contaminants_text(ground)])")
	var/list/texts = list()
	for(var/vein in list("a", "b", "c", "d", "e", "f", "g", "h"))
		var/obj/item/ore/iron/other = allocate(/obj/item/ore/iron, floor)
		other.lot_key = "vein [vein]"
		texts[contaminants_text(ore_trace_contaminants(other))] = TRUE
	TEST_ASSERT(length(texts) >= 3, "veins differ ([length(texts)] distinct of 8)")

// ---- feedstock ----

/// Any item grinds into the feedstock of what it is made of, sheet for sheet: an item that costs a sheet of steel gives a sheet of steel's worth, never more.
/datum/unit_test/dq_grinding_any_item_gives_the_feedstock_of_its_materials
	boot_needs = list()

/datum/unit_test/dq_grinding_any_item_gives_the_feedstock_of_its_materials/Run()
	var/turf/floor = test_floor()
	var/obj/item/reagent_containers/spray/bottle = allocate(/obj/item/reagent_containers/spray, floor)
	TEST_ASSERT(item_grindable(bottle), "an item made of something goes in a grinder")
	var/list/composition = bottle.get_material_composition()
	var/paid = 0
	for(var/datum/material/M as anything in composition)
		paid += composition[M] / SHEET_MATERIAL_AMOUNT * REAGENTS_PER_SHEET
	TEST_ASSERT(paid > 0, "the bottle records what it is made of")
	var/list/feed = item_feedstock(bottle)
	var/total = 0
	for(var/id in feed)
		total += feed[id]
	TEST_ASSERT(total > 0 && total <= paid + 0.01, "it grinds into [total]u of the [paid]u it is worth")
	TEST_ASSERT(feed[REAGENT_ID_IRON] > 0 && feed[REAGENT_ID_SILICON] > 0, "the steel gave iron and the glass silicon ([contaminants_text(feed)])")
	var/list/ground = dq_feed_ground(bottle, floor)
	TEST_ASSERT(ground[REAGENT_ID_IRON] > 0, "and the grinder made it")

/// The hand-written rows: every one names an item that exists and reagents that exist, covers the types below it, and grinds into what the row says.
/datum/unit_test/dq_grinding_item_rows
	boot_needs = list()

/datum/unit_test/dq_grinding_item_rows/Run()
	var/rows = 0
	for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_GRINDING))
		if(rule.takes[1][1] != XCUR_ITEM || ispath(rule.takes[1][2], /obj/item/ore))
			continue
		rows++
		var/item_type = rule.takes[1][2]
		TEST_ASSERT(ispath(item_type, /obj/item), "[rule.rule_type] names an item that exists ([item_type])")
		TEST_ASSERT_EQUAL(grinding_item_rule_for(item_type), rule, "[item_type] finds its row")
		var/list/weights = rule.grind_weights()
		TEST_ASSERT(length(weights), "[item_type] has reagents")
		for(var/id in weights)
			TEST_ASSERT(SSchemistry.ready().chemical_reagents[id], "[item_type] grinds into [id], a reagent that exists")
			TEST_ASSERT(weights[id] > 0, "[item_type]'s [id] has a weight")
	TEST_ASSERT(rows >= 55, "about sixty hand-written rows ([rows])")
	// A row covers the types below it.
	var/found_below = FALSE
	for(var/below in subtypesof(/obj/item/light/tube))
		TEST_ASSERT_EQUAL(grinding_item_rule_for(below), grinding_item_rule_for(/obj/item/light/tube), "[below] is covered by the row of the light tubes")
		found_below = TRUE
		break
	TEST_ASSERT(found_below, "there is a tube below the tubes")
	// What a row gives, by weight, with its carried contaminant beside it.
	var/turf/floor = test_floor()
	var/obj/item/light/tube/tube = allocate(/obj/item/light/tube, floor)
	var/list/ground = dq_feed_ground(tube, floor)
	TEST_ASSERT(ground[REAGENT_ID_SILICON] > ground[REAGENT_ID_TUNGSTEN], "a tube is mostly glass ([contaminants_text(ground)])")
	TEST_ASSERT(ground[REAGENT_ID_TUNGSTEN] > 0 && ground[REAGENT_ID_CONTAMINANT_HEAVY_METAL] > 0, "with its tungsten and the mercury it carries")
	TEST_ASSERT(ground[REAGENT_ID_CONTAMINANT_HEAVY_METAL] < ground[REAGENT_ID_TUNGSTEN], "which is a trace")
	var/obj/item/soap/soap = allocate(/obj/item/soap, floor)
	ground = dq_feed_ground(soap, floor)
	TEST_ASSERT(ground[REAGENT_ID_FATTYACID] > 0 && ground[REAGENT_ID_GLYCEROL] > 0, "soap gives its fatty acid back and glycerol ([contaminants_text(ground)])")
	var/obj/item/cell/cell = allocate(/obj/item/cell, floor)
	ground = dq_feed_ground(cell, floor)
	TEST_ASSERT(ground[REAGENT_ID_LITHIUM] > 0 && ground[REAGENT_ID_SACID] > 0, "a power cell gives lithium and sulphuric acid ([contaminants_text(ground)])")

/// Nothing is ground into more than it costs to make: a sweep of printed designs (a fixed stride; the exhaustive tier is dq_fab_conservation).
/datum/unit_test/dq_grinding_never_returns_more_than_the_cost
	boot_needs = list()

/datum/unit_test/dq_grinding_never_returns_more_than_the_cost/Run()
	var/list/ids = list()
	for(var/id in SSresearch.techweb_designs)
		ids += id
	ids = sortList(ids)
	var/checked = 0
	var/list/gains = list()
	for(var/index in 1 to length(ids))
		if((index - 1) % 20)
			continue
		var/datum/design_techweb/D = SSresearch.techweb_designs[ids[index]]
		if(!D || D.id == DESIGN_ID_IGNORE || D.make_reagent || length(D.reagents_list))
			continue
		var/product_path = saved_type_path(D.build_path)
		if(!ispath(product_path, /obj/item) || ispath(product_path, /obj/item/stack))
			continue
		var/list/needed = list()
		var/list/source = (D.build_type & (MECHFAB | PROSFAB)) ? mechfab_cost(D) : D.effective_materials(null)
		for(var/key in source)
			var/datum/material/M = istype(key, /datum/material) ? key : get_material_by_name(key)
			if(istype(M))
				needed[M] += source[key]
		var/obj/item/made
		try
			made = D.create_item(null, null)
			if(isitem(made))
				split_materials_uniformly(needed, 1, made)
		catch(var/exception/e)
			log_world("CONSERVATION: grinding [D.id] ([product_path]) could not be made: [e.name]")
			continue
		if(!isitem(made))
			if(made)
				qdel(made)
			continue
		var/list/paid = dq_fab_basic(needed)
		var/paid_units = dq_fab_total(paid) / SHEET_MATERIAL_AMOUNT * REAGENTS_PER_SHEET
		var/list/feed = item_feedstock(made)
		var/total = 0
		for(var/id in feed)
			total += feed[id]
		checked++
		if(total > paid_units + 1)
			gains += "[D.id] ([product_path]) costs [round(paid_units, 0.1)]u and grinds into [round(total, 0.1)]u"
		qdel(made)
	log_world("CONSERVATION: grinding sweep checked [checked] designs, [length(gains)] gain")
	TEST_ASSERT(checked > 0, "no design was checked")
	TEST_ASSERT(!length(gains), "[length(gains)] items grind into more than they cost: [jointext(gains.Copy(1, min(length(gains), 8) + 1), " | ")]")

// ---- polymers ----

/// The six polymers exist as materials, break down in a grinder into the units they were made of, and cost at least what they give back.
/datum/unit_test/dq_polymers_exist_and_conserve
	boot_needs = list()

/datum/unit_test/dq_polymers_exist_and_conserve/Run()
	for(var/name in list(MAT_RUBBER, MAT_NYLON, MAT_HARD_PLASTIC, MAT_GUNCOTTON, MAT_ARAMID, MAT_CARBON_FIBRE))
		var/datum/material/M = get_material_by_name(name)
		TEST_ASSERT_NOTNULL(M, "[name] is a material")
		var/datum/xform/rule = grinding_sheet_rule_for(M.stack_type)
		TEST_ASSERT_NOTNULL(rule, "[name] grinds back into units")
	for(var/recipe_id in GLOB.polymer_recipes)
		var/datum/polymer_recipe/recipe = GLOB.polymer_recipes[recipe_id]
		var/datum/material/made = get_material_by_name(recipe.material)
		TEST_ASSERT_NOTNULL(made, "[recipe_id] makes a material")
		var/cost = 0
		for(var/reagent_id in recipe.inputs)
			TEST_ASSERT(SSchemistry.ready().chemical_reagents[reagent_id], "[recipe_id] takes [reagent_id], a reagent that exists")
			cost += recipe.inputs[reagent_id]
		if(recipe.sheet_sources)
			cost += REAGENTS_PER_SHEET // the sheet it is made from is worth that in a grinder
		TEST_ASSERT(cost >= REAGENTS_PER_SHEET, "[recipe_id] costs [cost]u a sheet and a sheet grinds back into [REAGENTS_PER_SHEET]u")
		var/datum/xform/rule = grinding_sheet_rule_for(made.stack_type)
		if(!recipe.sheet_sources)
			for(var/id in rule.grind_ids())
				TEST_ASSERT(id in recipe.inputs, "[recipe_id] grinds into [id], which is one of the units it is made of")

/// The furnace polymerises the units of a polymer in its medium into sheets, and spends them.
/datum/unit_test/dq_polymers_are_made_in_the_furnace
	boot_needs = list()

/datum/unit_test/dq_polymers_are_made_in_the_furnace/Run()
	var/turf/floor = test_floor()
	var/obj/machinery/material_furnace/furnace = new(floor)
	TEST_ASSERT_NULL(polymer_recipe_for(furnace), "an empty furnace polymerises nothing")
	furnace.reagents.add_reagent(REAGENT_ID_PHENOL, 25)
	furnace.reagents.add_reagent(REAGENT_ID_WOODALDEHYDE, 25)
	var/datum/polymer_recipe/recipe = polymer_recipe_for(furnace)
	TEST_ASSERT_NOTNULL(recipe, "phenol and wood aldehyde are a polymer")
	TEST_ASSERT_EQUAL(recipe.material, MAT_HARD_PLASTIC, "hard plastic")
	TEST_ASSERT(furnace.polymerise(recipe), "it polymerises")
	var/obj/item/stack/material/hard_plastic/sheets = locate() in floor
	TEST_ASSERT_NOTNULL(sheets, "the sheets come out")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 2, "two sheets from 24u each of the pair, with a little left over")
	TEST_ASSERT_EQUAL(furnace.reagents.total_volume, 0, "and the medium is spent")
	qdel(sheets)
	qdel(furnace)

// ---- tungsten, silicon ----

/// Tungsten is a heat-resistant solid metal catalyst: it runs the high-temperature crack and reduce that nothing else does, and does what a solid metal does.
/datum/unit_test/dq_tungsten_is_the_refractory_catalyst
	boot_needs = list()

/datum/unit_test/dq_tungsten_is_the_refractory_catalyst/Run()
	var/datum/material/tungsten = get_material_by_name(MAT_TUNGSTEN)
	TEST_ASSERT(tungsten.trait(MT_CATALYTIC) >= CHEM_SOLID_MIN_ACTIVITY, "tungsten is catalytic")
	TEST_ASSERT(tungsten.heat_resistance >= CHEM_REFRACTORY_HEAT, "and heat-resistant")
	var/obj/item/reagent_containers/glass/beaker/vessel = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	var/obj/item/stack/material/tungsten/sheet = allocate(/obj/item/stack/material/tungsten, test_floor(), 1)
	rel_add(vessel, nameof(vessel.solids), sheet)
	TEST_ASSERT_EQUAL(vessel.catalyst_kind(), CHEM_CATALYST_SOLID_REFRACTORY, "a tungsten sheet in the glass is a refractory catalyst")
	var/found_crack = FALSE
	var/found_reduce = FALSE
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		if(R.kind != CHEM_CATALYST_SOLID_REFRACTORY)
			continue
		if(R.process_id == CHEM_PROCESS_CRACK)
			found_crack = TRUE
		if(R.process_id == CHEM_PROCESS_REDUCE)
			found_reduce = TRUE
		TEST_ASSERT(R.solid_runs(CHEM_CATALYST_SOLID_REFRACTORY) && !R.solid_runs(CHEM_CATALYST_SOLID_METAL), "[route_id] runs on tungsten and on no other solid metal")
	TEST_ASSERT(found_crack && found_reduce, "tungsten runs a crack and a reduce")
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		if(R.kind == CHEM_CATALYST_SOLID_METAL)
			TEST_ASSERT(R.solid_runs(CHEM_CATALYST_SOLID_REFRACTORY), "a refractory sheet does what a solid metal does ([route_id])")
			break

/// Silicon (what glass grinds to) has a route to silicate, and silicate to the siloxane core.
/datum/unit_test/dq_silicon_builds_the_siloxane_core_from_silicate
	boot_needs = list()

/datum/unit_test/dq_silicon_builds_the_siloxane_core_from_silicate/Run()
	var/found = FALSE
	for(var/datum/xform/rule as anything in dq_chem_rules())
		if(rule.rule_type == /transformation/chem/instant/silicate_from_silicon)
			found = TRUE
			TEST_ASSERT(rule.reagent_takes[REAGENT_ID_SILICON] && rule.reagent_takes[REAGENT_ID_LYE], "silicon in lye")
			TEST_ASSERT_EQUAL(rule.result, REAGENT_ID_SILICATE, "is silicate")
	TEST_ASSERT(found, "the route is declared")
	var/silanol_route = FALSE
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		if(R.process_id == CHEM_PROCESS_NEUTRALISE && (REAGENT_ID_SILICATE in R.from) && (REAGENT_ID_KELOTANE in R.products))
			silanol_route = TRUE
			break
	TEST_ASSERT(silanol_route, "and an acid on silicate sets the siloxane core free")

// ---- the spray bottle ----

/// A spray bottle is one refillable container: what it holds is a starting fill, and a pen gives it a label.
/datum/unit_test/dq_spray_bottle_is_one_refillable_container
	boot_needs = list()

/datum/unit_test/dq_spray_bottle_is_one_refillable_container/Run()
	var/turf/floor = test_floor()
	var/obj/item/reagent_containers/spray/plain = allocate(/obj/item/reagent_containers/spray, floor)
	TEST_ASSERT_EQUAL(plain.reagents.total_volume, 0, "the generic bottle comes empty")
	var/list/fills = list(\
		VARIANT(/obj/item/reagent_containers/spray/cleaner) = REAGENT_ID_CLEANER, \
		VARIANT(/obj/item/reagent_containers/spray/sterilizine) = REAGENT_ID_STERILIZINE, \
		VARIANT(/obj/item/reagent_containers/spray/plantbgone) = REAGENT_ID_PLANTBGONE, \
		VARIANT(/obj/item/reagent_containers/spray/pepper) = REAGENT_ID_CONDENSEDCAPSAICIN, \
		VARIANT(/obj/item/reagent_containers/spray/windowsealant) = REAGENT_ID_SILICATE, \
		VARIANT(/obj/item/reagent_containers/spray/luminol) = REAGENT_ID_LUMINOL)
	for(var/ref in fills)
		var/obj/item/reagent_containers/spray/bottle = own(variant_new(ref, floor))
		TEST_ASSERT(bottle.starting_fill && bottle.starting_fill[fills[ref]], "[ref] is a starting fill of [fills[ref]]")
		TEST_ASSERT(bottle.reagents.get_reagent_amount(fills[ref]) > 0, "[ref] comes holding it")
	// Refill it with something else and the fill is what it holds now.
	var/obj/item/reagent_containers/spray/cleaner = own(variant_new(VARIANT(/obj/item/reagent_containers/spray/cleaner), floor))
	cleaner.reagents.clear_reagents()
	cleaner.reagents.add_reagent(REAGENT_ID_WATER, 30)
	TEST_ASSERT_EQUAL(cleaner.reagents.get_reagent_amount(REAGENT_ID_WATER), 30, "it is refilled with water")
	TEST_ASSERT_EQUAL(cleaner.reagents.get_reagent_amount(REAGENT_ID_CLEANER), 0, "and holds no cleaner")

/// Every spray bottle that was a type of its own is a row of one type, and keeps what made it that bottle: its name, description, sprite, size, fill and (the
/// pepper spray) its safety. No subtype of the spray bottle is left that only set data.
/datum/unit_test/dq_spray_variants_keep_their_look
	boot_needs = list()

/datum/unit_test/dq_spray_variants_keep_their_look/Run()
	var/turf/floor = test_floor()
	// key = list(name, icon file, icon_state, item_state, volume, reagent, units, safety lock)
	var/list/expected = list(
		"cleaner" = list("space cleaner", 'icons/obj/janitor.dmi', "cleaner", "cleaner", 250, REAGENT_ID_CLEANER, 250, FALSE),
		"drone_cleaner" = list("space cleaner", 'icons/obj/janitor.dmi', "cleaner", "cleaner", 50, REAGENT_ID_CLEANER, 50, FALSE),
		"sterilizine" = list(REAGENT_ID_STERILIZINE, 'icons/obj/janitor.dmi', "cleaner", "cleaner", 250, REAGENT_ID_STERILIZINE, 250, FALSE),
		"pepper" = list("pepperspray", 'icons/obj/weapons.dmi', "pepperspray", "pepperspray", 40, REAGENT_ID_CONDENSEDCAPSAICIN, 40, TRUE),
		"luminol" = list("luminol bottle", 'icons/obj/forensics.dmi', "luminol", "cleaner", 250, REAGENT_ID_LUMINOL, 250, FALSE),
		"plantbgone" = list(REAGENT_PLANTBGONE, 'icons/obj/hydroponics_machines.dmi', "plantbgone", "plantbgone", 100, REAGENT_ID_PLANTBGONE, 100, FALSE),
		"windowsealant" = list("Krak-b-gone", 'icons/obj/items.dmi', "windowsealant", "spraycan", 80, REAGENT_ID_SILICATE, 80, FALSE))
	for(var/key in expected)
		var/list/row = expected[key]
		var/ref = variant_ref(/obj/item/reagent_containers/spray, key)
		var/obj/item/reagent_containers/spray/S = own(variant_new(ref, floor))
		TEST_ASSERT_EQUAL(S.type, /obj/item/reagent_containers/spray, "[ref] is made as the one spray type")
		TEST_ASSERT_EQUAL(S.variant, key, "[ref] keeps its key")
		TEST_ASSERT_EQUAL(S.name, row[1], "[ref]: name")
		TEST_ASSERT_EQUAL("[S.icon]", "[row[2]]", "[ref]: icon file")
		TEST_ASSERT_EQUAL(S.icon_state, row[3], "[ref]: icon_state")
		TEST_ASSERT_EQUAL(S.item_state, row[4], "[ref]: in-hand sprite")
		TEST_ASSERT_EQUAL(S.volume, row[5], "[ref]: volume")
		TEST_ASSERT_EQUAL(round(S.reagents.get_reagent_amount(row[6]), 0.01), row[7], "[ref]: starts holding its fill")
		TEST_ASSERT_EQUAL(S.reagents.total_volume, row[7], "[ref]: and nothing else")
		TEST_ASSERT_EQUAL(S.safety_lock, row[8], "[ref]: safety lock")
		TEST_ASSERT_EQUAL(S.safety, row[8], "[ref]: safety starts on where there is one")
	// The old paths are gone as types: only the behaviours that differ (the chem sprayer, the hose nozzle, the water flower) are subtypes.
	for(var/key in expected)
		TEST_ASSERT_NULL(text2path("/obj/item/reagent_containers/spray/[key]"), "/obj/item/reagent_containers/spray/[key] is no type any more")
	for(var/path in subtypesof(/obj/item/reagent_containers/spray))
		TEST_ASSERT(ispath(path, /obj/item/reagent_containers/spray/chemsprayer) || path == /obj/item/reagent_containers/spray/waterflower, "[path] is a subtype of the spray bottle that is not a behaviour")
	// The old path still resolves for a map (variant_alias_of): the row's vars on the one type.
	for(var/key in expected)
		TEST_ASSERT(variant_alias_of("/obj/item/reagent_containers/spray/[key]"), "the old map path of [key] still resolves")

#endif

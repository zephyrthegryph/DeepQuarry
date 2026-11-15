// Chemical block structures, processes and the routes generated from them (code/domains/world_model/reagents/blocks/, the declarations and the processes:
// code/content/reagents/blocks/): what a structure derives, what each process does to one, the generated set pinned, and the burn medicines made through them
// in a beaker, with their catalysts, their fallout and their interference.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A beaker on the test floor, at `celsius`.
/datum/unit_test/proc/dq_blk_beaker(celsius = 20)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.inherit_heat(T0C + celsius)
	return B

/// The compiled rule of a generated route.
/proc/dq_route_rule(datum/chem_route/route)
	RETURN_TYPE(/datum/xform)
	for(var/datum/xform/X as anything in GLOB.chem_route_rules)
		if(X.route_id == route.id)
			return X
	return null

/datum/unit_test/proc/dq_blk_near(a, b, tolerance = 0.01)
	return abs(a - b) <= tolerance

/// A generator context over these structures (reagent id => structure): everything exists.
/datum/unit_test/proc/dq_blk_gen(list/structures)
	var/datum/chem_gen/G = new /datum/chem_gen
	G.structures = structures
	G.ids = list()
	for(var/id in structures)
		G.ids += id
	sortTim(G.ids, GLOBAL_PROC_REF(cmp_text_asc))
	G.reagents = SSchemistry.ready().chemical_reagents
	G.condensed = list()
	return G

/// The keys of the structures a process makes of `S`.
/datum/unit_test/proc/dq_blk_made(process_id, datum/chem_structure/S, datum/chem_gen/G, id = "dq_substrate")
	var/list/keys = list()
	var/list/made = chem_process_variants(process_id, id, S, G)
	for(var/variant in made)
		var/datum/chem_variant/V = variant
		for(var/entry in V.to)
			if(istext(entry))
				keys += entry
				continue
			var/datum/chem_structure/T = entry
			keys += T.key
	return keys

// ---- structures ----

/datum/unit_test/dq_chem_blocks_structure_derives_formula_class_tags

/datum/unit_test/dq_chem_blocks_structure_derives_formula_class_tags/Run()
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_ETHANOL).formula(), "C2H6O", "ethanol is a short chain with a hydroxyl")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_ETHANOL).class_name(), "alcohol", "an alcohol")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_LYE).formula(), "NaOH", "lye is sodium and hydroxide")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_LYE).class_name(), "base", "a base")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_SACID).formula(), "H2SO4", "sulphuric acid takes two hydrogens for a sulfate")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_SACID).class_name(), "acid", "an acid")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_WATER).formula(), "HOH", "water")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_WATER).class_name(), "water", "neither acid nor base")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_SODIUMCHLORIDE).class_name(), "salt", "a salt")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_SUGAR).class_name(), "sugar", "a sugar")
	var/datum/chem_structure/ester = chem_structure_make(list(CHEM_CORE_RING, CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_AMINE), list(CHEM_LINK_ESTER))
	TEST_ASSERT_EQUAL(ester.formula(), "C9H11NO2", "an ester of a ring amine and a short chain is C9H11NO2")
	TEST_ASSERT_EQUAL(ester.class_name(), "ester", "an ester")
	var/list/lye_tags = chem_structure_of(REAGENT_ID_LYE).tags
	TEST_ASSERT((CHEM_TAG_IONIC in lye_tags) && (CHEM_TAG_BASIC in lye_tags), "lye is ionic and basic")
	var/list/ethanol_tags = chem_structure_of(REAGENT_ID_ETHANOL).tags
	TEST_ASSERT((CHEM_TAG_ORGANIC in ethanol_tags) && (CHEM_TAG_POLAR in ethanol_tags) && !(CHEM_TAG_NONPOLAR in ethanol_tags), "ethanol is organic and polar")
	TEST_ASSERT(CHEM_TAG_NONPOLAR in chem_structure_of(REAGENT_ID_CONTAMINANT_OILY_RESIDUE).tags, "oily residue is nonpolar")
	TEST_ASSERT(CHEM_TAG_BIOLOGICAL in chem_structure_of(REAGENT_ID_CONTAMINANT_BIOLOGICAL).tags, "endotoxin is biological")
	TEST_ASSERT(CHEM_TAG_OXIDISER in chem_structure_of(REAGENT_ID_CONTAMINANT_PEROXIDE).tags, "peroxide is an oxidiser")
	// The same blocks are the same structure however they were listed.
	var/datum/chem_structure/a = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_HYDROXYL, CHEM_GROUP_CARBOXYL))
	var/datum/chem_structure/b = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_CARBOXYL, CHEM_GROUP_HYDROXYL))
	TEST_ASSERT_EQUAL(a.key, b.key, "a structure is its blocks, not their order")

/datum/unit_test/dq_chem_blocks_declarations_are_sound

/datum/unit_test/dq_chem_blocks_declarations_are_sound/Run()
	var/list/reagents = SSchemistry.ready().chemical_reagents
	for(var/id in GLOB.chem_declared_structures)
		TEST_ASSERT_NOTNULL(reagents[id], "[id] is declared a structure and is a reagent")
	TEST_ASSERT(length(GLOB.chem_structures) >= 20, "the structures were built ([length(GLOB.chem_structures)])")
	for(var/key in GLOB.chem_structure_index)
		TEST_ASSERT_EQUAL(length(GLOB.chem_structure_index[key]), 1, "two chemicals have one structure ([key]: [jointext(GLOB.chem_structure_index[key], ", ")])")
	for(var/id in contaminant_ids())
		var/datum/reagent/contaminant/C = contaminant_def(id)
		TEST_ASSERT(C.filter_floor >= 0 && C.filter_floor < 0.05, "[id] has a filter floor")
		if(id != REAGENT_ID_CONTAMINANT_INERT_FILLER)
			TEST_ASSERT_NOTNULL(chem_structure_of(id), "contaminant [id] has a structure (its tags come from it)")
	// A subtype does not inherit a structure: every vodka is not an ethanol.
	TEST_ASSERT_NULL(chem_structure_of(REAGENT_ID_VODKA), "a vodka declares nothing")

// ---- the processes ----

/datum/unit_test/dq_chem_blocks_fifteen_processes

/datum/unit_test/dq_chem_blocks_fifteen_processes/Run()
	TEST_ASSERT_EQUAL(length(GLOB.chem_processes), 15, "fifteen processes")
	for(var/id in list(CHEM_PROCESS_OXIDISE, CHEM_PROCESS_REDUCE, CHEM_PROCESS_HALOGENATE, CHEM_PROCESS_NITRATE, CHEM_PROCESS_SUBSTITUTE, CHEM_PROCESS_PHOSPHORYLATE, \
			CHEM_PROCESS_DECARBOXYLATE, CHEM_PROCESS_CONDENSE, CHEM_PROCESS_HYDROLYSE, CHEM_PROCESS_FERMENT, CHEM_PROCESS_CRACK, CHEM_PROCESS_NEUTRALISE, \
			CHEM_PROCESS_DISPLACE, CHEM_PROCESS_ELECTROLYSE, CHEM_PROCESS_POLYMERISE))
		TEST_ASSERT_NOTNULL(chem_process_of(id), "process [id] exists")
	var/datum/chem_process/polymerise = chem_process_of(CHEM_PROCESS_POLYMERISE)
	TEST_ASSERT(!polymerise.reserved, "polymerise makes the chemistry-side products (lube); the workshop's polymers are the materials lane's")
	var/polymerised = 0
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		if(R.process_id == CHEM_PROCESS_POLYMERISE)
			polymerised++
			TEST_ASSERT(R.products[1] == REAGENT_ID_LUBE, "[route_id]: the only polymer a chemist makes is silicone oil")
		TEST_ASSERT_NOTNULL(dq_route_rule(R), "[route_id] compiled into a rule")
	TEST_ASSERT_EQUAL(polymerised, 1, "one route polymerises: kelotane into lube")

/// What each process does to a structure, with structures of its own (so no reagent has to exist).
/datum/unit_test/dq_chem_blocks_processes_change_structures

/datum/unit_test/dq_chem_blocks_processes_change_structures/Run()
	var/datum/chem_structure/alcohol = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_HYDROXYL))
	var/datum/chem_structure/aldehyde = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_CARBONYL))
	var/datum/chem_structure/acid = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_CARBOXYL))
	var/datum/chem_structure/nitro = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_NITRO))
	var/datum/chem_structure/halide = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_HALIDE))
	var/datum/chem_gen/G = dq_blk_gen(list())
	TEST_ASSERT(aldehyde.key in dq_blk_made(CHEM_PROCESS_OXIDISE, alcohol, G), "oxidise takes a hydroxyl to a carbonyl")
	TEST_ASSERT(acid.key in dq_blk_made(CHEM_PROCESS_OXIDISE, aldehyde, G), "and a carbonyl to a carboxyl")
	TEST_ASSERT(aldehyde.key in dq_blk_made(CHEM_PROCESS_REDUCE, acid, G), "reduce takes a carboxyl to a carbonyl")
	TEST_ASSERT(alcohol.key in dq_blk_made(CHEM_PROCESS_REDUCE, aldehyde, G), "a carbonyl to a hydroxyl")
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_AMINE)).key in dq_blk_made(CHEM_PROCESS_REDUCE, nitro, G), "and a nitro to an amine")
	TEST_ASSERT(halide.key in dq_blk_made(CHEM_PROCESS_HALOGENATE, chem_structure_make(list(CHEM_CORE_RING)), G), "halogenate hangs a halide on a core")
	TEST_ASSERT(nitro.key in dq_blk_made(CHEM_PROCESS_NITRATE, chem_structure_make(list(CHEM_CORE_RING)), G), "nitrate hangs a nitro")
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_AMINE)).key in dq_blk_made(CHEM_PROCESS_SUBSTITUTE, halide, G), "substitute swaps a halide for an amine")
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_THIOL)).key in dq_blk_made(CHEM_PROCESS_SUBSTITUTE, halide, G), "or a thiol")
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_HYDROXYL, CHEM_GROUP_PHOSPHATE)).key in dq_blk_made(CHEM_PROCESS_PHOSPHORYLATE, alcohol, G), "phosphorylate hangs a phosphate on a core with a hydroxyl")
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_RING)).key in dq_blk_made(CHEM_PROCESS_DECARBOXYLATE, acid, G), "decarboxylate drives a carboxyl off")
	var/datum/chem_structure/sugar = chem_structure_make(list(CHEM_CORE_SUGAR_RING), list(CHEM_GROUP_HYDROXYL))
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_HYDROXYL)).key in dq_blk_made(CHEM_PROCESS_FERMENT, sugar, G), "ferment takes a sugar ring to a short chain")
	var/datum/chem_structure/wax = chem_structure_make(list(CHEM_CORE_LONG_CHAIN), list(CHEM_GROUP_HYDROXYL))
	TEST_ASSERT(chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_HYDROXYL)).key in dq_blk_made(CHEM_PROCESS_CRACK, wax, G), "crack takes a long chain to a short one")
	// Condense joins an acid and an alcohol as an ester; hydrolyse undoes it.
	var/datum/chem_structure/ethanol = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_HYDROXYL))
	var/datum/chem_gen/joined = dq_blk_gen(list("dq_acid" = acid, "dq_alcohol" = ethanol))
	var/datum/chem_structure/ester = chem_structure_make(list(CHEM_CORE_RING, CHEM_CORE_SHORT_CHAIN), null, list(CHEM_LINK_ESTER))
	var/list/condensed = dq_blk_made(CHEM_PROCESS_CONDENSE, acid, joined, "dq_acid")
	TEST_ASSERT(ester.key in condensed, "condense makes an ester of a carboxyl and a hydroxyl")
	var/datum/chem_process/condense = chem_process_of(CHEM_PROCESS_CONDENSE)
	TEST_ASSERT(condense.blocked_by_water, "and water stops it")
	joined.condensed[ester.key] = list(list("dq_acid", "dq_alcohol"))
	var/datum/chem_process/hydrolyse = chem_process_of(CHEM_PROCESS_HYDROLYSE)
	var/list/split = hydrolyse.chem_variants("dq_ester", ester, joined)
	TEST_ASSERT_EQUAL(length(split), 1, "hydrolyse undoes the condensation")
	var/datum/chem_variant/V = split[1]
	TEST_ASSERT(V.to[1] == "dq_acid" && V.to[2] == "dq_alcohol", "into the acid and the alcohol")
	TEST_ASSERT(REAGENT_ID_WATER in V.agents, "with water")
	// Neutralise: an acid and a base make the salt; an acid on a silicate sets silanol free.
	var/datum/chem_gen/real = dq_blk_gen(GLOB.chem_structures)
	var/list/neutral = dq_blk_made(CHEM_PROCESS_NEUTRALISE, chem_structure_of(REAGENT_ID_SACID), real, REAGENT_ID_SACID)
	TEST_ASSERT(chem_structure_of(REAGENT_ID_KELOTANE).key in neutral, "sulphuric acid on a silicate makes silanol: kelotane")
	var/datum/chem_structure/sodium_sulfate = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_SULFATE)
	TEST_ASSERT(sodium_sulfate.key in neutral, "and on lye makes sodium sulfate")
	TEST_ASSERT_EQUAL(sodium_sulfate.formula(), "Na2SO4", "whose formula carries both valences")
	// Electrolyse splits water; displace binds nothing where no chemical results.
	var/list/split_water = dq_blk_made(CHEM_PROCESS_ELECTROLYSE, chem_structure_of(REAGENT_ID_WATER), real, REAGENT_ID_WATER)
	TEST_ASSERT((REAGENT_ID_HYDROGEN in split_water) && (REAGENT_ID_OXYGEN in split_water), "electrolysis of water gives hydrogen and oxygen")
	var/list/displaced = dq_blk_made(CHEM_PROCESS_DISPLACE, chem_structure_of(REAGENT_ID_SODIUMCHLORIDE), real, REAGENT_ID_SODIUMCHLORIDE)
	TEST_ASSERT(chem_structure_of(REAGENT_ID_POTASSIUMCHLORIDE).key in displaced, "potassium takes the place of sodium in table salt")
	TEST_ASSERT(REAGENT_ID_SODIUM in displaced, "and sets the sodium free")
	TEST_ASSERT_EQUAL(length(dq_blk_made(CHEM_PROCESS_POLYMERISE, ethanol, G)), 0, "polymerise makes nothing of an ethanol")

/// A salt's metal binding to an acid group makes the organometallic that has the structure (a temporary entry in the index stands in for one).
/datum/unit_test/dq_chem_blocks_displace_binds_a_metal

/datum/unit_test/dq_chem_blocks_displace_binds_a_metal/Run()
	var/datum/chem_structure/phosphate = chem_structure_make(list(CHEM_CORE_SILOXANE), list(CHEM_GROUP_HYDROXYL, CHEM_GROUP_PHOSPHATE))
	var/datum/chem_structure/bound = phosphate.with_metal(CHEM_ION_CALCIUM)
	var/datum/chem_structure/copper_salt = chem_structure_make(null, null, null, CHEM_ION_CALCIUM, CHEM_ION_SULFATE)
	var/datum/chem_gen/G = dq_blk_gen(list("dq_phosphate" = phosphate, "dq_salt" = copper_salt))
	var/datum/chem_process/displace = chem_process_of(CHEM_PROCESS_DISPLACE)
	TEST_ASSERT_EQUAL(length(displace.chem_variants("dq_phosphate", phosphate, G)), 0, "no chemical has the bound structure: no route")
	GLOB.chem_structure_index[bound.key] = list("dq_bound")
	var/list/made = displace.chem_variants("dq_phosphate", phosphate, G)
	GLOB.chem_structure_index -= bound.key
	TEST_ASSERT_EQUAL(length(made), 1, "with a chemical that has it, the salt's metal binds")

// ---- the generated set ----

/// Every generated route, written out and compared with the recorded list: a new structure or process that makes a new route shows up here, and a cheap route to
/// something gated (an explosive, phoron) is read off this list before it is blessed.
/datum/unit_test/dq_chem_routes_pinned

/datum/unit_test/dq_chem_routes_pinned/Run()
	var/list/rows = chem_routes_dump()
	TEST_ASSERT(length(rows) > 20, "routes were generated ([length(rows)])")
	var/failure = dq_xform_pin_compare("chem_routes", rows)
	TEST_ASSERT(isnull(failure), failure)

/// What no route may make, whatever the structures say: the explosives and the phoron family are made by their own recipes.
/datum/unit_test/dq_chem_routes_make_nothing_gated

/datum/unit_test/dq_chem_routes_make_nothing_gated/Run()
	// Nitroglycerin and mutagen have approved routes (nitrate glycerol, halogenate diethylamine). Cyanide is made by its own recipe; the only route that ends in it is
	// the ion exchange of prussian blue with potassium, which gives back the cyanide that made it.
	var/list/gated = list(REAGENT_ID_PHORON, REAGENT_ID_THERMITE, REAGENT_ID_PACID, REAGENT_ID_LIQUIDFIRE, REAGENT_ID_CYANIDE)
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		for(var/id in R.products)
			if(id == REAGENT_ID_CYANIDE && R.process_id == CHEM_PROCESS_DISPLACE && (REAGENT_ID_PRUSSIANBLUE in R.from))
				continue
			TEST_ASSERT(!(id in gated), "[route_id] makes [id], which only its own recipe may")
		if(!R.matched)
			for(var/id in R.products)
				TEST_ASSERT(id == REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE || id == REAGENT_ID_CONTAMINANT_SALTS, "[route_id] ends in residue only, and makes [id]")
		for(var/id in R.from)
			TEST_ASSERT(!istype(SSchemistry.ready().chemical_reagents[id], /datum/reagent/contaminant) || R.process_id == CHEM_PROCESS_NEUTRALISE || R.process_id == CHEM_PROCESS_CLASH, "[route_id] starts from a contaminant")

// ---- the burn medicines, through the processes ----

/// Silicate and an acid make kelotane (a siloxane with a hydroxyl) and leave salts: neutralise.
/datum/unit_test/dq_chem_blocks_kelotane_from_silicate_and_acid

/datum/unit_test/dq_chem_blocks_kelotane_from_silicate_and_acid/Run()
	TEST_ASSERT_NULL(text2path("/transformation/chem/instant/kelotane"), "the old kelotane recipe is gone")
	TEST_ASSERT_NULL(text2path("/transformation/chem/instant/dermaline"), "and the old dermaline recipe")
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker()
	B.reagents.add_reagent(REAGENT_ID_SILICATE, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_SACID, 10)
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_KELOTANE), 10), "10u of kelotane ([B.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 10), "and 10u of salts")
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_SILICATE), 0, "the silicate is spent")
	TEST_ASSERT(B.reagents.purity() < 1, "the salts are in the mixture: kelotane made this way is not pure")
	// No purity gate: the same reaction in a dirty mixture goes.
	var/obj/item/reagent_containers/glass/beaker/dirty = dq_blk_beaker()
	dirty.reagents.add_reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 8, safety = 1)
	dirty.reagents.add_reagent(REAGENT_ID_SILICATE, 10, safety = 1)
	dirty.reagents.add_reagent(REAGENT_ID_SACID, 10)
	TEST_ASSERT(dq_blk_near(dirty.reagents.get_reagent_amount(REAGENT_ID_KELOTANE), 10), "a crude mixture reacts too: no recipe asks for a grade")

/// Kelotane and phosphorus make dermaline and water when hot; the uncatalysed step leaves a residue; too cold nothing goes.
/datum/unit_test/dq_chem_blocks_dermaline_from_kelotane_and_phosphorus

/datum/unit_test/dq_chem_blocks_dermaline_from_kelotane_and_phosphorus/Run()
	var/obj/item/reagent_containers/glass/beaker/cold = dq_blk_beaker(20)
	cold.reagents.add_reagent(REAGENT_ID_KELOTANE, 10, safety = 1)
	cold.reagents.add_reagent(REAGENT_ID_PHOSPHORUS, 10)
	TEST_ASSERT_EQUAL(cold.reagents.get_reagent_amount(REAGENT_ID_DERMALINE), 0, "at room temperature nothing goes")
	var/obj/item/reagent_containers/glass/beaker/hot = dq_blk_beaker(95)
	hot.reagents.add_reagent(REAGENT_ID_KELOTANE, 10, safety = 1)
	hot.reagents.add_reagent(REAGENT_ID_PHOSPHORUS, 10)
	TEST_ASSERT(dq_blk_near(hot.reagents.get_reagent_amount(REAGENT_ID_DERMALINE), 10), "at 95 C it makes 10u of dermaline ([hot.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(hot.reagents.get_reagent_amount(REAGENT_ID_WATER), 10), "and gives off water")
	TEST_ASSERT(dq_blk_near(hot.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE), 1), "an uncatalysed step is 80% selective: 1u of residue")
	TEST_ASSERT(hot.reagents.purity() < 1, "the natural fallout is the purity")

/// Acid and base cancel; hydrochloric acid freed by a halogenation is cleaned up by lye into table salt.
/datum/unit_test/dq_chem_blocks_acid_and_base_cancel

/datum/unit_test/dq_chem_blocks_acid_and_base_cancel/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker()
	B.reagents.add_reagent(REAGENT_ID_SACID, 5, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_LYE, 5)
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 5), "sulphuric acid and lye make salts")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 5), "and water")
	var/obj/item/reagent_containers/glass/beaker/chlorinated = dq_blk_beaker(55)
	chlorinated.reagents.add_reagent(REAGENT_ID_ETHANOL, 10, safety = 1)
	chlorinated.reagents.add_reagent(REAGENT_ID_CHLORINE, 10)
	TEST_ASSERT(dq_blk_near(chlorinated.reagents.get_reagent_amount(REAGENT_ID_HYDROCHLORIC), 10), "halogenating ethanol frees hydrochloric acid, a real chemical ([chlorinated.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(chlorinated.reagents.get_reagent_amount(REAGENT_ID_CHLORALHYDRATE), 10), "and makes chloral hydrate of the ethanol")
	chlorinated.reagents.add_reagent(REAGENT_ID_LYE, 10)
	TEST_ASSERT(dq_blk_near(chlorinated.reagents.get_reagent_amount(REAGENT_ID_HYDROCHLORIC), 0), "lye spends it")
	TEST_ASSERT(dq_blk_near(chlorinated.reagents.get_reagent_amount(REAGENT_ID_SODIUMCHLORIDE), 10), "into table salt, which is a chemical that exists")

/// An enzyme ferments sugar into ethanol at gentle heat, leaves methanol and endotoxin, is spent, and is poisoned by heavy metals.
/datum/unit_test/dq_chem_blocks_enzyme_route

/datum/unit_test/dq_chem_blocks_enzyme_route/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker(32)
	B.reagents.add_reagent(REAGENT_ID_SUGAR, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_ENZYME, 2)
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 10), "10u of sugar made 10u of ethanol ([B.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_METHANOL), 0.3, 0.02), "with a trace of methanol")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_BIOLOGICAL), 0.4, 0.02), "the enzyme spent into endotoxin")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_ENZYME), 1.6, 0.02), "so 1.6u of it is left")
	var/obj/item/reagent_containers/glass/beaker/hot = dq_blk_beaker(80)
	hot.reagents.add_reagent(REAGENT_ID_SUGAR, 10, safety = 1)
	hot.reagents.add_reagent(REAGENT_ID_ENZYME, 2)
	TEST_ASSERT_EQUAL(hot.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 0, "an enzyme does not work hot")
	var/obj/item/reagent_containers/glass/beaker/poisoned = dq_blk_beaker(32)
	poisoned.reagents.add_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 1, safety = 1)
	poisoned.reagents.add_reagent(REAGENT_ID_SUGAR, 10, safety = 1)
	poisoned.reagents.add_reagent(REAGENT_ID_ENZYME, 2)
	TEST_ASSERT_EQUAL(poisoned.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 0, "heavy metals kill the enzyme")

/// Uncatalysed and hot an oxidation leaves peroxide, which goes off when the container is heated; it is no hazard cold.
/datum/unit_test/dq_chem_blocks_peroxide_detonates_when_heated

/datum/unit_test/dq_chem_blocks_peroxide_detonates_when_heated/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker(90)
	B.reagents.add_reagent(REAGENT_ID_ETHANOL, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_OXYGEN, 10)
	var/peroxide = B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_PEROXIDE)
	TEST_ASSERT(peroxide > 0.1, "a hot uncatalysed oxidation left peroxide ([peroxide]u)")
	TEST_ASSERT(B.reagents.peroxide_hazard() > 0, "which is a hazard at that heat")
	dq_pur_set_temp(B, 30)
	TEST_ASSERT_EQUAL(B.reagents.peroxide_hazard(), 0, "and none cold")
	TEST_ASSERT(!B.reagents.detonate_peroxide(), "cold it does not go off")
	dq_pur_set_temp(B, 90)
	TEST_ASSERT(B.reagents.detonate_peroxide(), "heated it goes off")
	TEST_ASSERT_EQUAL(B.reagents.total_volume, 0, "and the container's contents with it")
	for(var/obj/effect/effect/sparks/spark in range(2, B))
		qdel(spark)

/// The fallout of each process: the trace-potent contaminants, under the conditions that make them.
/datum/unit_test/dq_chem_blocks_fallout

/datum/unit_test/dq_chem_blocks_fallout/Run()
	var/datum/chem_structure/phenol = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_HYDROXYL))
	var/datum/chem_structure/amine = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_AMINE))
	var/datum/chem_process/halogenate = chem_process_of(CHEM_PROCESS_HALOGENATE)
	TEST_ASSERT(halogenate.fallout(CHEM_CATALYST_NONE, phenol, T0C + 120)[REAGENT_ID_CONTAMINANT_DIOXIN] > 0, "a hot chlorination of a phenol leaves dioxin")
	TEST_ASSERT_EQUAL(length(halogenate.fallout(CHEM_CATALYST_NONE, phenol, T0C + 50)), 0, "not cool")
	TEST_ASSERT(chem_process_of(CHEM_PROCESS_NITRATE).fallout(CHEM_CATALYST_ACID, amine, T0C + 90)[REAGENT_ID_CONTAMINANT_NITROSAMINE] > 0, "nitrating an amine leaves nitrosamine")
	TEST_ASSERT(chem_process_of(CHEM_PROCESS_OXIDISE).fallout(CHEM_CATALYST_NONE, phenol, T0C + 100)[REAGENT_ID_CONTAMINANT_PEROXIDE] > 0, "a hot uncatalysed oxidation leaves peroxide")
	TEST_ASSERT_EQUAL(length(chem_process_of(CHEM_PROCESS_OXIDISE).fallout(CHEM_CATALYST_SOLID_METAL, phenol, T0C + 100)), 0, "a metal catalyst steers it clean")
	TEST_ASSERT(chem_process_of(CHEM_PROCESS_FERMENT).fallout(CHEM_CATALYST_ENZYME, phenol, T0C + 30)[REAGENT_ID_CONTAMINANT_METHANOL] > 0, "fermenting leaves methanol")
	TEST_ASSERT(chem_process_of(CHEM_PROCESS_CONDENSE).fallout(CHEM_CATALYST_ACID, phenol, T0C + 100)[REAGENT_ID_CONTAMINANT_PLASTICISER] > 0, "a hot condensation of a ring leaves plasticiser")
	TEST_ASSERT(chem_process_of(CHEM_PROCESS_CRACK).fallout(CHEM_CATALYST_NONE, phenol, T0C + 150)[REAGENT_ID_CONTAMINANT_TAR] > chem_process_of(CHEM_PROCESS_CRACK).fallout(CHEM_CATALYST_SOLID_ACID, phenol, T0C + 150)[REAGENT_ID_CONTAMINANT_TAR], "cracking leaves more tar without a solid acid")
	TEST_ASSERT(chem_process_of(CHEM_PROCESS_DECARBOXYLATE).fallout(CHEM_CATALYST_NONE, phenol, T0C + 150)[REAGENT_ID_CONTAMINANT_TAR] > 0, "decarboxylating leaves tar")

/// Each trace-potent contaminant does its one thing, strongly, at a trace.
/datum/unit_test/dq_chem_blocks_trace_effects

/datum/unit_test/dq_chem_blocks_trace_effects/Run()
	var/datum/reagents/holder = dq_pur_beaker().reagents
	for(var/id in list(REAGENT_ID_CONTAMINANT_HYDROCHLORIC, REAGENT_ID_CONTAMINANT_DIOXIN, REAGENT_ID_CONTAMINANT_NITROSAMINE, REAGENT_ID_CONTAMINANT_METHANOL, REAGENT_ID_CONTAMINANT_TAR, REAGENT_ID_CONTAMINANT_PLASTICISER, REAGENT_ID_CONTAMINANT_PEROXIDE))
		holder.add_reagent(id, 1, safety = 1)
	var/mob/living/carbon/human/burned = allocate(/mob/living/carbon/human)
	var/datum/reagent/contaminant/reactive/acid = holder.get_reagent(REAGENT_ID_CONTAMINANT_HYDROCHLORIC)
	acid.burn_chance = 100
	acid.affect_blood(burned, 0, 0.05)
	TEST_ASSERT(burned.injury_load(INJURY_CATEGORY_THERMAL) > 0.1, "0.05u of hydrochloric acid burns")
	var/mob/living/carbon/human/blinded = allocate(/mob/living/carbon/human)
	holder.get_reagent(REAGENT_ID_CONTAMINANT_METHANOL).affect_blood(blinded, 0, 0.5)
	TEST_ASSERT(blinded.organ_in(O_EYES).damage > 0, "half a unit of methanol damages the eyes")
	var/mob/living/carbon/human/tarred = allocate(/mob/living/carbon/human)
	holder.get_reagent(REAGENT_ID_CONTAMINANT_TAR).affect_blood(tarred, 0, 0.5)
	TEST_ASSERT(tarred.organ_in(O_LUNGS).damage > 0, "tar strains the lungs")
	var/mob/living/carbon/human/mutated = allocate(/mob/living/carbon/human)
	holder.get_reagent(REAGENT_ID_CONTAMINANT_NITROSAMINE).affect_blood(mutated, 0, 0.5)
	TEST_ASSERT(mutated.injury_load(INJURY_CATEGORY_GENETIC) > 0, "nitrosamine damages the cells")
	var/mob/living/carbon/human/lesioned = allocate(/mob/living/carbon/human)
	var/before = lesioned.injury_load(INJURY_CATEGORY_PHYSICAL) + lesioned.injury_load(INJURY_CATEGORY_THERMAL)
	holder.get_reagent(REAGENT_ID_CONTAMINANT_DIOXIN).affect_blood(lesioned, 0, 0.5)
	TEST_ASSERT(lesioned.injury_load(INJURY_CATEGORY_PHYSICAL) + lesioned.injury_load(INJURY_CATEGORY_THERMAL) > before, "dioxin leaves lesions on the skin")
	var/datum/reagent/contaminant/plasticiser/plasticiser = holder.get_reagent(REAGENT_ID_CONTAMINANT_PLASTICISER)
	TEST_ASSERT(plasticiser.factors[STAT_METABOLISM_MULT] < 1, "plasticiser slows the metabolism")

/// A filter takes nothing below a contaminant's floor: a trace of dioxin goes through charcoal, a bigger share is taken down to the floor.
/datum/unit_test/dq_chem_blocks_filter_floor

/datum/unit_test/dq_chem_blocks_filter_floor/Run()
	var/obj/item/chem_filter/charcoal/F = allocate(/obj/item/chem_filter/charcoal, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/target = dq_pur_funnelled_beaker(F)
	var/obj/item/reagent_containers/glass/beaker/bluespace/source = allocate(/obj/item/reagent_containers/glass/beaker/bluespace, test_floor())
	source.reagents.add_reagent(REAGENT_ID_DEXALIN, 100, safety = 1)
	source.reagents.add_reagent(REAGENT_ID_CONTAMINANT_DIOXIN, 0.1, safety = 1)
	source.reagents.trans_to_holder(target.reagents, 1000)
	TEST_ASSERT(dq_blk_near(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_DIOXIN), 0.1, 0.001), "a trace of dioxin is below the floor: charcoal takes none of it")
	var/obj/item/chem_filter/charcoal/F2 = allocate(/obj/item/chem_filter/charcoal, test_floor())
	var/obj/item/reagent_containers/glass/beaker/bluespace/target2 = dq_pur_funnelled_beaker(F2)
	var/obj/item/reagent_containers/glass/beaker/bluespace/source2 = allocate(/obj/item/reagent_containers/glass/beaker/bluespace, test_floor())
	source2.reagents.add_reagent(REAGENT_ID_DEXALIN, 100, safety = 1)
	source2.reagents.add_reagent(REAGENT_ID_CONTAMINANT_DIOXIN, 10, safety = 1)
	var/floor = contaminant_def(REAGENT_ID_CONTAMINANT_DIOXIN).filter_floor
	source2.reagents.trans_to_holder(target2.reagents, 1000)
	var/left = target2.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_DIOXIN)
	TEST_ASSERT(left < 10 && left >= floor * 108 - 0.05, "10u of it is taken, but only down to its floor ([left]u left)")

/// Filters take by tag: paper the solids, charcoal the organics, a sorbent the ionic.
/datum/unit_test/dq_chem_blocks_filters_catch_by_tag

/datum/unit_test/dq_chem_blocks_filters_catch_by_tag/Run()
	var/list/paper = chem_filter_catches(chem_filter_strengths(/obj/item/chem_filter/paper))
	TEST_ASSERT(paper[REAGENT_ID_CONTAMINANT_INERT_FILLER] > 0 && !paper[REAGENT_ID_CONTAMINANT_TAR], "paper takes solids and not tar")
	var/list/charcoal = chem_filter_catches(chem_filter_strengths(/obj/item/chem_filter/charcoal))
	TEST_ASSERT(charcoal[REAGENT_ID_CONTAMINANT_TAR] > 0 && charcoal[REAGENT_ID_CONTAMINANT_DIOXIN] > 0 && charcoal[REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE] > 0, "charcoal takes organics")
	TEST_ASSERT(!charcoal[REAGENT_ID_CONTAMINANT_SALTS] && !charcoal[REAGENT_ID_CONTAMINANT_HEAVY_METAL], "and not salts or metals")

// ---- no purity gate ----

/datum/unit_test/dq_chem_blocks_no_recipe_asks_for_a_grade

/datum/unit_test/dq_chem_blocks_no_recipe_asks_for_a_grade/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker()
	B.reagents.add_reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 40, safety = 1)
	var/datum/xform/X = dq_pur_fill_for(B, /transformation/chem/instant/lipozine, 10)
	B.reagents.handle_reactions()
	TEST_ASSERT(B.reagents.purity() < PURITY_STANDARD, "the mixture is Crude")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_LIPOZINE) > 0, "and a recipe that used to want Pharma goes: [X.name]")

#endif

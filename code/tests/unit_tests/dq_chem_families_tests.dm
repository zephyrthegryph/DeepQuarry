// The chemistry families converted to block structures (doc/rewrite/proposals/chemistry_recipes.md; the machinery: code/domains/world_model/reagents/blocks/, the
// declarations: code/content/reagents/blocks/): every declared chemical has a tier and is made by the route its structure gives, the staples are reachable in one or
// two steps without a solid catalyst, the dirty shortcuts leave their traces, the process chemicals do their process, the groups clash on contact (in a beaker and in the
// stomach, never in the blood), and the precursors are stocked.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The routes (and recipes) that make `product`, as rules.
/datum/unit_test/proc/dq_fam_makers(product)
	var/list/found = xform_makers_of(MEDIUM_REAGENTS, REGIME_INSTANT, product)
	return found ? found : list()

/// Is there a generated route that makes `product` and takes all of `takes` (reagent ids), of this kind (null: any)?
/datum/unit_test/proc/dq_fam_route(product, list/takes, kind = null)
	for(var/datum/xform/X as anything in dq_fam_makers(product))
		var/datum/chem_route/R = chem_route_of(X)
		if(!R || (kind && R.kind != kind))
			continue
		var/matched = TRUE
		for(var/take_id in takes)
			if(!(take_id in R.takes) && !(take_id in R.catalysts))
				matched = FALSE
		if(matched)
			return R
	return null

/// The base of the chemistry: what a chemist has before any step (the dispenser, the toolkit that is mixed or stocked, the stocked precursors).
/datum/unit_test/proc/dq_fam_base()
	return list(REAGENT_ID_CARBON, REAGENT_ID_CHLORINE, REAGENT_ID_FLUORINE, REAGENT_ID_HYDROGEN, REAGENT_ID_OXYGEN, REAGENT_ID_NITROGEN, REAGENT_ID_PHOSPHORUS, REAGENT_ID_SULFUR, \
		REAGENT_ID_POTASSIUM, REAGENT_ID_SODIUM, REAGENT_ID_LITHIUM, REAGENT_ID_CALCIUM, REAGENT_ID_IRON, REAGENT_ID_COPPER, REAGENT_ID_ALUMINIUM, REAGENT_ID_SILICON, \
		REAGENT_ID_WATER, REAGENT_ID_ETHANOL, REAGENT_ID_SUGAR, REAGENT_ID_SACID, REAGENT_ID_PHORON, REAGENT_ID_BORON11, REAGENT_ID_FUEL, REAGENT_ID_ENZYME, REAGENT_ID_YEAST, \
		REAGENT_ID_AMMONIA, REAGENT_ID_LYE, REAGENT_ID_DIETHYLAMINE, REAGENT_ID_CYANIDE, REAGENT_ID_CALCIUMCARBONATE, REAGENT_ID_FOAMINGAGENT, REAGENT_ID_SAND, \
		REAGENT_ID_PHENOL, REAGENT_ID_SALICYLICACID, REAGENT_ID_WOODALDEHYDE, REAGENT_ID_NITRICACID, REAGENT_ID_HYDROCHLORIC, REAGENT_ID_PHOSPHORICACID, REAGENT_ID_ACETICACID, \
		REAGENT_ID_BLEACH, REAGENT_ID_SODAASH, REAGENT_ID_GLYCEROL, REAGENT_ID_SILICATE, REAGENT_ID_FATTYACID, REAGENT_ID_PYRIDINE, REAGENT_ID_ALKALOID, REAGENT_ID_STEROL, REAGENT_ID_AMINOACID)

/// How many steps from the base each chemical is: id => depth (0 = the base). A step is a rule whose reactants are all known; the solid-catalyst routes are left out
/// (`clean_only` also leaves out the process chemicals and the one-pot shortcuts: the clean routes only), and so are the clashes.
/datum/unit_test/proc/dq_fam_depths(clean_only = FALSE)
	var/list/depth = list()
	for(var/id in dq_fam_base())
		depth[id] = 0
	var/list/rules = list()
	for(var/datum/xform/X as anything in GLOB.xform_rules)
		if(X.medium != MEDIUM_REAGENTS || X.regime != REGIME_INSTANT || !X.result)
			continue
		var/datum/chem_route/R = chem_route_of(X)
		if(R)
			if(R.kind == CHEM_CATALYST_SOLID_METAL || R.kind == CHEM_CATALYST_SOLID_ACID || R.kind == CHEM_CATALYST_CONTACT)
				continue
			if(clean_only && R.kind == CHEM_CATALYST_AGENT)
				continue
		else if(clean_only && findtext("[X.rule_type]", "shortcut_"))
			continue
		rules += X
	var/changed = TRUE
	var/passes = 0
	while(changed && passes < 14)
		changed = FALSE
		passes++
		for(var/datum/xform/X as anything in rules)
			var/worst = 0
			var/known = TRUE
			for(var/take_id in X.reagent_takes)
				if(isnull(depth[take_id]))
					known = FALSE
					break
				worst = max(worst, depth[take_id])
			for(var/catalyst_id in X.reagent_catalysts)
				if(isnull(depth[catalyst_id]))
					known = FALSE
					break
				worst = max(worst, depth[catalyst_id])
			if(!known)
				continue
			if(isnull(depth[X.result]) || worst + 1 < depth[X.result])
				depth[X.result] = worst + 1
				changed = TRUE
	return depth

// ---- the declarations ----

/// Every chemistry reagent that has a structure and is not a contaminant, a metal or a base has a tier; a staple, a standard and an advanced one are the three that exist.
/datum/unit_test/dq_chem_families_declared_chemicals_have_a_tier

/datum/unit_test/dq_chem_families_declared_chemicals_have_a_tier/Run()
	var/list/reagents = SSchemistry.ready().chemical_reagents
	var/counted = 0
	for(var/id in GLOB.chem_declared_structures)
		if(istype(reagents[id], /datum/reagent/contaminant))
			continue
		var/datum/chem_structure/S = GLOB.chem_declared_structures[id]
		if(S.cation && !S.anion && !S.is_organic())
			continue // a metal
		var/tier = chem_tier_of(id)
		TEST_ASSERT_NOTNULL(tier, "[id] has a tier")
		TEST_ASSERT(tier >= CHEM_TIER_STAPLE && tier <= CHEM_TIER_ADVANCED, "[id] is tier 1 to 3 (tier 4 is not converted: [tier])")
		counted++
	TEST_ASSERT(counted > 100, "the declared chemistry was counted ([counted])")
	TEST_ASSERT_NULL(text2path("/transformation/chem/instant/inaprovaline"), "the element mix of inaprovaline is gone")
	for(var/gone in list("bicaridine", "dylovene", "dexalin", "paracetamol", "sterilizine", "silicate", "lube", "tricordrazine", "hyronalin", "arithrazine", "lexorin", "mindbreaker", "sodiumchloride", "prussian_blue", "coolant"))
		TEST_ASSERT_NULL(text2path("/transformation/chem/instant/[gone]"), "the old [gone] recipe is gone")

/// The clean route of each converted chemical: what it is made from, by which process.
/datum/unit_test/dq_chem_families_clean_routes_exist

/datum/unit_test/dq_chem_families_clean_routes_exist/Run()
	var/list/rows = list(
		// tier 1
		list(REAGENT_ID_INAPROVALINE, list(REAGENT_ID_WOODALDEHYDE, REAGENT_ID_AMMONIA, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_BICARIDINE, list(REAGENT_ID_NITROSALICYLIC, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_NITROSALICYLIC, list(REAGENT_ID_SALICYLICACID, REAGENT_ID_NITRICACID, REAGENT_ID_SACID), CHEM_CATALYST_ACID),
		list(REAGENT_ID_CHLOROHYDRIN, list(REAGENT_ID_GLYCEROL, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_ANTITOXIN, list(REAGENT_ID_CHLOROHYDRIN, REAGENT_ID_SULFUR), CHEM_CATALYST_NONE),
		list(REAGENT_ID_DEXALIN, list(REAGENT_ID_PHORON, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_PARACETAMOL, list(REAGENT_ID_ACETICACID, REAGENT_ID_INAPROVALINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_STERILIZINE, list(REAGENT_ID_PHENOL, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_LUBE, list(REAGENT_ID_KELOTANE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_SILICATE, list(REAGENT_ID_SAND, REAGENT_ID_LYE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_COOLANT, list(REAGENT_ID_GLYCEROL, REAGENT_ID_HYDROGEN), null),
		list(REAGENT_ID_FERTILIZER, list(REAGENT_ID_AMMONIA, REAGENT_ID_PHOSPHORICACID), CHEM_CATALYST_NONE),
		list(REAGENT_ID_SODIUMCHLORIDE, list(REAGENT_ID_LYE, REAGENT_ID_HYDROCHLORIC), CHEM_CATALYST_NONE),
		list(REAGENT_ID_POTASSIUMCHLORIDE, list(REAGENT_ID_SODIUMCHLORIDE, REAGENT_ID_POTASSIUM), CHEM_CATALYST_NONE),
		list(REAGENT_ID_DRYAGENT, list(REAGENT_ID_CALCIUMCARBONATE, REAGENT_ID_HYDROCHLORIC), CHEM_CATALYST_NONE),
		list(REAGENT_ID_IRONSALT, list(REAGENT_ID_SACID, REAGENT_ID_IRON), CHEM_CATALYST_NONE),
		list(REAGENT_ID_ACETICACID, list(REAGENT_ID_ETHANOL, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		// tier 2
		list(REAGENT_ID_DEXALINP, list(REAGENT_ID_DEXALIN, REAGENT_ID_IRONSALT), CHEM_CATALYST_NONE),
		list(REAGENT_ID_TRICORDRAZINE, list(REAGENT_ID_CARTHATOLINE, REAGENT_ID_INAPROVALINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_TRAMADOL, list(REAGENT_ID_PARACETAMOL, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_LEPORAZINE, list(REAGENT_ID_ACETICACID, REAGENT_ID_SALICYLICACID), CHEM_CATALYST_ACID),
		list(REAGENT_ID_HYRONALIN, list(REAGENT_ID_CHLOROHYDRIN, REAGENT_ID_AMMONIA), CHEM_CATALYST_NONE),
		list(REAGENT_ID_CHLORALHYDRATE, list(REAGENT_ID_ETHANOL, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_STOXIN, list(REAGENT_ID_ACETICACID, REAGENT_ID_CHLORALHYDRATE), CHEM_CATALYST_ACID),
		list(REAGENT_ID_CRYOXADONE, list(REAGENT_ID_DEXALIN, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_MYELAMINE, list(REAGENT_ID_BICARIDINE, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_HYPERZINE, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_LUMINOL, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_PLANTBGONE, list(REAGENT_ID_ACETICACID, REAGENT_ID_STERILIZINE), CHEM_CATALYST_ACID),
		list(REAGENT_ID_CONDENSEDCAPSAICIN, list(REAGENT_ID_FATTYACID, REAGENT_ID_INAPROVALINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_FLUOROSURFACTANT, list(REAGENT_ID_FATTYACID, REAGENT_ID_FLUORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_ETHYLREDOXRAZINE, list(REAGENT_ID_PYRIDINE, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_ADRANOL, list(REAGENT_ID_PYRIDINE, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_ADRENALINE, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_PRUSSIANBLUE, list(REAGENT_ID_IRONSALT, REAGENT_ID_CYANIDE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_SPACEACILLIN, list(REAGENT_ID_AMINOACID, REAGENT_ID_INAPROVALINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_SYNAPTIZINE, list(REAGENT_ID_PYRIDONE, REAGENT_ID_AMMONIA, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		// tier 3
		list(REAGENT_ID_ARITHRAZINE, list(REAGENT_ID_HYRONALIN, REAGENT_ID_PHOSPHORUS), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_CARTHATOLINE, list(REAGENT_ID_ANTITOXIN, REAGENT_ID_STRONGOXIDISER), CHEM_CATALYST_AGENT),
		list(REAGENT_ID_MUTAGEN, list(REAGENT_ID_DIETHYLAMINE, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_CLONEXADONE, list(REAGENT_ID_CRYOXADONE, REAGENT_ID_LYE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_CHLOROPHORON, list(REAGENT_ID_PHORON, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_LEXORIN, list(REAGENT_ID_CHLOROPHORON, REAGENT_ID_AMMONIA), CHEM_CATALYST_NONE),
		list(REAGENT_ID_POTASSIUMCHLOROPHORIDE, list(REAGENT_ID_CHLOROPHORON, REAGENT_ID_POTASSIUMCHLORIDE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_NITROGLYCERIN, list(REAGENT_ID_GLYCEROL, REAGENT_ID_NITRICACID, REAGENT_ID_SACID), CHEM_CATALYST_ACID),
		list(REAGENT_ID_PERIDAXON, list(REAGENT_ID_BICARIDINE, REAGENT_ID_CLONEXADONE), CHEM_CATALYST_ACID),
		list(REAGENT_ID_SIZEOXADONE, list(REAGENT_ID_TRAMADOL, REAGENT_ID_LYE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_MACROCILLIN, list(REAGENT_ID_SIZEOXADONE, REAGENT_ID_AMMONIA, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_MICROCILLIN, list(REAGENT_ID_SIZEOXADONE, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_NORMALCILLIN, list(REAGENT_ID_SIZEOXADONE, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_COROPHIZINE, list(REAGENT_ID_ETHYLREDOXRAZINE, REAGENT_ID_FLUORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_ALKYSINE, list(REAGENT_ID_SYNAPTIZINE, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_IMIDAZOLINE, list(REAGENT_ID_ALKYSINE, REAGENT_ID_AMMONIA), CHEM_CATALYST_NONE),
		list(REAGENT_ID_PANACILLIN, list(REAGENT_ID_HALOSPACEACILLIN, REAGENT_ID_SULFUR), CHEM_CATALYST_NONE),
		list(REAGENT_ID_BLISS, list(REAGENT_ID_ALKALOID, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_CRYPTOBIOLIN, list(REAGENT_ID_BLISS, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_OXYCODONE, list(REAGENT_ID_CRYPTOBIOLIN, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_PSILOCYBIN, list(REAGENT_ID_BLISS, REAGENT_ID_PHOSPHORUS), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_PAROXETINE, list(REAGENT_ID_ALKALOID, REAGENT_ID_FLUORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_CITALOPRAM, list(REAGENT_ID_PAROXETINE, REAGENT_ID_CYANIDE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_TERCOZOLAM, list(REAGENT_ID_PAROXETINE, REAGENT_ID_SULFUR), CHEM_CATALYST_NONE),
		list(REAGENT_ID_MINDBREAKER, list(REAGENT_ID_ALKALOIDACID, REAGENT_ID_DIETHYLAMINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_METHYLPHENIDATE, list(REAGENT_ID_SALICYLICACID, REAGENT_ID_ADRANOL), CHEM_CATALYST_ACID),
		list(REAGENT_ID_GYNOROVIR, list(REAGENT_ID_STEROL, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_ANDROROVIR, list(REAGENT_ID_GYNOROVIR, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_ANDROGYNOROVIR, list(REAGENT_ID_ANDROROVIR, REAGENT_ID_OXYGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_IMMUNOSUPRIZINE, list(REAGENT_ID_ANDROROVIR, REAGENT_ID_OXYGEN), CHEM_CATALYST_ENZYME),
		list(REAGENT_ID_AMORPHOROVIR, list(REAGENT_ID_STEROL, REAGENT_ID_HYDROGEN), CHEM_CATALYST_NONE),
		list(REAGENT_ID_LIPOZILASE, list(REAGENT_ID_STEROL, REAGENT_ID_STRONGOXIDISER), CHEM_CATALYST_AGENT),
		list(REAGENT_ID_LIPOSTIPO, list(REAGENT_ID_STEROL, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_OSTEODAXON, list(REAGENT_ID_AMINOACID, REAGENT_ID_DRYAGENT), CHEM_CATALYST_NONE),
		list(REAGENT_ID_CORDRADAXON, list(REAGENT_ID_AMINOACID, REAGENT_ID_POTASSIUMCHLORIDE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_HEPANEPHRODAXON, list(REAGENT_ID_AMINOACID, REAGENT_ID_LITHIUMSALT), CHEM_CATALYST_NONE),
		list(REAGENT_ID_GASTIRODAXON, list(REAGENT_ID_AMINOACID, REAGENT_ID_LYE), CHEM_CATALYST_NONE),
		list(REAGENT_ID_RESPIRODAXON, list(REAGENT_ID_AMINOACID, REAGENT_ID_DEXALINP), CHEM_CATALYST_ACID),
		list(REAGENT_ID_BULLVALENE, list(REAGENT_ID_DERMALINE, REAGENT_ID_COPPERSALT), CHEM_CATALYST_NONE),
		list(REAGENT_ID_IMPEDREZENE, list(REAGENT_ID_CRYPTOBIOLIN, REAGENT_ID_CHLORINE), CHEM_CATALYST_NONE),
	)
	var/missing = list()
	for(var/list/row in rows)
		if(!dq_fam_route(row[1], row[2], row[3]))
			missing += "[row[1]] from [jointext(row[2], "+")] ([row[3] || "any"])"
	TEST_ASSERT_EQUAL(length(missing), 0, "no clean route for: [jointext(missing, "; ")]")

/// The staples are reached in one or two steps from the base, without a solid catalyst and without a process chemical.
/datum/unit_test/dq_chem_families_staples_are_one_or_two_steps

/datum/unit_test/dq_chem_families_staples_are_one_or_two_steps/Run()
	var/list/depth = dq_fam_depths(TRUE)
	var/list/too_far = list()
	for(var/id in list(REAGENT_ID_INAPROVALINE, REAGENT_ID_BICARIDINE, REAGENT_ID_KELOTANE, REAGENT_ID_ANTITOXIN, REAGENT_ID_DEXALIN, REAGENT_ID_PARACETAMOL, \
			REAGENT_ID_STERILIZINE, REAGENT_ID_LUBE, REAGENT_ID_COOLANT, REAGENT_ID_FERTILIZER, REAGENT_ID_SODIUMCHLORIDE, REAGENT_ID_SILICATE, REAGENT_ID_POTASSIUMCHLORIDE))
		var/steps = depth[id]
		if(isnull(steps) || steps > 3) // a step is a rule: the precursors and the toolkit that is mixed (ammonia, lye) are the base, the second step of paracetamol is a condensation of a staple
			too_far += "[id] ([isnull(steps) ? "unreachable" : steps])"
	TEST_ASSERT_EQUAL(length(too_far), 0, "staples more than a step or two from the stock: [jointext(too_far, ", ")]")
	TEST_ASSERT_EQUAL(depth[REAGENT_ID_DEXALIN], 1, "dexalin is one step from phoron")
	TEST_ASSERT_EQUAL(depth[REAGENT_ID_INAPROVALINE], 1, "inaprovaline is one step from wood aldehyde")
	TEST_ASSERT_EQUAL(depth[REAGENT_ID_ANTITOXIN], 2, "dylovene is two steps from glycerol")
	TEST_ASSERT_EQUAL(depth[REAGENT_ID_BICARIDINE], 2, "bicaridine is two steps from salicylic acid")

/// Every converted chemical is reachable at all, the process chemicals and the stock being allowed: nothing is declared that no route can make.
/datum/unit_test/dq_chem_families_everything_is_reachable

/datum/unit_test/dq_chem_families_everything_is_reachable/Run()
	var/list/depth = dq_fam_depths(FALSE)
	var/list/stranded = list()
	var/list/reagents = SSchemistry.ready().chemical_reagents
	for(var/id in GLOB.chem_tiers)
		if(isnull(depth[id]) && reagents[id])
			stranded += id
	TEST_ASSERT_EQUAL(length(stranded), 0, "no route reaches: [jointext(stranded, ", ")]")

// ---- the building blocks ----

/// The new reagents are real: a structure, a boiling point, a place in the book.
/datum/unit_test/dq_chem_families_new_reagents_are_whole

/datum/unit_test/dq_chem_families_new_reagents_are_whole/Run()
	var/list/reagents = SSchemistry.ready().chemical_reagents
	for(var/id in list(REAGENT_ID_HYDROCHLORIC, REAGENT_ID_NITRICACID, REAGENT_ID_PHOSPHORICACID, REAGENT_ID_ACETICACID, REAGENT_ID_BLEACH, REAGENT_ID_SODAASH, REAGENT_ID_PHENOL, \
			REAGENT_ID_WOODALDEHYDE, REAGENT_ID_SALICYLICACID, REAGENT_ID_FATTYACID, REAGENT_ID_PYRIDINE, REAGENT_ID_ALKALOID, REAGENT_ID_STEROL, REAGENT_ID_AMINOACID, \
			REAGENT_ID_IRONSALT, REAGENT_ID_COPPERSALT, REAGENT_ID_LITHIUMSALT, REAGENT_ID_SAND, REAGENT_ID_CHLOROHYDRIN, REAGENT_ID_NITROSALICYLIC, REAGENT_ID_CHLOROPHORON, \
			REAGENT_ID_ALKALOIDACID, REAGENT_ID_PYRIDONE, REAGENT_ID_HALOSPACEACILLIN))
		TEST_ASSERT_NOTNULL(reagents[id], "[id] is a reagent")
		TEST_ASSERT_NOTNULL(chem_structure_of(id), "[id] has a structure")
		var/datum/reagent/R = reagents[id]
		TEST_ASSERT(R.boiling_point_k() > 0, "[id] has a boiling point")
	for(var/id in list(REAGENT_ID_HYDRIDE, REAGENT_ID_STRONGOXIDISER, REAGENT_ID_NITRATINGMIX, REAGENT_ID_CHLORINATINGAGENT, REAGENT_ID_COUPLINGAGENT, REAGENT_ID_CAUSTICDIGEST, REAGENT_ID_SCAVENGERRESIN))
		TEST_ASSERT_NOTNULL(reagents[id], "the process chemical [id] is a reagent")
		TEST_ASSERT_NOTNULL(chem_tier_of(id), "and has a tier")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_HYDROCHLORIC).formula(), "HCl", "hydrochloric acid is HCl")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_PHOSPHORICACID).formula(), "H3PO4", "phosphoric acid is H3PO4")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_BLEACH).class_name(), "salt", "bleach is a salt")
	TEST_ASSERT(chem_structure_of(REAGENT_ID_SODAASH).is_base(), "soda ash is a base")
	TEST_ASSERT_EQUAL(chem_structure_of(REAGENT_ID_DEXALINP).formula(), "FeOPh2", "a metal-bound lattice carries its metal in its formula")
	TEST_ASSERT(length(chem_agents_of(REAGENT_ID_HYDRIDE)) == 2, "the hydride reduces and aminates")
	TEST_ASSERT(length(chem_agents_of(REAGENT_ID_BLEACH)) == 2, "bleach oxidises and halogenates")

/// The silicate a sand and hot lye make (the engine gap the burn medicines left), and the lube two silanols make (polymerise, chemistry side).
/datum/unit_test/dq_chem_families_sand_in_hot_lye_and_silicone_chains

/datum/unit_test/dq_chem_families_sand_in_hot_lye_and_silicone_chains/Run()
	var/obj/item/reagent_containers/glass/beaker/cold = dq_blk_beaker(20)
	cold.reagents.add_reagent(REAGENT_ID_SAND, 10, safety = 1)
	cold.reagents.add_reagent(REAGENT_ID_LYE, 10)
	TEST_ASSERT_EQUAL(cold.reagents.get_reagent_amount(REAGENT_ID_SILICATE), 0, "sand does not dissolve in cold lye")
	var/obj/item/reagent_containers/glass/beaker/hot = dq_blk_beaker(95)
	hot.reagents.add_reagent(REAGENT_ID_SAND, 10, safety = 1)
	hot.reagents.add_reagent(REAGENT_ID_LYE, 10)
	TEST_ASSERT(dq_blk_near(hot.reagents.get_reagent_amount(REAGENT_ID_SILICATE), 10), "in hot lye it goes into solution as silicate ([hot.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(hot.reagents.get_reagent_amount(REAGENT_ID_WATER), 10), "and water")
	var/obj/item/reagent_containers/glass/beaker/chain = dq_blk_beaker(90)
	chain.reagents.add_reagent(REAGENT_ID_KELOTANE, 20)
	TEST_ASSERT(dq_blk_near(chain.reagents.get_reagent_amount(REAGENT_ID_LUBE), 10), "two silanols join into a siloxane chain: lube ([chain.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(chain.reagents.get_reagent_amount(REAGENT_ID_WATER), 10), "giving up water")
	var/datum/chem_process/polymerise = chem_process_of(CHEM_PROCESS_POLYMERISE)
	TEST_ASSERT(!polymerise.reserved, "polymerise makes the chemistry-side products")

/// The cyanide arm of substitution: a halide swapped for a nitrile, with cyanide left behind.
/datum/unit_test/dq_chem_families_cyanide_arm_of_substitute

/datum/unit_test/dq_chem_families_cyanide_arm_of_substitute/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker(55)
	B.reagents.add_reagent(REAGENT_ID_PAROXETINE, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_CYANIDE, 10)
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CITALOPRAM), 10), "paroxetine and cyanide make citalopram ([B.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_POTASSIUMCHLORIDE), 10), "and potassium chloride")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_CYANIDE) > 0.2, "with cyanide traces left in the batch ([B.reagents.get_reagent_amount(REAGENT_ID_CYANIDE)]u)")

/// Displacement: an acid dissolves a metal, two salts swap their ions, a metal binds to a medicine out of a base or a salt.
/datum/unit_test/dq_chem_families_displacement_reaches_the_organometallics

/datum/unit_test/dq_chem_families_displacement_reaches_the_organometallics/Run()
	var/obj/item/reagent_containers/glass/beaker/salt = dq_blk_beaker(20)
	salt.reagents.add_reagent(REAGENT_ID_SACID, 10, safety = 1)
	salt.reagents.add_reagent(REAGENT_ID_IRON, 10)
	TEST_ASSERT(dq_blk_near(salt.reagents.get_reagent_amount(REAGENT_ID_IRONSALT), 10), "sulphuric acid dissolves iron into its salt ([salt.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(salt.reagents.get_reagent_amount(REAGENT_ID_HYDROGEN), 10), "and hydrogen")
	var/obj/item/reagent_containers/glass/beaker/plus = dq_blk_beaker(20)
	plus.reagents.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	plus.reagents.add_reagent(REAGENT_ID_IRONSALT, 10)
	TEST_ASSERT(dq_blk_near(plus.reagents.get_reagent_amount(REAGENT_ID_DEXALINP), 10), "iron binds to dexalin: dexalin plus ([plus.reagents.get_reagents()])")
	var/obj/item/reagent_containers/glass/beaker/clone = dq_blk_beaker(20)
	clone.reagents.add_reagent(REAGENT_ID_CRYOXADONE, 10, safety = 1)
	clone.reagents.add_reagent(REAGENT_ID_LYE, 10)
	TEST_ASSERT(dq_blk_near(clone.reagents.get_reagent_amount(REAGENT_ID_CLONEXADONE), 10), "sodium binds to cryoxadone out of lye: clonexadone ([clone.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(clone.reagents.get_reagent_amount(REAGENT_ID_WATER), 10), "and water")
	var/obj/item/reagent_containers/glass/beaker/blue = dq_blk_beaker(20)
	blue.reagents.add_reagent(REAGENT_ID_IRONSALT, 10, safety = 1)
	blue.reagents.add_reagent(REAGENT_ID_CYANIDE, 10)
	TEST_ASSERT(dq_blk_near(blue.reagents.get_reagent_amount(REAGENT_ID_PRUSSIANBLUE), 10), "two salts swap their ions: iron salt and cyanide make prussian blue ([blue.reagents.get_reagents()])")
	var/obj/item/reagent_containers/glass/beaker/kcl = dq_blk_beaker(20)
	kcl.reagents.add_reagent(REAGENT_ID_SODIUMCHLORIDE, 10, safety = 1)
	kcl.reagents.add_reagent(REAGENT_ID_POTASSIUM, 10)
	TEST_ASSERT(dq_blk_near(kcl.reagents.get_reagent_amount(REAGENT_ID_POTASSIUMCHLORIDE), 10), "potassium takes the place of sodium in table salt ([kcl.reagents.get_reagents()])")

/// A clip-on electrode pair is what an electrolysis needs besides a plate that is on.
/datum/unit_test/dq_chem_families_electrolysis_needs_the_electrode_pair

/datum/unit_test/dq_chem_families_electrolysis_needs_the_electrode_pair/Run()
	var/obj/machinery/chem_hot_plate/plate = allocate(/obj/machinery/chem_hot_plate, test_floor())
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.inherit_heat(T20C)
	B.forceMove(plate)
	plate.held_container = B
	plate.set_heating(TRUE)
	B.reagents.add_reagent(REAGENT_ID_SODIUMCHLORIDE, 10)
	TEST_ASSERT(!B.reagents.current_flows(), "a plate that is on is not enough: no electrode pair")
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_SODIUM), 0, "so the salt is left as it was")
	B.electrode = allocate(/obj/item/chem_electrode, B)
	TEST_ASSERT(B.reagents.current_flows(), "with the pair clipped on and the plate on a current flows")
	B.reagents.handle_reactions()
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_SODIUM), 10), "and table salt is split into sodium ([B.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CHLORINE), 10), "and chlorine")
	plate.set_heating(FALSE)
	TEST_ASSERT(!B.reagents.current_flows(), "and with the plate off it stops")
	TEST_ASSERT_NOTNULL(text2path("/datum/design_techweb/chem_electrode"), "the lathe can make the pair")

// ---- the process chemicals and the dirty shortcuts ----

/// One process chemical poured in does its process; each leaves its own residue.
/datum/unit_test/dq_chem_families_process_chemicals_leave_their_traces

/datum/unit_test/dq_chem_families_process_chemicals_leave_their_traces/Run()
	// A hydride and ammonia make an amine of an aldehyde in one pot: inaprovaline, with base residue and boron salts.
	var/obj/item/reagent_containers/glass/beaker/amination = dq_blk_beaker(40)
	amination.reagents.add_reagent(REAGENT_ID_WOODALDEHYDE, 10, safety = 1)
	amination.reagents.add_reagent(REAGENT_ID_AMMONIA, 10, safety = 1)
	amination.reagents.add_reagent(REAGENT_ID_HYDRIDE, 10)
	TEST_ASSERT(amination.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) > 9, "a hydride shortcut makes inaprovaline ([amination.reagents.get_reagents()])")
	TEST_ASSERT(amination.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_BASE_RESIDUE) > 0.5, "and leaves base residue")
	TEST_ASSERT(amination.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS) > 0.3, "and boron salts")
	TEST_ASSERT(amination.reagents.purity() < 1, "so the batch is not clean")
	// The clean route: the same aldehyde with ammonia and hydrogen.
	var/obj/item/reagent_containers/glass/beaker/clean = dq_blk_beaker(55)
	clean.reagents.add_reagent(REAGENT_ID_WOODALDEHYDE, 10, safety = 1)
	clean.reagents.add_reagent(REAGENT_ID_AMMONIA, 10, safety = 1)
	clean.reagents.add_reagent(REAGENT_ID_HYDROGEN, 10)
	TEST_ASSERT(clean.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) > 7, "ammonia and hydrogen make it too, with no process chemical ([clean.reagents.get_reagents()])")
	// Bleach on phoron is dexalin in one step, leaving a reactive impurity and a halide.
	var/obj/item/reagent_containers/glass/beaker/phoron = dq_blk_beaker(20)
	phoron.reagents.add_reagent(REAGENT_ID_PHORON, 10, safety = 1)
	phoron.reagents.add_reagent(REAGENT_ID_BLEACH, 10)
	TEST_ASSERT(dq_blk_near(phoron.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 10, 1), "phoron and bleach make dexalin ([phoron.reagents.get_reagents()])")
	TEST_ASSERT(phoron.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_REACTIVE) > 0.2, "with a reactive impurity")
	// Bleach on a phenol, warm, is sterilizine and dioxin.
	var/obj/item/reagent_containers/glass/beaker/phenol = dq_blk_beaker(40)
	phenol.reagents.add_reagent(REAGENT_ID_PHENOL, 10, safety = 1)
	phenol.reagents.add_reagent(REAGENT_ID_BLEACH, 10)
	TEST_ASSERT(phenol.reagents.get_reagent_amount(REAGENT_ID_STERILIZINE) > 9, "phenol and bleach make sterilizine ([phenol.reagents.get_reagents()])")
	TEST_ASSERT(phenol.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_DIOXIN) > 0.2, "and, warm, dioxin")
	// A strong oxidiser takes dylovene all the way to carthatoline and leaves heavy metals.
	var/obj/item/reagent_containers/glass/beaker/oxidised = dq_blk_beaker(40)
	oxidised.reagents.add_reagent(REAGENT_ID_ANTITOXIN, 10, safety = 1)
	oxidised.reagents.add_reagent(REAGENT_ID_STRONGOXIDISER, 10)
	TEST_ASSERT(oxidised.reagents.get_reagent_amount(REAGENT_ID_CARTHATOLINE) > 5, "a strong oxidiser makes carthatoline of dylovene ([oxidised.reagents.get_reagents()])")
	TEST_ASSERT(oxidised.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL) > 0.3, "and leaves heavy metals")
	// A nitrating mix nitrates salicylic acid with no nitric acid and no acid catalyst, and a hydride then reduces it: the one-pot bicaridine.
	var/obj/item/reagent_containers/glass/beaker/nitrated = dq_blk_beaker(40)
	nitrated.reagents.add_reagent(REAGENT_ID_SALICYLICACID, 10, safety = 1)
	nitrated.reagents.add_reagent(REAGENT_ID_NITRATINGMIX, 10)
	TEST_ASSERT(nitrated.reagents.get_reagent_amount(REAGENT_ID_NITROSALICYLIC) > 5, "a nitrating mix nitrates salicylic acid ([nitrated.reagents.get_reagents()])")
	TEST_ASSERT(nitrated.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ACID_RESIDUE) > 0.3, "leaving acid residue")
	// A coupling agent joins two chemicals in a warm bath that has water in it.
	var/obj/item/reagent_containers/glass/beaker/coupled = dq_blk_beaker(40)
	coupled.reagents.add_reagent(REAGENT_ID_CARTHATOLINE, 10, safety = 1)
	coupled.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 10, safety = 1)
	coupled.reagents.add_reagent(REAGENT_ID_WATER, 5, safety = 1)
	coupled.reagents.add_reagent(REAGENT_ID_COUPLINGAGENT, 10)
	TEST_ASSERT(coupled.reagents.get_reagent_amount(REAGENT_ID_TRICORDRAZINE) > 5, "a coupling agent makes tricordrazine of carthatoline and inaprovaline, water or no water ([coupled.reagents.get_reagents()])")
	TEST_ASSERT(coupled.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE) > 0.3, "leaving organic residue")
	// Yeast ferments sugar, and leaves endotoxin and methanol when the bath is warm.
	var/obj/item/reagent_containers/glass/beaker/yeast = dq_blk_beaker(36)
	yeast.reagents.add_reagent(REAGENT_ID_SUGAR, 10, safety = 1)
	yeast.reagents.add_reagent(REAGENT_ID_YEAST, 10)
	TEST_ASSERT(yeast.reagents.get_reagent_amount(REAGENT_ID_ETHANOL) > 7, "yeast makes ethanol of sugar ([yeast.reagents.get_reagents()])")
	TEST_ASSERT(yeast.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_METHANOL) > 0.5, "and methanol when it is warm")

/// The one-pot shortcuts of the staples: they always work and leave trace-potent contaminants.
/datum/unit_test/dq_chem_families_dirty_shortcuts_leave_traces

/datum/unit_test/dq_chem_families_dirty_shortcuts_leave_traces/Run()
	var/obj/item/reagent_containers/glass/beaker/bicaridine = dq_blk_beaker(55)
	bicaridine.reagents.add_reagent(REAGENT_ID_SALICYLICACID, 10, safety = 1)
	bicaridine.reagents.add_reagent(REAGENT_ID_NITRATINGMIX, 10, safety = 1)
	bicaridine.reagents.add_reagent(REAGENT_ID_HYDRIDE, 10)
	TEST_ASSERT(dq_blk_near(bicaridine.reagents.get_reagent_amount(REAGENT_ID_BICARIDINE), 10, 1), "bicaridine in one pot ([bicaridine.reagents.get_reagents()])")
	TEST_ASSERT(bicaridine.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_NITROSAMINE) > 0.3, "leaves nitrosamine")
	TEST_ASSERT(bicaridine.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ACID_RESIDUE) > 0.5, "and acid residue")
	var/obj/item/reagent_containers/glass/beaker/kelotane = dq_blk_beaker(20)
	kelotane.reagents.add_reagent(REAGENT_ID_SILICON, 10, safety = 1)
	kelotane.reagents.add_reagent(REAGENT_ID_LYE, 10)
	TEST_ASSERT(dq_blk_near(kelotane.reagents.get_reagent_amount(REAGENT_ID_KELOTANE), 10, 1), "kelotane from silicon and lye ([kelotane.reagents.get_reagents()])")
	TEST_ASSERT(kelotane.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_BASE_RESIDUE) > 2, "leaves the base un-neutralised")
	var/obj/item/reagent_containers/glass/beaker/dylovene = dq_blk_beaker(55)
	dylovene.reagents.add_reagent(REAGENT_ID_GLYCEROL, 10, safety = 1)
	dylovene.reagents.add_reagent(REAGENT_ID_SULFUR, 10, safety = 1)
	dylovene.reagents.add_reagent(REAGENT_ID_CHLORINATINGAGENT, 10)
	TEST_ASSERT(dq_blk_near(dylovene.reagents.get_reagent_amount(REAGENT_ID_ANTITOXIN), 10, 1), "dylovene in one pot ([dylovene.reagents.get_reagents()])")
	TEST_ASSERT(dylovene.reagents.get_reagent_amount(REAGENT_ID_HYDROCHLORIC) > 0.5 && dylovene.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SULFUR) > 0.5, "leaves hydrochloric acid and sulfur")
	var/obj/item/reagent_containers/glass/beaker/paracetamol = dq_blk_beaker(95)
	paracetamol.reagents.add_reagent(REAGENT_ID_PHENOL, 10, safety = 1)
	paracetamol.reagents.add_reagent(REAGENT_ID_NITRATINGMIX, 10, safety = 1)
	paracetamol.reagents.add_reagent(REAGENT_ID_ACETICACID, 10, safety = 1)
	paracetamol.reagents.add_reagent(REAGENT_ID_HYDRIDE, 10)
	TEST_ASSERT(dq_blk_near(paracetamol.reagents.get_reagent_amount(REAGENT_ID_PARACETAMOL), 10, 1), "paracetamol in one pot, hot ([paracetamol.reagents.get_reagents()])")
	TEST_ASSERT(paracetamol.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_NITROSAMINE) > 0.5 && paracetamol.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_TAR) > 0.5, "leaves nitrosamine and tar")
	var/obj/item/reagent_containers/glass/beaker/hyperzine = dq_blk_beaker(95)
	hyperzine.reagents.add_reagent(REAGENT_ID_FUEL, 10, safety = 1)
	hyperzine.reagents.add_reagent(REAGENT_ID_FERTILIZER, 10)
	TEST_ASSERT(dq_blk_near(hyperzine.reagents.get_reagent_amount(REAGENT_ID_HYPERZINE), 10, 1), "hyperzine by the Stimm route ([hyperzine.reagents.get_reagents()])")
	TEST_ASSERT(hyperzine.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_TAR) > 0.5 && hyperzine.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL) > 0.4, "leaves tar and heavy metals")
	// Each shortcut is on the book as the dirty way.
	for(var/shortcut in list("bicaridine", "kelotane", "dylovene", "paracetamol", "hyperzine"))
		TEST_ASSERT_NOTNULL(text2path("/transformation/chem/instant/shortcut_[shortcut]"), "the [shortcut] shortcut exists")

/// A route that is a process chemical poured in is marked in the book as the dirty way, a generated route as the clean one, a recipe named shortcut_ as the shortcut.
/datum/unit_test/dq_chem_families_book_says_tier_and_route_kind

/datum/unit_test/dq_chem_families_book_says_tier_and_route_kind/Run()
	TEST_ASSERT_EQUAL(chem_tier_of(REAGENT_ID_INAPROVALINE), CHEM_TIER_STAPLE, "inaprovaline is a staple")
	TEST_ASSERT_EQUAL(chem_tier_of(REAGENT_ID_TRICORDRAZINE), CHEM_TIER_STANDARD, "tricordrazine is standard")
	TEST_ASSERT_EQUAL(chem_tier_of(REAGENT_ID_OXYCODONE), CHEM_TIER_ADVANCED, "oxycodone is advanced")
	TEST_ASSERT_EQUAL(chem_tier_of(REAGENT_ID_HYDRIDE), CHEM_TIER_STAPLE, "a process chemical is stock")
	var/list/kinds = list()
	for(var/list/recipe in _dq_reagent_recipe(REAGENT_ID_INAPROVALINE))
		kinds[recipe["route_kind"]] = TRUE
	TEST_ASSERT(kinds["clean route"], "inaprovaline has a clean route")
	TEST_ASSERT(kinds["process chemical"], "and a process chemical route (the hydride)")
	var/list/bicaridine_kinds = list()
	for(var/list/recipe in _dq_reagent_recipe(REAGENT_ID_BICARIDINE))
		bicaridine_kinds[recipe["route_kind"]] = TRUE
	TEST_ASSERT(bicaridine_kinds["dirty shortcut"], "bicaridine has its dirty shortcut on the book")

// ---- group clashes ----

/// Two chemicals that meet react by the groups they carry: in a beaker and in the stomach, never in the bloodstream.
/datum/unit_test/dq_chem_families_groups_clash_on_contact

/datum/unit_test/dq_chem_families_groups_clash_on_contact/Run()
	// An acid group and an amine make a salt, both tied up.
	var/obj/item/reagent_containers/glass/beaker/salt = dq_blk_beaker(20)
	salt.reagents.add_reagent(REAGENT_ID_BICARIDINE, 5, safety = 1)
	salt.reagents.add_reagent(REAGENT_ID_HYPERZINE, 5)
	TEST_ASSERT(salt.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS) > 4, "bicaridine's acid group and hyperzine's amine make a salt ([salt.reagents.get_reagents()])")
	TEST_ASSERT(salt.reagents.get_reagent_amount(REAGENT_ID_BICARIDINE) < 1, "and the bicaridine is tied up")
	// A thiol takes a metal centre.
	var/obj/item/reagent_containers/glass/beaker/thiol = dq_blk_beaker(20)
	thiol.reagents.add_reagent(REAGENT_ID_ANTITOXIN, 5, safety = 1)
	thiol.reagents.add_reagent(REAGENT_ID_BULLVALENE, 5)
	TEST_ASSERT(thiol.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL) > 3, "dylovene takes the copper of bullvalene ([thiol.reagents.get_reagents()])")
	// A nitro compound and an amine make nitrosamine (or the amine is oxidised: either way both are spent).
	var/obj/item/reagent_containers/glass/beaker/nitro = dq_blk_beaker(20)
	nitro.reagents.add_reagent(REAGENT_ID_NITROGLYCERIN, 5, safety = 1)
	nitro.reagents.add_reagent(REAGENT_ID_HYPERZINE, 5)
	TEST_ASSERT(nitro.reagents.get_reagent_amount(REAGENT_ID_NITROGLYCERIN) < 1, "nitroglycerin and an amine spend each other ([nitro.reagents.get_reagents()])")
	TEST_ASSERT(nitro.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_NITROSAMINE) > 3, "into nitrosamine")
	// A phosphate drops out against calcium.
	var/obj/item/reagent_containers/glass/beaker/phosphate = dq_blk_beaker(20)
	phosphate.reagents.add_reagent(REAGENT_ID_DERMALINE, 5, safety = 1)
	phosphate.reagents.add_reagent(REAGENT_ID_CALCIUM, 5)
	TEST_ASSERT(phosphate.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS) > 4, "dermaline's phosphate drops out against calcium ([phosphate.reagents.get_reagents()])")
	// Building blocks mixed on purpose do not clash: acetic acid and an amine are a condensation waiting for a bath, not a salt.
	var/obj/item/reagent_containers/glass/beaker/blocks = dq_blk_beaker(20)
	blocks.reagents.add_reagent(REAGENT_ID_ACETICACID, 5, safety = 1)
	blocks.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 5)
	TEST_ASSERT_EQUAL(blocks.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 0, "a precursor and a medicine do not clash")
	TEST_ASSERT(dq_blk_near(blocks.reagents.get_reagent_amount(REAGENT_ID_ACETICACID), 5), "the acetic acid is waiting for its bath")
	// An intended join is not a clash: carthatoline and inaprovaline condense into tricordrazine.
	var/obj/item/reagent_containers/glass/beaker/join = dq_blk_beaker(20)
	join.reagents.add_reagent(REAGENT_ID_CARTHATOLINE, 5, safety = 1)
	join.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 5)
	TEST_ASSERT_EQUAL(join.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 0, "two chemicals that condense into a chemical are not a clash")

/// Swallowed doses mix in the stomach; the bloodstream keeps them apart.
/datum/unit_test/dq_chem_families_clashes_run_in_the_stomach_not_the_blood

/datum/unit_test/dq_chem_families_clashes_run_in_the_stomach_not_the_blood/Run()
	var/mob/living/carbon/human/swallowed = allocate(/mob/living/carbon/human)
	swallowed.ingested.add_reagent(REAGENT_ID_BICARIDINE, 5, safety = 1)
	swallowed.ingested.add_reagent(REAGENT_ID_HYPERZINE, 5)
	TEST_ASSERT(swallowed.ingested.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS) > 4, "in the stomach the two make a salt ([swallowed.ingested.get_reagents()])")
	var/mob/living/carbon/human/injected = allocate(/mob/living/carbon/human)
	injected.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, 5, safety = 1)
	injected.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, 5)
	TEST_ASSERT_EQUAL(injected.bloodstr.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 0, "in the bloodstream they do not")
	TEST_ASSERT(dq_blk_near(injected.bloodstr.get_reagent_amount(REAGENT_ID_BICARIDINE), 5, 0.5), "the bicaridine is still there")
	var/mob/living/carbon/human/touched = allocate(/mob/living/carbon/human)
	touched.touching.add_reagent(REAGENT_ID_BICARIDINE, 5, safety = 1)
	touched.touching.add_reagent(REAGENT_ID_HYPERZINE, 5)
	TEST_ASSERT_EQUAL(touched.touching.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 0, "nor on the skin")

/// The scavenger resin takes a contaminant out of a mixture, a unit for a unit; the dry agent drinks water so a condensation can finish.
/datum/unit_test/dq_chem_families_resin_and_dry_agent_act_on_contact

/datum/unit_test/dq_chem_families_resin_and_dry_agent_act_on_contact/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker(20)
	B.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 2, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_SCAVENGERRESIN, 2)
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 0, "the resin took the heavy metal")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_INERT_FILLER), 2), "and left inert filler")
	TEST_ASSERT(dq_blk_near(B.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE), 10), "the medicine is not touched")
	var/obj/item/reagent_containers/glass/beaker/dry = dq_blk_beaker(20)
	dry.reagents.add_reagent(REAGENT_ID_WATER, 5, safety = 1)
	dry.reagents.add_reagent(REAGENT_ID_DRYAGENT, 5)
	TEST_ASSERT_EQUAL(dry.reagents.get_reagent_amount(REAGENT_ID_WATER), 0, "the dry agent drank the water ([dry.reagents.get_reagents()])")

// ---- byproducts are real chemicals ----

/// Halogenating frees hydrochloric acid (the real chemical, reusable); mutagen and citalopram leave their poisons; hydrolysing and condensing give water.
/datum/unit_test/dq_chem_families_byproducts_are_chemicals

/datum/unit_test/dq_chem_families_byproducts_are_chemicals/Run()
	var/obj/item/reagent_containers/glass/beaker/mutagen = dq_blk_beaker(55)
	mutagen.reagents.add_reagent(REAGENT_ID_DIETHYLAMINE, 10, safety = 1)
	mutagen.reagents.add_reagent(REAGENT_ID_CHLORINE, 10)
	TEST_ASSERT(dq_blk_near(mutagen.reagents.get_reagent_amount(REAGENT_ID_MUTAGEN), 10, 1), "diethylamine and chlorine make mutagen ([mutagen.reagents.get_reagents()])")
	TEST_ASSERT(dq_blk_near(mutagen.reagents.get_reagent_amount(REAGENT_ID_HYDROCHLORIC), 10, 1), "and hydrochloric acid, a real chemical that a base can spend")
	mutagen.reagents.add_reagent(REAGENT_ID_LYE, 10)
	TEST_ASSERT(mutagen.reagents.get_reagent_amount(REAGENT_ID_SODIUMCHLORIDE) > 8, "lye turns it into table salt")
	// Waste has to be neutralised, boiled off or bottled: no chemical is a contaminant that a route could not make.
	var/datum/chem_route/R = dq_fam_route(REAGENT_ID_SODIUMCHLORIDE, list(REAGENT_ID_HYDROCHLORIC, REAGENT_ID_LYE))
	TEST_ASSERT_NOTNULL(R, "neutralising hydrochloric acid with lye is a route")

// ---- the stock ----

/// Sixteen precursors, bottled: the lab starts with them in the chemical closet and cargo sells a crate.
/datum/unit_test/dq_chem_families_precursors_are_stocked

/datum/unit_test/dq_chem_families_precursors_are_stocked/Run()
	var/list/expected = list(REAGENT_ID_PHENOL, REAGENT_ID_SALICYLICACID, REAGENT_ID_WOODALDEHYDE, REAGENT_ID_NITRICACID, REAGENT_ID_HYDROCHLORIC, REAGENT_ID_PHOSPHORICACID, \
		REAGENT_ID_ACETICACID, REAGENT_ID_BLEACH, REAGENT_ID_SODAASH, REAGENT_ID_GLYCEROL, REAGENT_ID_SILICATE, REAGENT_ID_FATTYACID, REAGENT_ID_PYRIDINE, REAGENT_ID_ALKALOID, \
		REAGENT_ID_STEROL, REAGENT_ID_AMINOACID)
	var/list/found = list()
	for(var/box_type in list(/obj/item/storage/box/precursors_inorganic, /obj/item/storage/box/precursors_ring, /obj/item/storage/box/precursors_bio))
		var/obj/item/storage/box/B = allocate(box_type, test_floor())
		for(var/obj/item/reagent_containers/glass/bottle/bottle in B.contents)
			TEST_ASSERT_EQUAL(length(bottle.reagents.reagent_list), 1, "[bottle] holds one chemical")
			var/datum/reagent/R = bottle.reagents.reagent_list[1]
			TEST_ASSERT(dq_blk_near(R.volume, 60), "[bottle] is full")
			found += R.id
	for(var/id in expected)
		TEST_ASSERT(id in found, "a bottle of [id] is in the boxes")
	TEST_ASSERT_EQUAL(length(found), 16, "sixteen precursors")
	var/obj/structure/closet/secure_closet/chemical/closet = allocate(/obj/structure/closet/secure_closet/chemical, test_floor())
	var/list/closet_start = list()
	for(var/obj/item/storage/box/in_closet in closet.contents)
		closet_start += in_closet.type
	for(var/box_type in list(/obj/item/storage/box/precursors_inorganic, /obj/item/storage/box/precursors_ring, /obj/item/storage/box/precursors_bio))
		TEST_ASSERT(box_type in closet_start, "the chemical closet starts with [box_type]")
	var/datum/supply_pack/med/chemprecursors/pack = new
	var/list/sold = pack.contains
	for(var/box_type in list(/obj/item/storage/box/precursors_inorganic, /obj/item/storage/box/precursors_ring, /obj/item/storage/box/precursors_bio))
		TEST_ASSERT(box_type in sold, "cargo sells [box_type]")

#endif

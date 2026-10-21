/*
	This is a self assembled wiki for chemical reagents, food recipies,
	and other information that should be assembled from game files.
*/

SYSTEM_DEF(internal_wiki)
	name = "Wiki"
	init_stage = INITSTAGE_MAIN
	needs = list(
		/datum/system/atoms
		// Supply packs come from SSsupply, which boots after SSmapping (before atoms).
	)

	VAR_PRIVATE/list/pages = list()

	VAR_PRIVATE/list/ores = list()
	VAR_PRIVATE/list/materials = list()
	VAR_PRIVATE/list/smashers = list()

	VAR_PRIVATE/list/appliance_list = list("Simple","Microwave","Fryer","Oven","Grill","Candy Maker","Cereal Maker")
	VAR_PRIVATE/list/catalog_list = list()
	VAR_PRIVATE/list/drinkreact = list()
	VAR_PRIVATE/list/chemreact = list()
	VAR_PRIVATE/list/botseeds = list()
	VAR_PRIVATE/list/viruses = list()
	VAR_PRIVATE/list/genes = list()

	VAR_PRIVATE/list/foodrecipe = list()

	VAR_PRIVATE/list/catalogs = list()

	VAR_PRIVATE/list/searchcache_ore = list()
	VAR_PRIVATE/list/searchcache_material = list()
	VAR_PRIVATE/list/searchcache_smasher = list()
	VAR_PRIVATE/list/searchcache_foodrecipe = list()
	VAR_PRIVATE/list/searchcache_drinkreact = list()
	VAR_PRIVATE/list/searchcache_chemreact = list()
	VAR_PRIVATE/list/searchcache_catalogs = list()
	VAR_PRIVATE/list/searchcache_botseeds = list()
	VAR_PRIVATE/list/searchcache_viruses = list()
	VAR_PRIVATE/list/searchcache_genes = list()

	VAR_PRIVATE/list/spoiler_entries = list()
	/// Wiki categories whose pages are built (WIKI_CATEGORY_* -> TRUE).
	/// Each category is built on its first read, not at boot.
	VAR_PRIVATE/list/built_categories = list()

	VAR_PRIVATE/max_donation = 100000
	VAR_PRIVATE/min_donation = 50000
	VAR_PRIVATE/donation_goal = 0
	VAR_PRIVATE/cur_donation = 0
	VAR_PRIVATE/list/dono_list = list()
	VAR_PRIVATE/highest_cached_donator = null

/datum/system/internal_wiki/stat_entry(msg)
	msg = "P: [length(pages)] | O: [length(ores)] | M: [length(materials)] | S: [length(smashers)] | F: [length(foodrecipe)]  | D: [length(drinkreact)]  | C: [length(chemreact)]  | B: [length(botseeds)] | V: [length(viruses)] | G: [length(genes)] "
	return ..()

/datum/system/internal_wiki/initialize()
	// Pages are built per category on first read (ensure_category()): the
	// data is static per build and most rounds never open most categories.
	// Donation gag
	donation_goal = rand(min_donation,max_donation)
	donation_goal = round(donation_goal,1)
	cur_donation = rand(0,donation_goal * 0.95)
	cur_donation = round(cur_donation,1)


///////////////////////////////////////////////////////////////////////////////////
// Donation system, for the joke of course
///////////////////////////////////////////////////////////////////////////////////
/datum/system/internal_wiki/proc/pay_with_card( obj/item/card/id/I, mob/M, obj/device, paying_amount, pin)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!purchase_with_id_card(I, M, "Bingle.Co.LLC.UK.M.XM.WMP.AVI.COM", device.name, "Donation", paying_amount, null, pin))
		return FALSE
	// Keep tabs on donations
	var/datum/money_account/customer_account = get_account(I.associated_account_number)
	if(isnull(dono_list[customer_account.owner_name]))
		dono_list[customer_account.owner_name] = 0
	dono_list[customer_account.owner_name] += paying_amount
	donation_add(paying_amount)
	return TRUE

/datum/system/internal_wiki/proc/donation_add(paying_amount)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	var/old_dono = cur_donation
	cur_donation += paying_amount
	if(old_dono < donation_goal)
		// If donation goal was not yet met upon donation, recalculate leader on donate
		highest_cached_donator = update_highest_donator(TRUE)
		if(cur_donation >= donation_goal) // Reached goal!
			message_admins("Bingle donation goal reached! Winner was [get_highest_donor_name()] with [get_highest_donor_value()]") // TODO - Removed me for something actually interesting

/datum/system/internal_wiki/proc/update_highest_donator(no_cache = FALSE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(no_cache)
		highest_cached_donator = null
	if(highest_cached_donator)
		return highest_cached_donator
	// Search through the donated names for a winner
	var/highest = "noone!"
	var/val = 0
	for(var/donor in dono_list)
		if(dono_list[donor] > val)
			val = dono_list[donor]
			highest = donor
	return highest


#define WIKI_CATEGORY_ORE "ore"
#define WIKI_CATEGORY_MATERIAL "material"
#define WIKI_CATEGORY_SMASHER "smasher"
#define WIKI_CATEGORY_REAGENT "reagent"
#define WIKI_CATEGORY_SEED "seed"
#define WIKI_CATEGORY_VIRUS "virus"
#define WIKI_CATEGORY_KITCHEN "kitchen"
#define WIKI_CATEGORY_LORE "lore"
#define WIKI_CATEGORY_GENE "gene"

/// Builds a category's pages the first time anything reads it.
/datum/system/internal_wiki/proc/ensure_category(category)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(built_categories[category])
		return
	built_categories[category] = TRUE
	switch(category)
		if(WIKI_CATEGORY_ORE)
			init_ore_data()
		if(WIKI_CATEGORY_MATERIAL)
			init_material_data()
		if(WIKI_CATEGORY_SMASHER)
			init_particle_smasher_data()
		if(WIKI_CATEGORY_REAGENT)
			init_reagent_data()
		if(WIKI_CATEGORY_SEED)
			init_seed_data()
		if(WIKI_CATEGORY_VIRUS)
			init_virus_data()
		if(WIKI_CATEGORY_KITCHEN)
			init_kitchen_data()
		if(WIKI_CATEGORY_LORE)
			init_lore_data()
		if(WIKI_CATEGORY_GENE)
			init_gene_data()

///////////////////////////////////////////////////////////////////////////////////
// Accessors for safely talking with the subsystem
///////////////////////////////////////////////////////////////////////////////////
// get a page from a search
/datum/system/internal_wiki/proc/get_page_food(search)
	RETURN_TYPE(/datum/internal_wiki/page/food)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_KITCHEN)
	return foodrecipe[search]
/datum/system/internal_wiki/proc/get_page_drink(search)
	RETURN_TYPE(/datum/internal_wiki/page/drink)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_REAGENT)
	return drinkreact[search]
/datum/system/internal_wiki/proc/get_page_chem(search)
	RETURN_TYPE(/datum/internal_wiki/page/chemical)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_REAGENT)
	return chemreact[search]
/datum/system/internal_wiki/proc/get_page_seed(search)
	RETURN_TYPE(/datum/internal_wiki/page/seed)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_SEED)
	return botseeds[search]
/datum/system/internal_wiki/proc/get_page_virus(search)
	RETURN_TYPE(/datum/internal_wiki/page/virus)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_VIRUS)
	return viruses[search]
/datum/system/internal_wiki/proc/get_page_gene(search)
	RETURN_TYPE(/datum/internal_wiki/page/gene)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_GENE)
	return genes[search]
/datum/system/internal_wiki/proc/get_page_catalog(search)
	RETURN_TYPE(/datum/internal_wiki/page/catalog)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_LORE)
	return catalogs[search]
/datum/system/internal_wiki/proc/get_page_material(search)
	RETURN_TYPE(/datum/internal_wiki/page/material)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_MATERIAL)
	return materials[search]
/datum/system/internal_wiki/proc/get_page_particle(search)
	RETURN_TYPE(/datum/internal_wiki/page/smasher)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_SMASHER)
	return smashers[search]
/datum/system/internal_wiki/proc/get_page_ore(search)
	RETURN_TYPE(/datum/internal_wiki/page/ore)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_ORE)
	return ores[search]
// Search lists
/datum/system/internal_wiki/proc/get_appliances()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	return appliance_list
/datum/system/internal_wiki/proc/get_searchcache_food(appliance)
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_KITCHEN)
	return searchcache_foodrecipe[appliance] || list()
/datum/system/internal_wiki/proc/get_searchcache_drink()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_REAGENT)
	return searchcache_drinkreact
/datum/system/internal_wiki/proc/get_searchcache_chem()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_REAGENT)
	return searchcache_chemreact
/datum/system/internal_wiki/proc/get_searchcache_seed()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_SEED)
	return searchcache_botseeds
/datum/system/internal_wiki/proc/get_searchcache_viruses()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_VIRUS)
	return searchcache_viruses
/datum/system/internal_wiki/proc/get_searchcache_genes()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_GENE)
	return searchcache_genes
/datum/system/internal_wiki/proc/get_catalogs()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_LORE)
	return catalog_list
/datum/system/internal_wiki/proc/get_searchcache_catalog(section)
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_LORE)
	var/list/known_entries = list()
	var/list/section_data = searchcache_catalogs[section] || list()
	for(var/PG in section_data)
		var/datum/internal_wiki/page/catalog/P = catalogs["[PG]"]
		var/datum/category_item/catalogue/C = P.catalog_record()
		if(C.visible || C.value <= CATALOGUER_REWARD_TRIVIAL)
			known_entries.Add(PG)
	return known_entries
/datum/system/internal_wiki/proc/get_searchcache_material()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_MATERIAL)
	return searchcache_material
/datum/system/internal_wiki/proc/get_searchcache_particle()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_SMASHER)
	return searchcache_smasher
/datum/system/internal_wiki/proc/get_searchcache_ore()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	ensure_category(WIKI_CATEGORY_ORE)
	return searchcache_ore
// Donating
/datum/system/internal_wiki/proc/get_donor_value(key)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!length(dono_list) || isnull(dono_list[key]))
		return 0
	return dono_list[key]
/datum/system/internal_wiki/proc/get_donation_current()
	SHOULD_NOT_OVERRIDE(TRUE)
	return cur_donation
/datum/system/internal_wiki/proc/get_donation_goal()
	SHOULD_NOT_OVERRIDE(TRUE)
	return donation_goal
/datum/system/internal_wiki/proc/get_highest_donor_name()
	SHOULD_NOT_OVERRIDE(TRUE)
	highest_cached_donator = update_highest_donator(FALSE)
	return highest_cached_donator
/datum/system/internal_wiki/proc/get_highest_donor_value()
	SHOULD_NOT_OVERRIDE(TRUE)
	highest_cached_donator = update_highest_donator(FALSE)
	return get_donor_value(highest_cached_donator)
// Helpers for formatting wiki data for tgui pages
/datum/system/internal_wiki/proc/assemble_reaction_data(list/data, datum/reagent/R)
	var/list/reaction_list = xform_makers_of(MEDIUM_REAGENTS, REGIME_INSTANT, R.id)
	var/list/distilled_list = xform_makers_of(MEDIUM_REAGENTS, REGIME_DISTILLING, R.id)

	data["instant_reactions"] = null
	if(reaction_list != null && length(reaction_list) > 0)
		var/list/display_reactions = list()
		for(var/datum/xform/CR as anything in reaction_list)
			if(CR.wiki & WIKI_SPOILER)
				continue
			display_reactions.Add(CR)

		var/reactions = list()
		for(var/datum/xform/CR as anything in display_reactions)
			var/list/assemble_reaction = list()
			var/list/reqs = list()
			for(var/RQ in CR.reagent_takes)
				var/datum/reagent/r_RQ = SSchemistry.ready().chemical_reagents[RQ]
				if(!r_RQ)
					log_runtime(EXCEPTION("Invalid reagent id: [RQ]"))
					continue
				reqs.Add("[r_RQ.name]")
			assemble_reaction["required"] = reqs
			var/list/inhib = list()
			for(var/IH in CR.reagent_blocked)
				var/datum/reagent/r_IH = SSchemistry.ready().chemical_reagents[IH]
				if(!r_IH)
					log_runtime(EXCEPTION("Invalid reagent id: [IH]"))
					continue
				inhib.Add("[r_IH.name]")
			assemble_reaction["inhibitor"] = inhib
			var/list/catal = list()
			for(var/CL in CR.reagent_catalysts)
				var/datum/reagent/r_CL = SSchemistry.ready().chemical_reagents[CL]
				if(!r_CL)
					log_runtime(EXCEPTION("Invalid reagent id: [CL]"))
					continue
				catal.Add("[r_CL.name]")
			assemble_reaction["catalysts"] = catal
			assemble_reaction["is_slime"] = null
			if(ispath(CR.rule_type, /transformation/chem/instant/slime))
				var/obj/item/slime_extract/slime_path = CR.subject_type
				assemble_reaction["is_slime"] = initial(slime_path.name)
			reactions += list(assemble_reaction)
		if(length(display_reactions))
			data["instant_reactions"] = reactions

	data["distilled_reactions"] = null
	if(distilled_list != null && length(distilled_list) > 0)
		var/list/display_reactions = list()
		for(var/datum/xform/CR as anything in distilled_list)
			if(CR.wiki & WIKI_SPOILER)
				continue
			display_reactions.Add(CR)

		var/reactions = list()
		for(var/datum/xform/CR as anything in display_reactions)
			var/list/assemble_reaction = list()
			var/list/window = CR.bands[1]
			var/list/ambient = xform_cond_ambient(CR.holds)
			assemble_reaction["temp_min"] = window[1]
			assemble_reaction["temp_max"] = window[2]
			assemble_reaction["xgm_min"] = ambient[3]
			assemble_reaction["xgm_max"] = ambient[4]
			assemble_reaction["require_xgm_gas"] = ambient[1] ? GLOB.gas_data.name[ambient[1]] : null
			assemble_reaction["rejects_xgm_gas"] = ambient[2] ? GLOB.gas_data.name[ambient[2]] : null
			var/list/reqs = list()
			for(var/RQ in CR.reagent_takes)
				var/datum/reagent/r_RQ = SSchemistry.ready().chemical_reagents[RQ]
				if(!r_RQ)
					log_runtime(EXCEPTION("Invalid reagent id: [RQ]"))
					continue
				reqs.Add("[r_RQ.name]")
			assemble_reaction["required"] = reqs
			var/list/inhib = list()
			for(var/IH in CR.reagent_blocked)
				var/datum/reagent/r_IH = SSchemistry.ready().chemical_reagents[IH]
				if(!r_IH)
					log_runtime(EXCEPTION("Invalid reagent id: [IH]"))
					continue
				inhib.Add("[r_IH.name]")
			assemble_reaction["inhibitor"] = inhib
			var/list/catal = list()
			for(var/CL in CR.reagent_catalysts)
				var/datum/reagent/r_CL = SSchemistry.ready().chemical_reagents[CL]
				if(!r_CL)
					log_runtime(EXCEPTION("Invalid reagent id: [CL]"))
					continue
				catal.Add("[r_CL.name]")
			assemble_reaction["catalysts"] = catal
			assemble_reaction["is_slime"] = null
			reactions += list(assemble_reaction)
		if(length(display_reactions))
			data["distilled_reactions"] = reactions

	var/grind_list = list()
	var/list/display_reactions = list()
	for(var/datum/xform/grind as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_GRINDING))
		if(grind.takes[1][1] != XCUR_ITEM)
			continue
		var/obj/item/ore/O = grind.takes[1][2]
		if(R.id in grind.grind_ids())
			display_reactions.Add(initial(O.name))
	grind_list["ore"] = null
	if(length(display_reactions) > 0)
		grind_list["ore"] = display_reactions

	display_reactions = list()
	for(var/datum/xform/grind as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_GRINDING))
		if(grind.takes[1][1] != XCUR_STACK)
			continue
		var/obj/item/stack/material/M = grind.takes[1][2]
		if(R.id in grind.grind_ids())
			display_reactions.Add(initial(M.name))
	grind_list["material"] = null
	if(length(display_reactions) > 0)
		grind_list["material"] = display_reactions

	display_reactions = list()
	for(var/SN in plants_seeds())
		var/datum/seed/S = plants_seeds()[SN]
		if(S && S.roundstart && !S.mysterious)
			if(S.wiki_flag & WIKI_SPOILER)
				continue
			if(!S.chems || !length(S.chems))
				continue
			if(!(R.id in S.chems))
				continue
			display_reactions.Add(S.display_name)
	grind_list["plant"] = null
	if(length(display_reactions) > 0)
		grind_list["plant"] = display_reactions

	data["grinding"] = grind_list

	display_reactions = list()
	for(var/O in GLOB.ore_data)
		var/datum/ore/OR = GLOB.ore_data[O]
		if(OR.reagent == R.id)
			display_reactions.Add(OR.name)
	data["fluid"] = null
	if(length(display_reactions) > 0)
		data["fluid"] = display_reactions

	display_reactions = list()

	// The transformation index keeps a rule under its first take only (that is what the settle looks up by), so a reagent that is a later take or a catalyst
	// is found by checking every rule's own terms.
	for(var/datum/xform/D as anything in GLOB.xform_rules)
		if(D.medium != MEDIUM_REAGENTS || ispath(D.rule_type, /transformation/chem/instant/slime))
			continue
		if(!D.result)
			continue
		if((R.id in D.reagent_takes) || (R.id in D.reagent_catalysts))
			display_reactions.Add(D.name)

	data["produces"] = null
	if(length(display_reactions) > 0)
		data["produces"] = display_reactions

/datum/system/internal_wiki/proc/assemble_sintering(sinter)
	if(sinter == REFINERY_SINTERING_EXPLODE)
		return "violent detonation"
	if(sinter == REFINERY_SINTERING_SMOKE)
		return "toxic fumes"
	if(sinter == REFINERY_SINTERING_SPIDERS)
		return "OH GOD WHY!?"
	return sinter

/datum/system/internal_wiki/proc/add_icon(list/data, ic, is, col)
	var/load_data = list()
	load_data["icon"] = ic // dmi path
	load_data["state"] = is // string
	load_data["color"] = col // html color
	data["icon_data"] = load_data


///////////////////////////////////////////////////////////////////////////////////
// Initilizing data and creating wiki pages
///////////////////////////////////////////////////////////////////////////////////
/datum/system/internal_wiki/proc/init_ore_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// assemble ore wiki
	for(var/N in GLOB.ore_data)
		var/datum/ore/OR = GLOB.ore_data[N]
		if(OR.wiki_flag & WIKI_SPOILER)
			spoiler_entries.Add(OR.type)
			continue
		var/datum/internal_wiki/page/ore/P = new()
		P.assemble(OR)
		ores["[OR.display_name]"] = P
		searchcache_ore.Add("[OR.display_name]")
		pages.Add(P)

/datum/system/internal_wiki/proc/init_material_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// assemble material wiki
	for(var/mat, value in GLOB.name_to_material)
		var/datum/material/M = value
		if(M.wiki_flag & WIKI_SPOILER)
			spoiler_entries.Add(M.type)
			continue
		var/datum/internal_wiki/page/material/P = new()
		var/id = "[M.display_name] [M.sheet_singular_name]"
		P.assemble(M)
		materials[id] = P
		searchcache_material.Add(id)
		pages.Add(P)

/datum/system/internal_wiki/proc/init_particle_smasher_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// assemble particle smasher wiki
	for(var/datum/particle_smasher_recipe/D  as anything in subtypesof(/datum/particle_smasher_recipe))
		if(initial(D.wiki_flag) & WIKI_SPOILER)
			spoiler_entries.Add(D)
			continue
		var/datum/particle_smasher_recipe/R = new D()
		var/datum/internal_wiki/page/smasher/P = new()
		var/id = "[initial(D.display_name)]"
		P.assemble(R)
		smashers[id] = P
		searchcache_smasher.Add(id)
		pages.Add(P)
		spent(R)

/datum/system/internal_wiki/proc/init_reagent_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// assemble chemical reactions wiki
	for(var/reagent in SSchemistry.ready().chemical_reagents)
		var/datum/internal_wiki/page/P = null
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent]
		if(!allow_reagent(R.id))
			continue
		if((R.wiki_flag & WIKI_FOOD)) // Processed later
			continue
		if(R.wiki_flag & WIKI_SPOILER)
			spoiler_entries.Add(R.type)
			continue
		var/id = "[R.name]"
		if((R.wiki_flag & WIKI_DRINK) && R.id != REAGENT_ID_ETHANOL) // This is no good way to use inheretance for ethanol... We exclude it here so it shows up in chems
			P = new /datum/internal_wiki/page/drink()
			P.assemble(R)
			searchcache_drinkreact.Add(id)
			drinkreact[id] = P
		else
			P = new /datum/internal_wiki/page/chemical()
			P.assemble(R)
			searchcache_chemreact.Add(id)
			chemreact[id] = P
		pages.Add(P)

/datum/system/internal_wiki/proc/init_seed_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// seeds and plants
	for(var/SN in plants_seeds())
		var/datum/seed/S = plants_seeds()[SN]
		if(S && S.roundstart && !S.mysterious)
			if(S.wiki_flag & WIKI_SPOILER)
				spoiler_entries.Add(S.type)
				continue
			var/datum/internal_wiki/page/seed/P = new()
			P.assemble(S)
			searchcache_botseeds.Add("[S.display_name]")
			botseeds["[S.display_name]"] = P
			pages.Add(P)

/datum/system/internal_wiki/proc/init_virus_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// viruses or diseases
	for(var/datum/affliction/contagion/D as anything in subtypesof(/datum/affliction/contagion))
		if(initial(D.name) == DEVELOPER_WARNING_NAME)
			continue
		if(initial(D.visibility_flags) & HIDDEN_PANDEMIC)
			spoiler_entries.Add(D)
			continue
		var/datum/internal_wiki/page/virus/P = new()
		P.assemble(D)
		searchcache_viruses.Add("[initial(D.medical_name)]")
		viruses["[initial(D.medical_name)]"] = P
		pages.Add(P)

/datum/system/internal_wiki/proc/init_gene_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// viruses or diseases
	for(var/datum/gene/G in GLOB.dna_genes)
		var/N = G.name
		if(istype(G,/datum/gene/trait))
			var/datum/gene/trait/T = G
			N = T.get_name()
		var/datum/internal_wiki/page/gene/P = new()
		P.assemble(G)
		searchcache_genes.Add("[N]")
		genes["[N]"] = P
		pages.Add(P)

/datum/system/internal_wiki/proc/init_kitchen_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// Build the kitchen recipe lists
	var/list/food_recipes = list()
	for(var/datum/xform/R as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_COOKING))
		if(!isnull(R.result))
			var/obj/item/res = R.result
			food_recipes[R.rule_type] = list(
						"Result" = "[initial(res.name)]",
						"ResultPath" = res,
						"Desc" = "[initial(res.desc)]",
						"ResAmt" = "1",
						"Reagents" = R.reagent_takes ? R.reagent_takes.Copy() : list(),
						"Catalysts" = list(),
						"Fruit" = R.fruit_takes ? R.fruit_takes.Copy() : list(),
						"Ingredients" = R.cook_items ? R.cook_items.Copy() : list(),
						"Coating" = R.coating,
						"Appliance" = R.cooks_in,
						"Allergens" = 0,
						"Medallergens" = 0,
						"Price" = initial(res.price_tag),
						"Flags" = R.wiki
						)
	// basically condiments, tofu, cheese, soysauce, etc
	for(var/datum/xform/CR as anything in xform_rules_in(MEDIUM_REAGENTS, REGIME_INSTANT))
		if(!allow_reagent(CR.result))
			continue
		if(CR.wiki & WIKI_SPOILER)
			continue
		if(!(CR.wiki & WIKI_FOOD))
			continue
		food_recipes[CR.rule_type] = list("Result" = CR.name,
								"ResultPath" = null,
								"ResAmt" = CR.result_amount,
								"Reagents" = CR.reagent_takes ? CR.reagent_takes.Copy() : list(),
								"Catalysts" = CR.reagent_catalysts ? CR.reagent_catalysts.Copy() : list(),
								"Fruit" = list(),
								"Ingredients" = list(),
								"Appliance" = 0,
								"Allergens" = 0,
								"Medallergens" = 0,
								"Flags" = CR.wiki
								)
	//Items needs further processing into human-readability.
	for(var/Rp in food_recipes)
		var/working_ing_list = list()
		food_recipes[Rp]["has_coatable_items"] = FALSE
		for(var/I in food_recipes[Rp]["Ingredients"])
			if(I == /obj/item/holder/mouse) // Time for the list of snowflakes
				if("mouse" in working_ing_list)
					var/sofar = working_ing_list["mouse"]
					working_ing_list["mouse"] = sofar+1
				else
					working_ing_list["mouse"] = 1
			else if(I == /obj/item/holder/diona) // YOU TOO
				if("diona" in working_ing_list)
					var/sofar = working_ing_list["diona"]
					working_ing_list["diona"] = sofar+1
				else
					working_ing_list["diona"] = 1
			else if(I == /obj/item/holder) // And you especially, needed for "splat" microwave recipe
				if("micro" in working_ing_list)
					var/sofar = working_ing_list["micro"]
					working_ing_list["micro"] = sofar+1
				else
					working_ing_list["micro"] = 1
			else
				if(I in typesof(/obj/item/reagent_containers/food/snacks)) // only subtypes of this have a coating variable and are checked for it (fruit are a subtype of this, so there's a check for them too later)
					food_recipes[Rp]["has_coatable_items"] = TRUE

				//So now we add something like "Bread" = 3
				var/id = initial(I:name)
				if(id in working_ing_list)
					var/sofar = working_ing_list[id]
					working_ing_list[id] = sofar+1
				else
					working_ing_list[id] = 1

		if(LAZYLEN(food_recipes[Rp]["Fruit"]))
			food_recipes[Rp]["has_coatable_items"] = TRUE
		food_recipes[Rp]["Ingredients"] = working_ing_list

	//Reagents can be resolved to nicer names as well
	for(var/Rp in food_recipes)
		for(var/rid in food_recipes[Rp]["Reagents"])
			var/datum/reagent/Rd = SSchemistry.ready().chemical_reagents[rid]
			if(!Rd) // Leaving this here in the event that if rd is ever invalid or there's a recipe issue, it'll be skipped and recipe dumps can still be ran.
				log_runtime(EXCEPTION("Food \"[Rp]\" had an invalid RID: \"[rid]\"! Check your reagents list for a missing or mistyped reagent!"))
				continue // This allows the dump to still continue, and it will skip the invalid recipes.
			var/R_name = Rd.name
			var/amt = food_recipes[Rp]["Reagents"][rid]
			food_recipes[Rp]["Reagents"] -= rid
			food_recipes[Rp]["Reagents"][R_name] = amt
			food_recipes[Rp]["Allergens"] |= Rd.allergen_type
			food_recipes[Rp]["Medallergens"] |= Rd.medallergen_type
		for(var/rid in food_recipes[Rp]["Catalysts"])
			var/datum/reagent/Rd = SSchemistry.ready().chemical_reagents[rid]
			if(!Rd) // Leaving this here in the event that if rd is ever invalid or there's a recipe issue, it'll be skipped and recipe dumps can still be ran.
				log_runtime(EXCEPTION("Food \"[Rp]\" had an invalid RID: \"[rid]\"! Check your reagents list for a missing or mistyped reagent!"))
				continue // This allows the dump to still continue, and it will skip the invalid recipes.
			var/R_name = Rd.name
			var/amt = food_recipes[Rp]["Catalysts"][rid]
			food_recipes[Rp]["Catalysts"] -= rid
			food_recipes[Rp]["Catalysts"][R_name] = amt

	//We can also change the appliance to its proper name.
	for(var/Rp in food_recipes)
		switch(food_recipes[Rp]["Appliance"])
			if(0)
				food_recipes[Rp]["Appliance"] = "Simple"
			if(1)
				food_recipes[Rp]["Appliance"] = "Microwave"
			if(2)
				food_recipes[Rp]["Appliance"] = "Fryer"
			if(4)
				food_recipes[Rp]["Appliance"] = "Oven"
			if(8)
				food_recipes[Rp]["Appliance"] = "Grill"
			if(16)
				food_recipes[Rp]["Appliance"] = "Candy Maker"
			if(32)
				food_recipes[Rp]["Appliance"] = "Cereal Maker"

	//////////////////////// SORTING
	var/list/foods_to_paths = list()
	for(var/Rp in food_recipes) // "Appliance" will sort the list by APPLIANCES first. Items without an appliance will append to the top of the list. The old method was "Result", which sorts the list by the name of the result.
		foods_to_paths["[food_recipes[Rp]["Appliance"]] [Rp]"] = Rp //Append recipe datum path to keep uniqueness
	foods_to_paths = sortAssoc(foods_to_paths)
	var/list/foods_newly_sorted = list()
	for(var/Rr in foods_to_paths)
		var/Rp = foods_to_paths[Rr]
		foods_newly_sorted[Rp] = food_recipes[Rp]
	food_recipes = foods_newly_sorted

	// assemble output pages
	for(var/Rp in food_recipes)
		if(food_recipes[Rp] && !isnull(food_recipes[Rp]["Result"]))
			if(food_recipes[Rp]["Flags"] & WIKI_SPOILER)
				spoiler_entries.Add(Rp)
				continue
			var/datum/internal_wiki/page/recipe/P = new()
			P.assemble(food_recipes[Rp])
			foodrecipe["[P.title]"] = P
			// organize into sublists
			var/app = food_recipes[Rp]["Appliance"]
			if(!searchcache_foodrecipe[app])
				searchcache_foodrecipe[app] = list()
			var/list/FL = searchcache_foodrecipe[app]
			FL.Add("[P.title]")
			pages.Add(P)

/datum/system/internal_wiki/proc/init_lore_data()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	// assemble low reward catalog entries
	for(var/datum/category_group/G in GLOB.catalogue_data.categories)
		for(var/datum/category_item/catalogue/item in G.items)
			if(istype(item,/datum/category_item/catalogue/anomalous))
				continue // lets always consider these spoilers
			if(istype(item,/datum/category_item/catalogue/fauna/catslug/custom))
				continue // too many silly entries
			var/datum/internal_wiki/page/catalog/P = new()
			P.title = item.name
			P.catalog_record_static = item
			P.assemble()
			catalogs["[item.name]"] = P
			if(!searchcache_catalogs[G.name])
				searchcache_catalogs[G.name] = list()
			var/list/SC = searchcache_catalogs[G.name]
			SC.Add(P.title)
			pages.Add(P)
		catalog_list.Add(G.name)

/datum/system/internal_wiki/proc/allow_reagent(reagent_id)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	// This is used to filter out some of the base reagent types, such as admin only reagents
	if(!reagent_id || reagent_id == "" || reagent_id == REAGENT_ID_DEVELOPER_WARNING || reagent_id == REAGENT_ID_DRINK || reagent_id == REAGENT_DRUGS || reagent_id == REAGENT_ID_ADMINORDRAZINE)
		return FALSE
	return TRUE


////////////////////////////////////////////////////////////////////////////////////////////////
// PAGES AND THEIR CONSTRUCTION
////////////////////////////////////////////////////////////////////////////////////////////////
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/internal_wiki/page)
/datum/internal_wiki/page
	var/title = ""
	var/list/data = list() // ALLOW(instance_list): d: every page fills its data table

/datum/internal_wiki/page/proc/assemble()
	return

/datum/internal_wiki/page/proc/get_data()
	RETURN_TYPE(/list)
	return data

/datum/internal_wiki/page/proc/get_print()
	return


// ORES
////////////////////////////////////////////
/datum/internal_wiki/page/ore/assemble(datum/ore/O)
	title = O.display_name
	set_data_at("title", title)
	var/obj/item/ore/ore_path = O.ore
	SSinternal_wiki.add_icon(data, initial(ore_path.icon), initial(ore_path.icon_state), "#ffffff")
	// Get internal data
	set_data_at("smelting", null)
	if(O.smelts_to)
		var/datum/material/S = get_material_by_name(O.smelts_to)
		set_data_at("smelting", S.display_name)

	set_data_at("compressing", null)
	if(O.compresses_to)
		var/datum/material/C = get_material_by_name(O.compresses_to)
		set_data_at("compressing", C.display_name)

	set_data_at("alloys", null)
	if(O.alloy)
		var/list/alloy_list = list()
		for(var/datum/xform/A as anything in xform_rules_in(MEDIUM_ORE_STOCK, REGIME_SMELTING))
			for(var/list/req as anything in A.takes)
				if(O.name == req[2])
					var/datum/material/M = get_material_by_name(A.id)
					alloy_list.Add(M.display_name)
					break
		set_data_at("alloys", alloy_list)

	set_data_at("pump_reagent", null)
	if(O.reagent)
		var/datum/reagent/REG = SSchemistry.ready().chemical_reagents[O.reagent]
		set_data_at("pump_reagent", REG.name)

	set_data_at("grind_reagents", null)
	var/datum/xform/ore_grind = grinding_ore_rule_for(O.ore)
	if(ore_grind)
		var/list/output = ore_grind.grind_ids()
		var/list/collect = list()
		var/total_parts = 0
		for(var/Rid in output)
			var/datum/reagent/CBR = SSchemistry.ready().chemical_reagents[Rid]
			if(!collect[CBR.name])
				collect[CBR.name] = 0
			collect[CBR.name] += 1
			total_parts += 1

		var/per_part = REAGENTS_PER_SHEET / total_parts
		var/list/grind_list = list()
		for(var/N in collect)
			grind_list[N] = "[collect[N] * per_part]"
		set_data_at("grind_reagents", grind_list)

/datum/internal_wiki/page/ore/get_print()
	var/body = ""
	if(data["smelting"])
		body += "<b>Smelting: [data["smelting"]]</b><br>"
	if(data["compressing"])
		body += "<b>Compressing: [data["compressing"]]</b><br>"
	if(data["alloys"])
		body += "<br>"
		body += "<b>Alloy Component of: </b><br>"
		var/list/alloy_list = data["alloys"]
		for(var/A in alloy_list)
			body += "<b>-[A]</b><br>"
	else
		body += "<br>"
		body += "<b>No known Alloys</b><br>"
	if(data["pump_reagent"])
		body += "<br>"
		body += "<b>Fluid Pump Results:</b><br>"
		body += "<b>-[data["pump_reagent"]]</b><br>"
	if(data["grind_reagents"])
		body += "<br>"
		body += "<b>Ore Grind Results: </b><br>"
		var/list/grind_list = data["grind_reagents"]
		for(var/A in grind_list)
			body += "<b>-[A]: [grind_list[A]]u</b><br>"
	return body

// MATERIALS
////////////////////////////////////////////
/datum/internal_wiki/page/material/assemble(datum/material/M)
	title = M.display_name + " "  + M.sheet_singular_name
	set_data_at("title", title)
	var/obj/item/stack/stack_path = M.stack_type
	SSinternal_wiki.add_icon(data, initial(stack_path.icon), initial(stack_path.icon_state), initial(M.icon_colour))
	// Get internal data
	// weight renamed to density; radioactivity is a component lookup.
	set_data_at("integrity", M.integrity)
	set_data_at("hardness", M.hardness)
	set_data_at("weight", M.density)
	set_data_at("stack_size", initial(stack_path.max_amount) ? initial(stack_path.max_amount) : 0)
	var/supply_value = M.supply_conversion_value ? M.supply_conversion_value : 0
	set_data_at("supply_points", supply_value)
	var/value = supply_value * supply_points_per_money()
	value = FLOOR(value * 100, 1) / 100 // Truncate decimals
	set_data_at("market_price", value)

	set_data_at("opacity", M.opacity)
	set_data_at("conductive", M.conductive)
	set_data_at("protectiveness", M.protectiveness)
	set_data_at("explosion_resistance", M.explosion_resistance)
	set_data_at("radioactivity", dq_material_radioactivity(M))
	set_data_at("reflectivity", M.reflectivity)
	set_data_at("melting_point", M.melting_point)
	set_data_at("ignition_point", M.ignition_point)

	set_data_at("grind_reagents", null)
	var/datum/xform/sheet_grind = grinding_sheet_rule_for(M.stack_type)
	if(sheet_grind)
		var/list/output = sheet_grind.grind_ids()
		if(output && length(output) > 0)
			var/list/collect = list()
			var/total_parts = 0
			for(var/Rid in output)
				var/datum/reagent/CBR = SSchemistry.ready().chemical_reagents[Rid]
				if(CBR)
					if(!collect[CBR.name])
						collect[CBR.name] = 0
					collect[CBR.name] += 1
					total_parts += 1
				else
					log_runtime(EXCEPTION("Invalid reagent id: [Rid] in grind results for sheet [title]"))
			if(total_parts > 0)
				var/per_part = REAGENTS_PER_SHEET / total_parts
				var/list/grind_list = list()
				for(var/N in collect)
					grind_list[N] = "[collect[N] * per_part]"
				set_data_at("grind_reagents", grind_list)

	set_data_at("recipies", null)
	var/list/mat_recipes = M.get_recipes()
	if(length(mat_recipes))
		var/list/recipie_list = list()
		for(var/datum/xform/R in mat_recipes)
			recipie_list.Add(R.title)
		set_data_at("recipies", recipie_list)

/datum/internal_wiki/page/material/get_print()
	var/body = ""
	body += "<b>Integrity: [data["integrity"]]</b><br>"
	body += "<b>Hardness: [data["hardness"]]</b><br>"
	body += "<b>Weight: [data["weight"]]</b><br>"
	var/points = data["supply_points"]
	var/stack_size = data["stack_size"]
	body += "<b>Supply Points: [points] per sheet, [points * stack_size] per stack of [stack_size]</b><br>"
	var/value = data["market_price"]
	body += "<b>Market Price: [value] [value > 1 ? "thalers" : "thaler"] per sheet  |  [(value*stack_size)] [(value*stack_size) > 1 ? "thalers" : "thaler"] per stack of [stack_size]</b><br>"
	body += "<br>"
	body += "<b>Transparent: [data["opacity"] >= 0.5 ? "No" : "Yes"]</b><br>"
	body += "<b>Conductive: [data["conductive"] ? "Yes" : "No"]</b><br>"
	body += "<b>Stability: [data["protectiveness"]]</b><br>"
	body += "<b>Blast Res.: [data["explosion_resistance"]]</b><br>"
	body += "<b>Radioactivity: [data["radioactivity"]]</b><br>"
	body += "<b>Reflectivity: [data["reflectivity"] * 100]%</b><br>"
	body += "<br>"
	if(data["melting_point"] > 0)
		body += "<b>Melting Point: [data["melting_point"]]K ([data["melting_point"] - T0C]C)</b><br>"
	else
		body += "<b>Melting Point: --- </b><br>"

	if(data["ignition_point"] > 0)
		body += "<b>Ignition Point: [data["ignition_point"]]K ([data["ignition_point"] - T0C]C)</b><br>"
	else
		body += "<b>Ignition Point: --- </b><br>"
	if(data["grind_reagents"])
		body += "<br>"
		var/list/grind_list = data["grind_reagents"]
		if(grind_list && length(grind_list) > 0)
			body += "<b>Sheet Grind Results: </b><br>"
			for(var/N in grind_list)
				body += "<b>-[N]: [grind_list[N]]u</b><br>"
	if(data["recipies"])
		body += "<br>"
		var/list/recipie_list = data["recipies"]
		body += "<b>Recipies: </b><br>"
		for(var/R in recipie_list)
			body += "<b>-[R]</b><br>"
	return body

// SEEDS
////////////////////////////////////////////
/datum/internal_wiki/page/seed/assemble(datum/seed/S)
	title = S.display_name
	set_data_at("title", title)
	SSinternal_wiki.add_icon(data, 'icons/obj/hydroponics_growing.dmi', "[S.get_trait(TRAIT_PLANT_ICON)]-[S.growth_stages]", S.get_trait(TRAIT_PLANT_COLOUR))
	// Get internal data
	set_data_at("feeding", S.get_trait(TRAIT_REQUIRES_NUTRIENTS))
	set_data_at("watering", S.get_trait(TRAIT_REQUIRES_WATER))
	set_data_at("lighting", S.get_trait(TRAIT_IDEAL_LIGHT))
	set_data_at("crop_yield", S.get_trait(TRAIT_YIELD))

	var/list/traits = list()
	if(S.has_item_product)
		traits.Add("Grown Byproducts")
	if(S.chems && !isnull(S.chems["woodpulp"]))
		traits.Add("Wooden Growths")
	if(S.get_trait(TRAIT_FLESH_COLOUR))
		traits.Add("Choppable")
	if(S.kitchen_tag == "pumpkin")
		traits.Add("Carvable")
	if(S.kitchen_tag == "potato")
		traits.Add("Sliceable")
	if(S.get_trait(TRAIT_JUICY))
		traits.Add("Juicy")
	if(S.get_trait(TRAIT_IMMUTABLE))
		traits.Add("Stable Genome")
	if(S.get_trait(TRAIT_PRODUCES_POWER))
		traits.Add("Voltaic")
	if(S.get_trait(TRAIT_BIOLUM))
		traits.Add("Bioluminescence")
	if(S.get_trait(TRAIT_STINGS))
		traits.Add("Stings")
	if(S.get_trait(TRAIT_SPORING))
		traits.Add("Produces Spores")
	if(S.get_trait(TRAIT_CARNIVOROUS))
		traits.Add("Carnivorous")
	if(S.get_trait(TRAIT_PARASITE))
		traits.Add("Parasitic")
	if(S.get_trait(TRAIT_SPREAD))
		traits.Add("Spreading")
	if(S.get_trait(TRAIT_EXPLOSIVE))
		traits.Add("Explosive")
	if(!length(traits))
		traits.Add("None")
	set_data_at("traits", traits)
	set_data_at("mob_product", S.has_mob_product)

	set_data_at("chem_breakdown", null)
	if(S.chems && length(S.chems) > 0)
		var/list/chems = list()
		for(var/CB in S.chems)
			var/datum/reagent/CBR = SSchemistry.ready().chemical_reagents[CB]
			if(CBR)
				chems.Add(CBR.name)
			else
				log_runtime(EXCEPTION("Invalid reagent id: [CB] in chemical breakdown for seed [title]"))
		set_data_at("chem_breakdown", chems)

	set_data_at("gas_consumed", null)
	if(S.consume_gasses && length(S.consume_gasses) > 0)
		var/list/consumed = list()
		for(var/CG in S.consume_gasses)
			consumed["[GLOB.gas_data.name[CG]]"] = S.consume_gasses[CG]
		set_data_at("gas_consumed", consumed)

	set_data_at("gas_exuded", null)
	if(S.exude_gasses && length(S.exude_gasses) > 0)
		var/list/exude = list()
		for(var/EG in S.exude_gasses)
			exude["[GLOB.gas_data.name[EG]]"] = S.exude_gasses[EG]
		set_data_at("gas_exuded", exude)

	set_data_at("mutations", null)
	if(S.mutants && length(S.mutants) > 0)
		var/list/mutations = list()
		for(var/MS in S.mutants)
			var/datum/seed/mut = plants_seeds()[MS]
			if(mut)
				mutations.Add(mut.display_name)
		set_data_at("mutations", mutations)

/datum/internal_wiki/page/seed/get_print()
	var/body = ""
	body  += "<b>Requires Feeding: [data["feeding"] ? "YES" : "NO"]</b><br>"
	body  += "<b>Requires Watering: [data["watering"] ? "YES" : "NO"]</b><br>"
	body  += "<b>Requires Light: [data["lighting"]] lumen[data["lighting"] == 1 ? "" : "s"]</b><br>"
	if(data["crop_yield"] > 0)
		body  += "<b>Yield: [data["crop_yield"]]</b><br>"
	body  += "<br>"
	body  += "<b>Traits:</b><br>"
	var/list/traits = data["traits"]
	for(var/A in traits)
		body  += "<b>-[A]</b><br>"
	body  += "<br>"
	if(data["mob_product"])
		body += "<b>DANGER - MAY BE MOBILE</b><br>"
	body  += "<br>"
	var/list/chem_list = data["chem_breakdown"]
	if(chem_list && length(chem_list) > 0)
		body  += "<b>Chemical Breakdown: </b><br>"
		for(var/CB in chem_list)
			body  += "<b>-[CB]</b><br>"
		body  += "<br>"
	var/list/consumed_list = data["gas_consumed"]
	if(consumed_list && length(consumed_list) > 0)
		body  += "<b>Gasses Consumed: </b><br>"
		for(var/CG in consumed_list)
			var/amount = "[consumed_list[CG]]"
			if (consumed_list[CG] < 5)
				amount = "[CG] (trace amounts)"
			body  += "<b>-[amount]</b><br>"
		body  += "<br>"
	var/list/exuded_list = data["gas_exuded"]
	if(exuded_list && length(exuded_list) > 0)
		body  += "<b>Gasses Produced: </b><br>"
		for(var/EG in exuded_list)
			var/amount = "[exuded_list[EG]]"
			if (exuded_list[EG] < 5)
				amount = "[EG] (trace amounts)"
			body  += "<b>-[amount]</b><br>"
		body  += "<br>"
	var/list/mutations = data["mutations"]
	if(mutations && length(mutations) > 0)
		body += "<b>Mutant Strains: </b><br>"
		for(var/MS in mutations)
			body  += "<b>-[MS]</b><br>"
	return body

// PARTICLE SMASHER
////////////////////////////////////////////
/datum/internal_wiki/page/smasher/assemble(datum/particle_smasher_recipe/M)
	title = M.display_name
	set_data_at("title", title)
	var/obj/item/stack/material/result_path = M.result
	var/datum/material/result_mat = get_material_by_name(initial(result_path.default_type))
	SSinternal_wiki.add_icon(data, initial(result_path.icon), initial(result_path.icon_state), initial(result_mat.icon_colour))
	// Get internal data
	var/obj/item/stack/req_mat = M.required_material
	set_data_at("req_mat", null)
	if(req_mat != null)
		set_data_at("req_mat", initial(req_mat.name))

	set_data_at("target_items", null)
	if(M.items && length(M.items) > 0)
		var/list/targs = list()
		for(var/obj/Ir as anything in M.items)
			targs.Add(initial(Ir.name))
		set_data_at("target_items", targs)

	set_data_at("required_energy_min", M.required_energy_min)
	set_data_at("required_energy_max", M.required_energy_max)
	set_data_at("required_atmos_temp_min", M.required_atmos_temp_min)
	set_data_at("required_atmos_temp_max", M.required_atmos_temp_max)

	set_data_at("inducers", null)
	if(M.reagents != null && length(M.reagents) > 0)
		var/list/inducers = list()
		for(var/R in M.reagents)
			var/amnt = M.reagents[R]
			var/datum/reagent/Rd = SSchemistry.ready().chemical_reagents[R]
			if(Rd)
				inducers["[Rd.name]"] = amnt
			else
				log_runtime(EXCEPTION("Invalid reagent id: [Rd] in inducer for atom smasher [title]"))
		set_data_at("inducers", inducers)
	set_data_at("result", initial(result_path.name))
	set_data_at("probability", M.probability)

/datum/internal_wiki/page/smasher/get_print()
	var/body = ""
	if(data["req_mat"] != null)
		body += "<b>Target Sheet: [data["req_mat"]]</b><br>"
	var/list/targ_items = data["target_items"]
	if(targ_items && length(targ_items) > 0)
		for(var/Ir in targ_items)
			body += "<b>-[Ir]</b><br>"
	body += "<b>Threshold Energy: [data["required_energy_min"]] - [data["required_energy_max"]]</b><br>"
	body += "<b>Threshold Temp: [data["required_atmos_temp_min"]]k - [data["required_atmos_temp_max"]]k | ([data["required_atmos_temp_min"] - T0C]C - [data["required_atmos_temp_max"] - T0C]C)</b><br>"
	var/list/inducers = data["inducers"]
	if(inducers && length(inducers) > 0)
		body += "<br>"
		body += "<b>Inducers: </b><br>"
		for(var/R in inducers)
			body += "<b>-[R] [inducers[R]]u</b><br>"
	body += "<br>"
	body += "<b>Results: [data["result"]]</b><br>"
	body += "<b>Probability: [data["probability"]]%</b><br>"
	return body


// CHEMICALS
////////////////////////////////////////////
/datum/internal_wiki/page/chemical/assemble(datum/reagent/R)
	title = R.name
	set_data_at("title", title)
	var/obj/item/reagent_containers/glass/beaker/large/beaker_path = /obj/item/reagent_containers/glass/beaker/large
	SSinternal_wiki.add_icon(data, initial(beaker_path.icon), initial(beaker_path.icon_state), R.color)
	// Get internal data
	set_data_at("description", R.description)
	set_data_at("addictive", 0)
	if(R.id in get_addictive_reagents(ADDICT_ALL))
		set_data_at("addictive", TRUE)
	set_data_at("industrial_use", R.industrial_use)
	set_data_at("supply_points", R.supply_conversion_value ? R.supply_conversion_value : 0)
	set_data_at("cooling_mod", R.coolant_modifier)
	var/value = R.supply_conversion_value * REAGENTS_PER_SHEET * supply_points_per_money()
	value = FLOOR(value * 100,1) / 100 // Truncate decimals
	set_data_at("market_price", value)
	set_data_at("sintering", SSinternal_wiki.assemble_sintering(GLOB.reagent_sheets[R.id]))
	set_data_at("overdose", R.overdose)
	set_data_at("flavor", R.taste_description)
	set_data_at("allergen", assembly_allergy_list(R.allergen_type, R.medallergen_type))
	SSinternal_wiki.assemble_reaction_data(data, R)

/datum/internal_wiki/page/chemical/get_print()
	var/body = ""
	body += "<b>Description: </b>[data["description"]]<br>"
	if(data["addictive"])
		body += "<b>DANGER, addictive.</b><br>"
	if(data["industrial_use"])
		body  += "<b>Industrial Use: </b>[data["industrial_use"]]<br>"
	var/tank_size = CARGOTANKER_VOLUME
	body += "<b>Supply Points: [data["supply_points"]] per unit, [data["supply_points"] * tank_size] per [tank_size] tank</b><br>"
	var/value = data["market_price"]
	if(value > 0)
		body += "<b>Market Price: [value] [value > 1 ? "thalers" : "thaler"] per [REAGENTS_PER_SHEET] units  |  [(value*tank_size)] [(value*tank_size) > 1 ? "thalers" : "thaler"] per [tank_size] unit tank</b><br>"
	if(data["sintering"])
		var/mat_id = data["sintering"]
		switch(mat_id)
			if(REFINERY_SINTERING_SMOKE)
				body += "<b>Sintering Results: COMBUSTION</b><br>"
			if(REFINERY_SINTERING_EXPLODE)
				body += "<b>Sintering Results: DETONATION</b><br>"
			if(REFINERY_SINTERING_SPIDERS)
				body += "<b>Sintering Results: DO NOT EVER</b><br>"
			else
				var/datum/material/C = get_material_by_name(data["sintering"])
				if(C)
					body += "<b>Sintering Results: [C.display_name] [C.sheet_plural_name]</b><br>"
	body += "<b>Coolant Factor: </b>[data["cooling_mod"]]x<br>"
	if(data["overdose"] > 0)
		body += "<b>Overdose: </b>[data["overdose"]]u<br>"
	body += "<b>Flavor: </b>[data["flavor"]]<br>"
	body += "<br>"
	body += print_allergens(data["allergen"])
	body += "<br>"
	body += print_reaction_data(data)
	return body

// FOOD REAGENTS
////////////////////////////////////////////
/datum/internal_wiki/page/food/assemble(datum/reagent/R)
	title = R.name
	set_data_at("title", title)
	var/obj/item/reagent_containers/glass/beaker/large/beaker_path = /obj/item/reagent_containers/glass/beaker/large
	SSinternal_wiki.add_icon(data, initial(beaker_path.icon), initial(beaker_path.icon_state), R.color)
	// Get internal data
	set_data_at("description", R.description)
	set_data_at("flavor", R.taste_description)
	set_data_at("allergen", assembly_allergy_list(R.allergen_type, R.medallergen_type))
	SSinternal_wiki.assemble_reaction_data(data, R)

/datum/internal_wiki/page/food/get_print()
	var/body = ""
	body += "<b>Description: </b>[data["description"]]<br>"
	body += "<br>"
	body += print_allergens(data["allergen"])
	body += "<br>"
	body += print_reaction_data(data)
	return body

// DRINK REAGENTS
////////////////////////////////////////////
/datum/internal_wiki/page/drink/assemble(datum/reagent/R)
	title = R.name
	set_data_at("title", title)
	// Use beaker by default, otherwise try metamorphic glass for icon
	var/ico = 'icons/obj/drinks.dmi'
	if(R.glass_icon_file)
		ico = R.glass_icon_file
	var/sta = "glass_empty"
	if(R.glass_icon_state)
		sta = R.glass_icon_state
	SSinternal_wiki.add_icon(data, ico, sta, R.color)
	// Get internal data
	set_data_at("description", R.description)
	set_data_at("flavor", R.taste_description)
	set_data_at("allergen", assembly_allergy_list(R.allergen_type, R.medallergen_type))
	SSinternal_wiki.assemble_reaction_data(data, R)

/datum/internal_wiki/page/drink/get_print()
	var/body = ""
	body += "<b>Description: </b>[data["description"]]<br>"
	body += "<b>Flavor: </b>[data["flavor"]]<br>"
	body += "<br>"
	body += print_allergens(data["allergen"])
	body += "<br>"
	body += print_reaction_data(data)
	return body

// FOOD RECIPIE
////////////////////////////////////////////
/datum/internal_wiki/page/recipe/assemble(list/recipe)
	title = recipe["Result"]
	set_data_at("title", title)
	var/obj/item/path = recipe["ResultPath"]
	if(path)
		SSinternal_wiki.add_icon(data, initial(path.icon), initial(path.icon_state), "#ffffff")
	else
		var/obj/item/reagent_containers/glass/beaker/large/beaker_path = /obj/item/reagent_containers/glass/beaker/large
		SSinternal_wiki.add_icon(data, initial(beaker_path.icon), initial(beaker_path.icon_state), "#ffffff")
	// Get internal data
	set_data_at("description", recipe["Desc"])
	set_data_at("allergen", assembly_allergy_list(recipe["Allergens"], recipe["Medallergens"]))
	var/list/recipe_data = list()
	var/value = recipe["Price"] ? recipe["Price"] : 0
	recipe_data["supply_points"] = value
	value *= supply_points_per_money() // convert to cash
	value = FLOOR(value * 100,1) / 100 // Truncate decimals
	recipe_data["market_price"] = value
	recipe_data["appliance"] = recipe["Appliance"]
	recipe_data["has_coating"] = recipe["has_coatable_items"]
	recipe_data["coating"] = recipe["Coating"]
	if(!isnull(recipe_data["coating"]) && recipe_data["coating"] != -1) // Null is no coatings, -1 is any coating, otherwise specifies the name of coating
		var/datum/reagent/nutriment/coating/coatingtype = recipe["Coating"]
		recipe_data["coating"] = initial(coatingtype.name)
	var/list/ingred = list()
	for(var/ing in recipe["Ingredients"])
		ingred["[ing]"] = recipe["Ingredients"][ing]
	recipe_data["ingredients"] = length(ingred) ? ingred : null
	var/list/fruits = list()
	for(var/fru in recipe["Fruit"])
		fruits["[fru]"] = recipe["Fruit"][fru]
	recipe_data["fruits"] = length(fruits) ? fruits : null
	var/list/reagents = list()
	for(var/rea in recipe["Reagents"])
		reagents["[rea]"] = recipe["Reagents"][rea]
	recipe_data["reagents"] = length(reagents) ? reagents : null
	var/list/catalysts = list()
	for(var/cat in recipe["Catalysts"])
		catalysts["[cat]"] = recipe["Catalysts"][cat]
	recipe_data["catalysts"] = length(catalysts) ? catalysts : null
	set_data_at("recipe", recipe_data)

/datum/internal_wiki/page/recipe/get_print()
	var/body = ""
	if(data["description"])
		body += "<b>Description: </b>[data["description"]]<br>"
	if(data["recipe"]["supply_points"] > 0)
		var/value = data["recipe"]["supply_points"]
		body += "<b>Supply Points: </b>[value]<br>"
	if(data["recipe"]["market_price"] > 0)
		var/value = data["recipe"]["market_price"]
		body += "<b>Market Price: [value] [value > 1 ? "thalers" : "thaler"]</b><br>"
	body += print_allergens(data["allergen"])
	body += "<br>"
	if(data["recipe"]["appliance"])
		body += "<b>Appliance: </b>[data["recipe"]["appliance"]]<br><br>"
	// ingredients
	var/list/ingreds = data["recipe"]["ingredients"]
	if(ingreds && length(ingreds))
		var/count = 0
		var/pretty_ing = ""
		for(var/ing in ingreds)
			pretty_ing += "[count == 0 ? "" : ", "][ing]x [ingreds[ing]]"
			count++
		if(pretty_ing != "")
			body +=  "<b>Ingredients: </b>[pretty_ing]<br>"
	// Coatings
	if(!data["recipe"]["has_coating"])
		body += "<b>Coating: </b>N/A, no coatable items<br>"
	else if(isnull(data["recipe"]["coating"]))
		body += "<b>Coating: </b> Must be uncoated<br>"
	else if(data["recipe"]["coating"] == -1)
		body += "<b>Coating: </b>Optionally, any coating<br>"
	else
		body += "<b>Coating: </b> [data["recipe"]["coating"]]<br>"
	// Fruits/Veggis
	var/list/fruits = data["recipe"]["fruits"]
	if(fruits && length(fruits)) // Can't use lazylen, assoc list
		var/count = 0
		var/pretty_fru = ""
		for(var/fru in fruits)
			pretty_fru += "[count == 0 ? "" : ", "][fru]x [fruits[fru]]"
			count++
		if(pretty_fru != "")
			body += "<b>Components: </b> [pretty_fru]<br>"
	//For each reagent
	var/list/reags = data["recipe"]["reagents"]
	if(reags && length(reags)) // Can't use lazylen, assoc list
		var/count = 0
		var/pretty_rea = ""
		for(var/reg in reags)
			pretty_rea += "[count == 0 ? "" : ", "][reg] [reags[reg]]u"
			count++
		if(pretty_rea != "")
			body += "<b>Mix in: </b> [pretty_rea]<br>"
	//For each catalyst
	var/list/catalis = data["recipe"]["catalysts"]
	if(catalis && length(catalis)) // Can't use lazylen, assoc list
		var/count = 0
		var/pretty_cat = ""
		for(var/cat in catalis)
			pretty_cat += "[count == 0 ? "" : ", "][cat] [catalis[cat]]u"
			count++
		if(pretty_cat != "")
			body += "<b>Catalysts: </b> [pretty_cat]<br>"
	return body

// CATALOG
////////////////////////////////////////////
/datum/internal_wiki/page/catalog
	var/datum/category_item/catalogue/catalog_record_static

/datum/internal_wiki/page/catalog/assemble()
	set_data_at("name", catalog_record().name)
	set_data_at("desc", catalog_record().desc)

// VIRUSES
/////////////////////////////////////////////
/datum/internal_wiki/page/virus/assemble(datum/affliction/contagion/D)
	title = initial(D.name)
	set_data_at("title", title)
	set_data_at("description", initial(D.desc))
	set_data_at("form", initial(D.form))
	set_data_at("agent", initial(D.agent))
	set_data_at("danger", initial(D.danger))
	set_data_at("max_stages", initial(D.max_stages))

	var/infectivity = ""
	switch(initial(D.infectivity))
		if(0)
			infectivity = "NA"
		if(1 to 3)
			infectivity = "Low"
		if(4 to 7)
			infectivity = "Medium"
		if(8 to INFINITY)
			infectivity = "High"
	set_data_at("infectivity", infectivity)

	var/resiliance = ""
	switch(initial(D.cure_chance))
		if(0 to 8)
			resiliance = "Extreme"
		if(9 to 12)
			resiliance = "High"
		if(13 to 16)
			resiliance = "Medium"
		if(17 to INFINITY)
			resiliance = "Low"
	set_data_at("resiliance", resiliance)

	var/discovery = ""
	switch(initial(D.discovery_threshold))
		if(0 to 0.24)
			discovery = "Extremely Elusive"
		if(0.25 to 0.49)
			discovery = "Difficult"
		if(0.5 to 0.74)
			discovery = "Moderate"
		if(0.75 to 0.89)
			discovery = "Easy"
		if(0.9 to INFINITY)
			discovery = "Trivial"
	set_data_at("discovery", discovery)

	var/spread_flags = initial(D.spread_flags)
	var/spread_type = "NA"
	if(spread_flags & DISEASE_SPREAD_CONTACT)
		spread_type = "Contact"
	else if(spread_flags & DISEASE_SPREAD_FLUIDS)
		spread_type = "Fluids"
	else if(spread_flags & DISEASE_SPREAD_BLOOD)
		spread_type = "Blood"
	else if(spread_flags & DISEASE_SPREAD_AIRBORNE)
		spread_type = "Airborne"
	else if(spread_flags & DISEASE_SPREAD_FALTERED)
		spread_type = "Faltered"
	set_data_at("spread", spread_type)

	var/mod_flags = initial(D.virus_modifiers)
	set_data_at("all_cures", mod_flags & NEEDS_ALL_CURES)
	set_data_at("aggressive", mod_flags & BYPASSES_IMMUNITY)
	var/flags = initial(D.disease_flags)
	set_data_at("curable", flags & CURABLE)
	set_data_at("resistable", flags & CAN_RESIST)
	set_data_at("carriable", flags & CAN_CARRY)
	set_data_at("spread_dead", flags & SPREAD_DEAD)
	set_data_at("infect_synth", flags & INFECT_SYNTHETICS)

/datum/internal_wiki/page/virus/get_print()
	var/body = ""
	body += "<b>Description: </b>[data["description"]]<br>"
	body += "<br>"
	body += "<b>Type: [data["form"]] - [data["agent"]]</b><br>"
	body += "<b>Hazard Level: [data["danger"]]</b><br>"
	body += "<b>Growth Stages: [data["max_stages"]]</b><br>"
	body += "<b>Curable: [(data["curable"]) ? "Yes" : "No"][!(data["all_cures"]) ? " - single treatment" : ""]</b><br>"
	body += "<b>Resistable: [(data["resistable"]) ? "Yes" : "No"]</b><br>"
	body += "<br>"
	// Transmission type
	body += "<b>Transmission: [data["spread"]] [(data["aggressive"]) ? "Aggressive" : ""]</b><br>"
	if(data["carriable"])
		body += "<b>Transmissable without symptoms</b><br>"
	if(data["spread_dead"])
		body += "<b>Transmissable from dead tissue</b><br>"
	if(data["infect_synth"])
		body += "<b>Inorganic pathogen</b><br>"
	// Difficulty of discovery
		body += "<b>Discoverability: [data["discovery"]]</b><br>"
	// Probability of spreading
		body += "<b>Infectivity: [data["infectivity"]]</b><br>"
	// Probability of cure, 10 to 20 regularly
		body += "<b>Resiliance: [data["resiliance"]]</b><br>"
	return body

// GENES
/////////////////////////////////////////////
/datum/internal_wiki/page/gene/assemble(datum/gene/G)
	if(istype(G,/datum/gene/trait))
		// Trait genetics
		var/datum/gene/trait/T = G
		title = T.get_name()
		set_data_at("title", title)
		set_data_at("description", T.get_desc())
		if(istype(T.linked_trait,/datum/trait/positive))
			if(!T.linked_trait.hidden)
				set_data_at("trait_type", "Positive")
			else
				set_data_at("trait_type", "Super Power") // Likely eye lasers
		else if(istype(T.linked_trait,/datum/trait/negative))
			if(!T.linked_trait.hidden)
				set_data_at("trait_type", "Negative")
			else
				set_data_at("trait_type", "Disability") // Likely gibbings or such
		else
			if(!T.linked_trait.hidden)
				set_data_at("trait_type", "Neutral")
			else
				set_data_at("trait_type", "Strange") // Not sure what neutrals are hidden, but just incase
		// Conflicts
		set_data_at("blockers", null)
		var/list/output_blockers = list()
		var/list/blockers = T.conflict_traits
		for(var/path in blockers)
			var/datum/trait/TG = GLOB.all_traits[path]
			output_blockers.Add(TG.name)
		if(length(output_blockers))
			set_data_at("blockers", output_blockers)
	else
		// Old style gene
		title = G.name
		set_data_at("title", title)
		set_data_at("description", G.desc)
		set_data_at("trait_type", "Neutral")
		set_data_at("blockers", null)
	var/list/bounds = GetDNABounds(G.block)
	set_data_at("bounds_off_min", EncodeDNABlock(bounds[1])) // Minimum hex where gene is off
	set_data_at("bounds_off_max", EncodeDNABlock(bounds[2])) // Maximum hex where gene is off
	set_data_at("bounds_on_min", EncodeDNABlock(bounds[3])) // Minimum hex where gene is on
	set_data_at("bounds_on_max", EncodeDNABlock(bounds[4])) // Maximum hex where gene is on

/datum/internal_wiki/page/gene/get_print()
	var/body = ""
	body += "<b>Description: </b>[data["description"]]<br>"
	body += "<br>"
	body += "<b>Type: [data["trait_type"]]</b><br>"
	body += "<b>Active Range: [data["bounds_on_min"]] - [data["bounds_on_max"]]</b><br>"
	body += "<b>Inactive Range: [data["bounds_off_min"]] - [data["bounds_off_max"]]</b><br>"
	body += "<br>"
	var/list/blockers = data["blockers"]
	if(blockers)
		body += "<b>Suppressed By:</b><br>"
		for(var/trait_name in blockers)
			body += "-[trait_name]<br>"
	return body

// MISC HELPERS
////////////////////////////////////////////
/datum/internal_wiki/page/proc/print_allergens(list/allergens)
	PROTECTED_PROC(TRUE)
	var/AG = ""
	if(allergens && length(allergens) > 0)
		AG += "<b>Allergens: </b><br>"
		for(var/ALGY in allergens)
			AG += "-[ALGY]<br>"
		AG += "<br>"
	return AG

/datum/internal_wiki/page/proc/print_reaction_data(list/data)
	var/body = ""
	var/list/instant = data["instant_reactions"]
	if(instant && length(instant) > 0)
		var/segment = 1
		for(var/list/react in instant)
			if(length(instant) == 1)
				body += "<b>Potential Chemical breakdown: </b><br>"
			else
				body += "<b>Potential Chemical breakdown [segment]: </b><br>"
				segment++
			if(react["is_slime"])
				for(var/RQ in react["required"])
					body += " <b>-[react["is_slime"]] Injection: </b>[RQ]<br>"
			else
				for(var/RQ in react["required"])
					body += " <b>-Component: </b>[RQ]<br>"
			for(var/IH in react["inhibitor"])
				body += " <b>-Inhibitor: </b>[IH]<br>"
			for(var/CL in react["catalysts"])
				body += " <b>-Catalyst: </b>[CL]<br>"
	else
		body += "<b>Potential Chemical breakdown: </b><br>UNKNOWN OR BASE-REAGENT<br>"

	var/list/distilled = data["distilled_reactions"]
	if(distilled && length(distilled) > 0)
		var/segment = 1
		for(var/list/react in distilled)
			if(length(distilled) == 1)
				body += "<b>Potential Chemical breakdown: </b><br>"
			else
				body += "<b>Potential Chemical breakdown [segment]: </b><br>"
				segment++
			body += " <b>-Temperature: </b> [react["temp_min"]]K to [react["temp_max"]]K | ([react["temp_min"] - T0C]C to [react["temp_max"] - T0C]C)<br>"
			if(react["xgm_min"] || react["xgm_max"])
				body += " <b>-Pressure: </b> [react["xgm_min"]]kpa - [react["xgm_max"]]kpa<br>"
			if(react["require_xgm_gas"])
				body += " <b>-Requires Gas: </b> [react["require_xgm_gas"]]<br>"
			if(react["rejects_xgm_gas"])
				body += " <b>-Rejects Gas: </b> [react["rejects_xgm_gas"]]<br>"
			for(var/RQ in react["required"])
				body += " <b>-Component: </b>[RQ]<br>"
			for(var/IH in react["inhibitor"])
				body += " <b>-Inhibitor: </b>[IH]<br>"
			for(var/CL in react["catalysts"])
				body += " <b>-Catalyst: </b>[CL]<br>"

	var/list/grind_ore = data["grinding"]["ore"]
	if(grind_ore && length(grind_ore))
		body += "<br>"
		body += "<b>Ore processing results: </b><br>"
		for(var/PL in grind_ore)
			body += " <b>-Grind: </b>[PL]<br>"

	var/list/grind_mats = data["grinding"]["material"]
	if(grind_mats && length(grind_mats))
		body += "<br>"
		body += "<b>Material processing results: </b><br>"
		for(var/PL in grind_mats)
			body += " <b>-Grind: </b>[PL]<br>"

	var/list/grind_plants = data["grinding"]["plant"]
	if(grind_plants && length(grind_plants))
		body += "<br>"
		body += "<b>Organic processing results: </b><br>"
		for(var/PL in grind_plants)
			body += " <b>-Grind: </b>[PL]<br>"

	var/list/fluid_pumping = data["fluid"]
	if(fluid_pumping && length(fluid_pumping))
		body += "<br>"
		body += "<b>Fluid pump results: </b><br>"
		for(var/PL in fluid_pumping)
			body += " <b>-Erosion: </b>[PL]<br>"

	body += "<br>"
	var/list/produces = data["produces"]
	if(produces && length(produces))
		body += "<b>Is a component of: </b><br>"
		for(var/PL in produces)
			body += "-[PL]<br>"
	return body

#undef WIKI_CATEGORY_ORE
#undef WIKI_CATEGORY_MATERIAL
#undef WIKI_CATEGORY_SMASHER
#undef WIKI_CATEGORY_REAGENT
#undef WIKI_CATEGORY_SEED
#undef WIKI_CATEGORY_VIRUS
#undef WIKI_CATEGORY_KITCHEN
#undef WIKI_CATEGORY_LORE
#undef WIKI_CATEGORY_GENE

/// A shared definition/flyweight (implicitly shared), never cleared.
/datum/internal_wiki/page/catalog/proc/catalog_record() as /datum/category_item/catalogue
	return catalog_record_static

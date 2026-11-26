// Polymerise, in the workshop (doc/rewrite/proposals/chemistry_redesign.md section 10): chemistry makes the units, the alloy furnace joins them into sheets.
//
// Fire the furnace with the units of a polymer in its medium (poured in as reagents) and it polymerises them: hard plastic from phenol and wood aldehyde, rubber from a fatty
// acid and sulfur, nylon from a fatty acid and diethylamine, aramid from myelamine. Two polymers are made from sheets instead: guncotton from cloth or cardboard with nitric
// acid in the medium (the nitration of cellulose), and carbon fibre from aramid or nylon sheets in a nitrogen atmosphere (cracked with no oxygen to burn them). A sheet costs
// POLYMER_UNITS_PER_SHEET units, and grinds back into REAGENTS_PER_SHEET of the same: nothing is made from nothing (code/content/refinery/grinding.dm).

/// Units of a polymer's reagents that make one sheet (a grinder gives back REAGENTS_PER_SHEET of them).
#define POLYMER_UNITS_PER_SHEET 24
/// The most sheets one firing makes.
#define POLYMER_SHEETS_PER_FIRING 5

/datum/polymer_recipe
	var/id
	/// The material of the sheets it makes.
	var/material
	/// Reagent id => units per sheet that the furnace's medium must hold.
	var/list/inputs
	/// Material names, any one of which the furnace's charge must hold a sheet of per sheet made (a polymer made from sheets), or null.
	var/list/sheet_sources
	/// The gas the chamber must be full of (at least MATERIAL_ROAST_OXYGEN moles) and no oxygen to burn in, or null.
	var/atmosphere
	/// The process of the chemistry this is, for the log.
	var/chem_process = CHEM_PROCESS_POLYMERISE

/datum/polymer_recipe/hard_plastic
	id = "hard_plastic"
	material = MAT_HARD_PLASTIC
	inputs = list(REAGENT_ID_PHENOL = 12, REAGENT_ID_WOODALDEHYDE = 12)

/datum/polymer_recipe/rubber
	id = "rubber"
	material = MAT_RUBBER
	inputs = list(REAGENT_ID_FATTYACID = 20, REAGENT_ID_SULFUR = 4)

/datum/polymer_recipe/nylon
	id = "nylon"
	material = MAT_NYLON
	inputs = list(REAGENT_ID_FATTYACID = 12, REAGENT_ID_DIETHYLAMINE = 12)

/datum/polymer_recipe/aramid
	id = "aramid"
	material = MAT_ARAMID
	inputs = list(REAGENT_ID_MYELAMINE = 24)

/datum/polymer_recipe/guncotton
	id = "guncotton"
	material = MAT_GUNCOTTON
	inputs = list(REAGENT_ID_NITRICACID = 20)
	sheet_sources = list(MAT_CLOTH, MAT_CARDBOARD)
	chem_process = CHEM_PROCESS_NITRATE

/datum/polymer_recipe/carbon_fibre
	id = "carbon_fibre"
	material = MAT_CARBON_FIBRE
	sheet_sources = list(MAT_ARAMID, MAT_NYLON)
	atmosphere = /datum/gas/nitrogen
	chem_process = CHEM_PROCESS_CRACK

/// Every recipe, id => the one instance of each.
GLOBAL_LIST_INIT(polymer_recipes, build_polymer_recipes())

/proc/build_polymer_recipes()
	var/list/table = list()
	for(var/type in subtypesof(/datum/polymer_recipe))
		var/datum/polymer_recipe/recipe = new type
		table[recipe.id] = recipe
	return table

/// How many sheets of the recipe the furnace holds the makings of in its medium and its charge (0: it does not fit). It reads no gas: a requirement asks it.
/datum/polymer_recipe/proc/sheets_possible(obj/machinery/material_furnace/furnace)
	var/possible = POLYMER_SHEETS_PER_FIRING
	for(var/reagent_id in inputs)
		possible = min(possible, round(furnace.reagents.get_reagent_amount(reagent_id) / inputs[reagent_id]))
	if(sheet_sources)
		var/have = 0
		for(var/obj/item/stack/material/stock in furnace.feedstock)
			if(stock.material?.name in sheet_sources)
				have += stock.get_amount()
		possible = min(possible, have)
	return max(possible, 0)

/// Does the furnace's chamber hold the atmosphere the recipe needs (the gas it is full of, and no oxygen to burn in)? Read when the furnace fires, never by a requirement
/// (the chamber's gas is not tracked).
/datum/polymer_recipe/proc/atmosphere_fits(obj/machinery/material_furnace/furnace)
	if(!atmosphere)
		return TRUE
	var/datum/gas_mixture/air = furnace.chamber_air
	return air.get_moles(atmosphere) >= MATERIAL_ROAST_OXYGEN && air.get_moles(/datum/gas/oxygen) < 1

/// The recipe whose makings the furnace holds in its medium and charge, whatever its chamber holds, or null (what a requirement asks: can it be fired with no sheets in it).
/proc/polymer_recipe_loaded(obj/machinery/material_furnace/furnace)
	RETURN_TYPE(/datum/polymer_recipe)
	if(!furnace.reagents?.total_volume && !LAZYLEN(furnace.feedstock))
		return null
	for(var/recipe_id in GLOB.polymer_recipes)
		var/datum/polymer_recipe/recipe = GLOB.polymer_recipes[recipe_id]
		if(recipe.sheets_possible(furnace) > 0)
			return recipe
	return null

/// The recipe the furnace makes now: the makings are in it and its chamber is right, or null.
/proc/polymer_recipe_for(obj/machinery/material_furnace/furnace)
	RETURN_TYPE(/datum/polymer_recipe)
	if(!furnace.reagents?.total_volume && !LAZYLEN(furnace.feedstock))
		return null
	for(var/recipe_id in GLOB.polymer_recipes)
		var/datum/polymer_recipe/recipe = GLOB.polymer_recipes[recipe_id]
		if(recipe.sheets_possible(furnace) > 0 && recipe.atmosphere_fits(furnace))
			return recipe
	return null

/// Polymerises the recipe's units into sheets and puts them on the furnace's turf: the reagents and the source sheets are spent, the rest of the medium is cleared.
/obj/machinery/material_furnace/proc/polymerise(datum/polymer_recipe/recipe)
	var/count = recipe.sheets_possible(src)
	if(count <= 0)
		return FALSE
	var/datum/material/made = get_material_by_name(recipe.material)
	for(var/reagent_id in recipe.inputs)
		reagents.remove_reagent(reagent_id, recipe.inputs[reagent_id] * count)
	var/list/spent = list()
	if(recipe.sheet_sources)
		var/still = count
		for(var/obj/item/stack/material/stock as anything in feedstock.Copy())
			if(still <= 0)
				break
			if(!(stock.material?.name in recipe.sheet_sources))
				continue
			var/taken = min(still, stock.get_amount())
			spent += "[taken] [stock.material.name]"
			still -= taken
			stock.use(taken) // a stack used up is destroyed, and its owner lets it go
	reagents.clear_reagents()
	// Whatever else was in the charge stays where it is: the sheets that were not spent come out with it when the furnace is unloaded.
	new made.stack_type(get_turf(src), count)
	material_log("[REF(src)] polymerised [count] sheet\s of [recipe.material] ([recipe.chem_process]) from [json_encode(recipe.inputs)] and [length(spent) ? jointext(spent, ", ") : "no sheets"]")
	visible_message(span_notice("[src] finishes polymerising and pushes out [count] sheet\s of [recipe.material]."))
	return TRUE

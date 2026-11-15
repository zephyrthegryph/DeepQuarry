// The sources of stock and what each carries (the machinery: code/domains/world_model/reagents/trace_sources.dm).
//
// A signature is what the source always has (iron ore is sulfurous; a coal seam is organic); the extras are what a roll may add for a round or a lot. Contaminants only
// from the standard set (code/content/reagents/reagents/content/contaminants.dm): the same ids a material's trace vocabulary maps (material_traces.dm), so a trace in a
// melt and a contaminant in a beaker are one thing. A source is named for the material, the ore or the reagent it is the source of.

/// What each rolled contaminant does to a route, in words: what an assay prints beside it.
GLOBAL_LIST_INIT(trace_route_taxes, list(
	REAGENT_ID_CONTAMINANT_SULFUR = "poisons a solid metal catalyst; in a melt it makes the metal hot-short",
	REAGENT_ID_CONTAMINANT_HEAVY_METAL = "poisons enzymes and metal catalysts; tools of the melt poison",
	REAGENT_ID_CONTAMINANT_REACTIVE = "oxidises the next step; oxide inclusions weaken a melt against corrosion",
	REAGENT_ID_CONTAMINANT_INERT_FILLER = "dilutes the product; silica in a melt",
	REAGENT_ID_CONTAMINANT_SALTS = "salts out an acid group and an amine; chloride in a melt",
	REAGENT_ID_CONTAMINANT_ACID_RESIDUE = "spends the next base step; an acid-borne gas embrittles a melt",
	REAGENT_ID_CONTAMINANT_BASE_RESIDUE = "spends the next acid step; alkali in a melt",
	REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = "carries into every condensation and fouls a crack; chars to carbon in a melt",
	REAGENT_ID_CONTAMINANT_OILY_RESIDUE = "coats a solid catalyst; chars in a melt",
	REAGENT_ID_CONTAMINANT_BIOLOGICAL = "kills nothing but poisons an enzyme's work and a patient's fever",
))

/datum/trace_source/default
	id = TRACE_SOURCE_DEFAULT
	extras = list(REAGENT_ID_CONTAMINANT_SULFUR = 3, REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_INERT_FILLER = 2, REAGENT_ID_CONTAMINANT_HEAVY_METAL = 1.5, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1)
	extras_min = 0
	extras_max = 1

// ---- materials and the reagents of the same name: metals ----

/datum/trace_source/iron
	id = MAT_IRON
	signature = list(REAGENT_ID_CONTAMINANT_SULFUR)
	extras = list(REAGENT_ID_CONTAMINANT_INERT_FILLER = 2, REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_HEAVY_METAL = 1)
	extras_max = 1

/datum/trace_source/steel
	id = MAT_STEEL
	signature = list(REAGENT_ID_CONTAMINANT_SULFUR)
	extras = list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 2, REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_HEAVY_METAL = 1)
	extras_max = 1

/datum/trace_source/copper
	id = MAT_COPPER
	signature = list(REAGENT_ID_CONTAMINANT_SULFUR)
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 3, REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_SALTS = 1)
	extras_max = 2

/datum/trace_source/aluminium
	id = MAT_ALUMINIUM
	signature = list(REAGENT_ID_CONTAMINANT_INERT_FILLER)
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 2, REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_BASE_RESIDUE = 1)
	extras_max = 1

/// The dispenser's aluminium (its reagent id is spelt another way from the material's).
/datum/trace_source/aluminium/reagent
	id = REAGENT_ID_ALUMINIUM

/datum/trace_source/lead
	id = MAT_LEAD
	signature = list(REAGENT_ID_CONTAMINANT_SULFUR)
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 3, REAGENT_ID_CONTAMINANT_REACTIVE = 1)
	extras_max = 1

/datum/trace_source/tin
	id = MAT_TIN
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 2, REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_INERT_FILLER = 1)
	extras_max = 2

/datum/trace_source/titanium
	id = MAT_TITANIUM
	signature = list(REAGENT_ID_CONTAMINANT_SALTS)
	extras = list(REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1, REAGENT_ID_CONTAMINANT_INERT_FILLER = 1)
	extras_max = 1

/datum/trace_source/tungsten
	id = MAT_TUNGSTEN
	extras = list(REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1, REAGENT_ID_CONTAMINANT_SULFUR = 1)
	extras_max = 1

/datum/trace_source/silver
	id = MAT_SILVER
	signature = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	extras = list(REAGENT_ID_CONTAMINANT_SALTS = 2, REAGENT_ID_CONTAMINANT_SULFUR = 1)
	extras_max = 1

/datum/trace_source/gold
	id = MAT_GOLD
	signature = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	extras = list(REAGENT_ID_CONTAMINANT_SALTS = 2, REAGENT_ID_CONTAMINANT_INERT_FILLER = 1)
	extras_max = 1

/datum/trace_source/platinum
	id = MAT_PLATINUM
	signature = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	extras = list(REAGENT_ID_CONTAMINANT_SALTS = 2, REAGENT_ID_CONTAMINANT_REACTIVE = 1)
	extras_max = 1

/datum/trace_source/uranium
	id = MAT_URANIUM
	signature = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	extras = list(REAGENT_ID_CONTAMINANT_SULFUR = 2, REAGENT_ID_CONTAMINANT_ACID_RESIDUE = 1)
	extras_max = 1

// ---- non-metals ----

/datum/trace_source/glass
	id = MAT_GLASS
	signature = list(REAGENT_ID_CONTAMINANT_BASE_RESIDUE)
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 2, REAGENT_ID_CONTAMINANT_SULFUR = 1)
	extras_max = 1

/datum/trace_source/silicon
	id = REAGENT_ID_SILICON
	signature = list(REAGENT_ID_CONTAMINANT_INERT_FILLER)
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 2, REAGENT_ID_CONTAMINANT_REACTIVE = 1, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1)
	extras_max = 1

/datum/trace_source/carbon
	id = REAGENT_ID_CARBON
	signature = list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE)
	extras = list(REAGENT_ID_CONTAMINANT_SULFUR = 2, REAGENT_ID_CONTAMINANT_INERT_FILLER = 2, REAGENT_ID_CONTAMINANT_HEAVY_METAL = 1)
	extras_max = 1

/// Graphite is carbon.
/datum/trace_source/carbon/graphite
	id = MAT_GRAPHITE

/datum/trace_source/phoron
	id = MAT_PHORON
	extras = list(REAGENT_ID_CONTAMINANT_REACTIVE = 2, REAGENT_ID_CONTAMINANT_HEAVY_METAL = 1, REAGENT_ID_CONTAMINANT_INERT_FILLER = 1)
	extras_max = 1

// ---- reagents of the dispenser ----

/datum/trace_source/sulfur
	id = REAGENT_ID_SULFUR
	signature = list(REAGENT_ID_CONTAMINANT_SULFUR)
	extras = list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 2, REAGENT_ID_CONTAMINANT_INERT_FILLER = 1)
	extras_max = 1

/datum/trace_source/sulphuric_acid
	id = REAGENT_ID_SACID
	signature = list(REAGENT_ID_CONTAMINANT_ACID_RESIDUE)
	extras = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 2, REAGENT_ID_CONTAMINANT_SALTS = 1)
	extras_max = 1

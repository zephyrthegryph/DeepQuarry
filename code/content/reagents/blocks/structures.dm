// What each chemistry reagent is built of (the machinery and what is derived: code/domains/world_model/reagents/blocks/structure.dm).
//
// chem_structure_make(cores, groups, links, cation, anion). A group named twice is two of it. Only the reagents the processes act on or make are declared so far;
// the rest of the chemistry joins family by family (the burn medicines are the first family). A declaration here is a decision about what the reagent is: a process
// that ends in this structure makes this reagent. Adding one adds the routes the processes make of it (the pin test, dq_chem_routes_pinned, says which).

GLOBAL_LIST_INIT(chem_declared_structures, list(
	// ---- the inorganic toolkit ----
	REAGENT_ID_WATER = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_HYDROXIDE),
	REAGENT_ID_SACID = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_SULFATE),
	REAGENT_ID_PACID = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_NITRATE),
	REAGENT_ID_LYE = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_HYDROXIDE),
	REAGENT_ID_AMMONIA = chem_structure_make(null, null, null, CHEM_ION_AMMONIUM, CHEM_ION_HYDROXIDE),
	REAGENT_ID_SODIUMCHLORIDE = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_CHLORIDE),
	REAGENT_ID_SILICATE = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_SILICATE),
	// ---- the dispenser's cores ----
	REAGENT_ID_ETHANOL = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_HYDROXYL)),
	REAGENT_ID_SUGAR = chem_structure_make(list(CHEM_CORE_SUGAR_RING), list(CHEM_GROUP_HYDROXYL)),
	REAGENT_ID_GLYCEROL = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_HYDROXYL, CHEM_GROUP_HYDROXYL, CHEM_GROUP_HYDROXYL)),
	REAGENT_ID_DIETHYLAMINE = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN, CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_AMINE)),
	// ---- the burn medicines: a siloxane (silicone burn gel). Silicate and acid make kelotane (neutralise), kelotane and phosphorus make dermaline (phosphorylate) ----
	REAGENT_ID_KELOTANE = chem_structure_make(list(CHEM_CORE_SILOXANE), list(CHEM_GROUP_HYDROXYL)),
	REAGENT_ID_DERMALINE = chem_structure_make(list(CHEM_CORE_SILOXANE), list(CHEM_GROUP_HYDROXYL, CHEM_GROUP_PHOSPHATE)),
	// ---- the contaminants ----
	REAGENT_ID_CONTAMINANT_HEAVY_METAL = chem_structure_make(null, null, null, CHEM_ION_HEAVY_METAL, CHEM_ION_CARBONATE),
	REAGENT_ID_CONTAMINANT_SULFUR = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_SULFATE),
	REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = chem_structure_make(list(CHEM_CORE_RING), list(CHEM_GROUP_HYDROXYL, CHEM_GROUP_CARBONYL)),
	REAGENT_ID_CONTAMINANT_SALTS = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_CHLORIDE),
	REAGENT_ID_CONTAMINANT_ACID_RESIDUE = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_SULFATE),
	REAGENT_ID_CONTAMINANT_BASE_RESIDUE = chem_structure_make(null, null, null, CHEM_ION_SODIUM, CHEM_ION_HYDROXIDE),
	REAGENT_ID_CONTAMINANT_OILY_RESIDUE = chem_structure_make(list(CHEM_CORE_LONG_CHAIN)),
	REAGENT_ID_CONTAMINANT_BIOLOGICAL = chem_structure_make(list(CHEM_CORE_AMINO, CHEM_CORE_AMINO)),
	REAGENT_ID_CONTAMINANT_REACTIVE = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_PEROXIDE),
	REAGENT_ID_CONTAMINANT_HYDROCHLORIC = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_CHLORIDE),
	REAGENT_ID_CONTAMINANT_DIOXIN = chem_structure_make(list(CHEM_CORE_DOUBLE_RING), list(CHEM_GROUP_HALIDE, CHEM_GROUP_HALIDE)),
	REAGENT_ID_CONTAMINANT_NITROSAMINE = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN, CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_AMINE, CHEM_GROUP_NITRO)),
	REAGENT_ID_CONTAMINANT_PEROXIDE = chem_structure_make(null, null, null, CHEM_ION_HYDROGEN, CHEM_ION_PEROXIDE),
	REAGENT_ID_CONTAMINANT_METHANOL = chem_structure_make(list(CHEM_CORE_SHORT_CHAIN), list(CHEM_GROUP_HYDROXYL)),
	REAGENT_ID_CONTAMINANT_PLASTICISER = chem_structure_make(list(CHEM_CORE_RING, CHEM_CORE_SHORT_CHAIN, CHEM_CORE_SHORT_CHAIN), null, list(CHEM_LINK_ESTER, CHEM_LINK_ESTER)),
	REAGENT_ID_CONTAMINANT_TAR = chem_structure_make(list(CHEM_CORE_DOUBLE_RING, CHEM_CORE_LONG_CHAIN)),
))

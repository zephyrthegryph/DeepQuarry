// Boiling points of the reagents (what code/domains/world_model/reagents/boiling.dm reads). Every reagent has one: its own `boiling_point` var when its type
// sets one (the contaminants do), else the row of its id below, else the default of the first category its type belongs to, else BOILING_POINT_DEFAULT.
// All of it is tunable here, in kelvin. A holder hotter than a reagent's boiling point loses that reagent (a hot plate, a bunsen burner); a condenser
// next to the plate collects it, anywhere else the vapour is deleted.

/// reagent id => boiling point (K). Real values where they are known; dissolved gases boil as gases do.
GLOBAL_LIST_INIT(reagent_boiling_points, list(
	REAGENT_ID_WATER = T0C + 100,
	REAGENT_ID_ETHANOL = T0C + 78.4,
	REAGENT_ID_FUEL = T0C + 90,
	REAGENT_ID_SUGAR = T0C + 186,
	REAGENT_ID_GLYCEROL = T0C + 290,
	REAGENT_ID_CAPSAICIN = T0C + 210,
	REAGENT_ID_AMMONIA = T0C + 36,
	REAGENT_ID_DIETHYLAMINE = T0C + 56,
	REAGENT_ID_SACID = T0C + 337,
	REAGENT_ID_PACID = T0C + 165,
	REAGENT_ID_LYE = T0C + 1388,
	REAGENT_ID_SODIUMCHLORIDE = T0C + 1413,
	REAGENT_ID_BLOOD = T0C + 100,
	REAGENT_ID_HYDROGEN = T0C - 253,
	REAGENT_ID_OXYGEN = T0C - 183,
	REAGENT_ID_NITROGEN = T0C - 196,
	REAGENT_ID_CHLORINE = T0C - 34,
	REAGENT_ID_FLUORINE = T0C - 188,
	REAGENT_ID_PHOSPHORUS = T0C + 280,
	REAGENT_ID_SULFUR = T0C + 445,
	REAGENT_ID_MERCURY = T0C + 357,
	REAGENT_ID_SODIUM = T0C + 883,
	REAGENT_ID_POTASSIUM = T0C + 759,
	REAGENT_ID_LITHIUM = T0C + 1342,
	REAGENT_ID_CALCIUM = T0C + 1484,
	REAGENT_ID_RADIUM = T0C + 1737,
	REAGENT_ID_TIN = T0C + 2602,
	REAGENT_ID_COPPER = T0C + 2562,
	REAGENT_ID_ALUMINIUM = T0C + 2470,
	REAGENT_ID_IRON = T0C + 2862,
	REAGENT_ID_SILICON = T0C + 3265,
	REAGENT_ID_TITANIUM = T0C + 3287,
	REAGENT_ID_CARBON = T0C + 3642,
	REAGENT_ID_TUNGSTEN = T0C + 5930,
	// the building blocks, intermediates and process chemicals (reagents/content/chemistry/blocks.dm)
	REAGENT_ID_HYDROCHLORIC = T0C + 110,
	REAGENT_ID_NITRICACID = T0C + 83,
	REAGENT_ID_PHOSPHORICACID = T0C + 158,
	REAGENT_ID_ACETICACID = T0C + 118,
	REAGENT_ID_NITRATINGMIX = T0C + 120,
	REAGENT_ID_PHENOL = T0C + 182,
	REAGENT_ID_BLEACH = T0C + 101,
	REAGENT_ID_SODAASH = BOILING_POINT_NEVER,
	REAGENT_ID_WOODALDEHYDE = T0C + 285,
	REAGENT_ID_SALICYLICACID = T0C + 211,
	REAGENT_ID_FATTYACID = T0C + 360,
	REAGENT_ID_PYRIDINE = T0C + 115,
	REAGENT_ID_ALKALOID = T0C + 300,
	REAGENT_ID_STEROL = T0C + 360,
	REAGENT_ID_AMINOACID = T0C + 280,
	REAGENT_ID_IRONSALT = BOILING_POINT_NEVER,
	REAGENT_ID_COPPERSALT = BOILING_POINT_NEVER,
	REAGENT_ID_LITHIUMSALT = BOILING_POINT_NEVER,
	REAGENT_ID_SAND = BOILING_POINT_NEVER,
	REAGENT_ID_CHLOROHYDRIN = T0C + 190,
	REAGENT_ID_NITROSALICYLIC = T0C + 300,
	REAGENT_ID_CHLOROPHORON = T0C + 140,
	REAGENT_ID_ALKALOIDACID = T0C + 330,
	REAGENT_ID_PYRIDONE = T0C + 280,
	REAGENT_ID_HALOSPACEACILLIN = T0C + 340,
	REAGENT_ID_PEPTIDE = T0C + 350,
	REAGENT_ID_RINGAMINOACID = T0C + 310,
	REAGENT_ID_HALOACETIC = T0C + 189,
	REAGENT_ID_NICOTINICACID = T0C + 260,
	REAGENT_ID_HYDRIDE = BOILING_POINT_NEVER,
	REAGENT_ID_STRONGOXIDISER = BOILING_POINT_NEVER,
	REAGENT_ID_CHLORINATINGAGENT = T0C + 76,
	REAGENT_ID_COUPLINGAGENT = T0C + 200,
	REAGENT_ID_CAUSTICDIGEST = T0C + 140,
	REAGENT_ID_SCAVENGERRESIN = BOILING_POINT_NEVER,
	// the exotic trees' intermediates and finds
	REAGENT_ID_CHLOROFIRE = T0C + 240,
	REAGENT_ID_LIFEACID = T0C + 250,
	REAGENT_ID_HALOSOULDEW = T0C + 320,
	REAGENT_ID_RELICICHOR = T0C + 260,
	REAGENT_ID_RELICESSENCE = T0C + 270,
	REAGENT_ID_VOIDAMBER = T0C + 250,
	REAGENT_ID_CHLOROVOID = T0C + 260,
))

/// The boiling point of a reagent type's category, K: the first row its type belongs to, so a narrower category goes above a wider one.
/// Anything else is an organic compound of the lab shelf (BOILING_POINT_DEFAULT).
GLOBAL_LIST_INIT(reagent_boiling_categories, list(
	/datum/reagent/ethanol = T0C + 80,
	/datum/reagent/drink = T0C + 100,
	/datum/reagent/nutriment = T0C + 105,
))

/// This reagent's boiling point, K.
/datum/reagent/proc/boiling_point_k()
	if(boiling_point > 0)
		return boiling_point
	var/known = GLOB.reagent_boiling_points[id]
	if(!isnull(known))
		return known
	for(var/category_type in GLOB.reagent_boiling_categories)
		if(istype(src, category_type))
			return GLOB.reagent_boiling_categories[category_type]
	return BOILING_POINT_DEFAULT

/datum/reagent
	/// This type's own boiling point, K; 0: the tables above decide (boiling_point_k()).
	var/boiling_point = 0

SCHEMA(/datum/reagent, boiling_point, num())

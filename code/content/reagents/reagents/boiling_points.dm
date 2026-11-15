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

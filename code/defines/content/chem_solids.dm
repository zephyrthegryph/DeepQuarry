// Solids in a glass container (code/content/reagents/purification/solids.dm): a small item lies in the beaker, and either dissolves in the liquid or, left whole, works as a
// solid catalyst.

/// The most solids a glass container holds.
#define CHEM_SOLIDS_MAX 3
/// Units of a solvent that must be in the glass before it dissolves anything.
#define CHEM_SOLID_MIN_SOLVENT 2
/// A solid dissolves this much faster for every 10 K the liquid is above room temperature (and slower below), within the limits below.
#define CHEM_SOLID_HEAT_DOUBLING 10
#define CHEM_SOLID_SPEED_MIN 0.25
#define CHEM_SOLID_SPEED_MAX 16
/// The longest span (seconds) one dissolving step counts, so a beaker that was not asked for a while does not finish its solids at once.
#define CHEM_SOLID_STEP_MAX 30

// What a solid is, by the reagent that makes most of its feedstock (the classes of the table below).
/// Metals: dissolved by an acid.
#define CHEM_SOLID_METAL "metal"
/// Soap, sugars, salts: dissolved by water.
#define CHEM_SOLID_SOLUBLE "soluble"
/// Waxes and oils: dissolved by ethanol.
#define CHEM_SOLID_ORGANIC "organic"

// The columns of a solvent rule.
/// The reagent ids that dissolve the class.
#define CHEM_SOLVENT_IDS 1
/// Seconds one such solid takes to dissolve at room temperature.
#define CHEM_SOLVENT_SECONDS 2
/// Units of solvent spent for each unit of feedstock that comes out (an acid is eaten by the metal; water is not used up).
#define CHEM_SOLVENT_SPEND 3

/// reagent id => the class of solid it makes. A reagent not named (tungsten, gold, glass, plastics) does not dissolve in anything a beaker holds.
GLOBAL_LIST_INIT(chem_solid_classes, list(
	REAGENT_ID_IRON = CHEM_SOLID_METAL,
	REAGENT_ID_COPPER = CHEM_SOLID_METAL,
	REAGENT_ID_ALUMINIUM = CHEM_SOLID_METAL,
	REAGENT_ID_TIN = CHEM_SOLID_METAL,
	REAGENT_ID_LEAD = CHEM_SOLID_METAL,
	REAGENT_ID_LITHIUM = CHEM_SOLID_METAL,
	REAGENT_ID_SILVER = CHEM_SOLID_METAL,
	REAGENT_ID_SUGAR = CHEM_SOLID_SOLUBLE,
	REAGENT_ID_SODIUMCHLORIDE = CHEM_SOLID_SOLUBLE,
	REAGENT_ID_LYE = CHEM_SOLID_SOLUBLE,
	REAGENT_ID_GLYCEROL = CHEM_SOLID_SOLUBLE,
	REAGENT_ID_FATTYACID = CHEM_SOLID_SOLUBLE,
	REAGENT_ID_TRIGLYCERIDE = CHEM_SOLID_ORGANIC,
	REAGENT_ID_NICOTINE = CHEM_SOLID_ORGANIC))

/// class => list(solvent reagent ids, seconds to dissolve at room temperature, units of solvent spent per unit dissolved).
GLOBAL_LIST_INIT(chem_solid_solvents, list(
	CHEM_SOLID_METAL = list(list(REAGENT_ID_SACID, REAGENT_ID_HYDROCHLORIC, REAGENT_ID_NITRICACID, REAGENT_ID_PACID), 90, 0.25),
	CHEM_SOLID_SOLUBLE = list(list(REAGENT_ID_WATER), 45, 0),
	CHEM_SOLID_ORGANIC = list(list(REAGENT_ID_ETHANOL), 60, 0)))

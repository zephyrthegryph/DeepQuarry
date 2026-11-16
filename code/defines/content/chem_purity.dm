// Mixture purity: the share of a holder that is contaminant (code/domains/world_model/reagents/contaminants.dm).
//
// A contaminant is a reagent (/datum/reagent/contaminant, code/content/reagents/reagents/content/contaminants.dm) with a volume of its own. A holder's purity
// is 1 minus the contaminant volume over its total volume, computed, never stored; its grade is the band the purity falls in.

/// Grades, worst to best: a readout of a mixture's purity (no recipe asks for one).
#define GRADE_CRUDE 1
#define GRADE_STANDARD 2
#define GRADE_PHARMA 3
#define GRADE_REAGENT 4

/// Lowest purity of each grade (a purity under PURITY_STANDARD is Crude).
#define PURITY_STANDARD 0.6
#define PURITY_PHARMA 0.9
#define PURITY_REAGENT 0.99

/// Slack when a computed purity is compared with a band edge (a purity of exactly 0.9 is Pharma despite float rounding).
#define PURITY_EPSILON 0.0001

// The contaminant reagents (names and ids).
#define REAGENT_CONTAMINANT_HEAVY_METAL "Heavy metals"
#define REAGENT_ID_CONTAMINANT_HEAVY_METAL "contaminant_heavy_metal"
#define REAGENT_CONTAMINANT_SULFUR "Sulfur compounds"
#define REAGENT_ID_CONTAMINANT_SULFUR "contaminant_sulfur"
#define REAGENT_CONTAMINANT_ORGANIC_RESIDUE "Organic residue"
#define REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE "contaminant_organic_residue"
#define REAGENT_CONTAMINANT_SALTS "Salts"
#define REAGENT_ID_CONTAMINANT_SALTS "contaminant_salts"
#define REAGENT_CONTAMINANT_ACID_RESIDUE "Acid residue"
#define REAGENT_ID_CONTAMINANT_ACID_RESIDUE "contaminant_acid_residue"
#define REAGENT_CONTAMINANT_BASE_RESIDUE "Base residue"
#define REAGENT_ID_CONTAMINANT_BASE_RESIDUE "contaminant_base_residue"
#define REAGENT_CONTAMINANT_OILY_RESIDUE "Oily residue"
#define REAGENT_ID_CONTAMINANT_OILY_RESIDUE "contaminant_oily_residue"
#define REAGENT_CONTAMINANT_INERT_FILLER "Inert filler"
#define REAGENT_ID_CONTAMINANT_INERT_FILLER "contaminant_inert_filler"
#define REAGENT_CONTAMINANT_BIOLOGICAL "Endotoxin"
#define REAGENT_ID_CONTAMINANT_BIOLOGICAL "contaminant_biological"
#define REAGENT_CONTAMINANT_REACTIVE "Reactive impurity"
#define REAGENT_ID_CONTAMINANT_REACTIVE "contaminant_reactive"
// The trace-potent contaminants: made by processes, strong at a trace (code/content/reagents/blocks/).
#define REAGENT_CONTAMINANT_HYDROCHLORIC "Hydrochloric acid"
#define REAGENT_ID_CONTAMINANT_HYDROCHLORIC "contaminant_hydrochloric"
#define REAGENT_CONTAMINANT_DIOXIN "Dioxin"
#define REAGENT_ID_CONTAMINANT_DIOXIN "contaminant_dioxin"
#define REAGENT_CONTAMINANT_NITROSAMINE "Nitrosamine"
#define REAGENT_ID_CONTAMINANT_NITROSAMINE "contaminant_nitrosamine"
#define REAGENT_CONTAMINANT_PEROXIDE "Peroxide"
#define REAGENT_ID_CONTAMINANT_PEROXIDE "contaminant_peroxide"
#define REAGENT_CONTAMINANT_METHANOL "Methanol"
#define REAGENT_ID_CONTAMINANT_METHANOL "contaminant_methanol"
#define REAGENT_CONTAMINANT_PLASTICISER "Plasticiser"
#define REAGENT_ID_CONTAMINANT_PLASTICISER "contaminant_plasticiser"
#define REAGENT_CONTAMINANT_TAR "Tar"
#define REAGENT_ID_CONTAMINANT_TAR "contaminant_tar"

// Roles: what a contaminant does to the patient.
#define CONTAMINANT_ROLE_TOXIC "toxic"           // slow organ damage per unit
#define CONTAMINANT_ROLE_INERT "inert"           // only takes up volume: dilutes whatever it is mixed with
#define CONTAMINANT_ROLE_REACTIVE "reactive"     // a chance of a minor burn
#define CONTAMINANT_ROLE_BIOLOGICAL "biological" // toxin and a mild fever

/// A purity band is rolled this far inside its edges, so a rolled source never sits on a boundary.
#define CONTAMINANT_ROLL_MARGIN 0.02

// ---- Purification by temperature, boiling and filtering (code/domains/world_model/reagents/chem_temperature.dm, boiling.dm, code/content/reagents/purification/) ----

/// The temperature classes a reaction is filed under (code/content/reagents/reactions/reaction_temperatures.dm): the working range and the ideal band inside it.
#define REACTION_TEMP_AMBIENT "ambient"
#define REACTION_TEMP_GENTLE "gentle"
#define REACTION_TEMP_WARM "warm"
#define REACTION_TEMP_HOT "hot"
#define REACTION_TEMP_VIOLENT "violent"

/// Off the ideal band but inside the working range, a reaction makes contaminants and loses product, each scaled by how far off it is (0 at the band's edge, 1 at the
/// edge of the range): units of contaminant per unit of product at the far end of the range, and the share of the product lost to heat.
#define REACTION_COLD_RESIDUE_RATE 0.6
#define REACTION_HOT_IMPURITY_RATE 0.4
#define REACTION_HOT_LOSS_SHARE 0.25

/// A reagent with no boiling point of its own boils at this temperature, K.
#define BOILING_POINT_DEFAULT (T0C + 200)
/// A reagent that effectively never boils (salts, heavy metals).
#define BOILING_POINT_NEVER 5000
/// Units per second boiled off per kelvin above the boiling point, never less than the minimum rate (units per second) while above it.
#define BOIL_RATE_PER_KELVIN 0.08
#define BOIL_RATE_MINIMUM 0.2
/// Joules a unit of boiled-off reagent carries away from the container.
#define BOIL_LATENT_HEAT 1800

/// The power of a hot plate's element, W, and the hottest it can be set.
#define HOT_PLATE_POWER 4000
#define HOT_PLATE_MAX_TEMP (T0C + 300)
/// The share of the product a filter keeps back (units of product held per unit passed), by filter.
#define FILTER_RETENTION_PAPER 0.02
#define FILTER_RETENTION_CHARCOAL 0.04
#define FILTER_RETENTION_SORBENT 0.03
/// The most of any one contaminant class a filter can take out of a unit passing (before saturation and the material's stats).
#define FILTER_STRENGTH_MAX 0.9

/// What the temperature of a holder says about a reaction (reaction_temperature_state()): inside the ideal band, below it, above it, outside the working range.
#define REACTION_TEMP_STATE_IDEAL 0
#define REACTION_TEMP_STATE_COLD -1
#define REACTION_TEMP_STATE_HOT 1
#define REACTION_TEMP_STATE_OUT 2

// ---- Rolled traces (code/domains/world_model/reagents/trace_sources.dm) ----

/// A roll's scope: one roll for the whole round (station stock, the dispenser's cartridges, the lab's bottles), or one per lot (an ore vein, a cargo shipment, an expedition site).
#define TRACE_SCOPE_ROUND "round"
#define TRACE_SCOPE_LOT "lot"
/// The key of the round-wide roll.
#define TRACE_KEY_STATION "station"
/// The source a thing with no entry of its own is rolled as.
#define TRACE_SOURCE_DEFAULT "default"
/// Sheets of a trace per sheet of stock for a signature contaminant at full strength (a rolled strength is 0.3 to 1.2 of it).
#define TRACE_SHEET_SHARE 0.02
/// A lot is dirtier than station stock by this factor (raw ore carries more than refined stock).
#define TRACE_LOT_DIRT 1.6
/// Units of a contaminant that come out of one ground ore at full strength.
#define TRACE_ORE_UNITS 0.8

// ---- Vessel leaching (code/content/reagents/vessel_leaching.dm) ----

/// Units of a contaminant a vessel gives up per step or second at full strength (one harsh share, a fully susceptible material), before the material's resistance.
#define VESSEL_LEACH_UNIT 0.05
/// The least a leach gives up (twice the least volume a holder keeps).
#define VESSEL_LEACH_MINIMUM (MINIMUM_CHEMICAL_VOLUME * 2)
/// The share of the contents that is harsh (strong acid or base, process chemical, oxidiser) below which the vessel leaches nothing for it.
#define VESSEL_HARSH_FLOOR 0.05
/// How far above the material's hot point (K) the contents add one more unit of leaching, and the most a heat term counts.
#define VESSEL_HOT_SPAN 100
#define VESSEL_HOT_MAX 3
/// The temperature (K) above which a metal or a plastic leaches into what it holds, harsh or not.
#define VESSEL_HOT_POINT (T0C + 60)
/// The temperature (K) above which ordinary glass gives up a silicate trace.
#define VESSEL_GLASS_HOT_POINT (T0C + 150)

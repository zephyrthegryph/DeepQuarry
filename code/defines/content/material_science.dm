#define MATERIAL_PHASE_SOLID "solid"
#define MATERIAL_PHASE_MOLTEN "molten"

#define MATERIAL_SURFACE_CARBON "carbon case"
#define MATERIAL_SURFACE_SLIME_METAL "metal slime skin"
#define MATERIAL_SURFACE_SLIME_CRYO "cryogenic slime skin"
#define MATERIAL_SURFACE_SLIME_THERMAL "thermal slime skin"
#define MATERIAL_SURFACE_SLIME_CONDUCTIVE "conductive slime skin"
#define MATERIAL_SURFACE_SLIME_CORROSION "corrosion-resistant slime skin"
#define MATERIAL_SURFACE_SLIME_CATALYTIC "catalytic slime skin"
#define MATERIAL_SURFACE_SLIME_BLUESPACE "bluespace slime skin"

#define MATERIAL_FIELD_PARTICLE "particle-conditioned lattice"
#define MATERIAL_FIELD_EMITTER "emitter-charged lattice"
#define MATERIAL_FIELD_FUSION "fusion-field stabilized lattice"
#define MATERIAL_FIELD_RADIATION_HARDENED "radiation-hardened lattice"
#define MATERIAL_FIELD_ENERGY_STORAGE "energized storage lattice"

// The card: the six core stats every material has, on one scale (steel is 60 strength, 75 toughness, about 39 heat
// resistance; exotic stock may run past 100). Everything else a material does is a trait (traits below), present only
// when the material has it.
#define MATERIAL_STAT_STRENGTH "strength"
#define MATERIAL_STAT_TOUGHNESS "toughness"
#define MATERIAL_STAT_HEAT_RESISTANCE "heat_resistance"
#define MATERIAL_STAT_CONDUCTIVITY "conductivity"
#define MATERIAL_STAT_CORROSION_RESISTANCE "corrosion_resistance"
#define MATERIAL_STAT_WEIGHT "weight"
/// The card's stats in display order.
#define MATERIAL_CARD_STATS list(MATERIAL_STAT_STRENGTH, MATERIAL_STAT_TOUGHNESS, MATERIAL_STAT_HEAT_RESISTANCE, MATERIAL_STAT_CONDUCTIVITY, MATERIAL_STAT_CORROSION_RESISTANCE, MATERIAL_STAT_WEIGHT)

// Traits: id -> one strength (0-100). A trait the material lacks has no entry.
#define MT_SUPERCONDUCTING "superconducting"
#define MT_THERMAL_BUFFER "thermal buffer"
#define MT_CRYO_BUFFER "cryogenic buffer"
#define MT_THERMAL_SWITCH "thermal switch"
#define MT_SHAPE_MEMORY "shape memory"
#define MT_PIEZOELECTRIC "piezoelectric"
#define MT_THERMOELECTRIC "thermoelectric"
#define MT_RADIOVOLTAIC "radiovoltaic"
#define MT_FIELD_STORAGE "field storage"
#define MT_EXOTHERMIC "exothermic"
#define MT_REACTIVE "reactive"
#define MT_CATALYTIC "catalytic"
#define MT_SORBENT "sorbent"
#define MT_ANTIMICROBIAL "antimicrobial"
#define MT_HEMOSTATIC "hemostatic"
#define MT_LUMINESCENT "luminescent"
#define MT_RADIOACTIVE "radioactive"
#define MT_TOXIC "toxic"

/// Traits that are measured, not fixed: a batch's composition and treatment can lower or raise them.
#define MATERIAL_TRAIT_IDS list(MT_SUPERCONDUCTING, MT_THERMAL_BUFFER, MT_CRYO_BUFFER, MT_THERMAL_SWITCH, MT_SHAPE_MEMORY, MT_PIEZOELECTRIC, MT_THERMOELECTRIC, MT_RADIOVOLTAIC, MT_FIELD_STORAGE, MT_EXOTHERMIC, MT_REACTIVE, MT_CATALYTIC, MT_SORBENT, MT_ANTIMICROBIAL, MT_HEMOSTATIC, MT_LUMINESCENT, MT_RADIOACTIVE, MT_TOXIC)

/// Steel's toughness and heat resistance: calibration formulas that were authored against a steel part measure a part against these.
#define MATERIAL_REFERENCE_TOUGHNESS 75
#define MATERIAL_REFERENCE_HEAT 38.75
#define MATERIAL_REFERENCE_CORROSION 50
/// Hit points one point of toughness gives a structure (a wall, a girder, a door, a weapon's wear).
#define MATERIAL_HP_PER_TOUGHNESS 2
/// The temperatures a trait's fixed threshold sits at (one strength is all a trait carries).
#define MATERIAL_THERMAL_BUFFER_TEMPERATURE (T0C + 40)
#define MATERIAL_CRYO_BUFFER_TEMPERATURE 250
#define MATERIAL_SHAPE_MEMORY_TEMPERATURE (T0C + 80)
/// A batch's temper and flaws at rest: tempered halfway, a little flawed.
#define MATERIAL_TEMPER_DEFAULT 30
#define MATERIAL_FLAWS_DEFAULT 20

// Rare feedstocks are concrete phases, not spell-like effect payloads. They
// enter the same batch/composite model as ordinary metals and ceramics.
#define MAT_VOLTAIC_CRYSTAL "voltaic crystal"
#define MAT_THERMIC_CERAMIC "thermic ceramic"
#define MAT_KINETIC_CRYSTAL "kinetic crystal"
#define MAT_WARD_METAL "ward metal"
#define MAT_SPORE_BIOMASS "spore biomass"
#define MAT_ETCHING_CERAMIC "etching ceramic"
#define MAT_LUMEN_CRYSTAL "lumen crystal"
#define MAT_RIFT_GLASS "rift glass"

#define MATERIAL_PROCESS_MELT "melt"
#define MATERIAL_PROCESS_CAST "cast"
#define MATERIAL_PROCESS_QUENCH "quench"
#define MATERIAL_PROCESS_FORGE "forge"
#define MATERIAL_PROCESS_PURIFY "purify"
#define MATERIAL_PROCESS_HOMOGENIZE "homogenize"
#define MATERIAL_PROCESS_SOLUTION_TREAT "solution treat"
#define MATERIAL_PROCESS_ANNEAL "anneal"

/// Refining a melt with the shared chemistry processes (code/content/materials/engineering/material_traces.dm): reduce is smelting, oxidise roasting, displace
/// fluxing, electrolyse electrorefining, and a hard vacuum degasses. Each takes a trace down to its own floor (a percent of the batch), never to nothing.
#define MATERIAL_REFINE_SMELT "smelt"
#define MATERIAL_REFINE_ROAST "roast"
#define MATERIAL_REFINE_FLUX "flux"
#define MATERIAL_REFINE_ELECTRO "electrorefine"
#define MATERIAL_REFINE_DEGAS "degas"
/// Joules the furnace's current takes to electrorefine a charge, and the moles of oxygen a chamber needs for a roast (ordinary air holds about 4).
#define MATERIAL_ELECTROREFINE_ENERGY 200000
#define MATERIAL_ROAST_OXYGEN 8

/// A spectrometer reading: the one assay, it reveals the traces in a stack or lot.
#define MATERIAL_TEST_SPECTROMETRY "spectrometry"

#define MATERIAL_APPLICATION_TOOL "engineering tool"
#define MATERIAL_APPLICATION_SURGICAL "surgical instrument"
#define MATERIAL_APPLICATION_CELL "power cell"
#define MATERIAL_APPLICATION_ARMOR "armor"
#define MATERIAL_APPLICATION_PRESSURE "pressure service"
#define MATERIAL_APPLICATION_MACHINE_PART "machine component"
#define MATERIAL_APPLICATION_PROJECTILE "projectile"
#define MATERIAL_APPLICATION_ELECTRONICS "electronic assembly"
#define MATERIAL_APPLICATION_FIREARM "firearm"
#define MATERIAL_APPLICATION_CONTAINER "container"
#define MATERIAL_APPLICATION_CAPACITOR "capacitor"
#define MATERIAL_APPLICATION_MANIPULATOR "servo manipulator"
#define MATERIAL_APPLICATION_MATTER_BIN "matter containment bin"
#define MATERIAL_APPLICATION_SCANNER "sensor module"
#define MATERIAL_APPLICATION_LASER "emitter module"
#define MATERIAL_APPLICATION_MAGAZINE "ammunition magazine"
#define MATERIAL_APPLICATION_CIRCUIT_BOARD "circuit board"
#define MATERIAL_APPLICATION_SOFT_GOODS "soft goods"
#define MATERIAL_APPLICATION_MECHANICAL "mechanical assembly"
#define MATERIAL_APPLICATION_ENERGY_DEVICE "powered device"
#define MATERIAL_APPLICATION_CABLE "electrical cable"
#define MATERIAL_APPLICATION_LIGHT "light source"
#define MATERIAL_APPLICATION_MONOLITHIC "single-material object"

// Universal manufactured-object roles. A design chooses a small meaningful
// subset; the finished object stores the material used for every role.
#define MATERIAL_ROLE_BODY "body"
#define MATERIAL_ROLE_STRUCTURE "structure"
#define MATERIAL_ROLE_WORKING "working surface"
#define MATERIAL_ROLE_GRIP "grip"
#define MATERIAL_ROLE_CONDUCTOR "conductor"
#define MATERIAL_ROLE_ELECTRODE "electrodes"
#define MATERIAL_ROLE_THERMAL "thermal buffer"
#define MATERIAL_ROLE_INSULATION "insulation"
#define MATERIAL_ROLE_LINER "liner"
#define MATERIAL_ROLE_JACKET "jacket"
#define MATERIAL_ROLE_OPTICAL "optical element"
#define MATERIAL_ROLE_CATALYST "catalyst"
#define MATERIAL_ROLE_SUBSTRATE "substrate"
#define MATERIAL_ROLE_CONTACTS "contacts"
#define MATERIAL_ROLE_BARREL "barrel"
#define MATERIAL_ROLE_DIELECTRIC "dielectric"
#define MATERIAL_ROLE_ACTUATOR "actuator"
#define MATERIAL_ROLE_BEARINGS "bearings"
#define MATERIAL_ROLE_SENSOR "sensor element"
#define MATERIAL_ROLE_EMITTER "emitter element"
#define MATERIAL_ROLE_FEED "feed mechanism"
#define MATERIAL_ROLE_SPRING "spring"
#define MATERIAL_ROLE_FRAME "frame"
#define MATERIAL_ROLE_FASTENERS "fasteners"
#define MATERIAL_ROLE_FABRIC "fabric"
#define MATERIAL_ROLE_CASING "cartridge case"
#define MATERIAL_ROLE_PRIMER "primer"

#define MATERIAL_LAYER_CORE "conductive/load-bearing core"
#define MATERIAL_LAYER_FUNCTIONAL "functional buffer"
#define MATERIAL_LAYER_LINER "internal liner"
#define MATERIAL_LAYER_JACKET "external jacket"

#define MATERIAL_COMPONENT_CABLE "power cable"
#define MATERIAL_COMPONENT_PIPE "pressure pipe"
#define MATERIAL_COMPONENT_VESSEL "chemical vessel"
#define MATERIAL_COMPONENT_STRUCTURE "structural panel"

#define MATERIAL_CABLE_REFERENCE_AREA 12
#define MATERIAL_SERVICE_INTERVAL (10 SECONDS)
/// Window over which services admitted during world init take their first (baseline) sample.
#define MATERIAL_SERVICE_BOOT_SPREAD (3 SECONDS)
#define MATERIAL_SERVICE_MAX_ELAPSED 10
#define MATERIAL_POWER_HEAT_SETTLEMENT_INTERVAL (5 SECONDS)
#define MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL (10 SECONDS)
#define MATERIAL_THERMAL_RESOLUTION 0.05
#define MATERIAL_POWER_LOAD_ABSOLUTE_EPSILON 1
#define MATERIAL_POWER_LOAD_RELATIVE_EPSILON 0.05
#define MATERIAL_SERVICE_NOMINAL_VOLTAGE 1000
#define MATERIAL_SERVICE_REFERENCE_MASS 8
#define MATERIAL_SERVICE_RESISTANCE_SCALE 0.001
#define MATERIAL_CHARGE_FLOAT_EPSILON 0.00000011920928955078125
#define MATERIAL_POWER_EDGE_A 1
#define MATERIAL_POWER_EDGE_B 2
#define MATERIAL_POWER_EDGE_R 3
#define MATERIAL_POWER_EDGE_CABLES 4
#define MATERIAL_POWER_EDGE_CURRENT 5
#define MATERIAL_POWER_EDGE_WEIGHTS 6
#define MATERIAL_POWER_EDGE_DIRTY 7
#define MATERIAL_POWER_EDGE_CRITICAL 8
#define MATERIAL_PIPE_REFERENCE_RADIUS 40
#define MATERIAL_PIPE_REFERENCE_THICKNESS 4
#define MATERIAL_PRESSURE_STRESS_RATIO 0.78
#define MATERIAL_PRESSURE_FATIGUE_RATIO 0.90
#define MATERIAL_PRESSURE_RECOVERY_RATIO 0.85
#define MATERIAL_PRESSURE_BURST_RATIO 1.25
#define MATERIAL_PRESSURE_FATIGUE_RATE 4
#define MATERIAL_PRESSURE_RECOVERY_RATE 2
#define MATERIAL_CANISTER_REFERENCE_RADIUS 250
#define MATERIAL_CANISTER_REFERENCE_THICKNESS 8
#define MATERIAL_TANK_REFERENCE_RADIUS 60
#define MATERIAL_TANK_REFERENCE_THICKNESS 3

// Material-service admission is event driven. These are observations, not
// owner types: every assembly enters and leaves the same lifecycle policy.
#define MATERIAL_EVENT_CONFIGURATION "configuration"
#define MATERIAL_EVENT_MONITORING "monitoring"
#define MATERIAL_EVENT_PRESSURE "pressure"
#define MATERIAL_EVENT_TEMPERATURE "temperature"
#define MATERIAL_EVENT_CORROSION "corrosion"
#define MATERIAL_EVENT_ELECTRICAL "electrical"
#define MATERIAL_EVENT_DAMAGE "damage"
#define MATERIAL_EVENT_WORK "work"

/// Powered devices may draw above their ordinary envelope when their cell's
/// conductor is actively superconducting. The device chooses a lower ceiling
/// when its own construction cannot survive the full output.
#define MATERIAL_SUPERCONDUCTING_MAX_OUTPUT 1.5
#define MATERIAL_SUPERCONDUCTING_RECOVERY_MARGIN 5
#define MATERIAL_SUPERCONDUCTING_OVERDRIVE_HEAT 0.08


#define CONTRACT_EVENT_MATERIAL_PROCESSED "material_processed"
#define CONTRACT_EVENT_MATERIAL_CERTIFIED "material_certified"

#define MATERIAL_SCIENCE_MAX_BATCH 50
#define MATERIAL_SCIENCE_REAGENT_SAMPLE 10

#define MATERIAL_COST_FEEDSTOCK "feedstock"
#define MATERIAL_COST_CHEMICALS "chemical additives"
#define MATERIAL_COST_CATALYSTS "catalysts"
#define MATERIAL_COST_ELECTRICITY "electricity"
#define MATERIAL_COST_MEDIA "process media"
#define MATERIAL_COST_LABOR "process time"
#define MATERIAL_COST_EQUIPMENT "equipment wear"
#define MATERIAL_COST_WASTE_HANDLING "waste handling"
#define MATERIAL_COST_RECOVERY "byproduct recovery"
#define MATERIAL_COST_WASTE "waste value"
#define MATERIAL_POWER_UNITS_PER_THALER 1000
#define MATERIAL_LABOR_COST_PER_SECOND 0.25
#define MATERIAL_EQUIPMENT_COST_PER_SECOND 0.1

/// Role of the single-role bulk template, and of each material in a mix template.
#define MATERIAL_ROLE_BULK "bulk"
#define MATERIAL_BULK_ROLE(material_id) "bulk [material_id]"

/**
 * An object made of one plain material: MATERIAL_BULK(MAT_STEEL, 500) in its type body.
 * No lists: the template, material and total are plain type vars.
 */
#define MATERIAL_BULK(material_id, total) material_template = /datum/material_template/bulk; material_bulk_material = material_id; material_total = total

/**
 * An object made of a fixed mix of plain materials, declared at top level (not inside the
 * type body) just before the type:
 *     MATERIAL_MIX(/obj/item/foo, list(MAT_STEEL = 500, MAT_GLASS = 250))
 * Expands to an absolute declared_material_mix() override returning a proc-local static,
 * interned mix template (one per distinct mix, shared by every instance). The static
 * initialiser also registers it by type at world start, so it can be read without an instance.
 * Top level because DreamChecker forbids relatively pathed procs inside a type body.
 */
#define MATERIAL_MIX(P, L) P/material_template = /datum/material_template/mix; P/declared_material_mix() { var/static/datum/material_template/mix/_material_mix = dq_register_material_mix(P, L); return _material_mix; }

/// An object with no material composition, clearing any inherited one.
#define MATERIAL_NONE material_template = null

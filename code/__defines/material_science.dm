#define MATERIAL_PHASE_SOLID "solid"
#define MATERIAL_PHASE_MOLTEN "molten"
#define MATERIAL_PHASE_POWDER "powder"
#define MATERIAL_PHASE_SOLUTION "solution"

#define MATERIAL_SURFACE_CARBON "carbon case"
#define MATERIAL_SURFACE_SLIME_METAL "metal slime skin"
#define MATERIAL_SURFACE_SLIME_CRYO "cryogenic slime skin"
#define MATERIAL_SURFACE_SLIME_THERMAL "thermal slime skin"
#define MATERIAL_SURFACE_SLIME_CONDUCTIVE "conductive slime skin"
#define MATERIAL_SURFACE_SLIME_CORROSION "corrosion-resistant slime skin"
#define MATERIAL_SURFACE_SLIME_CATALYTIC "catalytic slime skin"
#define MATERIAL_SURFACE_SLIME_BLUESPACE "bluespace slime skin"
#define MATERIAL_SURFACE_PLATING "chemical plating"
#define MATERIAL_SURFACE_OXIDE "oxide scale"

#define MATERIAL_FIELD_PARTICLE "particle-conditioned lattice"
#define MATERIAL_FIELD_MAGNETIC "magnetically aligned lattice"

#define MATERIAL_PROCESS_MELT "melt"
#define MATERIAL_PROCESS_CAST "cast"
#define MATERIAL_PROCESS_ANNEAL "anneal"
#define MATERIAL_PROCESS_QUENCH "quench"
#define MATERIAL_PROCESS_TEMPER "temper"
#define MATERIAL_PROCESS_SINTER "sinter"
#define MATERIAL_PROCESS_FORGE "forge"
#define MATERIAL_PROCESS_PURIFY "purify"
#define MATERIAL_PROCESS_ELECTROLYZE "electrolyze"
#define MATERIAL_PROCESS_CRYSTALLIZE "crystallize"
#define MATERIAL_PROCESS_HEAT "heat"
#define MATERIAL_PROCESS_COOL "controlled cool"
#define MATERIAL_PROCESS_HOMOGENIZE "homogenize"
#define MATERIAL_PROCESS_SOLUTION_TREAT "solution treat"
#define MATERIAL_PROCESS_DISSOLVE "dissolve"
#define MATERIAL_PROCESS_PULVERIZE "pulverize"
#define MATERIAL_PROCESS_PLATE "electroplate"

#define MATERIAL_STRUCTURE_SOFT "soft matrix"
#define MATERIAL_STRUCTURE_HARDENED "hardened matrix"
#define MATERIAL_STRUCTURE_PRECIPITATE "precipitate"
#define MATERIAL_STRUCTURE_REINFORCEMENT "reinforcement"
#define MATERIAL_STRUCTURE_AMORPHOUS "amorphous"
#define MATERIAL_STRUCTURE_DEFECT "defect"

#define MATERIAL_TEST_SPECTROMETRY "spectrometry"
#define MATERIAL_TEST_MICROSCOPY "microscopy"
#define MATERIAL_TEST_HARDNESS "hardness indentation"
#define MATERIAL_TEST_CONDUCTIVITY "conductivity probe"
#define MATERIAL_TEST_TENSILE "tensile test"
#define MATERIAL_TEST_CORROSION "corrosion exposure"
#define MATERIAL_TEST_FIELD "fabricated article field test"

#define MATERIAL_ATMOSPHERE_AIR "air"
#define MATERIAL_ATMOSPHERE_INERT "nitrogen"
#define MATERIAL_ATMOSPHERE_VACUUM "vacuum"
#define MATERIAL_ATMOSPHERE_REDUCING "hydrogen"

#define MATERIAL_APPLICATION_TOOL "engineering tool"
#define MATERIAL_APPLICATION_SURGICAL "surgical instrument"
#define MATERIAL_APPLICATION_CELL "power cell"
#define MATERIAL_APPLICATION_ARMOR "armor"
#define MATERIAL_APPLICATION_PRESSURE "pressure service"

// Emergent capabilities carried by processed materials into every manufactured form.
#define MATERIAL_CAP_THERMOELECTRIC "thermoelectric"
#define MATERIAL_CAP_PIEZOELECTRIC "piezoelectric"
#define MATERIAL_CAP_ELECTROGENIC "electrogenic"
#define MATERIAL_CAP_SHAPE_MEMORY "shape_memory"
#define MATERIAL_CAP_SUPERCONDUCTING "superconducting"
#define MATERIAL_CAP_CATALYTIC "catalytic"
#define MATERIAL_CAP_ANTIMICROBIAL "antimicrobial"
#define MATERIAL_CAP_HEMOSTATIC "hemostatic"
#define MATERIAL_CAP_BIOMIMETIC "biomimetic"
#define MATERIAL_CAP_RADIOVOLTAIC "radiovoltaic"
#define MATERIAL_CAP_SCINTILLATING "scintillating"
#define MATERIAL_CAP_MAGNETOSTRICTIVE "magnetostrictive"
#define MATERIAL_CAP_REACTIVE_ARMOR "reactive_armor"
#define MATERIAL_CAP_PHASE_CHANGE "phase_change"
#define MATERIAL_CAP_GAS_GETTER "gas_getter"
#define MATERIAL_CAP_POROUS_REAGENT "porous_reagent"
#define MATERIAL_CAP_OPTICAL "optical_metamaterial"
#define MATERIAL_CAP_RESONANT "resonant"

#define MATERIAL_CAPABILITY_COOLDOWN (2 SECONDS)
#define MATERIAL_CAPABILITY_PIEZO_COOLDOWN (1 SECOND)
#define MATERIAL_CAPABILITY_ENERGY_SETTLE_LIMIT (5 MINUTES)
#define MATERIAL_CAPABILITY_PHASE_JOULES_PER_POTENCY 5000
#define MATERIAL_CAPABILITY_REACTIVE_CHARGE_ENERGY 1000
#define MATERIAL_CAPABILITY_MAX_CHARGES 6

#define COMSIG_MATERIAL_SURGERY "material_surgery"

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

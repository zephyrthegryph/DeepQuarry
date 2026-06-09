


#define MOLES_PHORON_VISIBLE 0.7 // Moles in a standard cell after which phoron is visible.
#define MOLES_O2ATMOS (MOLES_O2STANDARD*50)
#define MOLES_N2ATMOS (MOLES_N2STANDARD*50)

// These are for when a mob breathes poisonous air.
#define MIN_TOXIN_DAMAGE 1
#define MAX_TOXIN_DAMAGE 10

#define BREATH_MOLES        (ONE_ATMOSPHERE * BREATH_VOLUME / (T20C * R_IDEAL_GAS_EQUATION)) // Amount of air to take a from a tile
#define HUMAN_NEEDED_OXYGEN (MOLES_CELLSTANDARD * BREATH_PERCENTAGE * 0.16)
#define HUMAN_HEAT_CAPACITY 280000 //J/K For 80kg person

#define         LOW_PRESSURE_DAMAGE 2 // The amount of damage someone takes when in a low pressure area. (The pressure threshold is so low that it doesn't make sense to do any calculations, so it just applies this flat value).

#define MINIMUM_PRESSURE_DIFFERENCE_TO_SUSPEND (MINIMUM_AIR_TO_SUSPEND*R_IDEAL_GAS_EQUATION*T20C)/CELL_VOLUME			// Minimum pressure difference between zones to suspend

#define MINIMUM_TEMPERATURE_RATIO_TO_SUSPEND      0.012        // Minimum temperature difference before group processing is suspended.

// Must be between 0 and 1. Values closer to 1 equalize temperature faster. Should not exceed 0.4, else strange heat flow occurs.
#define  FLOOR_HEAT_TRANSFER_COEFFICIENT 0.4
#define   DOOR_HEAT_TRANSFER_COEFFICIENT 0.0
#define  SPACE_HEAT_TRANSFER_COEFFICIENT 0.2 // A hack to partly simulate radiative heat.

// Fire damage.
#define CARBON_LIFEFORM_FIRE_RESISTANCE (T0C + 200)
#define CARBON_LIFEFORM_FIRE_DAMAGE     4

// Phoron fire properties.
#define PHORON_MINIMUM_BURN_TEMPERATURE    (T0C +  126) //400 K - autoignite temperature in tanks and canisters - enclosed environments I guess
#define PHORON_FLASHPOINT                  (T0C +  246) //519 K - autoignite temperature in air if that ever gets implemented.

//These control the mole ratio of oxidizer and fuel used in the combustion reaction
#define FIRE_REACTION_OXIDIZER_AMOUNT	3 //should be greater than the fuel amount if fires are going to spread much
#define FIRE_REACTION_FUEL_AMOUNT		2

//These control the speed at which fire burns
#define FIRE_GAS_BURNRATE_MULT			1
#define FIRE_LIQUID_BURNRATE_MULT		0.225

//If the fire is burning slower than this rate then the reaction is going too slow to be self sustaining and the fire burns itself out.
//This ensures that fires don't grind to a near-halt while still remaining active forever.
#define FIRE_GAS_MIN_BURNRATE			0.01
#define FIRE_LIQUD_MIN_BURNRATE			0.0025

//How many moles of fuel are contained within one solid/liquid fuel volume unit
#define LIQUIDFUEL_AMOUNT_TO_MOL		0.45  //mol/volume unit

// XGM gas flags.
#define XGM_GAS_FUEL        1
#define XGM_GAS_OXIDIZER    2
#define XGM_GAS_CONTAMINANT 4
#define XGM_GAS_FUSION_FUEL 8


#define NORMPIPERATE             30   // Pipe-insulation rate divisor.
#define HEATPIPERATE             8    // Heat-exchange pipe insulation.
#define FLOWFRAC                 0.99 // Fraction of gas transfered per process.

//Flags for zone sleeping
#define ZONE_ACTIVE   1
#define ZONE_SLEEPING 0

// Defines how much of certain gas do the Atmospherics tanks start with. Values are in kpa per tile (assuming 20C)
#define ATMOSTANK_NITROGEN      90000 // A lot of N2 is needed to produce air mix, that's why we keep 90MPa of it
#define ATMOSTANK_OXYGEN        40000 // O2 is also important for airmix, but not as much as N2 as it's only 21% of it.
#define ATMOSTANK_CO2           25000 // CO2 and PH are not critically important for station, only for toxins and alternative coolants, no need to store a lot of those.
#define ATMOSTANK_PHORON        25000
#define ATMOSTANK_NITROUSOXIDE  10000 // N2O doesn't have a real useful use, i guess it's on station just to allow refilling of sec's riot control canisters?
#define ATMOSTANK_METHANE 		5000 // Methane! Lowest tank pressure, because it's not really useful anyway except as a dump tank

// Used in various things like tanks and oxygen pumps.
#define MAX_ATMOS_TEMPERATURE 1e30 //Without having a max temp, you can get .inf temps

///Minimum temperature for items on fire

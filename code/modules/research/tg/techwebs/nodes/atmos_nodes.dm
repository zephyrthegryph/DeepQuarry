// Atmos root
/datum/techweb_node/atmos
	id = TECHWEB_NODE_ATMOS
	starting_node = TRUE
	display_name = "Atmospherics"
	description = "Maintaining station air and related life support systems."
	// DQRestore — CHOMP atmos machinery is back; design IDs reactivated.
	design_ids = list(
		"atmosanalyzer",
		"atmosalerts",
		"air_management",
		"tank_management",
		"shutoff_monitor",
		"space_heater",
		"fire_extinguisher",
		"atmoscontrol",
		"area_atmos",
	)

/datum/techweb_node/gas_compression
	id = TECHWEB_NODE_GAS_COMPRESSION
	display_name = "Gas Compression"
	description = "Highly pressurized gases hold potential for unlocking immense energy capabilities."
	prereq_ids = list(TECHWEB_NODE_ATMOS)
	// DQRestore — CHOMP atmos machinery is back.
	design_ids = list(
		"gasheater",
		"gascooler",
		"algae_farm",
		"thermoregulator",
		"large_welding_tool",
	)
	research_costs = list(TECHWEB_POINT_TYPE_GENERIC = TECHWEB_TIER_1_POINTS)
	announce_channels = list(CHANNEL_ENGINEERING)

/datum/techweb_node/plasma_control
	id = TECHWEB_NODE_PLASMA_CONTROL
	display_name = "Controlled Plasma"
	description = "Experiments with high-pressure gases and electricity resulting in crystallization and controlled plasma reactions."
	prereq_ids = list(TECHWEB_NODE_GAS_COMPRESSION, TECHWEB_NODE_ENERGY_MANIPULATION)
	design_ids = list(
		"pacman",
		"superpacman",
		"mrspacman",
		// "electrolyzer",
		// "pipe_scrubber",
		// "mech_generator",
		// "plasmacutter",
	)
	research_costs = list(TECHWEB_POINT_TYPE_GENERIC = TECHWEB_TIER_2_POINTS)
	announce_channels = list(CHANNEL_ENGINEERING)

/datum/techweb_node/fusion
	id = TECHWEB_NODE_FUSION
	display_name = "Fusion"
	description = "Investigating fusion reactor technology to achieve sustainable and efficient energy production through controlled plasma reactions involving noble gases."
	prereq_ids = list(TECHWEB_NODE_PLASMA_CONTROL)
	// DQRestore — R-UST fusion engine is back.
	design_ids = list(
		"adv_rtg",
		"fusion_core_control",
		"fusion_fuel_compressor",
		"fusion_fuel_control",
		"gyrotron_control",
		"fusion_core",
		"fusion_injector",
	)
	research_costs = list(TECHWEB_POINT_TYPE_GENERIC = TECHWEB_TIER_3_POINTS)
	// discount_experiments = list(/datum/experiment/ordnance/gaseous/nitrous_oxide = TECHWEB_TIER_3_POINTS)
	announce_channels = list(CHANNEL_ENGINEERING)

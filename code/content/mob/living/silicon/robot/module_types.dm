// Used by robots and robot preferences for regular modules.
GLOBAL_LIST_INIT(robot_module_types, list(
	"Standard", "Engineering", /*"Surgeon",*/ "Crisis", "Miner",
	"Janitor", "Service", "Clown", "Clerical", "Security",
	"Research", "Command", "Exploration" // Enables Exploration borg.
))
// List of modules added during code red
GLOBAL_LIST_INIT(emergency_module_types, list(
	"Combat"
))
// List of modules available to AI shells
GLOBAL_LIST_INIT(shell_module_types, list(
	"Standard", "Engineering", "Surgeon", "Crisis", "Miner",
	"Janitor", "Service", "Clown", "Clerical", "Security",
	"Research", "Command", "Exploration" // Enables Exploration borg.
))
// List of modules available malf borgs
GLOBAL_LIST_INIT(malf_module_types, list("Lost", "Gravekeeper"))
// List of modules available toantags
GLOBAL_LIST_INIT(antag_module_types, list("Protector", "Mechanist", "Combat Medic", "Ninja"))

// List of whitelisted modules
GLOBAL_LIST_INIT(whitelisted_module_types, list("Combat", "Lost", "Gravekeeper", "Protector", "Mechanist", "Combat Medic", "Ninja"))

// Concrete faction relationship tables for the modern AI framework.
//
// Each subtype overrides get_relationships() with a proc-local static list.
// DM scopes proc-local statics to the proc-on-that-subtype, so each faction
// gets its own shared table with no per-instance allocation.

/datum/faction_data/neutral
	faction_key = FACTION_NEUTRAL
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_NEUTRAL

/datum/faction_data/station
	faction_key = FACTION_STATION
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_FRIENDLY

/datum/faction_data/station/get_relationships()
	var/static/list/L = list(
		FACTION_SYNDICATE = DQ_DISPOSITION_HOSTILE,
		FACTION_HIVEBOT   = DQ_DISPOSITION_HOSTILE,
		FACTION_PIRATE    = DQ_DISPOSITION_HOSTILE,
		FACTION_ECLIPSE   = DQ_DISPOSITION_HOSTILE,
		FACTION_CULT      = DQ_DISPOSITION_HOSTILE,
	)
	return L

/datum/faction_data/syndicate
	faction_key = FACTION_SYNDICATE
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_HOSTILE

/datum/faction_data/syndicate/get_relationships()
	var/static/list/L = list(
		FACTION_STATION = DQ_DISPOSITION_HOSTILE,
	)
	return L

/datum/faction_data/hivebot
	faction_key = FACTION_HIVEBOT
	default_disposition = DQ_DISPOSITION_HOSTILE
	player_disposition = DQ_DISPOSITION_HOSTILE

/datum/faction_data/hivebot/get_relationships()
	var/static/list/L = list(
		FACTION_HIVEBOT    = DQ_DISPOSITION_ALLY,
		FACTION_MALF_DRONE = DQ_DISPOSITION_FRIENDLY,
	)
	return L

/datum/faction_data/eclipse
	faction_key = FACTION_ECLIPSE
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_HOSTILE

/datum/faction_data/eclipse/get_relationships()
	var/static/list/L = list(
		FACTION_STATION = DQ_DISPOSITION_HOSTILE,
		FACTION_ECLIPSE = DQ_DISPOSITION_ALLY,
	)
	return L

/datum/faction_data/wild_animal
	faction_key = FACTION_WILD_ANIMAL
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_WARY

/datum/faction_data/wild_animal/get_relationships()
	var/static/list/L = list(
		FACTION_WILD_ANIMAL = DQ_DISPOSITION_FRIENDLY,
	)
	return L

// Predator wildlife — attacks players, ignores other animals.
/datum/faction_data/predator
	faction_key = FACTION_CREATURE
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_HOSTILE

/datum/faction_data/predator/get_relationships()
	var/static/list/L = list(
		FACTION_CREATURE    = DQ_DISPOSITION_ALLY,
		FACTION_WILD_ANIMAL = DQ_DISPOSITION_NEUTRAL,
	)
	return L

/datum/faction_data/cult
	faction_key = FACTION_CULT
	default_disposition = DQ_DISPOSITION_HOSTILE
	player_disposition = DQ_DISPOSITION_HOSTILE

/datum/faction_data/cult/get_relationships()
	var/static/list/L = list(
		FACTION_CULT = DQ_DISPOSITION_ALLY,
	)
	return L

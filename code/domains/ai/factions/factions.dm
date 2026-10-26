// Concrete faction relationship tables for the modern AI framework.
//
// Each subtype overrides the get_relationships type table, so each faction
// gets its own shared table with no per-instance allocation.

/datum/faction_data/neutral
	faction_key = FACTION_NEUTRAL
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_NEUTRAL

/datum/faction_data/station
	faction_key = FACTION_STATION
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_FRIENDLY

TYPE_TABLE(/datum/faction_data/station, get_relationships, list( \
	FACTION_SYNDICATE = DQ_DISPOSITION_HOSTILE, \
	FACTION_HIVEBOT   = DQ_DISPOSITION_HOSTILE, \
	FACTION_PIRATE    = DQ_DISPOSITION_HOSTILE, \
	FACTION_ECLIPSE   = DQ_DISPOSITION_HOSTILE, \
	FACTION_CULT      = DQ_DISPOSITION_HOSTILE, \
))

/datum/faction_data/syndicate
	faction_key = FACTION_SYNDICATE
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_HOSTILE

TYPE_TABLE(/datum/faction_data/syndicate, get_relationships, list( \
	FACTION_STATION = DQ_DISPOSITION_HOSTILE, \
))

/datum/faction_data/hivebot
	faction_key = FACTION_HIVEBOT
	default_disposition = DQ_DISPOSITION_HOSTILE
	player_disposition = DQ_DISPOSITION_HOSTILE

TYPE_TABLE(/datum/faction_data/hivebot, get_relationships, list( \
	FACTION_HIVEBOT    = DQ_DISPOSITION_ALLY, \
	FACTION_MALF_DRONE = DQ_DISPOSITION_FRIENDLY, \
))

/datum/faction_data/eclipse
	faction_key = FACTION_ECLIPSE
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_HOSTILE

TYPE_TABLE(/datum/faction_data/eclipse, get_relationships, list( \
	FACTION_STATION = DQ_DISPOSITION_HOSTILE, \
	FACTION_ECLIPSE = DQ_DISPOSITION_ALLY, \
))

/datum/faction_data/wild_animal
	faction_key = FACTION_WILD_ANIMAL
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_WARY

TYPE_TABLE(/datum/faction_data/wild_animal, get_relationships, list( \
	FACTION_WILD_ANIMAL = DQ_DISPOSITION_FRIENDLY, \
))

// Predator wildlife — attacks players, ignores other animals.
/datum/faction_data/predator
	faction_key = FACTION_CREATURE
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_HOSTILE

TYPE_TABLE(/datum/faction_data/predator, get_relationships, list( \
	FACTION_CREATURE    = DQ_DISPOSITION_ALLY, \
	FACTION_WILD_ANIMAL = DQ_DISPOSITION_NEUTRAL, \
))

/datum/faction_data/cult
	faction_key = FACTION_CULT
	default_disposition = DQ_DISPOSITION_HOSTILE
	player_disposition = DQ_DISPOSITION_HOSTILE

TYPE_TABLE(/datum/faction_data/cult, get_relationships, list( \
	FACTION_CULT = DQ_DISPOSITION_ALLY, \
))

// Pack animals (pack_join_radius, doc/rewrite/ai_packs.md B7): wolves, spiders and xenomorphs fight in packs; every other faction forms none.
// A pack never mixes factions, so a faction's own key is its packmates. Spiders and xenomorphs behave toward everyone else as the unregistered
// default always made them (neutral in the table, hostile on sight to strangers); wolves keep the neutral-faction animals as allies, as their old
// FACTION_NEUTRAL did.
/datum/faction_data/spiders
	faction_key = FACTION_SPIDERS
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_NEUTRAL
	pack_join_radius = 5

/datum/faction_data/xeno
	faction_key = FACTION_XENO
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_NEUTRAL
	pack_join_radius = 5

/datum/faction_data/wolves
	faction_key = FACTION_WOLF
	default_disposition = DQ_DISPOSITION_NEUTRAL
	player_disposition = DQ_DISPOSITION_NEUTRAL
	pack_join_radius = 5

TYPE_TABLE(/datum/faction_data/wolves, get_relationships, list( \
	FACTION_NEUTRAL = DQ_DISPOSITION_ALLY, \
))

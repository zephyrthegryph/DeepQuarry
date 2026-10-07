// /datum/faction_data — relationship table for a faction.
//
// Faction itself is still a string on /mob (FACTION_NEUTRAL, FACTION_ECLIPSE,
// etc.) — we don't replace that. Instead, each faction string maps to one
// /datum/faction_data singleton that owns the disposition table.
//
// Registry is built once on world boot from every /datum/faction_data subtype
// that sets `faction_key`. Lookup is GLOB.dq_faction_data[mob.faction].
// Missing entries fall back to the default-everything data datum.
//
// Each subtype overrides the `get_relationships` type table (TYPE_TABLE),
// giving a per-subtype shared table with no per-instance cost.

GLOBAL_LIST_EMPTY(dq_faction_data)
GLOBAL_DATUM_INIT(dq_faction_data_default, /datum/faction_data, new())

/datum/faction_data
	/// The mob.faction string this data is keyed by. Subclasses set this; if null, the subtype is abstract and isn't registered.
	var/faction_key = null

	/// Default disposition toward any faction not in the get_relationships table.
	var/default_disposition = DQ_DISPOSITION_NEUTRAL

	/// Disposition toward client-controlled mobs (humans).
	var/player_disposition = DQ_DISPOSITION_NEUTRAL

	/// Disposition toward mobs without a brain or with no recognised faction.
	var/unknown_disposition = DQ_DISPOSITION_NEUTRAL

	// --- Packs (pack/pack.dm). Per faction: 0 radius is "everyone fights alone" (a pack of one). ---
	/// Tiles within which another pack's leader makes this one merge into it (and a lone brain join it); 0 forms no packs.
	var/pack_join_radius = 0
	/// A member farther than this from its leader leaves the pack (the gap to pack_join_radius is the hysteresis).
	var/pack_leave_radius = 9
	/// Deciseconds before pack members other than the spotter learn of a sighting.
	var/alert_delay = 0.75 SECONDS
	/// Tiles within which a spotter's alert reaches a packmate.
	var/comm_radius = 12
	/// PACK_SPREAD or PACK_FOCUS.
	var/pack_doctrine = PACK_SPREAD
	/// Members per target under PACK_SPREAD.
	var/spread_cap = 2

/// Per-subtype type table of faction_key (string) => DQ_DISPOSITION_*.
/// Override with TYPE_TABLE(); one shared table per subtype, no per-instance allocation.
TYPE_TABLE_DECLARE(/datum/faction_data, get_relationships, list())

/datum/faction_data/proc/disposition_to_faction(other_faction_key)
	if(other_faction_key == faction_key)
		return DQ_DISPOSITION_ALLY
	if(!other_faction_key)
		return unknown_disposition
	var/list/table = TYPE_TABLE_GET(src, get_relationships)
	var/result = table[other_faction_key]
	if(isnull(result))
		return default_disposition
	return result

/// Builds the global registry. Runs on the first lookup (it used to be SSdq_combat_ai's init).
/proc/dq_build_faction_registry()
	GLOB.dq_faction_data.Cut()
	for(var/T in typesof(/datum/faction_data))
		var/datum/faction_data/template = T
		var/key = initial(template.faction_key)
		if(!key)
			continue
		if(GLOB.dq_faction_data[key])
			continue
		GLOB.dq_faction_data[key] = new T()

/// Convenience lookup used by the brain.
/proc/dq_faction_data_for(faction_string)
	if(!length(GLOB.dq_faction_data))
		dq_build_faction_registry()
	if(!faction_string)
		return GLOB.dq_faction_data_default
	. = GLOB.dq_faction_data[faction_string]
	if(!.)
		return GLOB.dq_faction_data_default

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
// IMPORTANT — per the project's DM list patterns memory: you cannot redeclare
// a static list var on a subtype if the parent already declared it. Each
// subtype therefore overrides `get_relationships()`, which internally returns
// a proc-local `var/static/list/L = list(...)` — DM scopes the static to the
// proc-on-that-type, giving us a per-subtype shared table with no per-instance
// cost.

GLOBAL_LIST_EMPTY(dq_faction_data)
GLOBAL_DATUM_INIT(dq_faction_data_default, /datum/faction_data, new())

/datum/faction_data
	/// The mob.faction string this data is keyed by. Subclasses set this; if null, the subtype is abstract and isn't registered.
	var/faction_key = null

	/// Default disposition toward any faction not in get_relationships().
	var/default_disposition = DQ_DISPOSITION_NEUTRAL

	/// Disposition toward client-controlled mobs (humans).
	var/player_disposition = DQ_DISPOSITION_NEUTRAL

	/// Disposition toward mobs without a brain or with no recognised faction.
	var/unknown_disposition = DQ_DISPOSITION_NEUTRAL

/// Override per subtype. Returns a per-subtype static list of
///   faction_key (string) => DQ_DISPOSITION_*.
/// Use the static-list-in-proc pattern so we get a single shared table per
/// subtype with no per-instance allocation.
/datum/faction_data/proc/get_relationships()
	var/static/list/L = list()
	return L

/datum/faction_data/proc/disposition_to_faction(other_faction_key)
	if(other_faction_key == faction_key)
		return DQ_DISPOSITION_ALLY
	if(!other_faction_key)
		return unknown_disposition
	var/list/table = get_relationships()
	var/result = table[other_faction_key]
	if(isnull(result))
		return default_disposition
	return result

/// Build the global registry at world init.
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
	if(!faction_string)
		return GLOB.dq_faction_data_default
	. = GLOB.dq_faction_data[faction_string]
	if(!.)
		return GLOB.dq_faction_data_default

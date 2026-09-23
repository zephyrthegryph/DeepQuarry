// Property definitions (doc/rewrite/rules.md ยง1).
//
// A property is declared once as a /datum/property_def subtype: its id, kind
// (measure or tag), SI unit and aggregator. Its values come from providers
// (providers.dm). The registry (registry.dm) builds every definition and
// provider once, validates them, and answers reads.
//
// Families are declared in code/datums/properties/families/.

/datum/property_def
	/// PROP_* or TAG_* id. A subtype without an id is abstract.
	var/id
	var/name
	var/desc
	/// PROP_KIND_MEASURE or PROP_KIND_TAG.
	var/kind = PROP_KIND_MEASURE
	/// PROP_UNIT_*. Tags have none.
	var/unit
	/// PROP_AGG_*: how values combine across contributors and contents.
	var/aggregator = PROP_AGG_NONE
	var/min_value = -INFINITY
	var/max_value = INFINITY
	/// Predicate reasons (predicates.dm): "too [high_word]" when a value is
	/// too large, "too [low_word]" when too small. Null: "<name> too high".
	var/high_word
	var/low_word
	/// Tags: how reasons describe it ("must be [adjective]"). Null: lowercase name.
	var/adjective
	/// Test fixtures set this so the global registry skips them.
	var/test_only = FALSE
	/// DM-owned properties: the reactor key kind published when the value
	/// changes (reactor.md ง4), so rules re-evaluate on it (rules.md ง4).
	var/dm_key_kind

/// Tags: capability flags, TRUE or FALSE, combined with OR.
/datum/property_def/tag
	kind = PROP_KIND_TAG
	aggregator = PROP_AGG_OR
	min_value = 0
	max_value = 1

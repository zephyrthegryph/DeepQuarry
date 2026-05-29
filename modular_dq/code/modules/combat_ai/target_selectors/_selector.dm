// /datum/target_selector — pluggable target picking strategy.
//
// Stateless singletons keyed by typepath. Mobs declare an ordered list of
// selectors; the brain calls them in order and uses the first non-null result.
//
// All selectors operate over the world model's visible_hostiles list. They do
// not run their own view() calls — perception is centralised.

GLOBAL_LIST_EMPTY(dq_target_selectors)

/proc/dq_get_selector(type)
	. = GLOB.dq_target_selectors[type]
	if(!.)
		. = new type()
		GLOB.dq_target_selectors[type] = .

/datum/target_selector
	/// For debug only. Selectors are stateless.
	var/name = "abstract selector"

/// Override per subtype. Should return one of the candidates or null.
/// Brain owns the world_model — selectors never run perception themselves.
/datum/target_selector/proc/select(datum/ai_brain/brain, list/candidates)
	return null

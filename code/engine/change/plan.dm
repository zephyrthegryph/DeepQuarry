// The change graph's plans (doc/rewrite/proposals/change_graph.md sections 2, 4, 11 step 2).
//
// `analyze gen plans` writes, per type that declares a draw(), what that draw reads (GLOB.generated_plans) and the interned keys
// (CGK_<var>, GLOB.generated_key_names). A type with no row of its own uses its nearest ancestor's. Step 2 only builds and answers the plan;
// state_changed() still dispatches through today's tables, and dq_change_plan_parity proves the plan answers what they answer for every type.
// Step 3 moves the dispatch onto the plan and deletes the tables.

/// Type path -> its resolved plan (the nearest generated row up the parent chain), or 0 for none. Filled on first use.
GLOBAL_LIST_EMPTY(plan_cache)
/// Writes to a type the generator marked unresolved (D5: such a type keeps marking every output). The plan_fallback count.
GLOBAL_VAR_INIT(plan_fallbacks, 0)
/// Runtime-only keys: name -> id above CGK_BUILD_MAX, interned on first use.
GLOBAL_LIST_EMPTY(runtime_key_ids)

/// The plan of `type`: "<var>" or "<hop>.<var>" -> PLAN_* bits, or null when no draw of the type (or an ancestor) is generated.
/proc/plan_of(type)
	var/known = GLOB.plan_cache[type]
	if(!isnull(known))
		return known || null
	var/list/table = GLOB.generated_plans
	var/path = type
	var/list/found
	while(path)
		found = table?["[path]"]
		if(found)
			break
		var/datum/typed = path
		path = initial(typed.parent_type)
	GLOB.plan_cache[type] = found || 0
	return found

/// The PLAN_* bits of `key` (a var name, or "<hop>.<var>") on E's type.
/proc/plan_bits(datum/E, key)
	var/list/plan = plan_of(E.type)
	return plan ? (plan[key] || 0) : 0

/// Whether the generator could not resolve the reads of E's type's draw (D5). Counted: plan_fallback.
/proc/plan_is_fallback(datum/E)
	var/path = E.type
	while(path)
		if(GLOB.generated_plan_fallbacks?["[path]"])
			GLOB.plan_fallbacks++
			return TRUE
		var/datum/typed = path
		path = initial(typed.parent_type)
	return FALSE

/// The int id of key `name`: a build-time key's CGK_ value, or a runtime-only key interned above CGK_BUILD_MAX on first use.
/proc/change_key_id(name)
	var/index = GLOB.generated_key_names.Find(name)
	if(index)
		return index
	var/id = GLOB.runtime_key_ids[name]
	if(!id)
		id = CGK_BUILD_MAX + length(GLOB.runtime_key_ids) + 1
		GLOB.runtime_key_ids[name] = id
	return id

/// The name of key id `id` (logs, the redraw trace).
/proc/change_key_name(id)
	if(id >= 1 && id <= length(GLOB.generated_key_names))
		return GLOB.generated_key_names[id]
	for(var/name in GLOB.runtime_key_ids)
		if(GLOB.runtime_key_ids[name] == id)
			return name
	return null

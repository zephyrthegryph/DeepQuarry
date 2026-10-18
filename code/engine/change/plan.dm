// The change graph's plans (doc/rewrite/proposals/change_graph.md sections 2, 4, 11 step 2).
//
// `analyze gen plans` writes, per type that declares a draw(), what that draw reads (GLOB.generated_plans) and the interned keys
// (CGK_<var>, GLOB.generated_key_names). A type with no row of its own uses its nearest ancestor's. Step 2 only builds and answers the plan;
// state_changed() still dispatches through today's tables, and dq_change_plan_parity proves the plan answers what they answer for every type.
// Step 3 moves the dispatch onto the plan and deletes the tables.

/// Writes to a type the generator marked unresolved (D5: such a type keeps marking every output). The plan_fallback count.
GLOBAL_VAR_INIT(plan_fallbacks, 0)
/// Runtime-only keys: name -> id above CGK_BUILD_MAX, interned on first use.
GLOBAL_LIST_EMPTY(runtime_key_ids)

/// Builds plan_of()'s cache entry: the nearest generated row up `type`'s parent chain (an empty list for none).
/proc/plan_build(type)
	var/list/table = GLOB.generated_plans
	var/path = type
	while(path)
		var/list/found = table?["[path]"]
		if(found)
			return found
		var/datum/typed = path
		path = initial(typed.parent_type)
	return list()

/// Type path -> its resolved plan, built once (the plans are build output: they never change in a running world).
DECLARE_SHARED_CACHE(change_plans, GLOBAL_PROC_REF(plan_build), SC_NEVER)

/// The plan of `type`: "<var>" or "<hop>.<var>" -> PLAN_* bits; empty when no draw of the type (or an ancestor) is generated.
/proc/plan_of(type)
	return CACHED(change_plans, type)

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

/// Builds plan_keys()'s cache entry: the keys of `type`'s plan that carry `bit` (an empty list for none).
/proc/plan_keys_build(type, bit)
	. = list()
	var/list/plan = plan_of(type)
	for(var/key in plan)
		if(plan[key] & bit)
			. += key

/// "<type>|<bit>" -> plan_keys_build(), built once.
DECLARE_SHARED_CACHE(change_plan_keys, GLOBAL_PROC_REF(plan_keys_build), SC_NEVER)

/// The keys of `type`'s plan that carry PLAN_* `bit`: what the type's draw reads (PLAN_DRAW) or reads a hop away (PLAN_DRAW_HOP). Read only.
/proc/plan_keys(type, bit)
	return CACHED2(change_plan_keys, type, bit)

// ---- narrowing a write's redraw (step 3c) ----

#define PLAN_SPARE 1
#define PLAN_KEEP 2

/// The nearest row of `table` ("<type>" -> list(var, ...)) for `type`, or null.
/proc/plan_nearest_row(list/table, type)
	var/path = type
	while(path)
		var/list/row = table?["[path]"]
		if(row)
			return row
		var/datum/typed = path
		path = initial(typed.parent_type)
	return null

/// TRUE when the generator could not resolve a draw or verb output of `type` or an ancestor (D5).
/proc/plan_type_fallback(type)
	return !!plan_nearest_row(GLOB.generated_plan_fallbacks, type)

/// Builds plan_spares_draw()'s entry for (E's type, var_name): PLAN_SPARE when nothing that refreshes on DEP_DRAW reads the var.
/proc/plan_spares_build(atom/E, var_name)
	if(plan_type_fallback(E.type))
		return PLAN_KEEP // D5: the walk could not resolve an output; every write redraws it
	var/list/plan = plan_of(E.type)
	if(!length(plan))
		return PLAN_KEEP // no generated draw: the base draw (capabilities, look layers) is not in a plan yet
	if(plan[var_name] & PLAN_DRAW)
		return PLAN_KEEP
	var/list/hidden = plan_nearest_row(GLOB.generated_plan_hidden_verbs, E.type)
	if(hidden && (var_name in hidden))
		return PLAN_KEEP
	var/list/granted = plan_nearest_row(GLOB.generated_plan_granted_verbs, E.type)
	if(granted && (var_name in granted))
		return PLAN_KEEP
	// What the plans do not cover yet: capability draws and verbs, declared look layers.
	if(length(caps_of(E)) || present_declares_look(E) || look_table_has_layers(table_of(E)))
		return PLAN_KEEP
	return PLAN_SPARE

DECLARE_SHARED_CACHE(change_plan_spares, GLOBAL_PROC_REF(plan_spares_build), SC_NEVER)

/// TRUE when a write of `var_name` on E needs no redraw (look and verbs, DEP_DRAW): E is an atom (not a mob: species and traits grant verbs no
/// plan sees) whose type's generated plans say neither its draw nor its verb outputs read the var. Asked by state_changed() for a type that
/// declares no dependencies (one that does is narrowed by its derived table already).
/proc/plan_spares_draw(datum/E, var_name)
	if(!isatom(E) || ismob(E))
		return FALSE
	return CACHED_KEY(change_plan_spares, "[E.type]|[var_name]", E, var_name) == PLAN_SPARE

#undef PLAN_SPARE
#undef PLAN_KEEP

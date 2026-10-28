// The compiled per-type init plan (perf/init-plan). engine_holder_init() and engine_holder_preinit() used to discover, for every
// instance, which of the type's compiled entries have init work: three compiled_entries() calls (each a fresh list copy), a walk of
// every capability definition, the change index and verb entry lookups. All of that is a fact of the type, so it is worked out once
// here and an instance replays the flat steps. A plan is built only once the declaration globals exist (before that the lookups it
// folds answer "nothing yet" without caching, and so does the plan: the old path runs).
//
// GLOB.init_plan_off (a debug toggle) runs the old discovery path; dq_init_plan_parity proves both leave an instance in the same state.

/// The engine's init work for one type, in order. Immutable once built.
/datum/init_plan
	var/owner_type
	/// Capability definitions with an on_holder_preinit / on_holder_init hook, in compiled order.
	var/list/preinit_caps
	var/list/init_caps
	/// The rel_grants() var names, in compiled order.
	var/list/rel_grant_vars
	/// The type table's ENGINE_HOOK_* bits.
	var/hook_flags = 0
	/// The type declares an on_change hook (hooks_change_baseline() has a baseline to take).
	var/change_baseline = FALSE
	/// The type has type-level every() entries (type_every_arm() has work).
	var/every_arm = FALSE
	/// The type declares verb entries (verb_entries_init() has work).
	var/verb_entries = FALSE
	/// Number of steps the plan runs per instance (the trace's measure).
	var/steps = 0

/// TRUE runs the old per-instance discovery path in engine_holder_init()/engine_holder_preinit() (parity tests, debugging).
GLOBAL_VAR_INIT(init_plan_off, FALSE)
/// Plans compiled, and the steps they hold in total (the INIT PLAN trace line).
GLOBAL_VAR_INIT(init_plan_types, 0)
GLOBAL_VAR_INIT(init_plan_steps, 0)
/// init_plan_types at the last trace line.
GLOBAL_VAR_INIT(init_plan_traced_types, 0)

/// type -> /datum/init_plan. A static: atoms initialize while the globals are still being made.
/proc/init_plan_cache()
	RETURN_TYPE(/list)
	var/static/list/cache = list() // ALLOW(cache,sys_static_getter): plans are read while the globals are still being made, like the type tables they fold
	return cache

/// The plan of holder's type, or null while it cannot be compiled yet (the old path runs then).
/proc/init_plan_of(datum/holder, datum/type_table/T)
	RETURN_TYPE(/datum/init_plan)
	var/list/cache = init_plan_cache()
	var/datum/init_plan/P = cache[holder.type]
	if(P)
		return P
	if(!GLOB?.change_index_by_type || !GLOB.verb_entry_sets || T == table_empty())
		return null
	P = new
	P.owner_type = holder.type
	P.hook_flags = T.hook_flags
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
		var/datum/capability/def = C.item
		if(def.holder_hooks & HOLDER_HOOK_PREINIT)
			LAZYADD(P.preinit_caps, def)
		if(def.holder_hooks & HOLDER_HOOK_INIT)
			LAZYADD(P.init_caps, def)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_REL_GRANTS))
		var/datum/entry/E = C.item
		LAZYADD(P.rel_grant_vars, E.args["var"])
	P.change_baseline = !!change_index_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_EVERY))
		if(isnull(C.owner))
			P.every_arm = TRUE
			break
	P.verb_entries = isatom(holder) && !!verb_entries_of(holder)
	P.steps = LAZYLEN(P.preinit_caps) + LAZYLEN(P.init_caps) + LAZYLEN(P.rel_grant_vars) + P.change_baseline + P.every_arm + P.verb_entries
	for(var/bit in list(ENGINE_HOOK_SLOT_STARTS, ENGINE_HOOK_STATS, ENGINE_HOOK_MODES, ENGINE_HOOK_COND_SCOPED, ENGINE_HOOK_LIFEFORMS, ENGINE_HOOK_AFTER_INIT))
		if(P.hook_flags & bit)
			P.steps++
	cache[holder.type] = P
	GLOB.init_plan_types++
	GLOB.init_plan_steps += P.steps
	return P

/// The trace line: how many types have a plan and how many steps they hold.
/proc/init_plan_trace(where)
	if(GLOB.init_plan_types == GLOB.init_plan_traced_types)
		return
	GLOB.init_plan_traced_types = GLOB.init_plan_types
	log_world("INIT PLAN: [GLOB.init_plan_types] types compiled, [GLOB.init_plan_steps] steps in total ([where])")

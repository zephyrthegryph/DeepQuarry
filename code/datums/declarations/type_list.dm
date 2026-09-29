// Per-type lists (doc/rewrite/dx_conventions.md §2). Defines: code/__defines/type_list.dm.

/**
 * The list D's type returns from the well-known proc `proc_ref` (PROC_REF(interactions), ...),
 * built once per (type, proc) by calling it on the first instance that asks, and shared: never
 * write into it. Nested lists stay as the proc returned them; a null result is an empty list.
 */
/proc/type_list(datum/D, proc_ref)
	RETURN_TYPE(/list)
	var/list/result = CACHED_KEY(type_lists, "[D.type]|[proc_ref]", D, proc_ref)
#ifdef UNIT_TESTS
	type_list_purity_check(D, proc_ref, result)
#endif
	return result

/// Builder for type_lists.
/proc/build_type_list(datum/D, proc_ref)
	var/result = call(D, proc_ref)()
	if(isnull(result))
		return list()
	if(!islist(result))
		stack_trace("type_list: [D.type].[proc_ref] returned [result], not a list")
		return list(result)
	return result

DECLARE_SHARED_CACHE(type_lists, GLOBAL_PROC_REF(build_type_list), SC_NEVER)

/// "[type]|[proc]" -> the first instance's ref, until a second instance has been compared (then TRUE).
GLOBAL_LIST_EMPTY(type_list_purity)
/// Impurity reports this round (the fixture test reads it).
GLOBAL_LIST_EMPTY(type_list_impure)
/// Set by the fixture test around a deliberate impurity: record it without a runtime.
GLOBAL_VAR_INIT(type_list_expect_impure, FALSE)

#ifdef UNIT_TESTS
/// The first time a second, different instance of a type asks for a list, rebuild it on that
/// instance and compare: a per-type list that reads instance state fails the run.
/proc/type_list_purity_check(datum/D, proc_ref, list/cached)
	var/key = "[D.type]|[proc_ref]"
	var/seen = GLOB.type_list_purity[key]
	if(seen == TRUE)
		return
	var/my_ref = ref(D)
	if(isnull(seen))
		GLOB.type_list_purity[key] = my_ref
		return
	if(seen == my_ref)
		return
	GLOB.type_list_purity[key] = TRUE
	var/list/again = build_type_list(D, proc_ref)
	if(!type_list_same(cached, again, 0))
		var/msg = TYPE_LIST_IMPURE(D.type, proc_ref)
		GLOB.type_list_impure += msg
		if(!GLOB.type_list_expect_impure)
			stack_trace(msg)
#endif

/// Structural equality for per-type list results: lists element by element (keys and values),
/// datums by type and by every var that differs from its initial value, anything else by ==.
/proc/type_list_same(a, b, depth)
	if(a == b)
		return TRUE
	if(depth > 8)
		return TRUE // deep enough: constructors return shallow data
	if(islist(a) && islist(b))
		var/list/la = a
		var/list/lb = b
		if(length(la) != length(lb))
			return FALSE
		for(var/i in 1 to length(la))
			var/ka = la[i]
			var/kb = lb[i]
			if(!type_list_same(ka, kb, depth + 1))
				return FALSE
			if(!isnum(ka) && !isnull(ka) && !type_list_same(la[ka], lb[kb], depth + 1))
				return FALSE
		return TRUE
	if(isdatum(a) && isdatum(b) && !isatom(a) && !isatom(b))
		var/datum/da = a
		var/datum/db = b
		if(da.type != db.type)
			return FALSE
		for(var/name in da.vars)
			if(name == "vars" || name == "tag")
				continue
			if(!issaved(da.vars[name]))
				continue // tmp vars are caches filled on use (a capability's built_entries), not declared data
			var/va = da.vars[name]
			if(va == initial(da.vars[name]) && db.vars[name] == initial(db.vars[name]))
				continue
			if(!type_list_same(va, db.vars[name], depth + 1))
				return FALSE
		return TRUE
	return FALSE

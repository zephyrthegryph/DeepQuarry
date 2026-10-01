// Per-type lists (doc/rewrite/dx_conventions.md §2). Defines: code/__defines/type_list.dm.

/**
 * The list D's type returns from the well-known proc `proc_ref` (PROC_REF(interactions), ...),
 * built once per (type, proc) by calling it on the first instance that asks, and shared: never
 * write into it. Nested lists stay as the proc returned them; a null result is an empty list.
 */
/proc/type_list(datum/D, proc_ref, post)
	RETURN_TYPE(/list)
	var/list/result = CACHED_KEY(type_lists, "[D.type]|[proc_ref]", D, proc_ref, post)
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	type_list_purity_check(D, proc_ref, result, post)
#endif
	return result

/// Builder for type_lists. `post` (a global proc ref, optional) maps the built list once, before it
/// is cached (capabilities are interned through it).
/proc/build_type_list(datum/D, proc_ref, post)
	var/result
	try
		// A global builder takes the instance (caps_build(A)); a type proc is called on it.
		result = IS_GLOBAL_PROC_REF(proc_ref) ? call(proc_ref)(D) : call(D, proc_ref)()
	catch(var/exception/e)
		// Surface it and don't cache an empty list: the next instance tries again (and fails loudly).
		CRASH("type_list: [D.type].[proc_ref] failed while building: [e] ([e.file]:[e.line])")
	if(isnull(result))
		result = list()
	else if(!islist(result))
		stack_trace("type_list: [D.type].[proc_ref] returned [result], not a list")
		result = list(result)
	if(post)
		result = call(post)(result)
	return result

/**
 * A stable text signature of a value, for interning shared declaration data: numbers, text, paths,
 * lists (keys and values) and non-atom datums (their type and every saved var that differs from its
 * initial value; tmp vars are caches and don't count). Atoms are keyed by a never-reused uid.
 */
/proc/datum_signature(value, depth = 0)
	if(isnull(value))
		return "~"
	if(isnum(value))
		return "n[value]"
	if(istext(value))
		return "t[length(value)]:[value]"
	if(ispath(value))
		return "p[value]"
	if(depth > 8)
		return "?"
	if(islist(value))
		var/list/L = value
		var/list/parts = list()
		for(var/i in 1 to length(L))
			var/k = L[i]
			var/entry = datum_signature(k, depth + 1)
			if(!isnum(k) && !isnull(k) && !isnull(L[k]))
				entry += "=" + datum_signature(L[k], depth + 1)
			parts += entry
		return "\[[jointext(parts, ",")]]"
	if(isatom(value))
		var/atom/A = value
		return "a[SHARED_CACHE_UID(A)]"
	if(isdatum(value))
		var/datum/D = value
		var/list/parts = list()
		for(var/name in D.vars)
			if(name == "vars" || name == "tag" || !issaved(D.vars[name]))
				continue
			var/v = D.vars[name]
			if(v == initial(D.vars[name]))
				continue
			parts += "[name]:[datum_signature(v, depth + 1)]"
		return "d[D.type]{[jointext(parts, ";")]}"
	return "x[value]"

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
/proc/type_list_purity_check(datum/D, proc_ref, list/cached, post)
	// A table built during global init (a GLOB datum's New() writing an owned var reads its type's
	// ownership() list) runs before these globals exist: that type is checked on a later instance.
	if(!islist(GLOB.type_list_purity))
		return
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
	var/list/again = build_type_list(D, proc_ref, post)
	if(!type_list_same(cached, again, 0))
		var/msg = TYPE_LIST_IMPURE(D.type, proc_ref)
		GLOB.type_list_impure += msg
		if(!GLOB.type_list_expect_impure)
			stack_trace(msg)
#endif

/// Structural equality for per-type list results: lists element by element (keys and values),
/// datums by type and by every non-tmp var that differs from its initial value, anything else by ==.
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

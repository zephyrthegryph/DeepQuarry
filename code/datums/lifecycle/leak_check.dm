// Destroy postcondition (doc/rewrite/object_model_core.md, lifecycle section).
//
// After a destroy transaction's links have run and Destroy() has returned,
// nothing on the object should still reach a deleted object. BYOND frees by
// reference count, so two deleted objects that still point at each other are
// never freed, and a reference search from live roots can't see the cycle
// (the /datum/reagents -> reagent_by_id -> reagent.holder -> reagents loop
// that hard-deleted every holder once `reagent_by_id = null` was dropped).
//
// dq_lifecycle_leak_lines(D) lists every var of D (tmp vars included) that
// still holds a deleted datum -- directly, or in a list as a key or value --
// which still reaches D back through one of its own vars: a cycle among
// deleted objects. In strict mode it also lists any non-tmp var still holding
// any datum, deleted or live (noisy on legacy types; a debugging aid). Exempt: BYOND's built-in vars, the lifecycle bookkeeping vars below,
// vars equal to their initial value, and DECLARE_REF(..., KEEP) vars. Text (handles), numbers
// and type paths never match.
//
// Test builds run it on every destroy and report each line as
// "LIFECYCLE LEAK: [type].[var] still holds [what] after Destroy" through
// dq_lifecycle_report() (a runtime: the run fails). Servers run it only while
// GLOB.dq_lifecycle_leak_check is set ("Toggle Lifecycle Leak Check" verb,
// verbs.dm). SSgarbage prints the same lines for an object it failed to
// collect.

/// 0 off, 1 deleted-object references (the default in test builds), 2 strict
/// (also live datums held by non-tmp vars).
#ifdef UNIT_TESTS
GLOBAL_VAR_INIT(dq_lifecycle_leak_check, 1)
#else
GLOBAL_VAR_INIT(dq_lifecycle_leak_check, 0)
#endif

/// Var names never checked: BYOND built-ins and the framework's own
/// bookkeeping (cleared or read by qdel/SSgarbage themselves).
/proc/dq_lifecycle_leak_ignored_names()
	var/static/list/names = list(
		"type" = TRUE, "parent_type" = TRUE, "vars" = TRUE, "tag" = TRUE,
		"gc_destroyed" = TRUE, "datum_flags" = TRUE, "weak_reference" = TRUE,
		// atom / movable / mob / client built-ins
		"loc" = TRUE, "locs" = TRUE, "contents" = TRUE, "overlays" = TRUE, "underlays" = TRUE,
		"verbs" = TRUE, "vis_contents" = TRUE, "vis_locs" = TRUE, "filters" = TRUE,
		"appearance" = TRUE, "icon" = TRUE, "screen_loc" = TRUE, "x" = TRUE, "y" = TRUE, "z" = TRUE,
		"client" = TRUE, "group" = TRUE, "areas" = TRUE, "particles" = TRUE, "render_source" = TRUE,
	)
	return names

/// Per type: the names of D's vars worth looking at (not ignored, not
/// DECLARE_REF(..., KEEP)), and which of them are tmp (issaved() is FALSE for tmp, const,
/// static and global vars). Cached once per type.
/proc/dq_lifecycle_leak_candidates(datum/D)
	var/static/list/cache = list()
	var/list/entry = cache[D.type]
	if(entry)
		return entry
	var/list/ignored = dq_lifecycle_leak_ignored_names()
	var/list/links = dq_lifecycle_link_table(D)
	var/list/keep = links[REFKIND_KEEP]
	var/list/static_names = links[REFKIND_STATIC]
	var/list/names = list()
	var/list/tmp_names = list()
	for(var/name in D.vars)
		if(ignored[name] || (keep && (name in keep)) || (static_names && (name in static_names)))
			continue
		names += name
		if(!issaved(D.vars[name]))
			tmp_names[name] = TRUE
	entry = list(names, tmp_names)
	cache[D.type] = entry
	return entry

/// The name of a var of `X` that still reaches `D` (directly, or as a member
/// of a list var), or null.
/proc/dq_lifecycle_leak_backref(datum/X, datum/D)
	var/list/names = dq_lifecycle_leak_candidates(X)[1]
	for(var/name in names)
		var/value = X.vars[name]
		if(value == D)
			return name
		if(islist(value))
			var/list/L = value
			if(D in L)
				return name
	return null

/// Describes the held `thing` if it is a leak from `D`, else null. A deleted
/// datum that still reaches D back is a cycle between deleted objects (never
/// freed, invisible to a reference search); strict also reports any held datum.
/proc/dq_lifecycle_leak_datum(datum/D, datum/thing, strict)
	if(QDELETED(thing))
		var/back = dq_lifecycle_leak_backref(thing, D)
		if(back)
			return "deleted [thing.type], which holds it back through [thing.type].[back] (a cycle of deleted objects is never freed)"
		return strict ? "deleted [thing.type]" : null
	return strict ? "live [thing.type]" : null

/// Describes `value` (a var of `D`) if it is a leak, else null.
/proc/dq_lifecycle_leak_describe(datum/D, value, strict)
	if(isdatum(value))
		return dq_lifecycle_leak_datum(D, value, strict)
	if(!islist(value))
		return null
	var/list/L = value
	var/n = 0
	for(var/key in L)
		if(++n > 256) // a huge list is looked at in part
			break
		if(isdatum(key))
			var/what = dq_lifecycle_leak_datum(D, key, strict)
			if(what)
				return "a list with [what] in it"
		// Assoc values: only a text or datum key can be looked up without
		// indexing a plain list by position.
		if(istext(key) || isdatum(key))
			var/list_value = L[key]
			if(isdatum(list_value))
				var/what = dq_lifecycle_leak_datum(D, list_value, strict)
				if(what)
					var/datum/key_datum = isdatum(key) ? key : null
					return "a list with [what] in it (at key [key_datum ? "[key_datum.type]" : key])"
	return null

/// "LIFECYCLE LEAK: ..." lines for every var of `D` still reaching a deleted
/// object that reaches D back (strict: any object). Cheap enough to run on
/// every destroy in test builds: one cached name list per type, one vars[]
/// read per name, and a back-reference scan only for deleted objects held.
/proc/dq_lifecycle_leak_lines(datum/D, strict = FALSE)
	var/list/candidates = dq_lifecycle_leak_candidates(D)
	var/list/names = candidates[1]
	var/list/tmp_names = candidates[2]
	var/list/lines
	for(var/name in names)
		var/value = D.vars[name]
		if(isnull(value) || istext(value) || isnum(value) || ispath(value))
			continue
		if(value == initial(D.vars[name]))
			continue
		var/what = dq_lifecycle_leak_describe(D, value, strict && !tmp_names[name])
		if(what)
			LAZYADD(lines, "LIFECYCLE LEAK: [D.type].[name] still holds [what] after Destroy")
	return lines

/// Phase 9 (test builds, or while the check is switched on): the postcondition.
/proc/dq_lifecycle_postcondition(datum/D)
	var/level = GLOB.dq_lifecycle_leak_check
	if(!level)
		return
	for(var/line in dq_lifecycle_leak_lines(D, level >= 2))
		dq_lifecycle_report(line)

ADMIN_VERB(toggle_lifecycle_leak_check, R_DEBUG, "Toggle Lifecycle Leak Check", "Cycles the destroy postcondition (LIFECYCLE LEAK runtimes) off / deleted-cycles / strict for this round.", ADMIN_CATEGORY_DEBUG_MISC)
	GLOB.dq_lifecycle_leak_check = (GLOB.dq_lifecycle_leak_check + 1) % 3
	var/static/list/level_names = list("off", "deleted-object cycles", "strict")
	var/level_name = level_names[GLOB.dq_lifecycle_leak_check + 1]
	log_admin("[key_name(user)] set the lifecycle leak check to [level_name].")
	message_admins("[key_name_admin(user)] set the lifecycle leak check to [level_name].")

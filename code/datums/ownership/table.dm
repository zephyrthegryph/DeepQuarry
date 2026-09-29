// Ownership tables (doc/rewrite/ownership.md): one per type, built from the type's
// OWN / SHARED / PROTO / REF declarations (code/__defines/ownership.dm) the first time an
// instance asks, cached in the `own_table` shared cache.

/// The type's declarations: var name -> entry list(kind, arg, partner, extra). Each
/// declaration macro overrides this and adds one entry on top of ..(). Never override by hand.
/datum/proc/declared_ownership()
	return null

/// KEEP_AFTER_DESTROY vars (diagnostics: the leak check skips them).
/datum/proc/declared_keep_vars()
	return null

/// POOL_RESET vars (pool_release() resets them).
/datum/proc/declared_pool_reset()
	return null

/// Declaration plumbing: `parent` (a fresh table from ..(), or null) with `entry` for `var_name`.
/// One kind per var across the hierarchy: a subtype may change an OWN policy or a REF's
/// partner, never the kind. A conflict is kept on the table and reported when it is built.
/proc/own_declare(list/parent, var_name, list/entry)
	. = parent ? parent : list()
	var/list/old = .[var_name]
	if(old && old[OWNE_KIND] != entry[OWNE_KIND])
		var/list/conflicts = .["\[conflicts]"]
		if(!conflicts)
			conflicts = list()
			.["\[conflicts]"] = conflicts
		conflicts += "[var_name]: declared [own_kind_name(old[OWNE_KIND])] by an ancestor and [own_kind_name(entry[OWNE_KIND])] here"
	.[var_name] = entry

/proc/own_kind_name(kind)
	switch(kind)
		if(OWNK_OWN)
			return "OWN"
		if(OWNK_SHARED)
			return "SHARED"
		if(OWNK_PROTO)
			return "PROTO"
		if(OWNK_REL)
			return "REL"
	return "?[kind]"

/// One type's ownership table. Read-only after build.
/datum/own_table
	var/owner_type
	/// var name -> entry
	var/list/entries
	/// Var names by kind, in declaration order.
	var/list/own_vars
	var/list/ref_vars
	var/list/proto_vars
	var/list/shared_vars
	/// REL_KEYED var names.
	var/list/keyed_vars
	/// KEEP_AFTER_DESTROY / POOL_RESET names.
	var/list/keep_vars
	var/list/pool_reset_vars
	/// TRUE when the type declares nothing to tear down (the fast path).
	var/empty = TRUE
	/// TRUE when materialize/dematerialize has keyed-link work (REL_KEYED views or KEYED_TARGET).
	var/materialize_work = FALSE

/// D's ownership table (never null).
/proc/own_table_of(datum/D)
	RETURN_TYPE(/datum/own_table)
	return CACHED_KEY(own_table, D.type, D)

DECLARE_SHARED_CACHE(own_table, GLOBAL_PROC_REF(build_own_table), SC_NEVER)

/proc/build_own_table(datum/D)
	var/datum/own_table/T = new
	T.owner_type = D.type
	var/list/decl = D.declared_ownership()
	var/list/conflicts = decl?["\[conflicts]"]
	if(conflicts)
		decl -= "\[conflicts]"
		for(var/line in conflicts)
			OWN_REPORT("[D.type]: one kind per var: [line]")
	T.entries = decl || list()
	for(var/var_name in T.entries)
		var/list/entry = T.entries[var_name]
		if(!(var_name in D.vars))
			OWN_REPORT("[D.type] declares [own_kind_name(entry[OWNE_KIND])] var '[var_name]', which it doesn't have")
			continue
		switch(entry[OWNE_KIND])
			if(OWNK_OWN)
				LAZYADD(T.own_vars, var_name)
			if(OWNK_REL)
				LAZYADD(T.ref_vars, var_name)
				if(entry[OWNE_EXTRA])
					LAZYADD(T.keyed_vars, var_name)
			if(OWNK_PROTO)
				LAZYADD(T.proto_vars, var_name)
			if(OWNK_SHARED)
				LAZYADD(T.shared_vars, var_name)
	T.keep_vars = D.declared_keep_vars()
	T.pool_reset_vars = D.declared_pool_reset()
	T.empty = !(T.own_vars || T.ref_vars || T.proto_vars)
	T.materialize_work = !!(T.keyed_vars || D.keyed_target_var())
	own_validate_table(D, T)
	return T

/// The kind x value matrix, per built table (boot and first use): the checks that need an
/// instance. The static half (declared var types) is tools/ci/ownership_lint.py.
/proc/own_validate_table(datum/D, datum/own_table/T)
	for(var/var_name in T.entries)
		if(!(var_name in D.vars))
			continue
		var/list/entry = T.entries[var_name]
		var/value = D.vars[var_name]
		switch(entry[OWNE_KIND])
			if(OWNK_OWN)
				var/policy = entry[OWNE_ARG]
				if(!ispath(policy) && !(policy in list(OWN_DELETE, OWN_SPILL, OWN_CONTAINED)))
					OWN_REPORT("[D.type].[var_name]: unknown teardown policy [policy]")
				if(ispath(policy) && !hascall(D, own_proc_name(policy)))
					OWN_REPORT("[D.type].[var_name]: policy proc [policy] is not a proc of [D.type]")
				if(policy == OWN_CONTAINED && !ismovable(D) && !isturf(D))
					OWN_REPORT("[D.type].[var_name]: CONTAINED on a type with no contents")
				if(entry[OWNE_PARTNER] && !(entry[OWNE_PARTNER] in D.vars))
					OWN_REPORT("[D.type].[var_name]: OWN_IF flag [entry[OWNE_PARTNER]] is not a var")
				var/datum/held = value
				if(isdatum(held) && is_registered(held))
					OWN_REPORT("[D.type].[var_name]: OWN of registry type [held.type] (a registered instance is SHARED; a per-holder copy is PROTO)")
			if(OWNK_REL)
				if(entry[OWNE_ARG] == RELS_SYMMETRIC && !islist(value) && !isnull(value))
					OWN_REPORT("[D.type].[var_name]: REL_SET needs a list var")

/// The bare name of a proc path (/obj/foo/proc/bar -> "bar").
/proc/own_proc_name(proc_path)
	var/text = "[proc_path]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

/// The declaration entry for `var_name` on `holder`, or null.
/proc/own_entry(datum/holder, var_name)
	return own_table_of(holder).entries[var_name]

/// The entry for holder.var_name, which must be of `kind`. An undeclared var is learned: the
/// first own_set()/own_add() on it records an implicit OWN(DELETE), the first rel_set()/rel_add()
/// an implicit REF, in the type's table (ownership.md §7: declarations are only for exceptions).
/// A var of another kind is reported and null is returned.
/proc/own_entry_of_kind(datum/holder, var_name, kind, is_list = FALSE)
	var/datum/own_table/T = own_table_of(holder)
	var/list/entry = T.entries[var_name]
	if(!entry)
		if(!(var_name in holder.vars))
			OWN_REPORT("[holder.type] has no var '[var_name]'")
			return null
		switch(kind)
			if(OWNK_OWN)
				entry = list(OWNK_OWN, OWN_DELETE, null, null, is_list)
				LAZYADD(T.own_vars, var_name)
			if(OWNK_REL)
				entry = list(OWNK_REL, RELS_PLAIN, null, null, is_list)
				LAZYADD(T.ref_vars, var_name)
			else
				OWN_REPORT("[holder.type].[var_name] is not declared [own_kind_name(kind)]")
				return null
		T.entries[var_name] = entry
		T.empty = FALSE
		return entry
	if(entry[OWNE_KIND] != kind)
		OWN_REPORT("[holder.type].[var_name] is [own_kind_name(entry[OWNE_KIND])], not [own_kind_name(kind)]")
		return null
	return entry

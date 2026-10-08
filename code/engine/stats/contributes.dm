// contributes(), contributes_to(), immune_to() and what a type's compiled table says about its stats (doc/rewrite/final_api.html, section 5
// "Declaring" and "Conditional entries"; section 7 "What is consistent when"; section 19 "E3, stats").
//
//	contributes(STAT_X, cond | value | STAT_Y, priority =, reason =, key =, reads =)
//	contributes_to(nameof(rel), STAT_X, cond | value, priority =, key =, reads =)
//
// A contribution's second argument is a CONDITION when the stat is boolean and a VALUE when it is not: nameof(v) (a var), a PROC_REF (a holder proc
// x(datum/act/A), which returns the boolean or the number), another stat's id, a capability key id, cond_not()/cond_all()/cond_any() of those, or a
// constant. An enclosing when(cond, ...) gates the contribution: its condition is one of the stat's inputs, so the stat is right the moment the
// condition flips. `reads` is the var names a PROC_REF reads ("var", "rel.var" one hop, or SYSTEM_READ(system, "var")), written by hand until E5's
// generated reads replace it.

/// What a contribution's value is read from.
#define CV_CONST 1
#define CV_VAR 2
#define CV_STAT 3
#define CV_CAPKEY 4
#define CV_PROC 5
#define CV_TREE 6

/// A contribution of the entity's type to one of its stats (the compiled form of a contributes() entry).
/datum/stat_contrib
	var/stat_id
	var/value_kind
	/// The constant, var name, stat id, key id, proc name or condition tree.
	var/value_spec
	var/priority = PRIORITY_DEFAULT
	var/reason
	var/key
	var/origin
	/// The enclosing when() conditions, outermost first, or null.
	var/list/whens
	/// The raw reads list of the entry.
	var/list/reads
	/// The target entity's relation var, for a contributes_to entry.
	var/rel
	var/serial = 0

/// One dependent of an input key: a stat to recompute, or a contributes_to entry to re-evaluate.
/datum/stat_dep
	var/stat_id
	/// The contributes_to entry's compiled contribution, or null for a stat of the same entity.
	var/datum/stat_contrib/ct

/// One hop reader: this type's stat reads `remote_var` of what `rel_var` names.
/datum/stat_hop
	var/rel_var
	var/remote_var
	var/stat_id
	var/datum/stat_contrib/ct
	/// SETTLE_INLINE for a single-valued edge, SETTLE_MARKED for a collection or a system edge.
	var/settle = SETTLE_MARKED
	/// For a system read: the system name and var.
	var/system
	/// The stat's text key, or null for a contributes_to reader.
	var/skey
	/// TRUE for a one-relation hop: the reverse index on the target (stat_record.hop_in) finds its readers.
	var/fast = FALSE
	/// The relation vars to walk from the written entity back to the reader, nearest the reader first: one for "rel.var", more for "a.b.var".
	var/list/path

/// Everything the stat layer knows about one entity type, built from its compiled table. Read-only after build.
/datum/stat_type_info
	var/owner_type
	/// The stats declared for the type.
	var/list/defs
	/// stat id -> list of /datum/stat_contrib (the type's own contributions to that stat)
	var/list/contribs
	/// input key (a var name, "capkey:ID") -> list of /datum/stat_dep
	var/list/inputs
	/// stat id -> list of stat ids that read it on the same entity
	var/list/stat_readers
	/// contributes_to contributions of this type, in order.
	var/list/ct_entries
	/// Hops this type's stats read through (relation var -> hop list).
	var/list/hops
	/// A stat id -> TRUE when the instance has a var of the stat's name.
	var/list/has_var
	/// A stat key -> the type's own default of that var (the type-level constant), for the stats that have a var.
	var/list/consts
	/// TRUE when instances need their stats computed at init (any static contribution or gating).
	var/init_needed = FALSE
	/// The relation vars of this type's one-relation hops, whose targets the stat layer indexes (stat_hop_attach).
	var/list/hop_rels
	/// "[stat id]" -> its rank: one above the highest rank of any stat it reads on the entity (0 when it reads none).
	var/list/ranks

/proc/contributes(stat_id, value = null, priority = PRIORITY_DEFAULT, reason = null, key = null, list/reads = null)
	return entry_make("contributes", key, list("stat" = stat_id, "value" = value, "priority" = priority, "reason" = reason, "reads" = reads))

/proc/contributes_to(rel_var, stat_id, value = null, priority = PRIORITY_DEFAULT, key = null, list/reads = null)
	return entry_make("contributes_to", key, list("rel" = rel_var, "stat" = stat_id, "value" = value, "priority" = priority, "reads" = reads))

/// immune_to(STATUS_X, when = cond): a contribution that zeroes the status (TRUE on its companion immunity stat).
/proc/immune_to(status_id, when = null)
	if(isnull(when))
		return entry_make("contributes", null, list("stat" = STAT_IMMUNE(status_id), "value" = TRUE, "priority" = PRIORITY_DEFAULT))
	return entry_make("contributes", null, list("stat" = STAT_IMMUNE(status_id), "value" = when, "priority" = PRIORITY_DEFAULT))

// ---- the compiled view of a type ----

/// The stat layer's view of E's type, built on first use: a /datum/stat_type_info, or FALSE for a type that has no stats, no contributions and no inputs.
/proc/stat_type_of(datum/E)
	var/list/index = GLOB?.stat_type_index
	if(!islist(index))
		return FALSE
	var/info = index[E.type]
	if(!isnull(info))
		return info
	return stat_type_build(E)

/proc/stat_type_build(datum/E)
	var/datum/type_table/T = table_of(E)
	if(T == table_empty())
		return FALSE // the globals are still being built: nothing is cached
	if(!GLOB.stat_defs_built)
		stat_defs_build()
	var/datum/stat_type_info/I = new
	I.owner_type = E.type
	I.defs = list()
	I.contribs = list()
	I.inputs = list()
	I.stat_readers = list()
	I.ct_entries = list()
	I.hops = list()
	I.has_var = list()
	I.consts = list()
	for(var/id in GLOB.stat_defs)
		var/datum/stat_def/def = GLOB.stat_defs[id]
		if(!stat_declared_on(E.type, def))
			continue
		I.defs += def // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
		I.has_var[def.skey] = (def.name in E.vars) ? TRUE : FALSE
		if(I.has_var[def.skey])
			I.consts[def.skey] = initial(E.vars[def.name])
	var/serial = 0
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/entry = C.item
		if(!istype(entry))
			continue
		if(entry.kind != "contributes" && entry.kind != "contributes_to")
			continue
		var/datum/stat_contrib/contrib = stat_contrib_from(E, entry, C, I, T)
		if(!contrib)
			continue
		contrib.serial = --serial
		if(entry.kind == "contributes_to")
			I.ct_entries += contrib // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
			stat_index_inputs(E, I, contrib, null)
			continue
		var/list/for_stat = I.contribs["[contrib.stat_id]"]
		if(!for_stat)
			for_stat = list()
			I.contribs["[contrib.stat_id]"] = for_stat
		for_stat += contrib
		stat_index_inputs(E, I, contrib, contrib.stat_id)
	for(var/datum/stat_def/def as anything in I.defs)
		if(def.immune_of)
			// A status reads its companion immunity stat: the immunity flipping recomputes it.
			var/datum/stat_def/status = def.immune_of
			var/list/immune_readers = I.stat_readers["[def.id]"]
			if(!immune_readers)
				immune_readers = list()
				I.stat_readers["[def.id]"] = immune_readers
			immune_readers |= list(status.id)
	// FORMULA stats read what they declare.
	for(var/datum/stat_def/def as anything in I.defs)
		if(def.rule == STAT_RULE_FORMULA)
			var/datum/stat_contrib/pseudo = new
			pseudo.stat_id = def.id
			pseudo.reads = def.formula_reads
			stat_index_inputs(E, I, pseudo, def.id)
	I.init_needed = length(I.contribs) > 0 || length(I.ct_entries) > 0
	for(var/datum/stat_def/def as anything in I.defs)
		if(def.rule == STAT_RULE_FORMULA)
			I.init_needed = TRUE
	if(!length(I.defs) && !length(I.inputs) && !length(I.ct_entries))
		GLOB.stat_type_index[E.type] = FALSE
		return FALSE
	stat_check_contribs(E, I, T)
	stat_build_ranks(I)
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		GLOB.stat_input_keys[ct.rel] = TRUE
	GLOB.stat_type_index[E.type] = I
	return I

/// The compiled contribution of one contributes() / contributes_to() entry. null (reported) when it is malformed.
/proc/stat_contrib_from(datum/E, datum/entry/entry, datum/centry/C, datum/stat_type_info/I, datum/type_table/T)
	var/datum/stat_contrib/contrib = new
	contrib.stat_id = entry.args["stat"]
	contrib.priority = entry.args["priority"]
	contrib.reason = entry.args["reason"]
	contrib.key = entry.key
	contrib.origin = C.origin
	contrib.reads = entry.args["reads"]
	contrib.rel = entry.args["rel"]
	var/list/whens = null
	for(var/datum/entry/W as anything in C.whens)
		LAZYADD(whens, list(W))
	contrib.whens = whens
	var/spec = entry.args["value"]
	if(islist(spec))
		contrib.value_kind = CV_TREE
	else if(isnum(spec) && stat_def_of(spec))
		contrib.value_kind = CV_STAT
	else if(isnum(spec) && spec >= CAPKEY_ID_BASE)
		contrib.value_kind = CV_CAPKEY
	else if(istext(spec))
		contrib.value_kind = (spec in E.vars) ? CV_VAR : CV_PROC
	else
		contrib.value_kind = CV_CONST
	contrib.value_spec = spec
	if(contrib.value_kind == CV_PROC && !length(contrib.reads))
		contrib.reads = stat_generated_reads(E, spec)
	return contrib

GLOBAL_LIST_EMPTY(stat_input_keys) // var name -> TRUE: some type's stats read it (state_changed() asks before it calls the stat layer)

/// The reads E5's generator recorded for holder proc `proc_name` of E's type (or an ancestor), as input keys: "var", "rel.var", "a.b.var",
/// "sys:system.var". A read through an actor, held item or target is not an input of the holder and is left out.
/proc/stat_generated_reads(datum/E, proc_name)
	var/list/table = GLOB.generated_reads_table
	if(!length(table))
		return null
	var/path = "[E.type]"
	var/row
	while(length(path))
		row = table["[path]::[proc_name]"]
		if(row)
			break
		var/slash = findlasttext(path, "/")
		if(slash <= 1)
			break
		path = copytext(path, 1, slash)
	if(!row)
		return null
	var/list/names = GLOB.generated_read_names
	var/list/roots = GLOB.generated_read_roots
	var/list/keys = list()
	var/list/rows = row
	for(var/i in 2 to length(rows))
		var/list/read = rows[i]
		var/root = roots[read[1]]
		var/name = names[read[3]]
		if(read[2] == SREAD_KIND_SYSTEM)
			if(findtext(root, "system:") == 1)
				keys += list("sys:[copytext(root, 8)].[name]")
			continue
		if(!(read[2] in list(SREAD_KIND_VAR, SREAD_KIND_ACCESSOR)) || read[1] != SREAD_ROOT_HOLDER)
			continue
		var/key = ""
		if(length(read) > 3)
			for(var/h in 4 to length(read))
				key += "[names[read[h]]]."
		keys += list("[key][name]")
	return keys

/// Registers the inputs of a contribution (its value spec, its when() conditions, its reads) in the type's index: each input key points at the stat
/// (or contributes_to entry) to recompute when it changes.
/proc/stat_index_inputs(datum/E, datum/stat_type_info/I, datum/stat_contrib/contrib, stat_id)
	var/list/keys = list()
	if(contrib.value_kind)
		stat_collect_condition_inputs(E, contrib.value_kind, contrib.value_spec, keys)
	for(var/datum/entry/W as anything in contrib.whens)
		stat_collect_tree_inputs(E, W.args["cond"], keys)
		for(var/read in W.args["reads"])
			keys += list(read)
	for(var/read in contrib.reads)
		keys += list(read)
	for(var/key in keys)
		// A var that is itself a declared stat of this type is read as that stat (so ranks and settling follow it).
		if(istext(key) && !findtext(key, ".") && !findtext(key, ":"))
			var/datum/stat_def/named = stat_def_named(key)
			if(named && stat_declared_on(E.type, named) && !(named.id == stat_id))
				key = stat_ref_key(named.id)
		stat_register_input(E, I, key, stat_id, contrib)

/// Adds the inputs of one value spec to `keys`.
/proc/stat_collect_condition_inputs(datum/E, kind, spec, list/keys)
	switch(kind)
		if(CV_VAR)
			keys += list(spec)
		if(CV_STAT)
			keys += list(stat_ref_key(spec))
		if(CV_CAPKEY)
			keys += list("capkey:[spec]")
		if(CV_TREE)
			stat_collect_tree_inputs(E, spec, keys)

/// The inputs of a condition tree or a leaf (a var name, a stat or key id, cond_not/all/any of those, a PROC_REF whose reads are declared).
/proc/stat_collect_tree_inputs(datum/E, cond, list/keys)
	if(islist(cond))
		var/list/tree = cond
		for(var/i in 2 to length(tree))
			stat_collect_tree_inputs(E, tree[i], keys)
		return
	if(isnum(cond))
		if(stat_def_of(cond))
			keys += list(stat_ref_key(cond))
		else if(cond >= CAPKEY_ID_BASE)
			keys += list("capkey:[cond]")
		return
	if(istext(cond) && (cond in E.vars))
		keys += list(cond)

/// The input key of another stat read on the same entity.
/proc/stat_ref_key(stat_id)
	return "stat:[stat_id]"

/// One input key -> the dependent: a stat of this entity, a hop reader, or a system read.
/proc/stat_register_input(datum/E, datum/stat_type_info/I, key, stat_id, datum/stat_contrib/contrib)
	if(istext(key) && findtext(key, "sys:") == 1)
		var/datum/stat_hop/sys = new
		sys.system = copytext(key, 5)
		sys.stat_id = stat_id
		sys.skey = stat_id ? "[stat_id]" : null
		sys.ct = stat_id ? null : contrib // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
		sys.settle = SETTLE_MARKED
		var/list/sys_list = I.hops["sys"]
		if(!sys_list)
			sys_list = list()
			I.hops["sys"] = sys_list
		sys_list += sys
		var/dot_at = findtext(sys.system, ".")
		if(dot_at)
			GLOB.stat_input_keys[copytext(sys.system, dot_at + 1)] = TRUE
		return
	if(istext(key) && findtext(key, "stat:") == 1)
		var/read_id = text2num(copytext(key, 6))
		var/list/readers = I.stat_readers["[read_id]"]
		if(!readers)
			readers = list()
			I.stat_readers["[read_id]"] = readers
		if(stat_id)
			readers |= list(stat_id)
		else
			var/datum/stat_dep/ct_dep = new
			ct_dep.ct = contrib // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
			var/list/ct_readers = I.inputs[key]
			if(!ct_readers)
				ct_readers = list()
				I.inputs[key] = ct_readers
			ct_readers += ct_dep
		return
	if(istext(key) && findtext(key, "."))
		var/list/segments = splittext(key, ".")
		var/datum/stat_hop/hop = new
		hop.remote_var = segments[length(segments)]
		segments.len--
		hop.path = segments
		hop.fast = (length(segments) == 1)
		hop.rel_var = segments[1]
		if(hop.fast)
			LAZYOR(I.hop_rels, hop.rel_var)
		hop.stat_id = stat_id
		hop.skey = stat_id ? "[stat_id]" : null
		hop.ct = stat_id ? null : contrib // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
		hop.settle = length(segments) == 1 ? stat_hop_settle(E, hop.rel_var, hop.remote_var) : SETTLE_MARKED
		var/list/hop_list = I.hops[hop.remote_var]
		if(!hop_list)
			hop_list = list()
			I.hops[hop.remote_var] = hop_list
		hop_list += hop
		var/list/index = GLOB.stat_hop_index[hop.remote_var]
		if(!index)
			index = list()
			GLOB.stat_hop_index[hop.remote_var] = index
		index += list(list(E.type, hop))
		GLOB.stat_input_keys[hop.remote_var] = TRUE
		// The relation itself changing (the reader now names another entity) recomputes the reader too.
		stat_register_input(E, I, hop.rel_var, stat_id, contrib)
		return
	// A plain var of this entity (or a capkey): the stat (or ct entry) recomputes when it changes.
	var/datum/stat_dep/dep = new
	dep.stat_id = stat_id
	dep.ct = stat_id ? null : contrib // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
	var/list/deps = I.inputs[key]
	if(!deps)
		deps = list()
		I.inputs[key] = deps
	deps += dep
	GLOB.stat_input_keys[key] = TRUE

/// Ranks: a stat reads the stats before it, so its rank is one above the highest rank among them (relaxation over the readers graph, which the
/// cycle check proves finite).
/proc/stat_build_ranks(datum/stat_type_info/I)
	I.ranks = list()
	for(var/datum/stat_def/def as anything in I.defs)
		I.ranks["[def.id]"] = 0
	for(var/pass in 1 to length(I.defs) + 1)
		var/changed_rank = FALSE
		for(var/read_key in I.stat_readers)
			var/read_rank = I.ranks[read_key] || 0
			for(var/reader in I.stat_readers[read_key])
				if((I.ranks["[reader]"] || 0) < read_rank + 1)
					I.ranks["[reader]"] = read_rank + 1
					changed_rank = TRUE
		if(!changed_rank)
			break

/// How a write reaches a reader through relation var `rel_var` of the reader's type (section 7: "the build derives which is which from the
/// relation declarations, and no author declares it"). A write travels from the target to the reader: it is single-valued when at most one
/// reader can name the target through that relation (a one-to-one link, or an owned value read by its one owner); a plain reference may be named
/// by many, so it is a collection edge, and marked. Two or more hops are always marked.
/proc/stat_hop_settle(datum/E, rel_var, remote_var)
	if(findtext(remote_var, "."))
		return SETTLE_MARKED
	var/datum/type_table/T = table_of(E)
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/entry = C.item
		if(!istype(entry))
			continue
		switch(entry.kind)
			if(ENTRY_OWNS_ONE)
				if(entry.args["var"] == rel_var)
					return SETTLE_INLINE
			if(ENTRY_REF_ONE)
				if(entry.args["var"] == rel_var)
					return SETTLE_MARKED
			if(ENTRY_REF_MANY, ENTRY_OWNS_MANY)
				if(entry.args["var"] == rel_var)
					return SETTLE_MARKED
			if(ENTRY_LINK)
				for(var/end in list("a", "b"))
					if(entry.args["[end]_var"] == rel_var && ispath(E.type, entry.args["[end]_type"]))
						var/other = end == "a" ? "b" : "a"
						return (entry.args["[end]_many"] || entry.args["[other]_many"]) ? SETTLE_MARKED : SETTLE_INLINE
	return SETTLE_MARKED

/// The build-time checks of a type's stat declarations: a contribution to a stat the type does not declare, a value outside the stat's schema, a
/// cycle among the stats it reads.
/proc/stat_check_contribs(datum/E, datum/stat_type_info/I, datum/type_table/T)
	for(var/stat_key in I.contribs)
		var/datum/stat_def/def = stat_def_of(text2num(stat_key))
		for(var/datum/stat_contrib/contrib as anything in I.contribs[stat_key])
			if(!def || !stat_declared_on(E.type, def))
				declare_report("[contrib.origin]: [declare_rule(RULE_STAT)] [E.type]: contributes() names stat [def ? def.name : contrib.stat_id], which the type does not declare -- add STAT([E.type], name, RULE, id = ...) or contribute to a stat it has")
				continue
			if(stat_rule_is_boolean(def.rule) && contrib.value_kind == CV_CONST && isnull(contrib.value_spec))
				declare_report("[contrib.origin]: [declare_rule(RULE_STAT)] [E.type]: a contribution to the boolean stat [def.name] needs a condition or a value")
			if(def.schema && contrib.value_kind == CV_CONST && !stat_rule_is_boolean(def.rule))
				var/list/checked = schema_check(def.schema, contrib.value_spec)
				if(checked[1] == SCHEMA_REJECT || checked[2])
					declare_report("[contrib.origin]: [declare_rule(RULE_STAT)] [E.type]: a contribution of [contrib.value_spec] to [def.name] does not satisfy its schema ([checked[2]])")
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		var/datum/stat_def/ct_def = stat_def_of(ct.stat_id)
		if(!ct_def)
			declare_report("[ct.origin]: [declare_rule(RULE_STAT)] [E.type]: contributes_to() names stat [ct.stat_id], which is not declared")
	stat_check_cycles(E, I)

/// A cycle among the stats one entity's type reads is a build error naming the loop.
/proc/stat_check_cycles(datum/E, datum/stat_type_info/I)
	var/list/state = list() // "[id]" -> 1 visiting, 2 done
	for(var/stat_key in I.stat_readers)
		stat_cycle_visit(E, I, stat_key, state, list())

/proc/stat_cycle_visit(datum/E, datum/stat_type_info/I, stat_key, list/state, list/chain)
	if(state[stat_key] == 2)
		return
	if(state[stat_key] == 1)
		var/list/names = list()
		for(var/k in chain)
			names += stat_label(text2num(k))
		names += stat_label(text2num(stat_key))
		declare_report("[RULE_STAT_CYCLE] [E.type]: a cycle among stats: [jointext(names, " -> ")]")
		return
	state[stat_key] = 1
	var/list/next_chain = chain + list(stat_key)
	for(var/reader in I.stat_readers[stat_key])
		stat_cycle_visit(E, I, "[reader]", state, next_chain)
	state[stat_key] = 2


/// The types that declare a FORMULA stat (STAT(type, x, FORMULA)), read from the generated /datum/stat_decl rows so it works while the
/// globals initialize too (type tables are statics and may be built then).
/proc/stat_formula_types()
	var/static/list/types // ALLOW(sys_static_getter): read while the globals initialize (type tables build then), so it cannot be a GLOBAL_LIST_INIT
	if(!types)
		types = list()
		for(var/decl_type in subtypesof(/datum/stat_decl))
			var/datum/stat_decl/D = new decl_type
			var/list/row = D.spec()
			if(length(row) < 2)
				continue
			var/list/made = call(row[2])()
			if(length(made) >= 2 && made[2] == STAT_RULE_FORMULA)
				types |= row[1]
	return types

/// TRUE when `type` inherits a FORMULA stat that `table_type` (the type whose table it would share) does not: it needs a table of its own,
/// or the shared table's hooks never compute that formula at init.
/proc/stat_type_needs_own_table(type, table_type)
	for(var/declared in stat_formula_types())
		if(ispath(type, declared) && !ispath(table_type, declared))
			return TRUE
	return FALSE

/// TRUE when instances of the table's type compute stats at init: it has a contributes()/contributes_to() entry or declares a FORMULA stat.
/proc/stat_table_needs_init(datum/type_table/T)
	if(T.owner_type)
		for(var/declared in stat_formula_types())
			if(ispath(T.owner_type, declared))
				return TRUE
	if(!islist(GLOB?.stat_defs))
		return FALSE
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/entry = C.item
		if(istype(entry) && (entry.kind == "contributes" || entry.kind == "contributes_to"))
			return TRUE
	if(!GLOB.stat_defs_built)
		stat_defs_build()
	for(var/id in GLOB.stat_defs)
		var/datum/stat_def/def = GLOB.stat_defs[id]
		if(def.rule == STAT_RULE_FORMULA && T.owner_type && stat_declared_on(T.owner_type, def))
			return TRUE
	return FALSE

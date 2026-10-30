// The change graph's plans (doc/rewrite/proposals/change_graph.md sections 2, 4, 11 step 2).
//
// `analyze gen plans` writes, per type that declares a draw(), what that draw reads (GLOB.generated_plans) and the interned keys
// (CGK_<var>, GLOB.generated_key_names). A type with no row of its own uses its nearest ancestor's. Step 2 only builds and answers the plan;
// state_changed() still dispatches through today's tables, and dq_change_plan_parity proves the plan answers what they answer for every type.
// Step 3 moves the dispatch onto the plan and deletes the tables.

/// Writes to a type the generator marked unresolved (D5: such a type keeps marking every output). The plan_fallback count.
GLOBAL_VAR_INIT(plan_fallbacks, 0)
/// Tracked writes whose redraw the plans spared (state_changed()); the metric of step 3c/5.
GLOBAL_VAR_INIT(plan_spared_writes, 0)
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

/// Adds to `into` the holder vars a look condition (a var, a not/all_of/any_of tree, a stat id, a capability key, a PROC_REF) reads. FALSE when a
/// leaf's reads are unknown (a proc the build generated no reads for).
/proc/plan_condition_reads(atom/E, cond, list/into)
	if(islist(cond))
		var/list/tree = cond
		if(tree[1] == "config")
			return TRUE
		for(var/i in 2 to length(tree))
			if(!plan_condition_reads(E, tree[i], into))
				return FALSE
		return TRUE
	if(isnull(cond))
		return TRUE
	if(isnum(cond))
		var/datum/stat_def/def = stat_def_of(cond)
		if(def)
			into |= def.name // a stat publishes its own var
		return TRUE // a capability key marks its holder itself (capability_key_changed)
	if(!istext(cond))
		// A TYPE_PROC_REF: the proc's name is its last segment.
		var/proc_text = "[cond]"
		var/slash = findlasttext(proc_text, "/")
		if(!findtext(proc_text, "/proc/") || !slash)
			return FALSE
		cond = copytext(proc_text, slash + 1)
	if(cond in E.vars)
		into |= cond
		return TRUE
	if(!hascall(E, cond))
		return TRUE // a layer name, not a handler
	if(!stat_generated_row(GLOB.generated_reads_table, E, cond))
		return FALSE
	for(var/read in stat_generated_reads(E, cond))
		if(findtext(read, "sys:") == 1)
			continue // a system read: the system's own write redraws, not E's
		into |= copytext(read, 1, findtext(read, ".") || 0)
	return TRUE

/// What E's base draw beyond its own draw() reads on the holder: its look_layer / look_glow entries (their conditions, handlers and reads) and
/// its capabilities' on_draw() (output_reads()). null when something it draws reads what no table knows (a legacy capability draw, a handler with
/// no generated reads).
/proc/plan_presentation_reads(atom/E)
	. = list()
	var/datum/type_table/T = table_of(E)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_LOOK_LAYER))
		var/datum/entry/entry = C.item
		if(!plan_condition_reads(E, entry.args["when"], .) || !plan_condition_reads(E, entry.args["layer"], .) || !plan_condition_reads(E, entry.args["glow"], .))
			return null
		for(var/datum/entry/W as anything in C.whens)
			if(!plan_condition_reads(E, W.args["cond"], .))
				return null
		for(var/read in entry.args["reads"])
			. |= read
	// The look layers an activation brings (present_rows() reads them beside the type's own).
	for(var/datum/activation/A as anything in E.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		for(var/datum/centry/C as anything in activation_plan(A.def))
			var/datum/entry/entry = C.item
			if(!istype(entry) || entry.kind != ENTRY_LOOK_LAYER)
				continue
			if(!plan_condition_reads(E, entry.args["when"], .) || !plan_condition_reads(E, entry.args["layer"], .) || !plan_condition_reads(E, entry.args["glow"], .))
				return null
			for(var/datum/entry/W as anything in C.whens)
				if(!plan_condition_reads(E, W.args["cond"], .))
					return null
			for(var/read in entry.args["reads"])
				. |= read
	for(var/datum/capability/C as anything in caps_of(E))
		if(GLOB.generated_capability_legacy_outputs["[C.type]"])
			return null
		if(C.output_hooks & OUTPUT_HOOK_DRAW)
			for(var/read in C.output_reads(OUTPUT_HOOK_DRAW))
				. |= read

/// Builds plan_spares_draw()'s entry for (E's type, var_name): PLAN_SPARE when nothing that refreshes on DEP_DRAW reads the var.
/proc/plan_spares_build(atom/E, var_name, base_key)
	if(plan_type_fallback(E.type))
		return PLAN_KEEP // D5: the walk could not resolve an output; every write redraws it
	var/list/plan = plan_of(E.type)
	if(plan[var_name] & PLAN_DRAW)
		return PLAN_KEEP
	var/list/hidden = plan_nearest_row(GLOB.generated_plan_hidden_verbs, E.type)
	if(hidden && (var_name in hidden))
		return PLAN_KEEP
	var/list/granted = plan_nearest_row(GLOB.generated_plan_granted_verbs, E.type)
	if(granted && (var_name in granted))
		return PLAN_KEEP
	var/list/presented = plan_presented_for(E, base_key)
	if(isnull(presented) || (var_name in presented))
		return PLAN_KEEP
	return PLAN_SPARE

DECLARE_SHARED_CACHE(change_plan_spares, GLOBAL_PROC_REF(plan_spares_build), SC_NEVER)

/// plan_presentation_reads(E) for the type and activation set `base_key` names, built once for all the vars of that type (the spares cache asks per var).
/// A hit wraps the answer in a list because a shared cache treats a null value as a miss and "the walk gave up" is null.
/proc/plan_presented_for(atom/E, base_key)
	var/list/wrapped = CACHED_KEY(change_plan_presented, base_key, E)
	return wrapped[1]

/proc/plan_presented_build(atom/E)
	return list(plan_presentation_reads(E))

DECLARE_SHARED_CACHE(change_plan_presented, GLOBAL_PROC_REF(plan_presented_build), SC_NEVER)

/// TRUE when a write of `var_name` on E needs no redraw (look and verbs, DEP_DRAW): E is an atom (not a mob: species and traits grant verbs no
/// plan sees) with no activations, and neither its type's generated plans (its draw, its verb outputs) nor its look layers and capability draws
/// read the var. Asked by state_changed() for a type that
/// declares no dependencies (one that does is narrowed by its derived table already).
/proc/plan_spares_draw(datum/E, var_name)
	if(!isatom(E) || ismob(E))
		return FALSE
	// A lookup read (lookup_reads.dm) publishes under its own pseudo-key: it is no var, so no plan names it, and it exists only because an
	// output of the holder reads the looked-up field (the generated drawn_from / ui_from rows), so its publication always redraws.
	if(IS_LOOKUP_READ_KEY(var_name))
		return FALSE
	// The answer depends on the type and on the activations the holder carries (they bring look layers): both are in the key.
	var/base_key = "[E.type]"
	var/list/activations = E.rx?.activations
	if(length(activations))
		var/list/defs = list()
		for(var/datum/activation/A as anything in activations)
			if(!A.dead && A.runs)
				defs |= "[A.def.key]"
		if(length(defs))
			base_key += "||[jointext(sortList(defs), ",")]"
	return CACHED_KEY(change_plan_spares, "[base_key]|[var_name]", E, var_name, base_key) == PLAN_SPARE

#undef PLAN_SPARE
#undef PLAN_KEEP

// ---- the stat layer's input names (the stats fold, change_graph.md section 11 step 3) ----

/// The stat input names from the generated, over-inclusive declared reads (generated_stat_input_reads_build(), `gen plans`): a var, the link
/// and the var of "rel.var", the var of "sys:system.var". Called by GLOB.stat_input_keys' initializer, so it calls the generated builder itself
/// rather than reading another global that may not be built yet.
/proc/stat_input_names_build()
	. = list()
	for(var/raw in generated_stat_input_reads_build())
		if(!istext(raw) || !length(raw))
			continue
		var/text = raw
		if(findtext(text, "sys:") == 1)
			text = copytext(text, 5)
			var/dot_at = findtext(text, ".")
			if(dot_at)
				.[copytext(text, dot_at + 1)] = TRUE
			continue
		for(var/segment in splittext(text, "."))
			if(length(segment))
				.[segment] = TRUE

/// Tracked writes state_changed() handed to the stat layer, and those the stat layer then found nothing for (no input, hop or system read of
/// the var): the cost of the generated set being over-inclusive.
GLOBAL_VAR_INIT(stat_input_queries, 0)
GLOBAL_VAR_INIT(stat_input_noops, 0)

// ---- the reader keys (step 3d: reactions, hooks, lifecycle forms and sequences consult the plan first; step 3e: per type) ----

/// name -> PLAN_READ_* bits read on every type: the generated rows with no owner (capability entries and reactions, entry procs, sequences, stats,
/// the far ends of hop paths), stat ids resolved to their names. null until built (plan_reader_bits()).
GLOBAL_LIST_INIT(plan_reader_keys, null)
/// owner type text -> list(name -> bits): the generated rows of a type's own declarations (its CAPABILITIES block, reactions(), derived(),
/// generated_reads()); a subtype inherits them.
GLOBAL_LIST_INIT(plan_reader_type_rows, null)
/// type text -> list("<type>::<proc>" rows of GLOB.generated_reads_table declared on exactly that type).
GLOBAL_LIST_INIT(plan_reader_handler_rows, null)
/// The tracked var names (generated_tracked_names_build()): the keys plan_reader_bits() narrows.
GLOBAL_LIST_INIT(plan_tracked_names, null)

/// Adds name `name` (a text key, or a stat id resolved to its name and key) with `bits` to `into`.
/proc/plan_reader_add(list/into, name, bits)
	if(isnum(name))
		var/datum/stat_def/def = stat_def_of(name)
		if(!def)
			return
		into[def.name] |= bits
		if(istext(def.stat_key))
			into[def.stat_key] |= bits
		return
	if(istext(name))
		into[name] |= bits

/// Builds the reader plan's global part. FALSE when the stat ids cannot be resolved yet (the stat defs are not built): nothing is cached then.
/proc/plan_reader_keys_build()
	if(!islist(GLOB?.stat_defs) || !islist(GLOB.generated_read_names) || !islist(GLOB.generated_reads_table) || !islist(GLOB.generated_plans))
		return FALSE
	var/list/keys = list()
	var/list/typed = list()
	for(var/list/row as anything in generated_reader_keys_build())
		var/owner = row[3]
		if(isnull(owner))
			plan_reader_add(keys, row[1], row[2])
			continue
		var/list/into = typed[owner]
		if(!into)
			into = list()
			typed[owner] = into
		plan_reader_add(into, row[1], row[2])
	var/list/handlers = list()
	for(var/id in GLOB.generated_reads_table)
		var/sep = findtext(id, "::")
		if(!sep)
			continue
		var/owner = copytext(id, 1, sep)
		var/list/rows = handlers[owner]
		if(!rows)
			rows = list()
			handlers[owner] = rows
		rows += id
	GLOB.plan_tracked_names = generated_tracked_names_build()
	GLOB.plan_reader_type_rows = typed
	GLOB.plan_reader_handler_rows = handlers
	GLOB.plan_reader_keys = keys
	return TRUE

/// Builds plan_reader_type_keys()'s entry: name -> bits that `type`'s own chain may read. Its declarations' rows (and its ancestors'), what its
/// generated handler rows read (any name a read names, a hop's links included) and what its draw and verb outputs read (derived() and the generated
/// reads feed those into the reaction table too).
/proc/plan_reader_type_build(type)
	. = list()
	var/path = type
	while(path)
		var/text = "[path]"
		var/list/own = GLOB.plan_reader_type_rows[text]
		for(var/name in own)
			.[name] |= own[name]
		for(var/id in GLOB.plan_reader_handler_rows[text])
			var/list/row = GLOB.generated_reads_table[id]
			for(var/i in 2 to length(row))
				var/list/read = row[i]
				if(!islist(read))
					continue
				for(var/j in 3 to length(read))
					var/name = GLOB.generated_read_names[read[j]]
					if(!istext(name))
						continue
					for(var/segment in splittext(name, "."))
						if(length(segment))
							.[segment] |= PLAN_READ_REACT | PLAN_READ_HOOK
		for(var/list/verb_rows as anything in list(GLOB.generated_plans[text], GLOB.generated_plan_hidden_verbs[text], GLOB.generated_plan_granted_verbs[text]))
			for(var/raw in verb_rows)
				for(var/segment in splittext("[raw]", "."))
					if(length(segment))
						.[segment] |= PLAN_READ_REACT | PLAN_READ_HOOK
		var/datum/typed = path
		path = initial(typed.parent_type)

DECLARE_SHARED_CACHE(change_reader_types, GLOBAL_PROC_REF(plan_reader_type_build), SC_NEVER)

/// name -> bits read on `type` by its own chain's declarations (plan_reader_type_build()), built once per type.
/proc/plan_reader_type_keys(type)
	return CACHED(change_reader_types, type)

/// The PLAN_READ_* classes whose static tables may read the tracked var `key` on an entity of `type` (null: on some type). 0 for a tracked var no
/// reaction, hook, form or sequence of that type reads. PLAN_READ_ALL for any other key (an engine key a producer publishes, "capkey:<n>", a
/// runtime-only key) and before the plan is built.
/proc/plan_reader_bits(key, type)
	var/list/keys = GLOB.plan_reader_keys
	if(!keys)
		if(!plan_reader_keys_build())
			return PLAN_READ_ALL
		keys = GLOB.plan_reader_keys
	if(!istext(key) || !GLOB.plan_tracked_names[key])
		return PLAN_READ_ALL
	. = keys[key] || 0
	if(type)
		var/list/typed = plan_reader_type_keys(type)
		. |= typed[key] || 0
	else
		for(var/owner in GLOB.plan_reader_type_rows)
			. |= GLOB.plan_reader_type_rows[owner][key] || 0
		if(!.)
			. = PLAN_READ_REACT | PLAN_READ_HOOK // without a type the handler and output reads of every type would have to be searched

/// Tracked writes whose static reader probes the reader plan spared (state_changed(): no reaction, hook or form of any type reads the var).
GLOBAL_VAR_INIT(plan_spared_reader_probes, 0)
/// Tracked writes state_changed() asked the reader plan about (the denominator of plan_spared_reader_probes).
GLOBAL_VAR_INIT(plan_reader_probes, 0)

// Object-model core: the registry (doc/rewrite/object_model_core.md, "Boot").
//
// Built once, on first use (SSbehaviours.Initialize() forces it at boot).
// It instantiates every DEF, parses every table row, compiles run order,
// wake tables, event handler tables and derived order, and collects every
// declaration error in `errors` (each also a stack_trace unless `quiet`).
// Unit tests build private registries from a named set of decls.

GLOBAL_DATUM(om_reg, /datum/om/registry)

/proc/om_registry()
	RETURN_TYPE(/datum/om/registry)
	if(!GLOB.om_reg)
		GLOB.om_reg = new /datum/om/registry
		GLOB.om_reg.build()
	return GLOB.om_reg

/datum/om/registry
	var/list/errors = list()
	/// Collect errors without stack traces (tests of broken tables).
	var/quiet = FALSE
	/// Null: every non-skipped bundle/decl. Else only these (plus their includes).
	var/list/only_bundles
	/// Also build DEFs marked registry_skip (private test registries).
	var/include_skipped = FALSE
	var/built = FALSE

	var/list/behaviours = list()
	var/list/behaviour_by_type = list()
	var/list/effects = list()
	var/list/effect_by_id = list()
	var/list/clocks = list()
	var/list/clock_by_id = list()
	var/list/relations = list()
	var/list/relation_by_type = list()
	var/list/event_types = list()
	var/list/event_idx = list()
	/// event idx -> list of behaviour ids handling it (subtypes flattened).
	var/list/event_handlers = list()
	var/list/derived = list()
	var/list/derived_by_name = list()
	var/list/checks_cache = list()
	var/list/named_checks = list()
	var/list/tasks = list()
	var/list/task_by_name = list()
	var/list/task_by_type = list()
	var/list/services = list()
	var/list/bundles = list()
	var/list/bundle_by_type = list()
	var/list/decls = list()
	/// Every type some decl applies to (on_materialize checks this).
	var/list/decl_typecache = list()
	/// bundle type -> flattened list of bundles (includes first, then itself).
	var/list/expansions = list()
	/// entity type -> /datum/om/type_table (lazy).
	var/list/type_tables = list()
	/// Internal behaviours (expiry, rates, tasks, ui, edge refresh).
	var/datum/om/behaviour/expiry_behaviour
	var/datum/om/behaviour/rate_behaviour
	var/datum/om/behaviour/task_behaviour
	var/datum/om/behaviour/ui_behaviour
	var/datum/om/behaviour/edge_behaviour

/datum/om/registry/proc/error(msg)
	errors += msg
	if(!quiet)
		stack_trace("om registry: [msg]")

/proc/om_is_abstract(datum/om/D)
	return D.abstract_type == D.type

/datum/om/registry/proc/build()
	if(built)
		return
	built = TRUE
	build_bundles()
	build_clocks()
	build_effects()
	build_named_checks()
	build_relations()
	build_events()
	build_behaviours()
	build_derived()
	build_event_tables()
	build_tasks()
	build_services()

// ---------------------------------------------------------------- bundles

/datum/om/registry/proc/bundle_instance(path)
	var/datum/om/bundle/B = bundle_by_type[path]
	if(B)
		return B
	if(!ispath(path, /datum/om/bundle) && !ispath(path, /datum/om/decl))
		error("[path] is not a bundle")
		return null
	B = new path
	bundle_by_type[path] = B
	bundles += B
	if(istype(B, /datum/om/decl))
		var/datum/om/decl/D = B
		if(!om_is_abstract(D))
			if(!ispath(D.of))
				error("[D.type]: `of` must be a type path")
			else
				decls += D
	return B

/datum/om/registry/proc/build_bundles()
	var/list/roots
	if(!isnull(only_bundles))
		roots = only_bundles
	else
		roots = list()
		for(var/path in subtypesof(/datum/om/bundle) | subtypesof(/datum/om/decl))
			var/datum/om/bundle/proto = path
			if(initial(proto.registry_skip) || initial(proto.abstract_type) == path)
				continue
			roots += path
	for(var/path in roots)
		bundle_instance(path)
	for(var/datum/om/bundle/B as anything in bundles.Copy())
		expand(B.type, list())
	for(var/datum/om/decl/D as anything in decls)
		for(var/path in typesof(D.of))
			decl_typecache[path] = TRUE

/// Flattened include list of `path`: every included bundle (depth first, each
/// once), then `path` itself.
/datum/om/registry/proc/expand(path, list/stack)
	if(expansions[path])
		return expansions[path]
	if(path in stack)
		error("bundle include cycle: [jointext(stack + path, " -> ")]")
		return list()
	var/datum/om/bundle/B = bundle_instance(path)
	if(!B)
		return list()
	var/list/out = list()
	stack += path
	for(var/inc in B.include)
		for(var/datum/om/bundle/sub as anything in expand(inc, stack))
			out |= sub
	stack -= path
	out |= B
	expansions[path] = out
	return out

// ---------------------------------------------------------------- clocks and effects

/datum/om/registry/proc/build_clocks()
	var/list/rows = om_library_clocks()
	for(var/datum/om/bundle/B as anything in bundles)
		for(var/id in B.clocks)
			rows[id] = B.clocks[id]
	for(var/id in rows)
		var/list/row = rows[id]
		var/datum/om/clock_def/C = new
		C.id = id
		if(islist(row))
			for(var/key in row)
				if(!(key in list("min", "max")))
					error("clock [id]: unknown key [key]")
			if(!isnull(row["min"]))
				C.min_rate = row["min"]
			if(!isnull(row["max"]))
				C.max_rate = row["max"]
		clocks += C
		C.idx = length(clocks)
		clock_by_id[id] = C

/datum/om/registry/proc/build_effects()
	var/list/rows = om_library_effects()
	rows[EFFECT_RELEVANCE] = list("combine" = COMBINE_MAX, "channel" = CHANGE_RELEVANCE, "default" = RELEVANCE_NONE, "kind" = OM_EFFECT_RELEVANCE)
	rows[EFFECT_SUSPENDED] = list("combine" = COMBINE_ANY, "kind" = OM_EFFECT_SUSPEND)
	for(var/datum/om/clock_def/C as anything in clocks)
		rows["clock:[C.id]:mult"] = list("combine" = COMBINE_MULTIPLY, "channel" = CHANGE_CLOCK, "default" = 1, "kind" = OM_EFFECT_CLOCK_MULT, "clock" = C.id)
		rows["clock:[C.id]:inhibit"] = list("combine" = COMBINE_MAX, "channel" = CHANGE_CLOCK, "default" = 0, "kind" = OM_EFFECT_CLOCK_INHIBIT, "clock" = C.id)
	for(var/datum/om/bundle/B as anything in bundles)
		for(var/id in B.effects)
			if(rows[id])
				error("effect [id] defined twice (second in [B.type])")
			rows[id] = B.effects[id]
	var/static/list/allowed = list("combine", "stacking", "channel", "default", "expr", "type", "kind", "clock")
	for(var/id in rows)
		var/list/row = rows[id]
		if(!islist(row))
			error("effect [id]: row must be a list")
			continue
		var/path = row["type"] || /datum/om/effect
		if(!ispath(path, /datum/om/effect))
			error("effect [id]: type [path] is not a /datum/om/effect")
			path = /datum/om/effect
		var/datum/om/effect/E = new path
		E.id = id
		for(var/key in row)
			if(!(key in allowed))
				error("effect [id]: unknown key [key]")
		if(!isnull(row["combine"]))
			E.combine = row["combine"]
		if(!(E.combine in list(COMBINE_ANY, COMBINE_SUM, COMBINE_MAX, COMBINE_MIN, COMBINE_MULTIPLY, COMBINE_SUM_PER_KEY)))
			error("effect [id]: bad combine [E.combine]")
			E.combine = COMBINE_ANY
		if(!isnull(row["stacking"]))
			E.stacking = row["stacking"]
		if(!(E.stacking in list(STACKING_REPLACE, STACKING_EXTEND, STACKING_MAX)))
			error("effect [id]: bad stacking [E.stacking]")
			E.stacking = STACKING_REPLACE
		E.channel = row["channel"] || 0
		E.kind = row["kind"] || OM_EFFECT_PLAIN
		E.expr = row["expr"]
		if("default" in row)
			E.default_value = row["default"]
		else
			switch(E.combine)
				if(COMBINE_ANY)
					E.default_value = FALSE
				if(COMBINE_MULTIPLY)
					E.default_value = 1
				if(COMBINE_SUM_PER_KEY)
					E.default_value = null
				else
					E.default_value = 0
		if(row["clock"])
			var/datum/om/clock_def/C = clock_by_id[row["clock"]]
			E.clock_idx = C?.idx
			if(E.kind == OM_EFFECT_CLOCK_MULT)
				C.mult = E
			else if(E.kind == OM_EFFECT_CLOCK_INHIBIT)
				C.inhibit = E
		effects += E
		E.idx = length(effects)
		effect_by_id[id] = E
	// Composite dependencies.
	for(var/datum/om/effect/E as anything in effects)
		if(!E.expr)
			continue
		var/list/refs = list()
		if(!om_effect_expr_refs(E.expr, refs))
			error("effect [E.id]: malformed expr")
			E.expr = null
			continue
		for(var/ref in refs)
			var/datum/om/effect/part = effect_by_id[ref]
			if(!part)
				error("effect [E.id]: expr names unknown effect [ref]")
				continue
			if(part.expr)
				error("effect [E.id]: composites of composites are not supported ([ref])")
				continue
			LAZYADD(part.dependents, E.idx)

/// Collects effect ids named in a composite expression. FALSE if malformed.
/proc/om_effect_expr_refs(expr, list/out)
	if(istext(expr))
		out |= expr
		return TRUE
	if(!islist(expr))
		return FALSE
	var/list/L = expr
	if(!length(L) || !(L[1] in list("all", "any", "not", "sum")))
		return FALSE
	if(L[1] == "not" && length(L) != 2)
		return FALSE
	for(var/i in 2 to length(L))
		if(!om_effect_expr_refs(L[i], out))
			return FALSE
	return TRUE

/datum/om/registry/proc/effect(id)
	RETURN_TYPE(/datum/om/effect)
	var/datum/om/effect/E = effect_by_id[id]
	if(!E)
		CRASH("om: unknown effect [id]")
	return E

// ---------------------------------------------------------------- checks

/datum/om/registry/proc/build_named_checks()
	for(var/datum/om/bundle/B as anything in bundles)
		for(var/name in B.checks)
			if(named_checks[name])
				error("check [name] defined twice (second in [B.type])")
			named_checks[name] = B.checks[name]
	for(var/name in named_checks)
		if(!om_check_get(named_checks[name], src))
			error("check [name]: malformed spec")

// ---------------------------------------------------------------- relations

/datum/om/registry/proc/build_relations()
	for(var/path in subtypesof(/datum/om/relation))
		var/datum/om/relation/R = new path
		if(om_is_abstract(R) || (R.registry_skip && !include_skipped))
			continue
		relations += R
		R.id = length(relations)
		relation_by_type[path] = R
		for(var/inc in R.include)
			for(var/datum/om/bundle/B as anything in expand(inc, list()))
				R.contributes = om_merge_assoc(R.contributes, B.contributes)
				R.source_contributes = om_merge_assoc(R.source_contributes, B.source_contributes)
				R.grants_target = om_merge_assoc(R.grants_target, B.grants_target)
				R.grants_occupant = om_merge_assoc(R.grants_occupant, B.grants_occupant)
		// Two loops, not `a | b`: in DM `list | null` appends null as an element.
		for(var/list/table in list(R.contributes, R.source_contributes))
			for(var/id in table)
				if(!effect_by_id[id])
					error("relation [path]: contributes unknown effect [id]")
		for(var/list/table in list(R.grants_target, R.grants_occupant))
			for(var/kind in table)
				if(!effect_by_id[kind])
					error("relation [path]: unknown grant kind [kind]")
		if(R.active_if)
			R.compiled_active_if = om_check_get(R.active_if, src)
			if(!R.compiled_active_if)
				error("relation [path]: malformed active_if")

/// Returns a new list: a's entries, then b's (b wins). Neither is modified.
/proc/om_merge_assoc(list/a, list/b)
	if(!length(b))
		return a
	. = a ? a.Copy() : list()
	for(var/key in b)
		.[key] = b[key]

// ---------------------------------------------------------------- events

/datum/om/registry/proc/build_events()
	for(var/path in subtypesof(/datum/om/event))
		event_types += path
		event_idx[path] = length(event_types)

// ---------------------------------------------------------------- behaviours

/datum/om/registry/proc/build_behaviours()
	var/list/pending = list()
	var/static/list/tick_keys = list("every", "clock", "lane", "max_interval", "max_dt", "relevance", "order_after", "requires", "step_interval", "max_catchup")
	for(var/path in subtypesof(/datum/om/behaviour))
		if(ispath(path, /datum/om/behaviour/inline))
			continue
		var/datum/om/behaviour/B = new path
		if(om_is_abstract(B) || (B.registry_skip && !include_skipped))
			continue
		if(!B.name)
			B.name = "[path]"
		pending += B
		behaviour_by_type[path] = B
	expiry_behaviour = behaviour_by_type[/datum/om/behaviour/internal/expiry]
	rate_behaviour = behaviour_by_type[/datum/om/behaviour/internal/rates]
	task_behaviour = behaviour_by_type[/datum/om/behaviour/internal/tasks]
	ui_behaviour = behaviour_by_type[/datum/om/behaviour/internal/ui_push]
	edge_behaviour = behaviour_by_type[/datum/om/behaviour/internal/edge_refresh]
	// Inline behaviours from table rows.
	for(var/datum/om/bundle/bundle as anything in bundles)
		bundle.compiled_behaviours = list()
		for(var/proc_path in bundle.reacts)
			var/mask = bundle.reacts[proc_path]
			if(!isnum(mask) || !mask)
				error("[bundle.type] reacts: [proc_path] needs a non-zero channel mask")
				continue
			var/datum/om/behaviour/inline/B = new
			B.mode = "react"
			B.call_path = proc_path
			B.wake_on = mask
			B.name = "[bundle.type]:[proc_path]"
			pending += B
			bundle.compiled_behaviours += B
		for(var/proc_path in bundle.ticks)
			var/list/row = bundle.ticks[proc_path]
			if(!islist(row))
				error("[bundle.type] ticks: [proc_path] row must be a list")
				continue
			var/bad = FALSE
			for(var/key in row)
				if(!(key in tick_keys))
					error("[bundle.type] ticks: [proc_path] unknown key [key]")
					bad = TRUE
			if(!isnum(row["every"]) || row["every"] <= 0)
				error("[bundle.type] ticks: [proc_path] needs every > 0")
				bad = TRUE
			if(bad)
				continue
			var/datum/om/behaviour/inline/B = new
			B.mode = "tick"
			B.call_path = proc_path
			B.every = row["every"]
			B.clock = row["clock"]
			B.lane = row["lane"] || LANE_SIMULATION
			B.max_interval = row["max_interval"] || 0
			B.max_dt = row["max_dt"] || 0
			B.relevance = row["relevance"]
			B.order_after = row["order_after"]
			B.requires = row["requires"]
			B.name = "[bundle.type]:[proc_path]"
			pending += B
			bundle.compiled_behaviours += B
		for(var/event_path in bundle.events)
			if(!ispath(event_path, /datum/om/event))
				error("[bundle.type] events: [event_path] is not an event type")
				continue
			var/datum/om/behaviour/inline/B = new
			B.mode = "event"
			B.call_path = bundle.events[event_path]
			B.handles = list(event_path)
			B.name = "[bundle.type]:[event_path]"
			pending += B
			bundle.compiled_behaviours += B
		for(var/path in bundle.behaviours)
			if(!behaviour_by_type[path])
				error("[bundle.type] behaviours: unknown behaviour [path]")
	for(var/datum/om/behaviour/B as anything in pending)
		compile_behaviour(B)
	behaviours = om_topo_order(pending, src)
	for(var/i in 1 to length(behaviours))
		var/datum/om/behaviour/B = behaviours[i]
		B.id = i

/datum/om/registry/proc/compile_behaviour(datum/om/behaviour/B)
	if(B.clock)
		var/datum/om/clock_def/C = clock_by_id[B.clock]
		if(!C)
			error("[B.name]: unknown clock [B.clock]")
		else
			B.clock_idx = C.idx
	if(!(B.lane in 1 to OM_LANE_COUNT))
		error("[B.name]: bad lane [B.lane]")
		B.lane = LANE_SIMULATION
	if(B.wake_if)
		B.compiled_wake_if = om_check_get(B.wake_if, src)
		if(!B.compiled_wake_if)
			error("[B.name]: malformed wake_if")
	B.requires_mask = 0
	if(B.requires)
		B.compiled_requires = list()
		for(var/spec in om_spec_list(B.requires))
			var/datum/om/check/C = om_check_get(spec, src)
			if(!C)
				error("[B.name]: malformed requires entry")
				continue
			B.compiled_requires += C
			B.requires_mask |= C.depends_on
	B.compiled_related = om_compile_related(B.wake_on_related, src, B.name)
	if(!length(B.compiled_related))
		B.compiled_related = null
	for(var/list/entry as anything in B.compiled_related)
		var/list/path = entry[1]
		if(length(path) == 1)
			B.related_added_mask |= entry[2] & (CHANGE_RELATION_ADDED | CHANGE_RELATION_REMOVED)
	B.interest = B.wake_on | B.requires_mask | B.related_added_mask
	var/list/intervals = list(B.every, B.every, B.every, B.every)
	if(B.relevance)
		if(length(B.relevance) != 4)
			error("[B.name]: relevance needs 4 entries (NONE, NEAR, VISIBLE, WATCHED)")
		else
			for(var/i in 1 to 4)
				if(!isnull(B.relevance[i]))
					intervals[i] = B.relevance[i]
	B.compiled_intervals = intervals
	B.compiled_max_interval = B.max_interval || (max(intervals) * 4)
	if(B.max_interval && B.every && B.max_interval < B.every)
		error("[B.name]: max_interval below every")
	for(var/path in B.order_after)
		if(!behaviour_by_type[path])
			error("[B.name]: order_after names unknown behaviour [path]")
	for(var/path in B.handles)
		if(!ispath(path, /datum/om/event))
			error("[B.name]: handles [path], not an event type")

/// A spec list may be a single spec (typepath, name, combinator) or a list of specs.
/proc/om_spec_list(spec)
	if(!islist(spec))
		return list(spec)
	var/list/L = spec
	if(length(L) && istext(L[1]) && (L[1] in list("all", "any", "not")))
		return list(spec)
	// A single parameterised spec list(path = arg).
	if(length(L) == 1 && ispath(L[1]) && !isnull(L[L[1]]))
		return list(spec)
	return L

/// wake_on_related / related_inputs: relation type = mask, or list(rel, rel..., mask) entries.
/proc/om_compile_related(list/table, datum/om/registry/reg, owner_name)
	. = list()
	for(var/key in table)
		var/list/path = list()
		var/mask
		if(islist(key))
			var/list/L = key
			if(length(L) < 2 || !isnum(L[length(L)]))
				reg.error("[owner_name]: related entry must be list(relation..., mask)")
				continue
			for(var/i in 1 to length(L) - 1)
				path += L[i]
			mask = L[length(L)]
		else
			path += key
			mask = table[key]
		var/list/ids = list()
		var/ok = TRUE
		for(var/rel_path in path)
			var/datum/om/relation/R = reg.relation_by_type[rel_path]
			if(!R)
				reg.error("[owner_name]: unknown relation [rel_path]")
				ok = FALSE
				break
			ids += R.id
		if(!ok)
			continue
		if(!isnum(mask) || !mask)
			reg.error("[owner_name]: related entry for [rel_path_text(path)] needs a mask")
			continue
		. += list(list(ids, mask))

/proc/rel_path_text(list/path)
	return jointext(path, ">")

/// Kahn's algorithm over order_after, deterministic by name. Cycles are boot
/// errors. Producer -> consumer edges (produces & wake_on) are added where
/// they don't create a cycle.
/proc/om_topo_order(list/nodes, datum/om/registry/reg)
	var/n = length(nodes)
	var/list/index_of = list()
	var/list/sorted_nodes = sortTim(nodes.Copy(), GLOBAL_PROC_REF(cmp_om_behaviour_name))
	for(var/i in 1 to n)
		var/datum/om/behaviour/B = sorted_nodes[i]
		index_of[B] = i
	var/list/succ = new /list(n)
	for(var/i in 1 to n)
		succ[i] = list()
	for(var/i in 1 to n)
		var/datum/om/behaviour/B = sorted_nodes[i]
		for(var/path in B.order_after)
			var/datum/om/behaviour/A = reg.behaviour_by_type[path]
			if(A && index_of[A])
				succ[index_of[A]] |= i
	var/list/order = om_kahn(succ, n)
	if(length(order) < n)
		var/list/stuck = list()
		for(var/i in 1 to n)
			if(!(i in order))
				var/datum/om/behaviour/B = sorted_nodes[i]
				stuck += B.name
				order += i
		reg.error("behaviour order_after cycle among: [jointext(stuck, ", ")]")
	else
		// Soft producer -> consumer edges.
		for(var/i in 1 to n)
			var/datum/om/behaviour/P = sorted_nodes[i]
			if(!P.produces)
				continue
			for(var/j in 1 to n)
				if(i == j)
					continue
				var/datum/om/behaviour/C = sorted_nodes[j]
				if(!(C.wake_on & P.produces) || (j in succ[i]))
					continue
				if(om_reaches(succ, j, i))
					continue
				succ[i] |= j
		order = om_kahn(succ, n)
	. = list()
	for(var/i in order)
		. += sorted_nodes[i]

/proc/om_kahn(list/succ, n)
	var/list/indeg = new /list(n)
	for(var/i in 1 to n)
		indeg[i] = 0
	for(var/i in 1 to n)
		for(var/j in succ[i])
			indeg[j]++
	var/list/ready = list()
	for(var/i in 1 to n)
		if(!indeg[i])
			ready += i
	. = list()
	while(length(ready))
		var/i = ready[1]
		ready.Cut(1, 2)
		. += i
		for(var/j in succ[i])
			indeg[j]--
			if(!indeg[j])
				// Keep deterministic: insert in index order.
				var/pos = 1
				while(pos <= length(ready) && ready[pos] < j)
					pos++
				ready.Insert(pos, j)

/proc/om_reaches(list/succ, start, goal)
	var/list/seen = list()
	var/list/stack = list(start)
	while(length(stack))
		var/i = stack[length(stack)]
		stack.len--
		if(i == goal)
			return TRUE
		if(seen["[i]"])
			continue
		seen["[i]"] = TRUE
		for(var/j in succ[i])
			stack += j
	return FALSE

/proc/cmp_om_behaviour_name(datum/om/behaviour/a, datum/om/behaviour/b)
	return sorttext(b.name, a.name)

// ---------------------------------------------------------------- derived

/datum/om/registry/proc/build_derived()
	for(var/path in subtypesof(/datum/om/derived))
		var/datum/om/derived/D = new path
		if(om_is_abstract(D) || (D.registry_skip && !include_skipped))
			continue
		if(!D.name)
			D.name = "[path]"
		add_derived(D, "[path]")
	for(var/datum/om/bundle/B as anything in bundles)
		for(var/row in B.derived)
			var/datum/om/derived/D = parse_derived_row(row, B)
			if(D)
				add_derived(D, "[B.type]")
	for(var/datum/om/derived/D as anything in derived)
		compile_derived(D)
	order_derived()

/datum/om/registry/proc/add_derived(datum/om/derived/D, where)
	if(derived_by_name[D.name])
		error("derived [D.name] defined twice (second in [where])")
		return
	derived += D
	D.idx = length(derived)
	derived_by_name[D.name] = D
	if(D.type != /datum/om/derived)
		derived_by_name[D.type] = D

/datum/om/registry/proc/parse_derived_row(row, datum/om/bundle/B)
	if(!islist(row))
		error("[B.type] derived: row must be a DERIVE*() list")
		return null
	var/list/L = row
	var/static/list/allowed = list("derive", "name", "expr", "channel", "over", "reader", "inputs", "derived_inputs", "member_inputs", "max_age", "related_inputs")
	for(var/key in L)
		if(!istext(key) || !(key in allowed))
			error("[B.type] derived: unknown key [key]")
			return null
	var/kind = L["derive"]
	if(!istext(L["name"]))
		error("[B.type] derived: row needs a name")
		return null
	var/datum/om/derived/D = new /datum/om/derived
	D.name = L["name"]
	D.channel = L["channel"] || 0
	D.inputs = L["inputs"] || 0
	D.derived_inputs = L["derived_inputs"]
	D.member_inputs = L["member_inputs"] || 0
	D.max_age = L["max_age"] || 0
	D.related_inputs = L["related_inputs"]
	switch(kind)
		if("check")
			D.expr = L["expr"]
			if(isnull(D.expr))
				error("[B.type] derived [D.name]: DERIVE needs a check expression")
				return null
		if("sum")
			D.aggregate = AGG_SUM
		if("count")
			D.aggregate = AGG_COUNT
		if("any")
			D.aggregate = AGG_ANY
		if("all")
			D.aggregate = AGG_ALL
		if("min")
			D.aggregate = AGG_MIN
		if("max")
			D.aggregate = AGG_MAX
		else
			error("[B.type] derived [D.name]: unknown kind [kind]")
			return null
	if(D.aggregate)
		D.over = L["over"]
		D.reader = L["reader"]
		if(isnull(D.over))
			error("[B.type] derived [D.name]: aggregate needs `over`")
			return null
		if(D.aggregate != AGG_COUNT && isnull(D.reader))
			error("[B.type] derived [D.name]: aggregate needs a reader")
			return null
	return D

/datum/om/registry/proc/compile_derived(datum/om/derived/D)
	if(D.expr)
		D.compiled_expr = om_check_get(D.expr, src)
		if(!D.compiled_expr)
			error("derived [D.name]: malformed check expression")
		else
			D.inputs |= D.compiled_expr.depends_on
	if(D.aggregate)
		if(islist(D.over) && length(D.over) == 2 && D.over[1] == "slot")
			D.over_slot = D.over[2]
			D.inputs |= CHANGE_CONTENTS
		else
			var/datum/om/relation/R = relation_by_type[D.over]
			if(!R)
				error("derived [D.name]: over names unknown relation [D.over]")
			else
				D.over_rel_id = R.id
		if(islist(D.reader) && D.reader[1] == "derived")
			var/datum/om/derived/src_d = derived_by_name[D.reader[2]]
			if(!src_d)
				error("derived [D.name]: reader names unknown derived [D.reader[2]]")
			else if(!src_d.channel)
				error("derived [D.name]: reader derived [src_d.name] has no channel")
			else
				D.member_inputs |= src_d.channel
		else if(islist(D.reader) && D.reader[1] == "effect")
			var/datum/om/effect/eff = effect_by_id[D.reader[2]]
			if(!eff)
				error("derived [D.name]: reader names unknown effect [D.reader[2]]")
			else
				D.member_inputs |= eff.channel | CHANGE_EFFECTS
	for(var/name in D.derived_inputs)
		var/datum/om/derived/src_d = derived_by_name[name]
		if(!src_d)
			error("derived [D.name]: input names unknown derived [name]")
		else if(!src_d.channel)
			error("derived [D.name]: input derived [name] has no channel")
		else
			D.inputs |= src_d.channel
	D.compiled_related = om_compile_related(D.related_inputs, src, "derived [D.name]")
	if(!length(D.compiled_related))
		D.compiled_related = null

/// Orders derived values so inputs come first; a cycle is a boot error.
/datum/om/registry/proc/order_derived()
	var/n = length(derived)
	var/list/succ = new /list(n)
	for(var/i in 1 to n)
		succ[i] = list()
	for(var/datum/om/derived/D as anything in derived)
		for(var/name in D.derived_inputs)
			var/datum/om/derived/src_d = derived_by_name[name]
			if(src_d)
				succ[src_d.idx] |= D.idx
		if(islist(D.reader) && D.reader[1] == "derived")
			var/datum/om/derived/src_d = derived_by_name[D.reader[2]]
			if(src_d && src_d != D)
				succ[src_d.idx] |= D.idx
	var/list/order = om_kahn(succ, n)
	if(length(order) < n)
		var/list/stuck = list()
		for(var/i in 1 to n)
			if(!(i in order))
				var/datum/om/derived/D = derived[i]
				stuck += D.name
				order += i
		error("derived input cycle among: [jointext(stuck, ", ")]")
	for(var/pos in 1 to length(order))
		var/datum/om/derived/D = derived[order[pos]]
		D.order = pos

/datum/om/registry/proc/derived_def(name_or_type)
	RETURN_TYPE(/datum/om/derived)
	var/datum/om/derived/D = derived_by_name[name_or_type]
	if(!D)
		CRASH("om: unknown derived [name_or_type]")
	return D

// ---------------------------------------------------------------- event tables

/datum/om/registry/proc/build_event_tables()
	var/nb = length(behaviours)
	event_handlers = new /list(length(event_types))
	for(var/e in 1 to length(event_types))
		var/event_path = event_types[e]
		var/list/flags = null
		for(var/datum/om/behaviour/B as anything in behaviours)
			for(var/handled in B.handles)
				if(ispath(event_path, handled))
					if(!flags)
						flags = new /list(nb)
					flags[B.id] = TRUE
					break
		event_handlers[e] = flags

// ---------------------------------------------------------------- tasks and services

/datum/om/registry/proc/build_tasks()
	for(var/path in subtypesof(/datum/om/task_def))
		var/datum/om/task_def/T = new path
		if(om_is_abstract(T) || (T.registry_skip && !include_skipped))
			continue
		add_task(T, "[path]")
		task_by_type[path] = T
	for(var/datum/om/bundle/B as anything in bundles)
		for(var/name in B.tasks)
			var/datum/om/task_def/T = parse_task_row(name, B.tasks[name], B)
			if(T)
				add_task(T, "[B.type]")
	for(var/datum/om/task_def/T as anything in tasks)
		T.compile(src)

/datum/om/registry/proc/add_task(datum/om/task_def/T, where)
	if(!T.name)
		T.name = "[T.type]"
	if(task_by_name[T.name])
		error("task [T.name] defined twice (second in [where])")
		return
	tasks += T
	task_by_name[T.name] = T

/datum/om/registry/proc/parse_task_row(name, row, datum/om/bundle/B)
	if(!islist(row))
		error("[B.type] tasks: [name] row must be a list")
		return null
	var/static/list/allowed = list("duration", "claims", "requires", "interrupted_by", "interrupt_on", "on_complete", "on_cancel")
	var/list/L = row
	for(var/key in L)
		if(!(key in allowed))
			error("[B.type] tasks: [name] unknown key [key]")
			return null
	if(isnull(L["duration"]))
		error("[B.type] tasks: [name] needs a duration")
		return null
	var/datum/om/task_def/T = new /datum/om/task_def
	T.name = name
	T.duration = L["duration"]
	T.claims = L["claims"]
	T.requires = L["requires"]
	T.interrupted_by = L["interrupted_by"]
	T.interrupt_on = L["interrupt_on"] || 0
	T.complete_proc = L["on_complete"]
	T.cancel_proc = L["on_cancel"]
	return T

/datum/om/registry/proc/build_services()
	for(var/path in subtypesof(/datum/om/service))
		var/datum/om/service/S = new path
		if(om_is_abstract(S) || (S.registry_skip && !include_skipped))
			continue
		services += S
		S.id = length(services)

// ---------------------------------------------------------------- per entity type

/// The compiled table for `path`: every decl whose `of` is an ancestor,
/// general first, with includes expanded. Built once per concrete type.
/datum/om/registry/proc/type_table(path)
	RETURN_TYPE(/datum/om/type_table)
	var/datum/om/type_table/T = type_tables[path]
	if(T)
		return T
	T = new
	type_tables[path] = T
	var/list/applicable = list()
	for(var/datum/om/decl/D as anything in decls)
		if(ispath(path, D.of))
			applicable += D
	applicable = sortTim(applicable, GLOBAL_PROC_REF(cmp_om_decl_depth))
	var/list/seen = list()
	var/list/behaviour_set = list()
	for(var/datum/om/decl/D as anything in applicable)
		for(var/datum/om/bundle/B as anything in expand(D.type, list()))
			if(seen[B])
				continue
			seen[B] = TRUE
			for(var/datum/om/behaviour/inline_b as anything in B.compiled_behaviours)
				behaviour_set |= inline_b
			for(var/bpath in B.behaviours)
				var/datum/om/behaviour/full = behaviour_by_type[bpath]
				if(full)
					behaviour_set |= full
			for(var/name in B.tasks)
				T.tasks[name] = task_by_name[name]
			for(var/row in B.ui)
				T.ui += list(row)
			for(var/id in B.self_effects)
				T.self_effects += list(id, B.self_effects[id])
			for(var/kind in B.self_grants)
				var/ids = B.self_grants[kind]
				for(var/id in (islist(ids) ? ids : list(ids)))
					T.self_grants += list(kind, id)
	T.behaviours = sortTim(behaviour_set, GLOBAL_PROC_REF(cmp_om_behaviour_id))
	for(var/datum/om/service/S as anything in services)
		for(var/observed in S.wake_on_any)
			if(ispath(path, observed))
				T.service_mask |= S.wake_on_any[observed]
				LAZYOR(T.services, S)
	return T

/proc/cmp_om_decl_depth(datum/om/decl/a, datum/om/decl/b)
	return length("[a.of]") - length("[b.of]")

/proc/cmp_om_behaviour_id(datum/om/behaviour/a, datum/om/behaviour/b)
	return a.id - b.id

/datum/om/registry/proc/behaviour(path_or_def)
	RETURN_TYPE(/datum/om/behaviour)
	if(istype(path_or_def, /datum/om/behaviour))
		return path_or_def
	var/datum/om/behaviour/B = behaviour_by_type[path_or_def]
	if(!B)
		CRASH("om: unknown behaviour [path_or_def]")
	return B

/datum/om/registry/proc/relation(path)
	RETURN_TYPE(/datum/om/relation)
	var/datum/om/relation/R = relation_by_type[path]
	if(!R)
		CRASH("om: unknown relation [path]")
	return R

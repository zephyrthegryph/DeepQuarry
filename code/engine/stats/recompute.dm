// The recompute, the settle rule and the marked drain (doc/rewrite/final_api.html, section 5 and section 7 "What is consistent when", "The execution
// model", "What a condition costs"; section 19 "E3, stats").
//
// A stat's effective value lives in a plain var that only this file writes. It recomputes eagerly, inline, when a contribution, a hold, a gating
// condition or a read it depends on changes, before the writer's next line:
//
//   inline   the stats of the written entity, and of the entity at the end of a single-valued relation edge (a contributes_to target; a one-to-one
//            link; an owned child read by its one owner), recompute in rank order, so a read on the next line is current with no drain;
//   marked   every other stat the write reaches (through a collection or membership edge: an area's machines, a system's members; through a
//            SYSTEM_ACCESSOR; two or more edges away) is flagged and waits in the marked queue. stat_drain_marked() recomputes it in rank order,
//            each evaluation charged to the lane's budget, and what does not finish resumes at the next marked drain (E6 runs it at the start of
//            phases D, P and R). A marked stat that changes marks its own readers, and the same drain loop recomputes them.
//
// The build derives which is which from the relation declarations (contributes.dm, stat_hop_settle()); no author declares it.

#define SETTLE_MAX_QUEUE 256

GLOBAL_VAR_INIT(stat_settle_depth, 0)
GLOBAL_LIST_EMPTY(stat_marked) // list(entity, stat def, contribution or null) rows waiting for a marked drain
GLOBAL_LIST_EMPTY(stat_hop_index) // remote var name -> list(list(reader type, /datum/stat_hop))
GLOBAL_LIST_EMPTY(stat_sys_index) // "system.var" -> assoc: entity -> TRUE (readers through a SYSTEM_ACCESSOR)
GLOBAL_VAR(stat_writing) // the stat var the engine is publishing: state_changed() does not feed it back to the stat layer
GLOBAL_VAR(stat_force_settle) // SETTLE_INLINE / SETTLE_MARKED: the apc_flip_50 spike forces every hop one way; null in play
GLOBAL_VAR_INIT(stat_spills, 0)
GLOBAL_VAR_INIT(stat_tick_spent, 0) // what this kernel pass's marked drains have charged to the lane so far
GLOBAL_VAR_INIT(stat_evals, 0)

/// Calls holder proc `proc_name` (a contribution's or a formula's handler) with the shared evaluation context.
/proc/stat_call(datum/holder, proc_name)
	// One context for every contribution handler: a handler may not keep it, and a recompute inside a handler puts the outer holder back.
	var/static/datum/act/eval/ctx = new
	var/datum/outer = ctx.holder
	ctx.holder = holder
	. = call(holder, proc_name)(ctx)
	ctx.holder = outer

/// The value of stat `stat_id` on E: its var, or (a virtual stat) what the record holds, or what it composes to now.
/proc/stat_value(datum/E, stat_id)
	READS_FROM(E)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def || !isdatum(E))
		return null
	var/datum/stat_type_info/I = stat_type_of(E)
	if(I ? I.has_var[def.skey] : (def.name in E.vars))
		return E.vars[def.name]
	var/datum/stat_record/rec = E.rx?.stats
	if(rec?.virtual && (def.skey in rec.virtual))
		return rec.virtual[def.skey]
	return stat_compute(E, def, I || null, rec)

/// Writes a stat's settled value where it lives.
/proc/stat_store(datum/E, datum/stat_def/def, value, datum/stat_type_info/I)
	if(I ? I.has_var[def.skey] : (def.name in E.vars))
		E.vars[def.name] = value // ALLOW(api): the stat layer is the one writer of a stat's var
	else
		var/datum/stat_record/rec = stat_record_of(E)
		if(!rec.virtual)
			rec.virtual = list()
		rec.virtual[def.skey] = value

// ---- computing ----

/**
 * The composed value of `def` on E now: the stat's base, the type's constant (the var's initial value, or the map's edit of it) as a contribution at
 * default priority, the type's contributes() entries whose gates hold, and the holds, combined by the rule. A status reads 0 while its immunity holds.
 */
/proc/stat_compute(datum/E, datum/stat_def/def, datum/stat_type_info/I, datum/stat_record/rec)
	var/value
	var/override_set = FALSE
	var/override_value = null
	if(def.is_formula)
		value = isnull(def.formula) ? def.base : stat_call(E, def.formula)
	else if(I && def.fast && !rec?.holds)
		value = stat_compute_fast(E, def, I, rec)
	else
		var/list/rows = list()
		var/has_var = I ? I.has_var[def.skey] : (def.name in E.vars)
		// The type's own constant: a var set in the type's definition is a type-level contribution at default priority.
		if(has_var)
			var/constant = I ? I.consts[def.skey] : initial(E.vars[def.name])
			if(rec?.constants && (def.skey in rec.constants))
				constant = rec.constants[def.skey]
			if(!isnull(constant))
				rows.Add(stat_boolean_normal(def, constant), PRIORITY_DEFAULT, -1000000)
		if(I)
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(!stat_contrib_active(E, C))
					continue
				rows.Add(stat_contrib_value(E, def, C), C.priority, C.serial)
		var/override_priority = null
		var/override_serial = 0
		for(var/list/row as anything in rec?.holds)
			if(row[H_STAT] != def.id)
				continue
			var/row_value = row[H_VALUE]
			var/list/spec = row[H_SPEC]
			if(spec)
				var/datum/stat_contrib/dyn = spec[1]
				if(!stat_contrib_active(E, dyn))
					continue
				row_value = stat_contrib_value(E, def, dyn)
			else if(def.boolean)
				row_value = !!row_value
			if(row[H_FLAGS] & HF_OVERRIDE)
				if(isnull(override_priority) || row[H_PRIORITY] > override_priority || (row[H_PRIORITY] == override_priority && row[H_SERIAL] >= override_serial))
					override_priority = row[H_PRIORITY]
					override_serial = row[H_SERIAL]
					override_set = TRUE
					override_value = row_value
				continue
			rows.Add(row_value, row[H_PRIORITY], row[H_SERIAL])
		value = stat_combine(def, rows)
		if(override_set)
			value = override_value
	if(def.units && E)
		if(stat_status_immune(E, def))
			value = 0
	return value

/// stat_compute() for the rules whose result needs no ordering (ALL, ANY, SUM) on an entity with no holds: no row list, no combine call.
/proc/stat_compute_fast(datum/E, datum/stat_def/def, datum/stat_type_info/I, datum/stat_record/rec)
	var/rule = def.rule
	var/has_const = FALSE
	var/constant = null
	if(I.has_var[def.skey])
		constant = I.consts[def.skey]
		var/list/edited = rec?.constants
		if(edited && (def.skey in edited))
			constant = edited[def.skey]
		has_const = !isnull(constant)
	switch(rule)
		if(STAT_RULE_ALL)
			if(has_const && !constant)
				return FALSE
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C) && !stat_contrib_value(E, def, C))
					return FALSE
			return TRUE
		if(STAT_RULE_ANY)
			if(has_const && constant)
				return TRUE
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C) && stat_contrib_value(E, def, C))
					return TRUE
			return FALSE
		else
			. = has_const ? constant : 0
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C))
					. += stat_contrib_value(E, def, C)

/// A boolean stat's contribution as TRUE or FALSE; any other value as it is.
/proc/stat_boolean_normal(datum/stat_def/def, value)
	if(def.boolean)
		return value ? TRUE : FALSE
	return value

/// TRUE when every when() block around a contribution holds on E (a contribution gated by a condition is an input of the stat).
/proc/stat_contrib_active(datum/E, datum/stat_contrib/C)
	for(var/datum/entry/W as anything in C.whens)
		if(!condition_holds(E, W.args["cond"]))
			return FALSE
	return TRUE

/// What one contribution contributes: its constant, a var read, another stat, a capability key, a holder proc, or a condition tree.
/proc/stat_contrib_value(datum/E, datum/stat_def/def, datum/stat_contrib/C)
	var/value
	switch(C.value_kind)
		if(CV_CONST)
			value = C.value_spec
		if(CV_VAR)
			value = E.vars[C.value_spec]
		if(CV_STAT)
			value = stat_value(E, C.value_spec)
		if(CV_CAPKEY)
			value = cap_key_get(E, C.value_spec)
		if(CV_PROC)
			value = stat_call(E, C.value_spec)
		if(CV_TREE)
			value = condition_holds(E, C.value_spec)
	return stat_boolean_normal(def, value)

/// Recomputes one stat on E and writes it when it changed. TRUE when it changed.
/proc/stat_recompute(datum/E, datum/stat_def/def, silent = FALSE, datum/stat_type_info/I = null)
	if(isnull(I))
		I = stat_type_of(E)
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.inited)
		rec = stat_ensure_inited(E, I || null)
	var/has_var = I ? I.has_var[def.skey] : (def.name in E.vars)
	var/old = has_var ? E.vars[def.name] : stat_value_now(E, def, FALSE)
	var/new_value = stat_compute(E, def, I || null, rec)
	GLOB.stat_evals++
	if(old == new_value && !islist(new_value))
		return FALSE
	if(islist(new_value) && stat_values_equal(old, new_value))
		return FALSE
	if(has_var)
		E.vars[def.name] = new_value // ALLOW(api): the stat layer is the one writer of a stat's var
	else
		stat_store(E, def, new_value, I || null)
	if(silent)
		return TRUE
#if defined(UNIT_TESTS)
	if(!isnull(GLOB.test_driver.recording))
		TEST_REC_DELTA(E, def.name, old, new_value)
#endif
	if(has_var)
		GLOB.stat_writing = def.name
		state_changed(E, 0, def.name)
		GLOB.stat_writing = null
	else
		op_changed(E)
		if(READERS(E, def.stat_key))
			publish_change(E, def.stat_key)
	// A status started or ended: its holder's hooks and presentation follow at once (code/library/mob/statuses.dm).
	if(def.units && ((isnum(old) && old > 0) != (isnum(new_value) && new_value > 0)))
		E.stat_status_changed(def.id, isnum(new_value) && new_value > 0)
	// Relevance moved: the sequences sweeping E and the OM cadences that read it follow (code/datums/om/contribution.dm).
	else if(def.id == STAT_RELEVANCE)
		relevance_changed(E, new_value || RELEVANCE_NONE)
	else if(def.id == STAT_SUSPENDED)
		suspended_changed(E)
	else if(def.id == STAT_CLOCK_RATE_BIO)
		bio_clock_rate_changed(E)
	return TRUE

/// The value a stat holds now, without computing it.
/proc/stat_value_now(datum/E, datum/stat_def/def, has_var)
	if(isnull(has_var))
		has_var = (def.name in E.vars)
	if(has_var)
		return E.vars[def.name]
	var/datum/stat_record/rec = E.rx?.stats
	if(rec?.virtual && (def.skey in rec.virtual))
		return rec.virtual[def.skey]
	return def.base

// ---- init ----

/// Captures a map's edit of each stat var as the stat's constant. Only the engine writes a stat var, so until the first recompute the var still holds
/// what the map set. Runs before an entity's first computation, from init or from the first hold.
/proc/stat_ensure_inited(datum/E, datum/stat_type_info/I)
	var/datum/stat_record/rec = stat_record_of(E)
	if(rec.inited)
		return rec
	rec.inited = TRUE
	if(!I)
		return rec
	for(var/datum/stat_def/def as anything in I.defs)
		if(I.has_var[def.skey])
			var/current = E.vars[def.name]
			if(!stat_values_equal(current, initial(E.vars[def.name])))
				if(!rec.constants)
					rec.constants = list()
				rec.constants[def.skey] = current
	return rec

/// The engine's work on an entity's stats when it initializes (from engine_holder_init): capture the map's edits of stat vars, then compute every
/// stat that has a contribution, a formula or a status, in rank order, silently (nothing publishes and no hook runs until map load completes).
/proc/stat_holder_init(datum/E, mapload)
	var/datum/stat_type_info/I = stat_type_of(E)
	if(!I || !I.init_needed)
		return
	var/datum/stat_record/rec = stat_ensure_inited(E, I)
	var/list/todo = list()
	for(var/datum/stat_def/def as anything in I.defs)
		if(length(I.contribs[def.skey]) || def.rule == STAT_RULE_FORMULA || rec.constants?[def.skey])
			todo += def
	todo = stat_sort_by_rank(I, todo)
	for(var/datum/stat_def/def as anything in todo)
		stat_recompute(E, def, TRUE)
	for(var/datum/stat_hop/sys as anything in I.hops["sys"])
		var/list/readers = GLOB.stat_sys_index[sys.system]
		if(!readers)
			readers = list()
			GLOB.stat_sys_index[sys.system] = readers
		readers[E] = TRUE
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		stat_ct_update(E, ct)
	for(var/rel_var in I.hop_rels)
		stat_hop_attach(E, rel_var)

/// The defs sorted by rank, lowest first (a stable insertion sort: a handful of stats per type).
/proc/stat_sort_by_rank(datum/stat_type_info/I, list/defs)
	var/list/out = list()
	for(var/datum/stat_def/def as anything in defs)
		var/rank = I?.ranks?[def.skey] || 0
		var/at = length(out) + 1
		for(var/i in 1 to length(out))
			var/datum/stat_def/other = out[i]
			if((I?.ranks?[other.skey] || 0) > rank)
				at = i
				break
		out.Insert(at, def)
	return out

// ---- settling: inline ----

/**
 * Recomputes `defs` on E now, then what reads them: the stats of E that read them (in rank order), contributes_to entries (a single-valued edge, so
 * inline on the target), and readers through a relation (inline over a single-valued edge, marked over a collection edge). Bounded: a write inside
 * the chain adds to the same loop and never starts a nested one.
 */
/proc/stat_settle(datum/E, list/defs)
	if(!isdatum(E) || QDELETED(E) || !length(defs))
		return
	var/datum/stat_type_info/I = stat_type_of(E)
	var/list/queue = length(defs) > 1 ? stat_sort_by_rank(I, defs) : defs.Copy()
	stat_settle_queue(E, I, queue, 1)

/// stat_settle() of one stat, the common case: no queue is made unless something on E reads the stat.
/proc/stat_settle_def(datum/E, datum/stat_def/def)
	if(QDELETED(E))
		return
	var/datum/stat_type_info/I = stat_type_of(E)
	if(GLOB.stat_settle_depth > DRAIN_MAX_PASSES)
		declare_report("[RULE_STAT_CYCLE] settle of [E.type] is [GLOB.stat_settle_depth] writes deep: a runtime cycle through relations or contributes_to")
		return
	GLOB.stat_settle_depth++
	if(stat_recompute(E, def, FALSE, I))
		if(I && (I.stat_readers[def.skey] || I.inputs[def.stat_key] || I.inputs[def.name]))
			var/list/queue = list(def)
			stat_changed_dependents(E, def, I, queue)
			stat_settle_queue_run(E, I, queue, 2)
		else
			if(GLOB.stat_hop_index[def.name])
				stat_notify_hops(E, def.name)
			if(length(GLOB.stat_sys_index))
				stat_notify_system(E, def.name)
	GLOB.stat_settle_depth--

/// Runs a settle queue from entry `start` (entries before it are done).
/proc/stat_settle_queue(datum/E, datum/stat_type_info/I, list/queue, start)
	if(GLOB.stat_settle_depth > DRAIN_MAX_PASSES)
		declare_report("[RULE_STAT_CYCLE] settle of [E.type] is [GLOB.stat_settle_depth] writes deep: a runtime cycle through relations or contributes_to")
		return
	GLOB.stat_settle_depth++
	stat_settle_queue_run(E, I, queue, start)
	GLOB.stat_settle_depth--

/proc/stat_settle_queue_run(datum/E, datum/stat_type_info/I, list/queue, start)
	var/i = start
	while(i <= length(queue))
		var/datum/stat_def/def = queue[i]
		i++
		if(length(queue) > SETTLE_MAX_QUEUE)
			declare_report("[RULE_STAT_CYCLE] settle of [E.type] queued more than [SETTLE_MAX_QUEUE] stats: stopping")
			break
		if(!stat_recompute(E, def, FALSE, I))
			continue
		stat_changed_dependents(E, def, I, queue)

/// What a changed stat on E moves: same-entity readers join the queue; contributes_to entries re-evaluate; hop readers settle or are marked.
/proc/stat_changed_dependents(datum/E, datum/stat_def/def, datum/stat_type_info/I, list/queue)
	if(I)
		for(var/reader_id in I.stat_readers[def.skey])
			stat_queue_insert(I, queue, stat_def_of(reader_id))
		for(var/datum/stat_dep/dep as anything in I.inputs[def.stat_key])
			stat_dep_run(E, I, dep, queue)
		for(var/datum/stat_dep/dep as anything in I.inputs[def.name])
			stat_dep_run(E, I, dep, queue)
	if(GLOB.stat_hop_index[def.name])
		stat_notify_hops(E, def.name)
	if(length(GLOB.stat_sys_index))
		stat_notify_system(E, def.name)

/// One dependent of a changed input: a contributes_to entry re-evaluates, a stat joins the settle queue.
/proc/stat_dep_run(datum/E, datum/stat_type_info/I, datum/stat_dep/dep, list/queue)
	if(dep.ct)
		stat_ct_update(E, dep.ct)
	else
		stat_queue_insert(I, queue, stat_def_of(dep.stat_id))

/// Adds `def` to a settle queue in rank order unless it is already there.
/proc/stat_queue_insert(datum/stat_type_info/I, list/queue, datum/stat_def/def)
	if(!def || (def in queue))
		return
	var/rank = I.ranks?[def.skey] || 0
	var/at = length(queue) + 1
	for(var/k in 1 to length(queue))
		var/datum/stat_def/other = queue[k]
		if((I.ranks?[other.skey] || 0) > rank)
			at = k
			break
	queue.Insert(at, def)

/// E's var/stat `key` changed: recompute what reads it on E, then tell the entities that read it through a relation or a system.
/proc/stat_inputs_changed(datum/E, key)
	var/datum/stat_type_info/I = stat_type_of(E)
	if(I)
		var/list/deps = I.inputs[key]
		if(deps)
			var/list/defs = list()
			for(var/datum/stat_dep/dep as anything in deps)
				if(dep.ct)
					stat_ct_update(E, dep.ct)
				else
					var/datum/stat_def/def = stat_def_of(dep.stat_id)
					if(def && !(def in defs))
						defs += def
			if(length(defs))
				stat_settle(E, defs)
	stat_notify_hops(E, key)
	if(length(GLOB.stat_sys_index))
		stat_notify_system(E, key)

/// A write to `key` on E reaches the entities whose stats read E.key through a relation (a hop), however many relations away. A single-valued edge
/// settles the reader at once; a collection edge, or more than one hop, marks it for the next marked drain.
/proc/stat_notify_hops(datum/E, key)
	var/list/entries = GLOB.stat_hop_index[key]
	if(!entries)
		return
	for(var/list/entry as anything in entries)
		var/reader_type = entry[1]
		var/datum/stat_hop/hop = entry[2]
		var/list/frontier
		if(hop.fast)
			var/list/direct = E.rx?.stats?.hop_in?[hop.rel_var]
			frontier = direct ? direct.Copy() : list()
		else
			frontier = list(E)
		for(var/i in (hop.fast ? 0 : length(hop.path)) to 1 step -1)
			var/segment = hop.path[i]
			var/list/next_frontier = list()
			for(var/datum/at as anything in frontier)
				for(var/list/pair as anything in rel_sources(at))
					var/datum/source = pair[1]
					if(pair[2] == segment && !QDELETED(source))
						next_frontier |= list(source)
			frontier = next_frontier
			if(!length(frontier))
				break
		var/settle = GLOB.stat_force_settle || hop.settle
		for(var/datum/reader as anything in frontier)
			if(!istype(reader, reader_type))
				continue
			if(hop.ct)
				if(settle == SETTLE_INLINE)
					stat_ct_update(reader, hop.ct)
				else
					stat_mark_ct(reader, hop.ct)
				continue
			var/datum/stat_def/def = GLOB.stat_defs[hop.skey]
			if(!def)
				continue
			if(settle == SETTLE_INLINE)
				stat_settle_def(reader, def)
			else
				stat_mark(reader, def)

/// The singleton a SYSTEM_ACCESSOR's system name stands for: a GLOB `<name>_service` (a lazy system) or the `SS<name>` real global that
/// SYSTEM_DEF declares. Indexing a vars list by a name it does not hold is a runtime, so each is looked up only when it exists.
/proc/stat_system_singleton(system_name)
	var/service_key = "[system_name]_service"
	if(service_key in GLOB.vars)
		var/datum/service = GLOB.vars[service_key]
		if(service)
			return service
	var/ss_key = "SS[system_name]"
	if(ss_key in global.vars)
		return global.vars[ss_key]
	return null

/// A system's tracked var changed: the readers registered through a SYSTEM_ACCESSOR are marked (an accessor edge is never inline).
/proc/stat_notify_system(datum/E, key)
	for(var/system_key in GLOB.stat_sys_index)
		var/dot = findtext(system_key, ".")
		if(!dot || copytext(system_key, dot + 1) != key)
			continue
		var/system_name = copytext(system_key, 1, dot)
		if(stat_system_singleton(system_name) != E)
			continue
		var/list/readers = GLOB.stat_sys_index[system_key]
		for(var/datum/reader as anything in readers)
			if(QDELETED(reader))
				readers -= reader
				continue
			var/datum/stat_type_info/I = stat_type_of(reader)
			if(!I)
				continue
			for(var/datum/stat_hop/sys as anything in I.hops["sys"])
				if(sys.system != system_key)
					continue
				if(sys.ct)
					stat_mark_ct(reader, sys.ct)
					continue
				var/datum/stat_def/def = GLOB.stat_defs[sys.skey]
				if(def)
					stat_mark(reader, def)

// ---- contributes_to ----

/**
 * Re-evaluates one contributes_to entry of E: what it contributes to the stat of the entity its relation names, now. The row on the target is E's
 * (source E, untimed, so E's deletion releases it); it moves when the relation changes and goes when the gate stops holding.
 */
/proc/stat_ct_update(datum/E, datum/stat_contrib/ct)
	if(QDELETED(E))
		return
	var/datum/stat_record/rec = stat_record_of(E)
	var/ct_key = "[ct.serial]"
	var/datum/old_target = rec.ct_targets?[ct_key]
	var/datum/target = (ct.rel in E.vars) ? E.vars[ct.rel] : null
	if(old_target && old_target != target)
		stat_ct_release(old_target, E, ct)
		if(rec.ct_targets)
			rec.ct_targets -= ct_key
	if(!isdatum(target) || QDELETED(target))
		return
	var/datum/stat_def/def = stat_def_of(ct.stat_id)
	if(!def || !stat_declared_on(target.type, def))
		declare_report("[ct.origin]: [declare_rule(RULE_STAT)] [E.type]: contributes_to([ct.rel], [def ? def.name : ct.stat_id]) names a stat the related [target.type] does not declare")
		return
	if(!stat_contrib_active(E, ct))
		stat_ct_release(target, E, ct)
		return
	var/value = stat_contrib_value(E, def, ct)
	if(stat_rule_is_boolean(def.rule) && ((def.rule == STAT_RULE_ALL && value) || (def.rule == STAT_RULE_ANY && !value)))
		stat_ct_release(target, E, ct) // the neutral direction can never change anything: no row
		return
	if(!rec.ct_targets)
		rec.ct_targets = list()
	rec.ct_targets[ct_key] = target
	stat_row_set(target, def, E, value, ct.priority, "ct:[ct.serial]")

/// Takes E's contributes_to row for `ct` off `target` and settles the stat.
/proc/stat_ct_release(datum/target, datum/E, datum/stat_contrib/ct)
	if(QDELETED(target))
		return
	var/datum/stat_record/trec = target.rx?.stats
	if(!trec?.holds)
		return
	var/list/row = stat_hold_find(trec, ct.stat_id, E, "ct:[ct.serial]")
	if(!row)
		return
	var/datum/stat_def/def = stat_def_of(ct.stat_id)
	stat_hold_remove(target, trec, row)
	stat_settle_def(target, def)

/// Places (or updates) an untimed keyed row without the hold() checks: the contribution engine's own writes. Settles the stat inline.
/proc/stat_row_set(datum/target, datum/stat_def/def, source, value, priority, key)
	var/datum/stat_record/rec = stat_record_of(target)
	var/list/row = stat_hold_find(rec, def.id, source, key)
	if(row)
		if(stat_values_equal(row[H_VALUE], value) && row[H_PRIORITY] == priority)
			return
		row[H_VALUE] = value
		row[H_PRIORITY] = priority
	else
		row = list(def.id, source, value, 0, priority, 0, HOLD_CLOCK_OWN, null, ++GLOB.stat_hold_serial, key, null)
		rec.holds += list(row)
		if(isdatum(source))
			var/datum/stat_record/src_rec = stat_record_of(source)
			LAZYOR(src_rec.held_on, target)
	stat_settle_def(target, def)

/// A contributes_to entity's relation var was written: its contribution moves to the new target and leaves the old one.
/proc/stat_relation_changed(datum/E, var_name)
	var/datum/stat_type_info/I = stat_type_of(E)
	if(!I)
		return
	if(I.hop_rels && (var_name in I.hop_rels))
		stat_hop_attach(E, var_name)
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		if(ct.rel == var_name)
			stat_ct_update(E, ct)

// ---- the marked queue ----

/// Flags a stat of an entity for the next marked drain. Nothing is evaluated now: the write that reached it pays one list add.
/proc/stat_mark(datum/E, datum/stat_def/def)
	var/datum/stat_record/rec = stat_record_of(E)
	if(!rec.marked)
		rec.marked = list()
	if(rec.marked[def.skey])
		return
	rec.marked[def.skey] = TRUE
	GLOB.stat_marked += list(list(E, def, null))

/// Flags a contributes_to entry for the next marked drain.
/proc/stat_mark_ct(datum/E, datum/stat_contrib/ct)
	var/datum/stat_record/rec = stat_record_of(E)
	if(!rec.marked)
		rec.marked = list()
	var/mark_key = "ct:[ct.serial]"
	if(rec.marked[mark_key])
		return
	rec.marked[mark_key] = TRUE
	GLOB.stat_marked += list(list(E, null, ct))

/// How many marked evaluations wait.
/proc/stat_marked_count()
	return length(GLOB.stat_marked)

/// The lane's budget for one marked drain, in microseconds of tick time: the test driver's when a test set one, else the default.
/proc/stat_lane_budget(lane)
	var/budget = TEST_LANE_BUDGET(lane)
	return isnull(budget) ? STAT_DRAIN_BUDGET_US : budget

/// Tick time in microseconds (test builds charge TEST_EVAL_COST per evaluation instead of reading the clock).
/proc/stat_clock_us()
	return world.tick_usage * world.tick_lag * 1000

/**
 * The marked drain (the start of phases D, P and R): recomputes the marked stats in rank order under the budget of `lane`. A marked stat that changes
 * marks its readers and the same loop recomputes them, up to DRAIN_MAX_PASSES; an evaluation that does not fit the budget stays queued, the key chain
 * is logged and TEST_REC_SPILL says so. Returns how many evaluations it ran.
 */
/proc/stat_drain_marked(lane = LANE_SIMULATION, fresh = TRUE)
	. = 0
	var/budget = stat_lane_budget(lane)
	var/spent = fresh ? 0 : GLOB.stat_tick_spent
	var/passes = 0
	while(length(GLOB.stat_marked) && passes < DRAIN_MAX_PASSES)
		passes++
		var/list/batch = stat_sort_marked(GLOB.stat_marked)
		GLOB.stat_marked = list()
		for(var/i in 1 to length(batch))
			var/list/row = batch[i]
			var/datum/E = row[1]
			var/datum/stat_def/def = row[2]
			var/datum/stat_contrib/ct = row[3]
			if(QDELETED(E))
				continue
			// The first evaluation of a pass always runs (a budget smaller than one evaluation still makes progress).
			if(spent && spent + STAT_EVAL_CHARGE > budget)
				var/list/rest = batch.Copy(i)
				GLOB.stat_marked = rest + GLOB.stat_marked
				GLOB.stat_spills++
				TEST_REC_SPILL("[lane]:[def ? def.name : "ct"] x[length(rest)] at pass [passes]")
				log_world("STATS: marked drain on lane [lane] spent its budget of [budget]us; [length(rest)] evaluation\s resume at the next drain (first: [E.type] [def ? def.name : "contributes_to"])")
				return
			var/datum/stat_record/rec = E.rx?.stats
			if(rec?.marked)
				rec.marked -= def ? def.skey : "ct:[ct.serial]"
			var/started = stat_charge_begin()
			if(ct)
				stat_ct_update(E, ct)
			else
				stat_settle_def(E, def)
			.++
			spent += stat_charge_end(started)
			GLOB.stat_tick_spent = spent
	if(length(GLOB.stat_marked) && passes >= DRAIN_MAX_PASSES)
		GLOB.stat_spills++
		TEST_REC_SPILL("[lane]: [length(GLOB.stat_marked)] marked evaluations past [DRAIN_MAX_PASSES] passes")
		log_world("STATS: marked drain stopped after [DRAIN_MAX_PASSES] passes with [length(GLOB.stat_marked)] still marked; the rest spills to the next drain point")

/// The batch in rank order (the entity's own type's rank of the stat), first marked first among equals.
/proc/stat_sort_marked(list/batch)
	var/list/keyed = list()
	for(var/list/row as anything in batch)
		var/datum/E = row[1]
		var/datum/stat_def/def = row[2]
		var/rank = 0
		if(def && !QDELETED(E))
			var/datum/stat_type_info/I = stat_type_of(E)
			rank = I?.ranks?[def.skey] || 0
		keyed += list(list(rank, row))
	// stable insertion by rank
	var/list/out = list()
	for(var/list/pair as anything in keyed)
		var/at = length(out) + 1
		for(var/i in length(out) to 1 step -1)
			var/list/other = out[i]
			if(other[1] <= pair[1])
				break
			at = i
		out.Insert(at, list(pair))
	var/list/rows = list()
	for(var/list/pair as anything in out)
		rows += list(pair[2])
	return rows

/// The kernel's drain point (the start of phases D, P and R): the marked stats recompute under the simulation lane's budget. Costs one list length
/// when nothing is marked. While a map loads (a load frame is open, even one suspended between chunks) it does nothing: initial evaluation is
/// silent until the load completes, and the load's own settling drain (SSatoms.initialize_atoms_finish()) then runs what is owed, once.
/proc/stat_drain_point()
	if(materialization_host().map_loading())
		return
	act_drain_point() // the notices queued past the depth cap and the marked on_change hooks (code/engine/actions)
	if(length(GLOB.stat_marked))
		stat_drain_marked(LANE_SIMULATION, FALSE)

/// A kernel pass begins: the lane's budget is whole again, shared by the drains of this tick's D, P and R.
/proc/stat_tick_begin()
	GLOB.stat_tick_spent = 0

// Charging: production reads the tick clock; test builds charge TEST_EVAL_COST per evaluation so a budget spills in the same place on every run.
#if defined(UNIT_TESTS)
/proc/stat_charge_begin()
	return 0

/proc/stat_charge_end(started)
	return TEST_EVAL_COST
#else
/proc/stat_charge_begin()
	return stat_clock_us()

/proc/stat_charge_end(started)
	return max(stat_clock_us() - started, 0)
#endif

// ---- the reverse index of one-relation hops ----

/// Records that reader E's relation var `rel_var` names what it names now: E joins the new target's hop_in[rel_var] and leaves the old one's.
/proc/stat_hop_attach(datum/E, rel_var)
	var/datum/stat_record/rec = stat_record_of(E)
	var/datum/old = rec.hop_targets?[rel_var]
	var/datum/target = E.vars[rel_var]
	if(!isdatum(target) || QDELETED(target))
		target = null
	if(old == target)
		return
	if(old)
		stat_hop_leave(E, old, rel_var)
	if(!target)
		if(rec.hop_targets)
			rec.hop_targets -= rel_var
			if(!length(rec.hop_targets))
				rec.hop_targets = null
		return
	if(!rec.hop_targets)
		rec.hop_targets = list()
	rec.hop_targets[rel_var] = target
	var/datum/stat_record/trec = stat_record_of(target)
	if(!trec.hop_in)
		trec.hop_in = list()
	var/list/readers = trec.hop_in[rel_var]
	if(!readers)
		readers = list()
		trec.hop_in[rel_var] = readers
	readers |= list(E)

/// E leaves `old`'s reader list for `rel_var`.
/proc/stat_hop_leave(datum/E, datum/old, rel_var)
	var/list/readers = old.rx?.stats?.hop_in?[rel_var]
	if(!readers)
		return
	readers -= E
	if(!length(readers))
		old.rx.stats.hop_in -= rel_var
		if(!length(old.rx.stats.hop_in))
			old.rx.stats.hop_in = null

/// A datum is destroyed: as a reader it leaves every target's list; as a target the readers' links to it are dropped (their relation vars are
/// cleared by the ownership teardown, which re-attaches them to nothing).
/proc/stat_hop_teardown(datum/D, datum/stat_record/rec)
	for(var/rel_var in rec.hop_targets)
		var/datum/target = rec.hop_targets[rel_var]
		if(target && !QDELETED(target))
			stat_hop_leave(D, target, rel_var)
	rec.hop_targets = null
	for(var/rel_var in rec.hop_in)
		for(var/datum/reader as anything in rec.hop_in[rel_var])
			var/datum/stat_record/rrec = reader.rx?.stats
			if(rrec?.hop_targets && rrec.hop_targets[rel_var] == D)
				rrec.hop_targets -= rel_var
				if(!length(rrec.hop_targets))
					rrec.hop_targets = null
	rec.hop_in = null

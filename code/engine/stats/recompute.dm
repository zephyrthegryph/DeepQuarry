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
GLOBAL_VAR(stat_writing) // the stat var the engine is publishing: changed() does not feed it back to the stat layer
GLOBAL_VAR_INIT(stat_spills, 0)
GLOBAL_VAR_INIT(stat_evals, 0)

/// Calls holder proc `proc_name` (a contribution's or a formula's handler) with the shared evaluation context.
/proc/stat_call(datum/holder, proc_name)
	var/datum/act/eval/A = take(/datum/act/eval)
	A.holder = holder // ALLOW(ownership): an engine record owned by its own end path (released below)
	. = call(holder, proc_name)(A)
	A.release()

/// The value of stat `stat_id` on E: its var, or (a virtual stat) what the record holds, or what it composes to now.
/proc/stat_value(datum/E, stat_id)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def || !isdatum(E))
		return null
	if(def.name in E.vars)
		return E.vars[def.name]
	var/datum/stat_record/rec = E.rx?.stats
	if(rec?.virtual && ("[def.id]" in rec.virtual))
		return rec.virtual["[def.id]"]
	var/datum/stat_type_info/I = stat_type_of(E)
	return stat_compute(E, def, I || null)

/// Writes a stat's settled value where it lives.
/proc/stat_store(datum/E, datum/stat_def/def, value)
	if(def.name in E.vars)
		E.vars[def.name] = value // ALLOW(api): the stat layer is the one writer of a stat's var
	else
		var/datum/stat_record/rec = stat_record_of(E)
		if(!rec.virtual)
			rec.virtual = list()
		rec.virtual["[def.id]"] = value

// ---- computing ----

/**
 * The composed value of `def` on E now: the stat's base, the type's constant (the var's initial value, or the map's edit of it) as a contribution at
 * default priority, the type's contributes() entries whose gates hold, and the holds, combined by the rule. A status reads 0 while its immunity holds.
 */
/proc/stat_compute(datum/E, datum/stat_def/def, datum/stat_type_info/I)
	var/value
	var/override_set = FALSE
	var/override_value = null
	if(def.rule == STAT_RULE_FORMULA)
		value = isnull(def.formula) ? def.base : stat_call(E, def.formula)
	else
		var/list/rows = list()
		var/has_var = (def.name in E.vars)
		var/datum/stat_record/rec = E.rx?.stats
		// The type's own constant: a var set in the type's definition is a type-level contribution at default priority.
		if(has_var)
			var/constant = (rec?.constants && ("[def.id]" in rec.constants)) ? rec.constants["[def.id]"] : initial(E.vars[def.name])
			if(!isnull(constant))
				rows += list(stat_boolean_normal(def, constant), PRIORITY_DEFAULT, -1000000)
		if(I)
			for(var/datum/stat_contrib/C as anything in I.contribs["[def.id]"])
				if(!stat_contrib_active(E, C))
					continue
				rows += list(stat_contrib_value(E, def, C), C.priority, C.serial)
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
			else if(stat_rule_is_boolean(def.rule))
				row_value = !!row_value
			if(row[H_FLAGS] & HF_OVERRIDE)
				if(isnull(override_priority) || row[H_PRIORITY] > override_priority || (row[H_PRIORITY] == override_priority && row[H_SERIAL] >= override_serial))
					override_priority = row[H_PRIORITY]
					override_serial = row[H_SERIAL]
					override_set = TRUE
					override_value = row_value
				continue
			rows += list(row_value, row[H_PRIORITY], row[H_SERIAL])
		value = stat_combine(def, rows)
		if(override_set)
			value = override_value
	if(def.units && E)
		if(stat_status_immune(E, def))
			value = 0
	return value

/// A boolean stat's contribution as TRUE or FALSE; any other value as it is.
/proc/stat_boolean_normal(datum/stat_def/def, value)
	if(stat_rule_is_boolean(def.rule))
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
/proc/stat_recompute(datum/E, datum/stat_def/def, silent = FALSE)
	var/datum/stat_type_info/I = stat_type_of(E)
	if(!E.rx?.stats?.inited)
		stat_ensure_inited(E, I || null)
	var/old = stat_value_now(E, def)
	var/new_value = stat_compute(E, def, I || null)
	GLOB.stat_evals++
	if(stat_values_equal(old, new_value))
		return FALSE
	stat_store(E, def, new_value)
	if(silent)
		return TRUE
	TEST_REC_DELTA(E, def.name, old, new_value)
	if(def.name in E.vars)
		GLOB.stat_writing = def.name
		changed(E, 0, def.name)
		GLOB.stat_writing = null
	else if(READERS(E, "stat:[def.id]"))
		publish_change(E, "stat:[def.id]")
	return TRUE

/// The value a stat holds now, without computing it.
/proc/stat_value_now(datum/E, datum/stat_def/def)
	if(def.name in E.vars)
		return E.vars[def.name]
	var/datum/stat_record/rec = E.rx?.stats
	if(rec?.virtual && ("[def.id]" in rec.virtual))
		return rec.virtual["[def.id]"]
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
		if(I.has_var["[def.id]"])
			var/current = E.vars[def.name]
			if(!stat_values_equal(current, initial(E.vars[def.name])))
				if(!rec.constants)
					rec.constants = list()
				rec.constants["[def.id]"] = current
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
		if(length(I.contribs["[def.id]"]) || def.rule == STAT_RULE_FORMULA || rec.constants?["[def.id]"])
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

/// The defs sorted by rank, lowest first (a stable insertion sort: a handful of stats per type).
/proc/stat_sort_by_rank(datum/stat_type_info/I, list/defs)
	var/list/out = list()
	for(var/datum/stat_def/def as anything in defs)
		var/rank = I?.ranks?["[def.id]"] || 0
		var/at = length(out) + 1
		for(var/i in 1 to length(out))
			var/datum/stat_def/other = out[i]
			if((I?.ranks?["[other.id]"] || 0) > rank)
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
	var/list/queue = stat_sort_by_rank(I, defs)
	if(GLOB.stat_settle_depth > DRAIN_MAX_PASSES)
		declare_report("[RULE_STAT_CYCLE] settle of [E.type] is [GLOB.stat_settle_depth] writes deep: a runtime cycle through relations or contributes_to")
		return
	GLOB.stat_settle_depth++
	var/i = 1
	while(i <= length(queue))
		var/datum/stat_def/def = queue[i]
		i++
		if(length(queue) > SETTLE_MAX_QUEUE)
			declare_report("[RULE_STAT_CYCLE] settle of [E.type] queued more than [SETTLE_MAX_QUEUE] stats: stopping")
			break
		if(!stat_recompute(E, def))
			continue
		stat_changed_dependents(E, def, I, queue)
	GLOB.stat_settle_depth--

/// What a changed stat on E moves: same-entity readers join the queue; contributes_to entries re-evaluate; hop readers settle or are marked.
/proc/stat_changed_dependents(datum/E, datum/stat_def/def, datum/stat_type_info/I, list/queue)
	if(I)
		for(var/reader_id in I.stat_readers["[def.id]"])
			stat_queue_insert(I, queue, stat_def_of(reader_id))
		for(var/key in list("stat:[def.id]", def.name))
			for(var/datum/stat_dep/dep as anything in I.inputs[key])
				if(dep.ct)
					stat_ct_update(E, dep.ct)
				else
					stat_queue_insert(I, queue, stat_def_of(dep.stat_id))
	stat_notify_hops(E, def.name)
	if(length(GLOB.stat_sys_index))
		stat_notify_system(E, def.name)

/// Adds `def` to a settle queue in rank order unless it is already there.
/proc/stat_queue_insert(datum/stat_type_info/I, list/queue, datum/stat_def/def)
	if(!def || (def in queue))
		return
	var/rank = I.ranks?["[def.id]"] || 0
	var/at = length(queue) + 1
	for(var/k in 1 to length(queue))
		var/datum/stat_def/other = queue[k]
		if((I.ranks?["[other.id]"] || 0) > rank)
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
		var/list/frontier = list(E)
		for(var/i in length(hop.path) to 1 step -1)
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
		for(var/datum/reader as anything in frontier)
			if(!istype(reader, reader_type))
				continue
			if(hop.ct)
				if(hop.settle == SETTLE_INLINE)
					stat_ct_update(reader, hop.ct)
				else
					stat_mark_ct(reader, hop.ct)
				continue
			var/datum/stat_def/def = stat_def_of(hop.stat_id)
			if(!def)
				continue
			if(hop.settle == SETTLE_INLINE)
				stat_settle(reader, list(def))
			else
				stat_mark(reader, def)

/// A system's tracked var changed: the readers registered through a SYSTEM_ACCESSOR are marked (an accessor edge is never inline).
/proc/stat_notify_system(datum/E, key)
	for(var/system_key in GLOB.stat_sys_index)
		var/dot = findtext(system_key, ".")
		if(!dot || copytext(system_key, dot + 1) != key)
			continue
		var/system_name = copytext(system_key, 1, dot)
		var/datum/singleton = GLOB.vars["[system_name]_service"] || GLOB.vars["SS[system_name]"]
		if(singleton != E)
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
				var/datum/stat_def/def = stat_def_of(sys.stat_id)
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
	stat_settle(target, list(def))

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
	stat_settle(target, list(def))

/// A contributes_to entity's relation var was written: its contribution moves to the new target and leaves the old one.
/proc/stat_relation_changed(datum/E, var_name)
	var/datum/stat_type_info/I = stat_type_of(E)
	if(!I)
		return
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		if(ct.rel == var_name)
			stat_ct_update(E, ct)

// ---- the marked queue ----

/// Flags a stat of an entity for the next marked drain. Nothing is evaluated now: the write that reached it pays one list add.
/proc/stat_mark(datum/E, datum/stat_def/def)
	var/datum/stat_record/rec = stat_record_of(E)
	if(!rec.marked)
		rec.marked = list()
	if(rec.marked["[def.id]"])
		return
	rec.marked["[def.id]"] = TRUE
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
/proc/stat_drain_marked(lane = LANE_SIMULATION)
	. = 0
	var/budget = stat_lane_budget(lane)
	var/spent = 0
	var/passes = 0
	while(length(GLOB.stat_marked) && passes < DRAIN_MAX_PASSES)
		passes++
		var/list/batch = GLOB.stat_marked
		GLOB.stat_marked = list()
		batch = stat_sort_marked(batch)
		for(var/i in 1 to length(batch))
			var/list/row = batch[i]
			var/datum/E = row[1]
			var/datum/stat_def/def = row[2]
			var/datum/stat_contrib/ct = row[3]
			if(QDELETED(E))
				continue
			var/cost = TEST_EVAL_COST
#if !defined(UNIT_TESTS)
			cost = 0
			var/started = stat_clock_us()
#endif
			if(spent + TEST_EVAL_COST > budget && !(. == 0))
				// Out of budget: the rest resumes at the next marked drain, nothing lost.
				var/list/rest = batch.Copy(i)
				GLOB.stat_marked = rest + GLOB.stat_marked
				GLOB.stat_spills++
				TEST_REC_SPILL("[lane]:[def ? def.name : "ct"] x[length(rest)] at pass [passes]")
				log_world("STATS: marked drain on lane [lane] spent its budget of [budget]us; [length(rest)] evaluation\s resume at the next drain (first: [E.type] [def ? def.name : "contributes_to"])")
				return
			var/datum/stat_record/rec = E.rx?.stats
			if(rec?.marked)
				rec.marked -= def ? "[def.id]" : "ct:[ct.serial]"
			if(ct)
				stat_ct_update(E, ct)
			else
				stat_settle(E, list(def))
			.++
#if defined(UNIT_TESTS)
			spent += TEST_EVAL_COST
#else
			spent += max(stat_clock_us() - started, 0)
#endif
			cost = cost
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
			rank = I?.ranks?["[def.id]"] || 0
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

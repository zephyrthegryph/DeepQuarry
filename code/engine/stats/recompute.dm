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
GLOBAL_LIST_EMPTY(stat_marked) // list(entity's slot, stat def, contribution or null) rows waiting for a marked drain
GLOBAL_LIST_EMPTY(stat_hop_index) // remote var name -> list(list(reader type, /datum/stat_hop))
GLOBAL_LIST_EMPTY(stat_sys_index) // "system.var" -> assoc: entity -> TRUE (readers through a SYSTEM_ACCESSOR)
GLOBAL_LIST_EMPTY(stat_sys_vars) // var name -> TRUE: the var half of every "system.var" key of stat_sys_index, so a write to any other var skips the key walk
GLOBAL_VAR(stat_writing) // the stat var the engine is publishing: state_changed() does not feed it back to the stat layer
GLOBAL_VAR(stat_force_settle) // SETTLE_INLINE / SETTLE_MARKED: the apc_flip_50 spike forces every hop one way; null in play
GLOBAL_VAR_INIT(stat_spills, 0)
GLOBAL_VAR_INIT(stat_tick_spent, 0) // what this kernel pass's marked drains have charged to the lane so far
GLOBAL_VAR_INIT(stat_evals, 0)
/// Hop reaches skipped because the reading contribution's when() gate was closed on the reader.
GLOBAL_VAR_INIT(stat_hops_gated, 0)
/// Settles the init frame queued instead of running (stat_settle_defer), how many it ran when the frame closed or a read needed them, and for how many targets.
GLOBAL_VAR_INIT(stat_deferred, 0)
GLOBAL_VAR_INIT(stat_deferred_settles, 0)
GLOBAL_VAR_INIT(stat_deferred_targets, 0)
/// The slots of the targets that have queued settles (rec.pending); a slot whose rows a read already settled is skipped when the frame closes.
GLOBAL_LIST_EMPTY(stat_pending_slots)
GLOBAL_LIST_EMPTY(stat_read_compute_by) // BENCHMARK builds: "type:stat" -> uncached read computes
GLOBAL_VAR_INIT(stat_read_computes, 0) // stat_value() calls that composed the value because nothing was cached (the bench's idle stat metric)

/// Calls holder proc `proc_name` (a contribution's or a formula's handler) with the shared evaluation context.
PROC_SUMMARY(/proc/stat_call) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_call(datum/holder, proc_name)
	lookup_reads_prepare(holder)
	// One context for every contribution handler: a handler may not keep it, and a recompute inside a handler puts the outer holder back.
	var/static/datum/act/eval/ctx = new
	var/datum/outer = ctx.holder
	ctx.holder = holder
	try
		. = call(holder, proc_name)(ctx)
	catch(var/exception/fault)
		ctx.holder = outer
		throw fault
	ctx.holder = outer

/// The value of stat `stat_id` on E: its var, or (a virtual stat) what the record holds, or what it composes to now.
PROC_SUMMARY(/proc/stat_value) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_value(datum/E, stat_id)
	READS_FROM(E)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def)
		// A condition reading a stat that does not exist would just read false for ever.
		declare_report("stat_value([E?.type], [stat_id]): no such stat")
		return null
	if(!isdatum(E))
		return null
	stat_pending_flush(E) // settles what the init frame queued for E: no reader sees a value a queued contribution has not reached
	var/datum/stat_type_info/I = stat_type_of(E)
	if(I ? I.has_var[def.skey] : (def.name in E.vars))
		. = E.vars[def.name]
		if(GLOB.staleness_on)
			staleness_check_stat(E, def, I || null, ., "stat_value")
		return .
	var/datum/stat_record/rec = E.rx?.stats
	// A stat whose inputs all publish keeps its value until one does (stat_recompute() rewrites it then); one that reads something nobody publishes
	// (code/engine/_generated/deps.dm, the untracked_inputs lint) is composed on every read, so it is never stale.
	var/tracked = stat_inputs_tracked(I || null, def)
	if(tracked && rec?.virtual && (def.skey in rec.virtual))
		. = rec.virtual[def.skey]
		if(GLOB.staleness_on)
			staleness_check_stat(E, def, I || null, ., "stat_value")
		return .
	GLOB.stat_read_computes++
#if defined(BENCHMARK)
	GLOB.stat_read_compute_by["[E.type]:[def.name]"]++
#endif
	. = stat_compute(E, def, I || null, rec)
	// Cached on first read once the stat layer has set the entity up (its init computation, or its first hold): before that a map edit or an
	// Initialize() write may still be on its way. A keyed stat's list is handed out, so it is cached only by a recompute, as before.
	if(tracked && rec?.inited && !def.keyed)
		stat_store(E, def, ., I || null)

/// PUBLISH_CHANGE(E, KEY): a producer key that is not one var changed. The stats that read it (through a READS_AS accessor) recompute before the
/// writer's next line, as for a tracked var, then the key's readers hear it.
/proc/publish_key_changed(datum/E, key)
	if(GLOB.stat_input_keys?[key] && key != GLOB.stat_writing)
		stat_inputs_changed(E, key)
	if(READERS(E, key))
		publish_change(E, key)
	// A draw that reads the key through a READS_AS accessor redraws (code/engine/_generated/deps.dm, generated_draw_keys).
	if(isatom(E) && draw_reads_key(E, key))
		// As state_changed() does: the look that watches E hears it on E's first mark of the frame, and marking E first would swallow that.
		var/first_mark = E.rel_watchers && REFRESH_IDLE(E)
		refresh_mark(E, DEP_DRAW)
		if(first_mark)
			rel_notify_watchers(E)

/// Writes a stat's settled value where it lives.
PROC_SUMMARY(/proc/stat_store) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
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
PROC_SUMMARY(/proc/stat_compute) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_compute(datum/E, datum/stat_def/def, datum/stat_type_info/I, datum/stat_record/rec)
	var/value
	var/override_set = FALSE
	var/override_value = null
	if(def.is_formula)
		value = isnull(def.formula) ? def.base : stat_call(E, def.formula)
	else if(def.keyed)
		value = stat_compute_keyed(def, rec)
	else if(I && def.fast && !rec?.by_stat?[def.skey])
		value = stat_compute_fast(E, def, I, rec)
		if(def.clamps)
			value = stat_clamp(def, value)
	else if(def.rule == STAT_RULE_SUM && rec?.sum_cache?[def.skey])
		// The running total of the rows (store.dm): the same number the walk below would add up.
		var/list/running = rec.sum_cache[def.skey]
		value = running[2] ? running[1] : def.base
		if(def.clamps)
			value = stat_clamp(def, value)
	else if(def.rule == STAT_RULE_SUM)
		// The same rows in the same order as the general path below, added as they are met: no row list and no second pass (an area's
		// demand stat holds a row per machine in it, and every machine's write re-sums them all).
		var/sum = 0
		var/count = 0
		var/has_var_sum = I ? I.has_var[def.skey] : (def.name in E.vars)
		if(has_var_sum)
			var/constant_sum = I ? I.consts[def.skey] : initial(E.vars[def.name])
			if(rec?.constants && (def.skey in rec.constants))
				constant_sum = rec.constants[def.skey]
			if(!isnull(constant_sum))
				sum += stat_boolean_normal(def, constant_sum)
				count++
		if(I)
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(!stat_contrib_active(E, C))
					continue
				sum += stat_contrib_value(E, def, C)
				count++
		var/override_priority_sum = null
		var/override_serial_sum = 0
		for(var/list/row as anything in rec?.by_stat?[def.skey])
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
				if(isnull(override_priority_sum) || row[H_PRIORITY] > override_priority_sum || (row[H_PRIORITY] == override_priority_sum && row[H_SERIAL] >= override_serial_sum))
					override_priority_sum = row[H_PRIORITY]
					override_serial_sum = row[H_SERIAL]
					override_set = TRUE
					override_value = row_value
				continue
			sum += row_value
			count++
		value = count ? sum : def.base
		// A stat of rows alone (a virtual total such as an area's demand), every row plain and whole: keep the running total from here on.
		if(rec && I && !has_var_sum && !def.boolean && !override_set && rec.by_stat?[def.skey] && !length(I.contribs[def.skey]) && sum < STAT_SUM_LIMIT)
			var/all_ok = TRUE
			for(var/list/plain as anything in rec.by_stat[def.skey])
				if(!stat_sum_row_ok(plain))
					all_ok = FALSE
					break
			if(all_ok)
				if(!rec.sum_cache)
					rec.sum_cache = list()
				rec.sum_cache[def.skey] = list(sum, count)
		if(def.clamps)
			value = stat_clamp(def, value)
		if(override_set)
			value = override_value
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
		for(var/list/row as anything in rec?.by_stat?[def.skey])
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
		if(def.clamps)
			value = stat_clamp(def, value)
		if(override_set)
			value = override_value
	if(def.units && E)
		if(stat_status_immune(E, def))
			value = 0
	return value

/// A SUM_PER_KEY stat: key -> the sum of the holds naming that key (a fresh list, empty with none).
/proc/stat_compute_keyed(datum/stat_def/def, datum/stat_record/rec)
	. = list()
	for(var/list/row as anything in rec?.by_stat?[def.skey])
		var/key = row[H_KEY]
		.[key] = (.[key] || 0) + row[H_VALUE]

/// A numeric stat's composed value held to its declared bounds (bounds = list(lo, hi)); anything that is not a number is left as it is.
/proc/stat_clamp(datum/stat_def/def, value)
	if(!isnum(value))
		return value
	if(!isnull(def.bound_lo) && value < def.bound_lo)
		return def.bound_lo
	if(!isnull(def.bound_hi) && value > def.bound_hi)
		return def.bound_hi
	return value

/// stat_compute() for the rules a row list adds nothing to (ALL, ANY, SUM, PRODUCT, MAX, MIN, MASK_OR) on a stat none of whose rows exist: no row
/// list, no combine call. The constant comes first and the contributions follow in order, as in the general path, so the value is the same.
/proc/stat_compute_fast(datum/E, datum/stat_def/def, datum/stat_type_info/I, datum/stat_record/rec)
	// The contributions gated by a holder proc share one evaluation context (as stat_relation_changed()'s run does): a context per gate was
	// a take and a release per condition (a machine's power stat asks three).
	var/datum/act/op/ctx = null
	for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
		if(C.gate_kinds && (CG_PROC in C.gate_kinds))
			ctx = pooled_op_context(E)
			break
	if(!ctx)
		return stat_compute_fast_with(E, def, I, rec, null)
	try
		. = stat_compute_fast_with(E, def, I, rec, ctx)
	catch(var/exception/fault)
		ctx.release()
		throw fault
	ctx.release()

/proc/stat_compute_fast_with(datum/E, datum/stat_def/def, datum/stat_type_info/I, datum/stat_record/rec, datum/act/op/ctx)
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
				if(stat_contrib_active(E, C, ctx) && !stat_contrib_value(E, def, C))
					return FALSE
			return TRUE
		if(STAT_RULE_ANY)
			if(has_const && constant)
				return TRUE
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C, ctx) && stat_contrib_value(E, def, C))
					return TRUE
			return FALSE
		if(STAT_RULE_PRODUCT)
			. = has_const ? constant : 1
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C, ctx))
					. *= stat_contrib_value(E, def, C)
		if(STAT_RULE_MASK_OR)
			var/any_member = has_const
			. = has_const ? constant : 0
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C, ctx))
					. |= stat_contrib_value(E, def, C)
					any_member = TRUE
			if(!any_member)
				return def.base
		if(STAT_RULE_MAX, STAT_RULE_MIN)
			. = has_const ? constant : null
			var/is_max = (rule == STAT_RULE_MAX)
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(!stat_contrib_active(E, C, ctx))
					continue
				var/v = stat_contrib_value(E, def, C)
				if(isnull(.) || (is_max ? (v > .) : (v < .)))
					. = v
			if(isnull(.))
				return def.base
		else
			. = has_const ? constant : 0
			for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
				if(stat_contrib_active(E, C, ctx))
					. += stat_contrib_value(E, def, C)

/// A boolean stat's contribution as TRUE or FALSE; any other value as it is.
/proc/stat_boolean_normal(datum/stat_def/def, value)
	if(def.boolean)
		return value ? TRUE : FALSE
	return value

/// TRUE when every when() block around a contribution holds on E (a contribution gated by a condition is an input of the stat).
/proc/stat_contrib_active(datum/E, datum/stat_contrib/C, datum/act/op/ctx = null)
	var/list/whens = C.whens
	var/list/kinds = C.gate_kinds
	for(var/i in 1 to length(whens))
		var/datum/entry/W = whens[i]
		var/cond = W.args["cond"]
		switch(kinds?[i])
			if(CG_VAR)
				if(!E.vars[cond])
					return FALSE
			if(CG_PROC)
				// A holder proc under the context the caller shares: the pure call, without the evaluator's form tests and its two scans of the vars.
				if(ctx && !GLOB.op_menu_read_frame)
					if(QDELETED(E) || !op_pure_call(E, cond, ctx))
						return FALSE
				else if(!condition_holds(E, cond, ctx))
					return FALSE
			else
				if(!condition_holds(E, cond, ctx))
					return FALSE
	return TRUE

/// What one contribution contributes: its constant, a var read, another stat, a capability key, a holder proc, or a condition tree.
PROC_SUMMARY(/proc/stat_contrib_value) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
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
PROC_SUMMARY(/proc/stat_recompute) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
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
	if((old == new_value && !islist(new_value)) || (islist(new_value) && stat_values_equal(old, new_value)))
		// Unchanged, but a virtual stat that equals its base was never stored: keep it now, so its reads stop composing it (stat_value()).
		if(!has_var && !def.keyed && !(rec.virtual && (def.skey in rec.virtual)) && stat_inputs_tracked(I || null, def))
			stat_store(E, def, new_value, I || null)
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
		var/outer_writing = GLOB.stat_writing
		GLOB.stat_writing = def.name
		try
			state_changed(E, 0, def.name)
		catch(var/exception/fault)
			GLOB.stat_writing = outer_writing
			throw fault
		GLOB.stat_writing = outer_writing
	else
		op_changed(E)
		if(READERS(E, def.stat_key))
			publish_change(E, def.stat_key)
	// A status started or ended: its holder's hooks and presentation follow at once (code/library/mob/statuses.dm).
	if(def.units && ((isnum(old) && old > 0) != (isnum(new_value) && new_value > 0)))
		E.stat_status_changed(def.id, isnum(new_value) && new_value > 0)
	// Relevance moved: the sequences sweeping E and the cadences that read it follow (code/engine/time/clocks.dm).
	else if(def.id == STAT_RELEVANCE)
		relevance_changed(E, new_value || RELEVANCE_NONE)
	else if(def.id == STAT_SUSPENDED)
		suspended_changed(E)
	else if(def.id == STAT_CLOCK_RATE_BIO)
		bio_clock_rate_changed(E)
	return TRUE

/// The value a stat holds now, without computing it.
PROC_SUMMARY(/proc/stat_value_now) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
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
PROC_SUMMARY(/proc/stat_ensure_inited) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_ensure_inited(datum/E, datum/stat_type_info/I)
	var/datum/stat_record/rec = stat_record_of(E)
	if(rec.inited)
		return rec
	rec.inited = TRUE
	staleness_track(E)
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
	// The stats every instance computes (a contribution or a formula), in rank order, are a fact of the type: built once (stat_type_init_todo()). Only
	// an instance whose map edits made a stat var a constant computes that stat too, and builds its own list.
	var/list/todo = I.init_todo || stat_type_init_todo(I)
	if(rec.constants)
		todo = list()
		for(var/datum/stat_def/def as anything in I.defs)
			if(length(I.contribs[def.skey]) || def.rule == STAT_RULE_FORMULA || rec.constants[def.skey])
				todo += def
		todo = stat_sort_by_rank(I, todo)
	var/census_start = GLOB.stat_template_census ? TICK_USAGE_REAL : 0
	// A per-type template (stat_templates.md): an instance whose computes read only its own vars, all at the type's defaults, ends with the values the
	// type's first such instance computed. Test builds compute the first instances of each type both ways and compare.
	var/list/template = (!rec.constants && stat_template_instance_ok(E, I, rec, todo)) ? GLOB.stat_templates[E.type] : null
	#if defined(UNIT_TESTS)
	if(template && GLOB.stat_template_checked[E.type] < 3)
		GLOB.stat_template_checked[E.type]++
		template = null
		for(var/datum/stat_def/def as anything in todo)
			stat_recompute(E, def, TRUE)
		var/list/computed = stat_template_values(E, I, todo)
		var/list/held = GLOB.stat_templates[E.type]
		if(!(computed ~= held)) // in order: each value against the same stat's
			stack_trace("STAT TEMPLATE MISMATCH: [E.type] computes [json_encode(computed)], its template holds [json_encode(GLOB.stat_templates[E.type])]")
		todo = list()
	#endif
	if(template)
		GLOB.stat_templates_served++
		for(var/i in 1 to length(todo))
			var/datum/stat_def/def = todo[i]
			var/value = template[i]
			if(I.has_var[def.skey])
				if(E.vars[def.name] != value)
					stat_store(E, def, value, I)
			else if(value != STAT_TEMPLATE_UNSTORED)
				stat_store(E, def, value, I) // a virtual stat the full compute stored (stat_recompute() keeps one that equals its base once its inputs are tracked)
		todo = list()
	else if(!rec.constants && isnull(GLOB.stat_templates[E.type]) && stat_template_instance_ok(E, I, rec, todo))
		for(var/datum/stat_def/def as anything in todo)
			stat_recompute(E, def, TRUE)
		GLOB.stat_templates[E.type] = stat_template_values(E, I, todo)
		todo = list()
	for(var/datum/stat_def/def as anything in todo)
		stat_recompute(E, def, TRUE)
	if(GLOB.stat_template_census)
		stat_template_census_note(E, I, rec, census_start)
	for(var/datum/stat_hop/sys as anything in I.hops["sys"])
		var/list/readers = GLOB.stat_sys_index[sys.system]
		if(!readers)
			readers = list()
			GLOB.stat_sys_index[sys.system] = readers
			var/sys_dot = findtext(sys.system, ".")
			if(sys_dot)
				GLOB.stat_sys_vars[copytext(sys.system, sys_dot + 1)] = TRUE
		readers[E] = TRUE
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		stat_ct_update(E, ct)
	for(var/rel_var in I.hop_rels)
		stat_hop_attach(E, rel_var)

/// The stats of type I that every instance computes at init (a contribution or a formula), in rank order: built once and kept on I (read-only after).
/proc/stat_type_init_todo(datum/stat_type_info/I)
	var/list/todo = list()
	for(var/datum/stat_def/def as anything in I.defs)
		if(length(I.contribs[def.skey]) || def.rule == STAT_RULE_FORMULA)
			todo += def
	I.init_todo = stat_sort_by_rank(I, todo)
	return I.init_todo

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
	try
		if(stat_recompute(E, def, FALSE, I))
			if(I && (I.stat_readers[def.skey] || I.inputs[def.stat_key] || I.inputs[def.name]))
				var/list/queue = list(def)
				stat_changed_dependents(E, def, I, queue)
				stat_settle_queue_run(E, I, queue, 2)
			else
				if(GLOB.stat_hop_index[def.name])
					stat_notify_hops(E, def.name)
				if(GLOB.stat_sys_vars[def.name])
					stat_notify_system(E, def.name)
	catch(var/exception/fault)
		GLOB.stat_settle_depth--
		throw fault
	GLOB.stat_settle_depth--

/// Runs a settle queue from entry `start` (entries before it are done).
/proc/stat_settle_queue(datum/E, datum/stat_type_info/I, list/queue, start)
	if(GLOB.stat_settle_depth > DRAIN_MAX_PASSES)
		declare_report("[RULE_STAT_CYCLE] settle of [E.type] is [GLOB.stat_settle_depth] writes deep: a runtime cycle through relations or contributes_to")
		return
	GLOB.stat_settle_depth++
	try
		stat_settle_queue_run(E, I, queue, start)
	catch(var/exception/fault)
		GLOB.stat_settle_depth--
		throw fault
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
	if(GLOB.stat_sys_vars[def.name])
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
	GLOB.stat_input_queries++
	var/datum/stat_type_info/I = GLOB.stat_type_index?[E.type] // stat_type_of() inlined: a pre-init write asks for every tracked var of every atom
	if(isnull(I))
		I = stat_type_of(E)
	if(!(I && I.inputs[key]) && !GLOB.stat_hop_index[key] && !GLOB.stat_sys_vars[key])
		GLOB.stat_input_noops++
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
	if(GLOB.stat_sys_vars[key])
		stat_notify_system(E, key)

/// A write to `key` on E reaches the entities whose stats read E.key through a relation (a hop), however many relations away. A single-valued edge
/// settles the reader at once; a collection edge, or more than one hop, marks it for the next marked drain.
/proc/stat_notify_hops(datum/E, key)
	var/list/entries = GLOB.stat_hop_index[key]
	if(!entries)
		return
	var/list/targets = stat_hop_targets(E, key, entries)
	for(var/i in 1 to length(targets) step 2)
		stat_hop_reach(targets[i], targets[i + 1])

/// TRUE when `reader` is built and the when() gate of `gated` (the contribution that reads the hop) is closed on it.
/proc/stat_hop_gate_closed(datum/reader, datum/stat_contrib/gated)
	if(isatom(reader))
		var/atom/built = reader
		if(!(built.flags & ATOM_INITIALIZED))
			return FALSE
	return !stat_contrib_active(reader, gated)

/// One reader reached through `hop`: settled at once or marked for the next marked drain.
/proc/stat_hop_reach(datum/reader, datum/stat_hop/hop)
	// A contribution inside a closed when() adds nothing, whatever the far var did (a machine that does not draw on the area's environment channel
	// has no use for its flip): the reader is not reached. When the gate opens, its own inputs recompute the stat from the far var as it then is.
	var/datum/stat_contrib/gated = hop.gated
	if(gated && stat_hop_gate_closed(reader, gated))
		GLOB.stat_hops_gated++
		return
	var/settle = GLOB.stat_force_settle || hop.settle
	if(hop.ct)
		if(settle == SETTLE_INLINE)
			stat_ct_update(reader, hop.ct)
		else
			stat_mark_ct(reader, hop.ct)
		return
	var/datum/stat_def/def = GLOB.stat_defs[hop.skey]
	if(!def)
		return
	if(settle == SETTLE_INLINE)
		stat_settle_def(reader, def)
	else
		stat_mark(reader, def)

/// Every (reader, hop) a write to `key` on E reaches, flat: reader, hop, reader, hop... An entry is a reader type and its hop; a reader of that type or a subtype is
/// reached through it. A single-relation hop (`fast`) reads the readers straight off E's reverse index, and the hops of one relation share that list: each reader
/// looks up the hops its type has (stat_hops_of_type(), built once per reader type) instead of every entry scanning every reader, which was entries x readers
/// istype() tests for one channel flip of a 555-machine area (60-265 ms).
/proc/stat_hop_targets(datum/E, key, list/entries)
	var/list/targets = list()
	var/list/fast_rels
	for(var/list/entry as anything in entries)
		var/datum/stat_hop/hop = entry[2]
		if(hop.fast)
			LAZYSET(fast_rels, hop.rel_var, TRUE)
			continue
		var/reader_type = entry[1]
		var/list/frontier = list(E)
		for(var/i in length(hop.path) to 1 step -1)
			var/segment = hop.path[i]
			var/list/next_frontier = list()
			for(var/datum/at as anything in frontier)
				for(var/datum/source as anything in hop_sources(at, segment))
					if(!QDELETED(source))
						next_frontier |= list(source)
			frontier = next_frontier
			if(!length(frontier))
				break
		for(var/datum/reader as anything in frontier)
			if(istype(reader, reader_type))
				targets += list(reader, hop)
	for(var/rel_var in fast_rels)
		var/list/direct = E.rx?.stats?.hop_in?[rel_var]
		if(!length(direct))
			continue
		var/list/by_type = stat_hops_by_type(key, rel_var, entries)
		for(var/datum/reader as anything in direct.Copy())
			var/list/hops = by_type[reader.type]
			if(isnull(hops))
				hops = stat_hops_of_type(by_type, reader.type, entries, rel_var)
			for(var/datum/stat_hop/hop as anything in hops)
				targets += list(reader, hop)
	return targets

/// key|relation -> reader type -> the fast hops of that relation a reader of the type is reached through (an entry's reader type or a supertype of it): cleared
/// whenever a type registers its hops (contributes.dm), so it never outlives the index it was built from.
GLOBAL_LIST_EMPTY(stat_hop_applicable)

/proc/stat_hops_by_type(key, rel_var, list/entries)
	var/index_key = "[key]|[rel_var]"
	var/list/by_type = GLOB.stat_hop_applicable[index_key]
	if(!by_type)
		by_type = list()
		GLOB.stat_hop_applicable[index_key] = by_type
	return by_type

/// The fast hops of relation `rel_var` that a reader of `reader_type` is reached through: the hops registered for the type or any supertype of it. The entries
/// are indexed by their reader type once per list (under "entry_index"), and a reader type walks its own ancestry (parent_type) instead of testing every
/// entry with ispath(): a channel flip of an area met each of its ~27 reader types for the first time at 0.36 ms apiece, three keys over, and the first
/// flip after boot took 70 ms for it.
/proc/stat_hops_of_type(list/by_type, reader_type, list/entries, rel_var)
	var/list/index = by_type["entry_index"]
	if(!index)
		index = list()
		for(var/list/entry as anything in entries)
			var/datum/stat_hop/hop = entry[2]
			if(hop.fast && hop.rel_var == rel_var)
				var/list/at = index[entry[1]]
				if(!at)
					at = list()
					index[entry[1]] = at
				at += hop
		by_type["entry_index"] = index
	var/list/hops = list()
	var/ancestor = reader_type
	while(ancestor)
		var/list/at = index[ancestor]
		if(at)
			hops += at
		if(ancestor == /datum)
			break
		var/datum/ancestor_instance = ancestor
		ancestor = initial(ancestor_instance.parent_type)
	by_type[reader_type] = hops
	return hops

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
			// stat_sys_forget() takes a reader out when it is destroyed; one in the middle of its destroy is skipped
			if(QDELETED(reader))
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
PROC_SUMMARY(/proc/stat_ct_update) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_ct_update(datum/E, datum/stat_contrib/ct, datum/act/op/gate_ctx = null)
	if(QDELETED(E))
		return
	// The record is made when this entry first holds something: an entity whose gate never opens (a pipe's idle draws) keeps none.
	BOOT_PHASE_BEGIN(bp_pre)
	var/datum/stat_record/rec = E.rx?.stats
	var/ct_key = ct.serial_text
	var/datum/old_target = slot_datum(rec?.ct_targets?[ct_key])
	var/datum/target = ct.rel_declared ? E.vars[ct.rel] : null
	BOOT_PHASE_END(bp_pre, "stat_ct_update: prelude [ct.rel]", E)
	if(old_target && old_target != target)
		stat_ct_release(old_target, E, ct)
		if(rec.ct_targets)
			rec.ct_targets -= ct_key
	if(!isdatum(target) || QDELETED(target))
		return
	if(ct.table_kind)
		stat_ct_hold_table(E, target, rec || stat_record_of(E), ct_key, ct)
		return
	BOOT_PHASE_BEGIN(bp_defs)
	var/datum/stat_def/def = ct.def || stat_def_of(ct.stat_id) // resolved with the type (stat_type_build); the lookup only for an entry whose stat is undeclared
	var/declared_ok = def && stat_declared_on(target.type, def)
	BOOT_PHASE_END(bp_defs, "stat_ct_update: def lookup [ct.rel]", E)
	if(!declared_ok)
		declare_report("[ct.origin]: [declare_rule(RULE_STAT)] [E.type]: contributes_to([ct.rel], [def ? def.name : ct.stat_id]) names a stat the related [target.type] does not declare")
		return
	BOOT_PHASE_BEGIN(bp_active)
	var/gate_holds = stat_contrib_active(E, ct, gate_ctx)
	BOOT_PHASE_END(bp_active, "stat_ct_update: gate [ct.rel]", E)
	// The entry holds a row on `target` only if the record already named it (set when a row is placed, dropped when the target changes): an entry
	// that never held anything here has no row to take off, and looking for one scans every row the target holds (an area holds one per machine).
	var/held_before = (old_target == target)
	if(!gate_holds)
		if(held_before)
			BOOT_PHASE_BEGIN(bp_release)
			stat_ct_release(target, E, ct)
			BOOT_PHASE_END(bp_release, "stat_ct_update: release [ct.rel]", E)
		return
	BOOT_PHASE_BEGIN(bp_value)
	var/value = stat_contrib_value(E, def, ct)
	BOOT_PHASE_END(bp_value, "stat_ct_update: value [ct.rel]", E)
	if(stat_rule_is_boolean(def.rule) && ((def.rule == STAT_RULE_ALL && value) || (def.rule == STAT_RULE_ANY && !value)))
		if(held_before)
			stat_ct_release(target, E, ct) // the neutral direction can never change anything: no row
		return
	rec ||= stat_record_of(E)
	if(!rec.ct_targets)
		rec.ct_targets = list()
	rec.ct_targets[ct_key] = SLOT(target)
	BOOT_PHASE_BEGIN(bp_set)
	stat_row_set(target, def, E, value, ct.priority, ct.row_key, fresh = !held_before)
	BOOT_PHASE_END(bp_set, "stat_ct_update: row_set [def.name]", E)

/// A factors() entry of E: the table it names, at its scale and stacks now, held on `target` as rows of E (part = the entry's), or released while its
/// when() conditions do not hold. The exact current values every time: nothing is banded. The target hears which of its stats moved (factors_held()).
PROC_SUMMARY(/proc/stat_ct_hold_table) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_ct_hold_table(datum/E, datum/target, datum/stat_record/rec, ct_key, datum/stat_contrib/ct)
	var/alist/table = null
	var/scale = 0
	var/stacks = 1
	if(stat_contrib_active(E, ct))
		table = stat_factors_arg(E, ct.table_kind, ct.table_spec)
		scale = stat_factors_arg(E, ct.scale_kind, ct.scale_spec)
		stacks = stat_factors_arg(E, ct.stacks_kind, ct.stacks_spec)
		if(!isnum(scale) || !isnum(stacks))
			declare_report("[ct.origin]: [declare_rule(RULE_STAT)] [E.type]: factors() scale [scale] and stacks [stacks] must be numbers")
			return
	if(!rec.ct_targets)
		rec.ct_targets = list()
	rec.ct_targets[ct_key] = SLOT(target)
	var/list/before = stat_table_snapshot(target, E, ct.part, table)
	if(length(table))
		hold_table(target, E, table, scale, stacks, ct.part, ct.priority, TRUE)
	else
		release_table(target, E, ct.part)
	stat_table_moved(target, before)

/// The value now of each stat a table call for (source, part) on `target` can change: those the table names and those the source's rows already hold.
/// Pure. "[stat id]" -> value.
/proc/stat_table_snapshot(datum/target, datum/source, part, alist/table)
	var/list/ids = list()
	for(var/id in table)
		ids |= list(id)
	var/key = TABLE_KEY(part)
	for(var/list/row as anything in target.rx?.stats?.holds)
		if((row[H_FLAGS] & HF_TABLE) && row[H_SOURCE] == source && row[H_KEY] == key)
			ids |= list(row[H_STAT])
	var/list/snapshot = list()
	for(var/id in ids)
		var/datum/stat_def/def = stat_def_of(id)
		if(def)
			snapshot["[id]"] = stat_value_now(target, def, null)
	return snapshot

/// Tells `target` which of the stats in `before` (a stat_table_snapshot()) ended with another value, through factors_held().
/proc/stat_table_moved(datum/target, list/before)
	if(QDELETED(target) || !length(before))
		return
	var/list/moved = list()
	for(var/id_key in before)
		var/datum/stat_def/def = stat_def_of(text2num(id_key))
		if(def && !stat_values_equal(before[id_key], stat_value_now(target, def, null)))
			moved += text2num(id_key)
	if(length(moved))
		target.factors_held(moved)

/// One argument of a factors() entry now: its constant, the var it names, or what its holder proc returns.
PROC_SUMMARY(/proc/stat_factors_arg) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_factors_arg(datum/E, kind, spec)
	switch(kind)
		if(CV_VAR)
			return E.vars[spec]
		if(CV_PROC)
			return stat_call(E, spec)
	return spec

/// Takes E's contributes_to row for `ct` off `target` and settles the stat.
/proc/stat_ct_release(datum/target, datum/E, datum/stat_contrib/ct)
	if(QDELETED(target))
		return
	if(ct.table_kind)
		var/list/before = stat_table_snapshot(target, E, ct.part, null)
		release_table(target, E, ct.part)
		stat_table_moved(target, before)
		return
	var/datum/stat_record/trec = target.rx?.stats
	if(!trec?.holds)
		return
	var/list/row = stat_hold_find(trec, ct.stat_id, E, ct.row_key)
	if(!row)
		return
	var/datum/stat_def/def = stat_def_of(ct.stat_id)
	stat_hold_remove(target, trec, row)
	if(!stat_settle_defer(target, def))
		stat_settle_def(target, def)

/**
 * Queues the settle of `def` on `target` while an init frame runs, instead of recomputing it now: an area's demand stat is settled once per machine that
 * joins it, each time over the same rows. The rows are already placed; only the recompute (and what it moves) waits. It runs once per target and stat
 * when the frame closes or yields (stat_pending_flush_all), or earlier when anything reads a stat of the target (stat_value() settles the target's
 * queue first), so no reader sees a value a queued contribution has not reached. Only a virtual stat (one with no var of its own, read through
 * stat_value()) with no unit and no side effect of its own waits. FALSE when it did not queue: the caller settles now.
 */
/proc/stat_settle_defer(datum/target, datum/stat_def/def)
	if(def.keyed || def.units || def.id == STAT_RELEVANCE || def.id == STAT_SUSPENDED || def.id == STAT_CLOCK_RATE_BIO)
		return FALSE
	var/datum/materialization_host/host = materialization_host()
	if(!host.frame_running())
		return FALSE
	var/datum/stat_type_info/I = stat_type_of(target)
	if(!I || I.has_var[def.skey])
		return FALSE
	var/datum/stat_record/rec = stat_record_of(target)
	var/list/queue = rec.pending
	var/new_target = isnull(queue)
	if(new_target)
		queue = list()
		rec.pending = queue
		GLOB.stat_pending_slots += SLOT(target)
		GLOB.stat_deferred_targets++
	queue[def.skey] = def
	GLOB.stat_deferred++
	host.frame_note_stat_deferred(new_target)
	return TRUE

/// Settles what the init frame queued for `E`. A no-op when nothing is queued (one field read).
/proc/stat_pending_flush(datum/E)
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.pending)
		return
	var/list/queued = rec.pending
	rec.pending = null
	for(var/skey in queued)
		var/datum/stat_def/def = queued[skey]
		GLOB.stat_deferred_settles++
		if(!QDELETED(E))
			stat_settle_def(E, def)

/// Settles every queued settle: the init frame closing or yielding. A target that is gone is dropped. Returns how many targets it settled.
/proc/stat_pending_flush_all()
	var/list/slots = GLOB.stat_pending_slots
	if(!length(slots))
		return 0
	GLOB.stat_pending_slots = list()
	for(var/slot in slots)
		var/datum/E = slot_datum(slot)
		if(!isdatum(E) || !E.rx?.stats?.pending)
			continue
		stat_pending_flush(E)
		. += 1

/// Places (or updates) an untimed keyed row without the hold() checks: the contribution engine's own writes. Settles the stat inline.
/// `fresh`: the caller knows `source` holds no row of this stat and key on `target` (a contribution that never held one there): the row is added without
/// the find, which scans every row of the stat the target holds (an area holds one per machine, so a map load's power joins were quadratic per area).
/proc/stat_row_set(datum/target, datum/stat_def/def, source, value, priority, key, fresh = FALSE)
	var/datum/stat_record/rec = stat_record_of(target)
	BOOT_PHASE_BEGIN(bp_find)
	var/list/row = fresh ? null : stat_hold_find(rec, def.id, source, key)
	BOOT_PHASE_END(bp_find, "stat_row_set: hold_find [def.name]", target)
	if(row)
		if(stat_values_equal(row[H_VALUE], value) && row[H_PRIORITY] == priority)
			return
		var/old_value = row[H_VALUE]
		row[H_VALUE] = value
		row[H_PRIORITY] = priority
		// The running total follows the one row that moved (a value it cannot hold drops it).
		var/list/cache = rec.sum_cache?["[def.id]"]
		if(cache)
			if(stat_sum_row_ok(row) && cache[1] - old_value + value < STAT_SUM_LIMIT)
				cache[1] += value - old_value
			else
				rec.sum_cache -= "[def.id]"
	else
		row = list(def.id, source, value, 0, priority, 0, HOLD_CLOCK_OWN, null, ++GLOB.stat_hold_serial, key, null)
		stat_rows_add(rec, row)
		if(isdatum(source))
			var/datum/stat_record/src_rec = stat_record_of(source)
			LAZYOR(src_rec.held_on, SLOT(target))
	BOOT_PHASE_BEGIN(bp_settle)
	if(!stat_settle_defer(target, def))
		stat_settle_def(target, def)
	BOOT_PHASE_END(bp_settle, "stat_row_set: settle [def.name]", target)

/// A contributes_to entity's relation var was written: its contribution moves to the new target and leaves the old one.
/proc/stat_relation_changed(datum/E, var_name)
	var/datum/stat_type_info/I = stat_type_of(E)
	if(!I)
		return
	if(I.hop_rels && (var_name in I.hop_rels))
		BOOT_PHASE_BEGIN(bp_hop)
		stat_hop_attach(E, var_name)
		BOOT_PHASE_END(bp_hop, "stat_relation_changed: hop_attach [var_name]", E)
	// The entries on one relation (a machine's three channel draws) are gated one after another: one evaluation context serves them all.
	var/datum/act/op/gate_ctx = null
	BOOT_PHASE_BEGIN(bp_loop)
	try
		for(var/datum/stat_contrib/ct as anything in I.ct_entries)
			if(ct.rel == var_name)
				if(!gate_ctx && length(ct.whens))
					BOOT_PHASE_BEGIN(bp_ctx)
					gate_ctx = pooled_op_context(E)
					BOOT_PHASE_END(bp_ctx, "stat_relation_changed: pooled ctx take [var_name]", E)
				BOOT_PHASE_BEGIN(bp_ct)
				stat_ct_update(E, ct, gate_ctx)
				BOOT_PHASE_END(bp_ct, "stat_relation_changed: ct_update [var_name]", E)
	catch(var/exception/fault)
		gate_ctx?.release()
		throw fault
	BOOT_PHASE_BEGIN(bp_rel_ctx)
	gate_ctx?.release()
	BOOT_PHASE_END(bp_rel_ctx, "stat_relation_changed: pooled ctx release [var_name]", E)
	BOOT_PHASE_END(bp_loop, "stat_relation_changed: ct loop [var_name]", E)

// ---- the marked queue ----

/// Flags a stat of an entity for the next marked drain. Nothing is evaluated now: the write that reached it pays one list add.
/proc/stat_mark(datum/E, datum/stat_def/def)
	var/datum/stat_record/rec = stat_record_of(E)
	if(!rec.marked)
		rec.marked = list()
	if(rec.marked[def.skey])
		return
	rec.marked[def.skey] = TRUE
	GLOB.stat_marked += list(list(SLOT(E), def, null))

/// Flags a contributes_to entry for the next marked drain.
/proc/stat_mark_ct(datum/E, datum/stat_contrib/ct)
	var/datum/stat_record/rec = stat_record_of(E)
	if(!rec.marked)
		rec.marked = list()
	var/mark_key = ct.row_key
	if(rec.marked[mark_key])
		return
	rec.marked[mark_key] = TRUE
	GLOB.stat_marked += list(list(SLOT(E), null, ct))

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
		var/list/batch = stat_sort_marked(GLOB.stat_marked, min(GLOB.stat_marked_sorted, length(GLOB.stat_marked)))
		GLOB.stat_marked = list()
		GLOB.stat_marked_sorted = 0
		for(var/i in 1 to length(batch))
			var/list/row = batch[i]
			var/datum/E = slot_datum(row[1])
			var/datum/stat_def/def = row[2]
			var/datum/stat_contrib/ct = row[3]
			if(QDELETED(E))
				continue
			// The first evaluation of a pass always runs (a budget smaller than one evaluation still makes progress).
			if(spent && spent + STAT_EVAL_CHARGE > budget)
				var/list/rest = batch.Copy(i)
				GLOB.stat_marked = rest + GLOB.stat_marked
				GLOB.stat_marked_sorted = length(rest) // already in rank order: the next drain sorts only what was marked after it and merges
				GLOB.stat_spills++
				TEST_REC_SPILL("[lane]:[def ? def.name : "ct"] x[length(rest)] at pass [passes]")
				drain_spill_log("stats lane [lane]", "STATS: marked drain on lane [lane] spent its budget of [budget]us; [length(rest)] evaluation\s resume at the next drain (first: [E.type] [def ? def.name : "contributes_to"])")
				return
			var/datum/stat_record/rec = E.rx?.stats
			if(rec?.marked)
				rec.marked -= def ? def.skey : ct.row_key
			var/started = stat_charge_begin()
			var/eval_started = TICK_USAGE
			var/eval_ledger = km_ledger_enter(KM_CAT_STAT_EVAL, E.type, def ? def.name : "contributes_to")
			if(ct)
				stat_ct_update(E, ct)
			else
				stat_settle_def(E, def)
			km_ledger_leave(eval_ledger)
			KM_SLOW_INNER(eval_started, "stat [E.type] [def ? def.name : "contributes_to"]")
			.++
			spent += stat_charge_end(started)
			GLOB.stat_tick_spent = spent
	if(length(GLOB.stat_marked) && passes >= DRAIN_MAX_PASSES)
		GLOB.stat_spills++
		TEST_REC_SPILL("[lane]: [length(GLOB.stat_marked)] marked evaluations past [DRAIN_MAX_PASSES] passes")
		log_world("STATS: marked drain stopped after [DRAIN_MAX_PASSES] passes with [length(GLOB.stat_marked)] still marked; the rest spills to the next drain point")

/// How many rows at the head of GLOB.stat_marked are a spilled drain's rest, already in rank order (stat_drain_marked()).
GLOBAL_VAR_INIT(stat_marked_sorted, 0)

/// The rank a marked row recomputes at (the entity's own type's rank of the stat; 0 for a contribution or a gone entity), kept on the row as its
/// 4th element once asked.
/proc/stat_marked_rank(list/row)
	if(length(row) >= 4)
		return row[4]
	var/rank = 0
	var/datum/stat_def/def = row[2]
	if(def)
		var/datum/E = slot_datum(row[1])
		if(!QDELETED(E))
			var/datum/stat_type_info/I = stat_type_of(E)
			rank = I?.ranks?[def.skey] || 0
	row += rank
	return rank

/// The batch in rank order (the entity's own type's rank of the stat), first marked first among equals. Its first `sorted` rows are already in that
/// order (a spilled drain's rest): only the rows after them are sorted, and the two runs merged, so a backlog is not sorted again at every drain point.
/proc/stat_sort_marked(list/batch, sorted = 0)
	if(sorted >= length(batch))
		return batch
	var/list/tail = sorted ? batch.Copy(sorted + 1) : batch
	// Stable bucket sort of the tail: one bucket per rank, filled in batch order, emitted by ascending rank.
	var/list/buckets = list() // "[rank]" -> rows in batch order
	var/list/ranks = list()
	for(var/list/row as anything in tail)
		var/rank = stat_marked_rank(row)
		var/key = "[rank]"
		var/list/bucket = buckets[key]
		if(!bucket)
			bucket = list()
			buckets[key] = bucket
			ranks += rank
		bucket += list(row)
	var/list/rows
	if(length(ranks) == 1)
		rows = buckets[buckets[1]]
	else
		sortTim(ranks, GLOBAL_PROC_REF(cmp_numeric_asc))
		rows = list()
		for(var/rank in ranks)
			rows += buckets["[rank]"]
	if(!sorted)
		return rows
	// Merge: the backlog's rows come first among equal ranks (they were marked first).
	var/list/merged = list()
	var/i = 1
	var/j = 1
	var/n_tail = length(rows)
	while(i <= sorted && j <= n_tail)
		if(stat_marked_rank(rows[j]) < stat_marked_rank(batch[i]))
			merged += list(rows[j++])
		else
			merged += list(batch[i++])
	while(i <= sorted)
		merged += list(batch[i++])
	while(j <= n_tail)
		merged += list(rows[j++])
	return merged

/// The kernel's drain point (the start of phases D, P and R): the marked stats recompute under the simulation lane's budget. Costs one list length
/// when nothing is marked. While a map loads (a load frame is open, even one suspended between chunks) it does nothing: initial evaluation is
/// silent until the load completes, and the load's own settling drain (SSatoms.initialize_atoms_finish()) then runs what is owed, once.
/proc/stat_drain_point()
	if(materialization_host().map_loading())
		return
	var/act_started = TICK_USAGE
	act_drain_point(FALSE) // the notices queued past the depth cap and the marked on_change hooks (code/engine/actions)
	KM_SLOW_INNER(act_started, "act_drain_point (late notices and on_change hooks)")
	// The stats a pass settles publish their changes, which mark on_change hooks (a machine's has_power flip, its power_change()): those run in
	// the same drain, and what they mark is settled after them, so a tracked write reaches its readers' reactions in one drain, not the next.
	var/passes = 0
	while(length(GLOB.stat_marked) && passes < DRAIN_MAX_PASSES)
		passes++
		var/spills = GLOB.stat_spills
		var/marked_started = TICK_USAGE
		stat_drain_marked(LANE_SIMULATION, FALSE)
		KM_SLOW_INNER(marked_started, "stat_drain_marked pass [passes]")
		act_started = TICK_USAGE
		act_drain_point(FALSE)
		KM_SLOW_INNER(act_started, "act_drain_point after pass [passes]")
		if(GLOB.stat_spills != spills)
			break // the lane's budget is spent: the rest resumes at the next drain

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
PROC_SUMMARY(/proc/stat_hop_attach) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/stat_hop_attach(datum/E, rel_var)
	var/datum/stat_record/rec = stat_record_of(E)
	var/datum/old = slot_datum(rec.hop_targets?[rel_var])
	var/datum/target = hop_step(E, rel_var)
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
	rec.hop_targets[rel_var] = SLOT(target)
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
		var/datum/target = slot_datum(rec.hop_targets[rel_var])
		if(target && !QDELETED(target))
			stat_hop_leave(D, target, rel_var)
	rec.hop_targets = null
	for(var/rel_var in rec.hop_in)
		for(var/datum/reader as anything in rec.hop_in[rel_var])
			var/datum/stat_record/rrec = reader.rx?.stats
			if(rrec?.hop_targets && rrec.hop_targets[rel_var] == SLOT_KNOWN(D))
				rrec.hop_targets -= rel_var
				if(!length(rrec.hop_targets))
					rrec.hop_targets = null
	rec.hop_in = null

// ---- the template census (stat_templates.md; -params bench_stat_template_census=1) ----

/// TRUE measures the init stat computes and which of them a per-type template could serve. Off unless the world asks.
GLOBAL_VAR_INIT(stat_template_census, FALSE)
/// "eligible" / "ineligible" -> list(instances, tick-usage percent spent); and per eligible type -> list(instances, percent).
GLOBAL_LIST_EMPTY(stat_template_census_rows)

/// TRUE when type I's init computes read nothing outside the instance: no hop, no system, no contributes_to across a relation, no read through a
/// relation ("x.y") and no capability key (stat_templates.md, "When an instance may take the template").
/proc/stat_template_type_eligible(datum/stat_type_info/I)
	var/static/list/verdicts = list()
	if(!isnull(verdicts[I.owner_type]))
		return verdicts[I.owner_type]
	. = TRUE
	if(length(I.hop_rels) || length(I.hops) || length(I.ct_entries) || length(I.untracked))
		. = FALSE
	else
		for(var/skey in I.contribs)
			for(var/datum/stat_contrib/C as anything in I.contribs[skey])
				if(C.value_kind == CV_CAPKEY)
					. = FALSE
				for(var/read in C.reads)
					if(findtext("[read]", ".") || findtext("[read]", "capkey"))
						. = FALSE
	verdicts[I.owner_type] = .

/// One instance's init computes: time and whether a template could have served it (type eligible, no map-edited stat constant, no own value on an input).
/proc/stat_template_census_note(datum/E, datum/stat_type_info/I, datum/stat_record/rec, start)
	var/spent = TICK_USAGE_REAL - start
	if(spent < 0)
		spent = 0 // the computes crossed a tick: not counted as time, still counted as an instance
	var/eligible = stat_template_type_eligible(I) && !rec.constants
	if(eligible)
		for(var/key in I.inputs)
			if(istext(key) && (key in E.vars) && E.vars[key] != initial(E.vars[key]))
				eligible = FALSE
				break
	var/bucket = eligible ? "eligible" : "ineligible"
	var/list/row = GLOB.stat_template_census_rows[bucket] || list(0, 0)
	row[1]++
	row[2] += spent
	GLOB.stat_template_census_rows[bucket] = row
	if(eligible)
		var/type_key = "[E.type]"
		var/list/type_row = GLOB.stat_template_census_rows[type_key] || list(0, 0)
		type_row[1]++
		type_row[2] += spent
		GLOB.stat_template_census_rows[type_key] = type_row

/proc/stat_template_census_report()
	for(var/bucket in list("eligible", "ineligible"))
		var/list/row = GLOB.stat_template_census_rows[bucket] || list(0, 0)
		log_world("STAT TEMPLATE CENSUS: [bucket]: [row[1]] instance(s), [round(row[2], 0.1)]% of a tick in total")
	var/list/types = list()
	for(var/key in GLOB.stat_template_census_rows)
		if(key != "eligible" && key != "ineligible")
			var/list/type_row = GLOB.stat_template_census_rows[key]
			types[key] = type_row[2]
	var/list/sorted = sortTim(types, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	var/shown = 0
	for(var/key in sorted)
		var/list/type_row = GLOB.stat_template_census_rows[key]
		log_world("STAT TEMPLATE CENSUS: [key]: [type_row[1]] instance(s), [round(type_row[2], 0.1)]%")
		if(++shown >= 25)
			break

// ---- per-type templates of the init computes (stat_templates.md) ----

/// type -> the values its template-eligible instances end their init computes with, parallel to the type's init_todo.
GLOBAL_LIST_EMPTY(stat_templates)
/// Instances whose init computes a template served.
GLOBAL_VAR_INIT(stat_templates_served, 0)
#if defined(UNIT_TESTS)
/// type -> how many of its instances computed both ways (the parity check).
GLOBAL_LIST_EMPTY(stat_template_checked)
#endif

/// TRUE when E's init computes may be served by its type's template: the type reads nothing outside the instance, every stat it computes is a plain
/// var of a fast rule, the instance holds nothing yet and every input var is at the type's default.
/proc/stat_template_instance_ok(datum/E, datum/stat_type_info/I, datum/stat_record/rec, list/todo)
	if(rec.holds || rec.by_stat || rec.virtual || !stat_template_type_eligible(I) || !stat_template_defs_ok(I, todo))
		return FALSE
	for(var/key in I.inputs)
		if(!istext(key) || !(key in E.vars))
			return FALSE
		var/value = E.vars[key]
		if(value != initial(E.vars[key]) || islist(value))
			return FALSE
	return TRUE

/// TRUE when every stat of `todo` is computed by a fast rule (no formula, no keyed stat, no status), so the template is the values it ends with.
/proc/stat_template_defs_ok(datum/stat_type_info/I, list/todo)
	var/static/list/verdicts = list()
	var/known = verdicts[I.owner_type]
	if(!isnull(known))
		return known
	. = length(todo) > 0
	for(var/datum/stat_def/def as anything in todo)
		if(!def.fast || def.is_formula || def.keyed || def.units || def.id == STAT_RELEVANCE || def.id == STAT_SUSPENDED || def.id == STAT_CLOCK_RATE_BIO)
			. = FALSE
			break
	verdicts[I.owner_type] = .

/// The values E's stats of `todo` hold now, in order: a var's value, or a virtual stat's stored value (STAT_TEMPLATE_UNSTORED when none was stored).
/// Null when one is a list (the type is not templated).
/proc/stat_template_values(datum/E, datum/stat_type_info/I, list/todo)
	. = list()
	var/list/virtual = E.rx?.stats?.virtual
	for(var/datum/stat_def/def as anything in todo)
		var/value
		if(I.has_var[def.skey])
			value = E.vars[def.name]
		else
			value = (virtual && (def.skey in virtual)) ? virtual[def.skey] : STAT_TEMPLATE_UNSTORED
		if(islist(value))
			return null
		. += value

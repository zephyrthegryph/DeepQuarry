// on_change: an edge trigger on a condition, or a change of a key's value (doc/rewrite/final_api.html, section 10 "After hooks"; section 19 "E4").
//
//	on_change(PROC_REF(is_powered), ENTER | EXIT, then(PROC_REF(power_flipped)))   // replaces a power_change() override
//	on_change(nameof(charge), ANY, then(PROC_REF(charge_changed)))                 // a key: fires when its value changed
//
// The condition or key is evaluated at the drain (act_drain_point(): the start of the kernel's D, P and R phases), and the parts run there, once
// per drain however many of its reads changed. A condition's edge is ENTER (became true) or EXIT (became false); ANY (= ENTER | EXIT) on a key
// compares values. Reads: a var name, a stat id (both its var and its stat key), a capability state key, cond_not/all/any of those, or a
// proc of the holder x(datum/act/A) whose own-var reads E5 generated. A read through a relation hop (nameof(terminal.charge)) watches the relation
// var itself; the far var's own change reaches it when the relation is rewritten (E3's hop reverse index serves stats, not these hooks).
//
// A type's own on_change entries watch through the compiled table (rx_readers() asks hooks_watching()); an activation's watch its holder as dynamic
// readers (rx_watch_adjust()) and end with the activation. The baseline (the value before the first change) is taken when the holder initializes
// or the activation attaches, silently.


GLOBAL_LIST_EMPTY(change_index_by_type) // instance type -> (key -> list of /datum/hook), or FALSE for a type with no on_change
GLOBAL_LIST_EMPTY(hook_change_pending) // holder -> list(hook -> TRUE), in the order first marked

/datum/rx_state
	/// hook serial -> the value its last evaluation saw (a boolean for an edge, the raw value for ANY).
	var/list/change_last

/// on_change(cond, ENTER | EXIT | ANY, parts...). The legacy form takes a list of reads and a handler.
/proc/on_change(cond, edge, ENTRY_SLOTS, at_most = 0, when = null)
	if(!isnum(edge))
		return legacy_on_change(cond, edge, at_most, when)
	return entry_make(ENTRY_ON_CHANGE, null, list("cond" = cond, "edge" = edge), entry_flatten(ENTRY_SLOT_LIST))

/// The keys whose publication means `cond` may have changed, for holder E.
/proc/change_read_keys(datum/E, cond)
	. = list()
	if(islist(cond))
		var/list/tree = cond
		for(var/i in 2 to length(tree))
			. |= change_read_keys(E, tree[i])
		return
	if(isnum(cond))
		var/datum/stat_def/def = stat_def_of(cond)
		if(def)
			return list(def.name, def.stat_key)
		if(cond >= CAPKEY_ID_BASE)
			return list("capkey:[cond]")
		return
	if(!istext(cond))
		return
	if(findtext(cond, "."))
		return list(copytext(cond, 1, findtext(cond, ".")))
	if(cond in E.vars)
		return list(cond)
	for(var/read in stat_generated_reads(E, cond))
		if(!findtext(read, ".") && !findtext(read, ":"))
			. |= read

/// The value the hook's condition or key has on E now: a boolean for an edge hook, the raw value for ANY.
/proc/change_value(datum/E, datum/hook/H)
	var/cond = H.entry.args["cond"]
	var/edge = H.entry.args["edge"]
	if(edge != ANY)
		return !!change_condition(E, cond)
	if(islist(cond))
		return !!change_condition(E, cond)
	if(isnum(cond))
		return stat_def_of(cond) ? stat_value(E, cond) : cap_key_get(E, cond)
	if(istext(cond))
		if(findtext(cond, "."))
			return change_walk(E, cond)
		if(cond in E.vars)
			return E.vars[cond] // ALLOW(api): on_change names a var of the holder by its declared key
	return change_condition(E, cond)

/// A condition (a var, an id, a tree, a proc of the holder) evaluated now. A proc gets a pooled eval context.
/proc/change_condition(datum/E, cond)
	if(istext(cond) && !(cond in E.vars) && !findtext(cond, "."))
		var/datum/act/eval/A = take(/datum/act/eval)
		A.holder = E // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		. = call(E, cond)(A)
		A.release()
		return
	if(istext(cond) && findtext(cond, "."))
		return change_walk(E, cond)
	return condition_holds(E, cond)

/// "terminal.charge": the value at the end of a path of relation vars.
/proc/change_walk(datum/E, path)
	var/list/segments = splittext(path, ".")
	var/walk = E
	for(var/segment in segments)
		if(!isdatum(walk))
			return null
		var/datum/D = walk
		walk = D.vars[segment] // ALLOW(api): on_change names a path of relation vars by their declared keys
	return walk

// ---- registration ----

/// The static change index of E's type: key -> hooks. FALSE when the type declares no on_change.
/proc/change_index_of(datum/E)
	var/known = GLOB.change_index_by_type[E.type]
	if(!isnull(known))
		return known
	var/datum/type_table/T = table_of(E)
	if(T == table_empty())
		return FALSE // the globals are still being built: nothing is declared yet, nothing is cached
	var/list/index = list()
	for(var/datum/hook/H as anything in hook_table_of(T))
		if(H.kind != HOOK_CHANGE)
			continue
		H.reads = change_read_keys(E, H.entry.args["cond"]) // ALLOW(ownership): compiled once per type and never rewritten
		for(var/key in H.reads)
			LAZYADD(index[key], H)
	GLOB.change_index_by_type[E.type] = length(index) ? index : FALSE
	return GLOB.change_index_by_type[E.type]

/// TRUE when a type-level on_change of E's type reads `key` (rx_readers() asks, so changed() publishes it).
/proc/hooks_watching(datum/E, key)
	if(!islist(GLOB?.change_index_by_type))
		return FALSE
	var/index = GLOB.change_index_by_type[E.type]
	if(isnull(index))
		index = change_index_of(E)
	return index ? !!index[key] : FALSE

/// `key` of E was published: the on_change hooks that read it are marked for the next drain point.
/proc/hooks_change_published(datum/E, key)
	var/index = GLOB.change_index_by_type[E.type]
	if(isnull(index))
		index = change_index_of(E)
	if(index)
		for(var/datum/hook/H as anything in index[key])
			hook_change_pend(E, H)
	for(var/datum/hook/H as anything in E.rx?.hooks)
		if(H.kind == HOOK_CHANGE && (key in H.reads) && H.activation && !H.activation.dead && H.activation.runs)
			hook_change_pend(E, H)

/proc/hook_change_pend(datum/E, datum/hook/H)
	var/list/per = GLOB.hook_change_pending[E]
	if(!per)
		per = list()
		GLOB.hook_change_pending[E] = per
	per[H] = TRUE

/// Takes the baseline of E's type-level on_change hooks (called when the holder initializes), silently.
/proc/hooks_change_baseline(datum/E)
	var/index = change_index_of(E)
	if(!index)
		return
	for(var/key in index)
		for(var/datum/hook/H as anything in index[key])
			LAZYSET(rx_of(E).change_last, "[H.serial]", change_value(E, H))

/// The drain: each marked (holder, hook) is evaluated once; an edge or a changed value runs the hook's parts.
/proc/hooks_drain_changes()
	var/passes = 0
	while(length(GLOB.hook_change_pending) && passes < DRAIN_MAX_PASSES)
		passes++
		var/list/batch = GLOB.hook_change_pending
		GLOB.hook_change_pending = list()
		for(var/datum/E as anything in batch)
			if(QDELETED(E))
				continue
			for(var/datum/hook/H as anything in batch[E])
				if(H.activation && (H.activation.dead || !H.activation.runs))
					continue
				if(!hook_conditions_hold(H, E))
					continue
				hook_change_eval(E, H)

/proc/hook_change_eval(datum/E, datum/hook/H)
	var/datum/rx_state/rx = rx_of(E)
	var/id = "[H.serial]"
	var/now = change_value(E, H)
	var/had = (id in rx.change_last)
	var/last = rx.change_last?[id]
	LAZYSET(rx.change_last, id, now)
	var/edge = H.entry.args["edge"]
	var/fire = FALSE
	if(edge == ANY)
		fire = !had || last != now
	else if(edge & ENTER)
		fire = now && (!had || !last)
	else if(edge & EXIT)
		fire = !now && (!had || last)
	if(!fire)
		return
	var/datum/act/notice/A = take(/datum/act/notice)
	A.holder = E // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.target = E // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.outcome = ACT_COMMITTED
	hook_context(A, H)
	var/depth = GLOB.act_depth
	GLOB.act_chain += "on_change:[E.type]"
	try
		hook_run_parts(H, A, H.entry.children)
	catch(var/exception/e)
		stack_trace("on_change hook on [E.type]: [e] ([e.file]:[e.line])")
	GLOB.act_depth = depth
	GLOB.act_chain.len--
	A.release()

// ---- the entry engine ----

/datum/entry_engine/hook_change
	kind = ENTRY_ON_CHANGE

/datum/entry_engine/hook_change/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	var/datum/hook/H = hook_change_make(A, E, C)
	var/datum/rx_state/rx = rx_of(A.holder)
	H.reads = change_read_keys(A.holder, E.args["cond"]) // ALLOW(ownership): compiled when the activation attaches
	LAZYADD(rx.hooks, H) // ALLOW(ownership): an engine record the one teardown path drops
	for(var/key in H.reads)
		rx_watch_adjust(A.holder, key, 1)
	LAZYSET(rx.change_last, "[H.serial]", change_value(A.holder, H))
	return TRUE

/datum/entry_engine/hook_change/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(!holder?.rx?.hooks)
		return
	for(var/datum/hook/H as anything in holder.rx.hooks.Copy())
		if(H.activation != A || H.source_entry != E)
			continue
		holder.rx.hooks -= H
		for(var/key in H.reads)
			rx_watch_adjust(holder, key, -1)
		holder.rx.change_last?.Remove("[H.serial]")
		H.activation = null
	if(!length(holder.rx.hooks))
		holder.rx.hooks = null

/proc/hook_change_make(datum/activation/A, datum/entry/E, datum/centry/C)
	var/datum/hook/H = hook_make(HOOK_CHANGE, null, E, E, C, A, 1000000 + A.serial * 1000 + ++GLOB.hook_serial % 1000)
	return H

/datum/hook
	/// on_change: the keys whose publication re-evaluates it.
	var/list/reads

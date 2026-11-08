// on_change: an edge trigger on a condition, or a change of a key's value (doc/rewrite/final_api.html, section 10 "After hooks"; section 19 "E4").
//
//	on_change(PROC_REF(is_powered), ENTER | EXIT, then(PROC_REF(power_flipped)))   // replaces a power_change() override
//	on_change(nameof(charge), ANY, then(PROC_REF(charge_changed)))                 // a key: fires when its value changed
//	on_change(cond_published(MOB_KEY_STATUS, nameof(stat)), ANY, then(PROC_REF(x))) // an event: fires each time one of its keys is published
//
// The condition or key is evaluated at the drain (act_drain_point(): the start of the kernel's D, P and R phases), and the parts run there, once
// per drain however many of its reads changed. A condition's edge is ENTER (became true) or EXIT (became false); ANY (= ENTER | EXIT) on a key
// compares values. Reads: a var name, a stat id (both its var and its stat key), a capability state key, not/all_of/any_of of those, or a
// proc of the holder x(datum/act/A) whose own-var reads E5 generated. A read through a relation hop (nameof(terminal.charge)) watches the relation
// var itself (rewriting it re-reads the far end) AND the far var's own changes: a hop path registers its last segment in GLOB.change_hop_keys, so a
// write of that var on any entity is published, and hooks_change_hop_published() walks the relations back along the path to the entities that read
// it (the same reverse walk the stat layer's hops use) and marks their hooks.
//
// A published-key condition (cond_published(), relations.dm) is for the keys that are not one var's value: a producer's PUBLISH_CHANGE(E, key)
// (a mob's MOB_KEY_* facts), and the vars that stand beside them. There is no value to compare, so ANY is its only edge and the parts run once per
// drain after any of its keys was published. The reads the generator found for the hook's handler (reaction_reads(), derived_reads_lint) join its keys.
//
// A type's own on_change entries watch through the compiled table (rx_readers() asks hooks_watching()); an activation's watch its holder as dynamic
// readers (rx_watch_adjust()) and end with the activation. The baseline (the value before the first change) is taken when the holder initializes
// or the activation attaches, silently.


GLOBAL_LIST_EMPTY(change_index_by_type) // instance type -> (key -> list of /datum/hook), or FALSE for a type with no on_change
GLOBAL_ALIST(hook_change_pending) // holder's handle (handle_of) -> list(hook -> TRUE), in the order first marked. Null while nothing is marked: test the var, never length() (an alist's length counts its keys)
GLOBAL_LIST_EMPTY(change_hop_keys) // far var name -> (hop path text -> number of hooks reading it): the keys whose writes on any entity may matter

/datum/rx_state
	/// hook serial -> the value its last evaluation saw (a boolean for an edge, the raw value for ANY).
	var/list/change_last

/// on_change(cond, ENTER | EXIT | ANY, parts...). The legacy form takes a list of reads and a handler.
/proc/on_change(cond, edge, ENTRY_SLOTS, at_most = 0, when = null)
	if(!isnum(edge))
		if(isnull(edge))
			declare_report("on_change([cond]): no edge and no handler: it would never do anything")
			return null
		return reaction_on_change(cond, edge, at_most, when)
	if(change_is_published(cond) && edge != ANY)
		declare_report("on_change(cond_published(...)): a published key has no value to compare, so its edge is ANY")
		return null
	var/list/parts = entry_flatten(ENTRY_SLOT_LIST)
	if(!length(parts))
		declare_report("on_change([cond]): no parts: it would never do anything; give it then(PROC_REF(x))")
		return null
	return entry_make(ENTRY_ON_CHANGE, null, list("cond" = cond, "edge" = edge), parts)

/// TRUE for a cond_published() condition: the hook runs when one of its keys is published, with no value to compare.
/proc/change_is_published(cond)
	return islist(cond) && length(cond) && cond[1] == COND_PUBLISHED

/// The keys whose publication means `cond` may have changed, for holder E.
PROC_SUMMARY(/proc/change_read_keys) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/change_read_keys(datum/E, cond, datum/act/A = null, datum/lookup_read_scope/scope = null)
	. = list()
	if(change_is_published(cond))
		var/list/keys = cond
		for(var/i in 2 to length(keys))
			if(istext(keys[i]))
				. |= list(keys[i])
		return
	if(islist(cond))
		var/list/tree = cond
		for(var/i in 2 to length(tree))
			. |= change_read_keys(E, tree[i], A, scope)
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
	// What the holder's type alone decides (a var of that name, a tracked setter, the build's read table) is worked out once per (type, name):
	// a menu asks it for every condition of every candidate, and `in vars` walks the holder's whole var list.
	var/list/typed = CACHED_KEY(change_text_read_keys, "[E.type]|[cond]", E, cond)
	if(typed[1])
		return list(cond)
	. |= typed[2]
	for(var/read in lookup_reads_for(E, cond, A, scope))
		if(change_read_key_kept(read))
			. |= read

/// The type half of change_read_keys() for a text condition: list(it is a var of the type, the keys its setter and its generated reads give).
DECLARE_SHARED_CACHE(change_text_read_keys, GLOBAL_PROC_REF(build_change_text_read_keys), SC_NEVER)

/proc/build_change_text_read_keys(datum/E, cond)
	if(cond in E.vars)
		return list(TRUE, list())
	var/list/keys = list()
	if(hascall(E, "__setter_[cond]"))
		keys |= list(cond)
	for(var/read in stat_generated_table_reads(E.type, cond))
		if(change_read_key_kept(read))
			keys |= read
	return list(FALSE, keys)

/// Whether a generated read is a key of the holder itself (not a hop through another entity, not a namespaced key other than a capability key).
/proc/change_read_key_kept(read)
	return !findtext(read, ".") && (!findtext(read, ":") || findtext(read, "capkey:") == 1)

/// The value the hook's condition or key has on E now: a boolean for an edge hook, the raw value for ANY.
/proc/change_value(datum/E, datum/hook/H)
	var/cond = H.entry.args["cond"]
	var/edge = H.entry.args["edge"]
	if(change_is_published(cond))
		return TRUE // an event has no value: every drain that reaches it runs it (hook_change_eval)
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
			return E.vars[cond]
	return change_condition(E, cond)

/// A condition (a var, an id, a tree, a proc of the holder) evaluated now. A proc gets a pooled eval context.
PROC_SUMMARY(/proc/change_condition) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/change_condition(datum/E, cond)
	if(istext(cond) && !(cond in E.vars) && !findtext(cond, "."))
		var/datum/act/eval/A = take(/datum/act/eval)
		A.holder = E // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		. = op_pure_call(E, cond, A)
		A.release()
		return
	if(istext(cond) && findtext(cond, "."))
		return change_walk(E, cond)
	return condition_holds(E, cond)

/// "terminal.charge": the value at the end of a path of hops (relation vars, `loc`, the turf and area hops: hop_step(), refs/hops.dm); null where
/// the far end lacks the var.
PROC_SUMMARY(/proc/change_walk) // vars[] / call() dispatcher: the walk cannot enter it; what it reaches is declared by the handlers it dispatches
/proc/change_walk(datum/E, path)
	var/list/segments = splittext(path, ".")
	var/walk = E
	for(var/segment in segments)
		if(!isdatum(walk))
			return null
		walk = hop_step(walk, segment)
	return walk

// ---- registration ----

/// The static change index of E's type: key -> hooks. FALSE when the type declares no on_change.
/proc/change_index_of(datum/E)
	if(!GLOB.change_index_by_type)
		return FALSE // the globals are still being built
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
		H.reads = change_read_keys(E, H.entry.args["cond"])
		for(var/key in H.reads)
			LAZYADD(index[key], H)
		if(change_is_published(H.entry.args["cond"]))
			// What the generator found its handler reads (a var, a relation, a published key) wakes it too, for this type only: the index is the type's, H.reads stays the declared keys.
			for(var/key in change_generated_reads(E, H))
				LAZYINITLIST(index[key])
				index[key] |= H
		change_hop_register(H.entry.args["cond"])
	GLOB.change_index_by_type[E.type] = length(index) ? index : FALSE
	return GLOB.change_index_by_type[E.type]

/// The reads the generator recorded for the handler of published hook H on E's type (reaction_reads() entries of generated_reads()): keys.
/proc/change_generated_reads(datum/E, datum/hook/H)
	. = list()
	var/list/handlers = list()
	for(var/datum/entry/part in H.entry.children)
		if(part.kind == ENTRY_THEN)
			handlers += part.args["handler"]
	if(!length(handlers))
		return
	for(var/datum/derived_entry/D in type_list(E, TYPE_PROC_REF(/datum, generated_reads)))
		if(D.kind != DKIND_REACTION || !(D.name in handlers))
			continue
		for(var/read in D.reads)
			if(istext(read))
				. |= list(read)

/// TRUE when a published on_change hook of E's type has `handler` as its then() (the reads the generator found for it feed that hook, not the legacy
/// reaction table).
/proc/change_handler_declared(datum/E, handler)
	var/datum/type_table/T = table_of(E)
	if(T == table_empty())
		return TRUE // the declarations are still being built: nothing can be said yet
	for(var/datum/hook/H as anything in hook_table_of(T))
		if(H.kind != HOOK_CHANGE || !change_is_published(H.entry.args["cond"]))
			continue
		for(var/datum/entry/part in H.entry.children)
			if(part.kind == ENTRY_THEN && part.args["handler"] == handler)
				return TRUE
	return FALSE

/// A hook reads `cond`: when it is a hop path ("terminal.charge"), its last segment becomes a key whose writes are published everywhere.
/proc/change_hop_register(cond, delta = 1)
	if(!istext(cond))
		return
	var/dot = findtext(cond, ".")
	if(!dot)
		return
	var/last = copytext(cond, findlasttext(cond, ".") + 1)
	var/list/paths = GLOB.change_hop_keys[last]
	if(!paths)
		if(delta < 0)
			return
		paths = list()
		GLOB.change_hop_keys[last] = paths
	var/count = (paths[cond] || 0) + delta
	if(count > 0)
		paths[cond] = count
	else
		paths -= cond
		if(!length(paths))
			GLOB.change_hop_keys -= last

/// TRUE when a type-level on_change of E's type reads `key` (rx_readers() asks, so state_changed() publishes it).
/proc/hooks_watching(datum/E, key)
	if(!islist(GLOB?.change_index_by_type))
		return FALSE
	if(GLOB.change_hop_keys[key])
		return TRUE // some hook reads this var on the far end of a relation
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
	if(GLOB.change_hop_keys[key])
		hooks_change_hop_published(E, key)

/// `key` of E, the far end of a hop path some hook reads, was published: the entities that reach E along such a path are found by walking the
/// relations back (rel_sources), and each one's hooks that read that path are marked for the next drain point.
/proc/hooks_change_hop_published(datum/E, key)
	for(var/path_text in GLOB.change_hop_keys[key])
		var/list/path = splittext(path_text, ".")
		path.len-- // the far var itself
		var/list/frontier = list(E)
		for(var/i in length(path) to 1 step -1)
			var/segment = path[i]
			var/list/next_frontier = list()
			for(var/datum/at as anything in frontier)
				// What reaches `at` through the segment: the sources of a relation, what is inside it for `loc`, what stands on it or is in it for
				// the turf and area hops (hop_sources(), refs/hops.dm).
				for(var/datum/source as anything in hop_sources(at, segment))
					if(!QDELETED(source))
						next_frontier |= list(source)
			frontier = next_frontier
			if(!length(frontier))
				break
		for(var/datum/reader as anything in frontier)
			var/index = change_index_of(reader)
			if(index)
				for(var/datum/hook/H as anything in index[path[1]])
					if(H.entry.args["cond"] == path_text)
						hook_change_pend(reader, H)
			for(var/datum/hook/H as anything in reader.rx?.hooks)
				if(H.kind == HOOK_CHANGE && H.entry.args["cond"] == path_text && H.activation && !H.activation.dead && H.activation.runs)
					hook_change_pend(reader, H)

/proc/hook_change_pend(datum/E, datum/hook/H)
	var/handle = handle_of(E)
	var/list/per = ALAZYACCESS(GLOB.hook_change_pending, handle)
	if(!per)
		per = list()
		ALAZYSET(GLOB.hook_change_pending, handle, per)
	per[H] = TRUE

/// Takes the baseline of E's type-level on_change hooks (called when the holder initializes), silently.
/proc/hooks_change_baseline(datum/E)
	var/index = change_index_of(E)
	if(!index)
		return
	for(var/key in index)
		for(var/datum/hook/H as anything in index[key])
			LAZYSET(rx_of(E).change_last, "[H.serial]", change_value(E, H))
	// What the init's own writes marked is moot: the baseline is the value now, so nothing is owed a first run.
	if(GLOB.hook_change_pending)
		GLOB.hook_change_pending -= handle_of(E)

/// The drain: each marked (holder, hook) is evaluated once; an edge or a changed value runs the hook's parts. The drain shares the simulation lane's
/// budget with the stat drain (GLOB.stat_tick_spent): when the next hook does not fit, the hooks not yet run are carried, in their order and ahead of
/// whatever was marked meanwhile, to the next drain point, so a cascade of power changes spreads over ticks instead of stalling one. Every marked
/// (holder, hook) is still evaluated exactly once per marking. `fresh` starts the budget whole (a direct call); the kernel's drain point passes FALSE.
/proc/hooks_drain_changes(fresh = TRUE)
	if(fresh)
		GLOB.stat_tick_spent = 0
	var/budget = stat_lane_budget(LANE_SIMULATION)
	var/depth = GLOB.act_depth
	var/chain_len = length(GLOB.act_chain)
	var/passes = 0
	while(GLOB.hook_change_pending && passes < DRAIN_MAX_PASSES)
		passes++
		var/alist/batch = GLOB.hook_change_pending
		GLOB.hook_change_pending = null
		var/handle_index = 0
		for(var/handle in batch)
			handle_index++
			var/datum/E = handle_get(handle)
			if(QDELETED(E))
				continue
			var/hook_index = 0
			for(var/datum/hook/H as anything in batch[handle])
				hook_index++
				if(H.activation && (H.activation.dead || !H.activation.runs))
					continue
				if(!change_hook_applies(E, H))
					continue
				var/spent = GLOB.stat_tick_spent
				// The first evaluation of a drain always runs (a budget smaller than one evaluation still makes progress).
				if(spent && spent + STAT_EVAL_CHARGE > budget)
					hooks_carry_rest(batch, handle_index, hook_index)
					GLOB.stat_spills++
					TEST_REC_SPILL("on_change: [length(GLOB.hook_change_pending)] holder(s) carried at pass [passes]")
					if(drain_spill_log_due("on_change")) // the holder count is an O(n) alist length: counted only for a line that is written
						drain_spill_log("on_change", "ACT: the on_change drain spent its budget of [budget]us; [length(GLOB.hook_change_pending)] holder(s) resume at the next drain point (first: [E.type] [H.entry ? copytext(H.entry.sig, 1, 100) : H.type])")
					return
				var/charge_started = stat_charge_begin()
				var/hook_started = TICK_USAGE
				try
					if(hook_conditions_hold(H, E))
						hook_change_eval(E, H)
				catch(var/exception/fault)
					// A throwing condition or value read must not abort the drain and strand the rest of the batch.
					dq_report_caught(fault, "on_change drain of [E.type]")
					act_unwind(depth, chain_len, "on_change drain", fault)
				KM_SLOW_INNER(hook_started, "on_change [E.type] [H.entry ? copytext(H.entry.sig, 1, 100) : H.type]")
				GLOB.stat_tick_spent = spent + stat_charge_end(charge_started)
	if(GLOB.hook_change_pending)
		log_world("ACT: the on_change drain stopped after [DRAIN_MAX_PASSES] passes with [length(GLOB.hook_change_pending)] holder(s) still marked (a hook keeps writing what another hook watches); they wait for the next drain point")

/// Source -> list(time of the next line, spills not yet in a line). A busy station spills the budget on most ticks of a brownout, and a line per spill
/// (7000 in 50 minutes) cost more than it told: one line per source per DRAIN_SPILL_LOG_INTERVAL says how many spills it stands for.
GLOBAL_LIST_EMPTY(drain_spill_state)

/// Whether drain_spill_log() for `source` writes a line now; when it does not, the spill is counted for the next line.
/proc/drain_spill_log_due(source)
	var/list/state = GLOB.drain_spill_state[source]
	if(!state || state[1] <= TIME_NOW(CLOCK_WORLD))
		return TRUE
	state[2]++
	return FALSE

/// Logs `line` for a spilled budget of `source` at most once per DRAIN_SPILL_LOG_INTERVAL; the line says how many spills happened since the last one.
/proc/drain_spill_log(source, line)
	var/list/state = GLOB.drain_spill_state[source]
	if(!state)
		state = list(0, 0)
		GLOB.drain_spill_state[source] = state
	state[2]++
	var/now = TIME_NOW(CLOCK_WORLD)
	if(state[1] > now)
		return
	state[1] = now + DRAIN_SPILL_LOG_INTERVAL
	log_world("[line] ([state[2]] spill\s of the [source] budget since the last line)")
	state[2] = 0

/// The budget ran out at hook `hook_index` of holder `handle_index` of `batch`: that hook and everything after it go back to the pending marks, ahead of
/// what was marked while the drain ran (a hook already pending for the same holder is one mark, not two).
/// The batch itself becomes the rest: the holders already drained leave it and the stopped holder keeps its hooks from `hook_index` on, so a spill
/// costs what the drain ran plus what was marked meanwhile, not the whole backlog (rebuilding a 35 k holder batch on each of ~560 boot spills was 30 s).
/proc/hooks_carry_rest(alist/batch, handle_index, hook_index)
	var/list/done = list()
	var/at = 0
	var/stopped
	for(var/handle in batch)
		if(++at < handle_index)
			done += handle
			continue
		stopped = handle
		break
	for(var/handle in done)
		batch -= handle
	if(!isnull(stopped) && hook_index > 1)
		var/list/hooks = batch[stopped]
		if(length(hooks) >= hook_index)
			batch[stopped] = hooks.Copy(hook_index)
		else
			batch -= stopped
	var/alist/newer = GLOB.hook_change_pending
	if(newer)
		for(var/handle in newer)
			var/list/held = batch[handle]
			if(held)
				for(var/datum/hook/H as anything in newer[handle])
					held[H] = TRUE
			else
				batch[handle] = newer[handle]
	var/any = FALSE
	for(var/handle in batch) // not length(): an alist's length walks every key
		any = TRUE
		break
	GLOB.hook_change_pending = any ? batch : null

/// Whether the hook marked against E is E's own. A turf that was replaced (ChangeTurf) since the mark is another object of another type behind the
/// same reference, and a hook of the old type is not its own; a hook an activation brought belongs to its holder.
/proc/change_hook_applies(datum/E, datum/hook/H)
	if(H.activation)
		return TRUE
	var/index = change_index_of(E)
	if(!index)
		return FALSE
	for(var/key in H.reads)
		if(H in index[key])
			return TRUE
	return FALSE

/proc/hook_change_eval(datum/E, datum/hook/H)
	var/datum/rx_state/rx = rx_of(E)
	var/id = "[H.serial]"
	var/now = change_value(E, H)
	var/had = (id in rx.change_last)
	var/last = rx.change_last?[id]
	LAZYSET(rx.change_last, id, now)
	var/edge = H.entry.args["edge"]
	var/fire = FALSE
	if(change_is_published(H.entry.args["cond"]))
		fire = TRUE
	else if(edge == ANY)
		fire = !had || last != now
	else if(edge & ENTER)
		fire = now && (!had || !last)
	else if(edge & EXIT)
		fire = !now && (!had || last)
	if(!fire)
		return
	if(GLOB.construction_census)
		construction_census_fire(E, H)
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
		dq_report_caught(e, "on_change hook on [E.type]")
	GLOB.act_depth = depth
	GLOB.act_chain.len--
	A.release()

// ---- the entry engine ----

/datum/entry_engine/hook_change
	kind = ENTRY_ON_CHANGE

/datum/entry_engine/hook_change/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	var/datum/hook/H = hook_change_make(A, E, C)
	var/datum/rx_state/rx = rx_of(A.holder())
	H.reads = change_read_keys(A.holder(), E.args["cond"])
	LAZYADD(rx.hooks, H) // ALLOW(ownership): an engine record the one teardown path drops
	rx.set_hooks_generation(rx.hooks_generation + 1)
	for(var/key in H.reads)
		rx_watch_adjust(A.holder(), key, 1)
	change_hop_register(E.args["cond"])
	LAZYSET(rx.change_last, "[H.serial]", change_value(A.holder(), H))
	return TRUE

/datum/entry_engine/hook_change/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder()
	if(!holder?.rx?.hooks)
		return
	for(var/datum/hook/H as anything in holder.rx.hooks.Copy())
		if(H.activation != A || H.source_entry != E)
			continue
		holder.rx.hooks -= H
		holder.rx.set_hooks_generation(holder.rx.hooks_generation + 1)
		for(var/key in H.reads)
			rx_watch_adjust(holder, key, -1)
		change_hop_register(E.args["cond"], -1)
		holder.rx.change_last?.Remove("[H.serial]")
		coalesce_cancel(holder, H)
		H.activation = null // ALLOW(ownership): an engine record the one teardown path drops
	if(!length(holder.rx.hooks))
		holder.rx.hooks = null

/proc/hook_change_make(datum/activation/A, datum/entry/E, datum/centry/C)
	var/datum/hook/H = hook_make(HOOK_CHANGE, null, E, E, C, A, 1000000 + A.serial * 1000 + ++GLOB.hook_serial % 1000)
	return H

/datum/hook
	/// on_change: the keys whose publication re-evaluates it.
	var/list/reads

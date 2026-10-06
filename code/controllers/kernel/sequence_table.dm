// Sequence step tables (doc/rewrite/life_sequences.md). The runner is sequence.dm; frames and states are
// sequence_state.dm.
//
// A sequence's steps are procs on the entity type. The type lists them in the table proc the sequence names
// (`table_proc`, e.g. /mob/living/proc/life_steps()), composed like reactions():
//
//	/mob/living/life_steps()
//		. = ..()
//		. += seq_step(PROC_REF(life_breathing), after = LIFE_INPUT, when = list("placed", "alive"),
//			reads = list(CHANGE_MOB_LOC, nameof(losebreath)), should_run = PROC_REF(life_breathing_due))
//
// A subtype changes a step by overriding its proc (with ..() for the parent's code): that is what the pipeline
// runner's families, variants and plans did. An entity's composed table is its type's table proc, plus the same
// proc on each capability of its type that defines it (a contributed step runs on the capability with
// (entity, frame)), plus its own contributors (seq_extra_add()), plus the sequence's anchors. It is built once per
// key: the type, seq_plan_key() (a body plan) and the contributors' types.
//
// Order is `after =` edges only. An anchor (seq_anchor(), a named no-op) is a barrier: it is passed only when no
// step is ready, so the steps after one anchor all run before the next anchor's. Steps no edge orders run by key.

/// One declared step, or an anchor. seq_step() and seq_anchor() make them; a table keeps its own compiled copies.
/datum/seq_step
	/// Its name in the table: `after` and run_step_now() name it. Default: the handler, or for a contributed step
	/// "[contributor type]:[handler]".
	var/key
	/// Proc name (PROC_REF) on its target. On the entity: handler(frame). On a contributor: handler(entity, frame).
	/// The return value is ignored, except STEP_ABORT.
	var/handler
	/// Keys this step runs after (steps or anchors). A key missing from a table orders nothing there.
	var/list/after
	/// Condition names (the sequence's conditions()) that must hold; "!name": must not.
	var/list/when
	/// What should_run() reads: publish_change() keys (text, a native() spec's keys) and change channels (numbers,
	/// changed()). Any of them changing wakes the step.
	var/list/reads
	/// Proc name on its target, TRUE while the step has work: should_run() on the entity, should_run(entity) on a
	/// contributor. Null: always (the step never sleeps on its own). Asked when a woken step is about to run (FALSE:
	/// back to sleep without running) and after every run (FALSE: it sleeps). Cheap, read-only, and right for an
	/// entity that isn't running: the missed-wake audit asks it of sleeping steps.
	var/should_run
	/// Deciseconds after it falls asleep before it wakes anyway (a step whose work still drifts): a number, or a
	/// proc name on its target returning one (0: no rewake).
	var/rewake
	/// What raises its reads (the audit's message).
	var/woken_by
	/// Runs once per wake: a wake by one of its reads runs it without asking should_run(), and it sleeps after every run
	/// (an event-driven step: its reads say there is work, nothing else does). Its should_run is seq_never().
	var/once = FALSE
	/// A named no-op: it only orders others.
	var/anchor = FALSE

	// ---- compiled into its table
	/// SEQ_TARGET_*.
	var/target_kind = SEQ_TARGET_ENTITY
	/// SEQ_TARGET_STATIC: the shared contributor (a capability).
	var/datum/contributor
	/// SEQ_TARGET_EXTRA: its contributor's index in the state's extras.
	var/extra_slot = 0
	/// Its position in the table (runnable steps only).
	var/pos = 0
	/// Condition bits `when` needs true / false.
	var/cond_req = 0
	var/cond_forbid = 0
	/// Condition bits whose reads all wake this step: a skip blocked only by these sleeps.
	var/covered = 0
	/// Change channels that wake it: its reads', its conditions' and the sequence's wake_all.
	var/chan_mask = 0
	/// publish_change() keys that wake it (its reads' and its conditions').
	var/list/keys
	/// Its cost slot in the sequence (profiled frames).
	var/slot = 0

/// A step of a sequence's table (see the top of this file). `when`, `after` and `reads` take one value or a list.
/// Named seq_step() because step() is BYOND's movement proc.
/proc/seq_step(handler, after = null, when = null, reads = null, should_run = null, rewake = null, key = null, woken_by = null, once = FALSE)
	var/datum/seq_step/S = new
	if(once)
		if(should_run)
			CRASH("seq_step([handler]): a once step has no should_run (it runs once per wake)")
		S.once = TRUE
		should_run = TYPE_PROC_REF(/datum, seq_never)
	S.handler = handler
	S.key = isnull(key) ? null : "[key]"
	S.after = seq_as_list(after)
	S.when = seq_as_list(when)
	S.reads = seq_reads(reads)
	S.should_run = should_run
	S.rewake = rewake
	S.woken_by = woken_by
	return S

/// The should_run of a once step: it has work only when a read woke it, which the wake itself says.
/datum/proc/seq_never()
	return FALSE

/// A named no-op step that orders others (a band: `after = LIFE_BODY`). A barrier: passed only when no step is ready.
/proc/seq_anchor(key, after = null)
	var/datum/seq_step/S = new
	S.key = "[key]"
	S.after = seq_as_list(after)
	S.anchor = TRUE
	return S

/// A named gate for steps (`when = "alive"`), replacing the pipeline runner's facts. `check` is a proc name on the
/// sequence's frame type (it reads the frame's entity); `reads` are the keys and channels whose change can flip it.
/// A step blocked by a condition with reads sleeps until one of them changes; one without reads (nothing announces
/// its change) keeps the step awake. Evaluated lazily, once per frame.
/datum/seq_condition
	var/name
	var/check
	var/list/reads

/proc/seq_condition(name, check, reads = null)
	var/datum/seq_condition/C = new
	C.name = "[name]"
	C.check = check
	C.reads = seq_reads(reads)
	return C

/proc/seq_as_list(value)
	if(isnull(value))
		return null
	if(islist(value))
		var/list/L = value
		return length(L) ? L.Copy() : null
	return list(value)

/// Reads as a flat list: numbers stay change channels, native() specs give their keys, anything else is a key.
/proc/seq_reads(reads)
	if(isnull(reads))
		return null
	if(!islist(reads))
		reads = list(reads)
	var/list/out = list()
	for(var/read in reads)
		if(isnum(read))
			out += read
		else if(istype(read, /datum/native_read))
			var/datum/native_read/N = read
			out |= N.keys
		else if(!isnull(read))
			out |= "[read]"
	return length(out) ? out : null

// ---------------------------------------------------------------- the compiled table

/// One composed, ordered and compiled step list, shared by every entity with the same key.
/datum/seq_table
	var/key
	var/datum/sequence/seq
	/// Runnable steps, in run order (anchors are dropped).
	var/list/steps
	var/n = 0
	/// Parallel to steps: TRUE where the step has conditions.
	var/list/gated
	/// Every key in run order, anchors included (what the order tests lock).
	var/list/order
	/// Step key -> position in steps.
	var/list/pos_of
	/// publish_change() key -> positions it wakes.
	var/list/by_key
	/// Every change channel some step wakes on.
	var/chan_union = 0
	/// `after` targets this table does not have (a step of another type or contributor, or a typo: the graph
	/// tests check every one is declared somewhere).
	var/list/unresolved
	var/list/errors

/datum/seq_table/proc/error(msg)
	LAZYADD(errors, msg)
	seq?.error("[key]: [msg]")

/// E's table: built on first use per key. `extras` are E's own contributors, sorted by type (seq_state.extras).
/datum/sequence/proc/table_for(datum/E, list/extras)
	RETURN_TYPE(/datum/seq_table)
	var/key = table_key(E, extras)
	var/datum/seq_table/T = tables[key]
	if(!T)
		T = build_table(E, extras, key)
		tables[key] = T
	return T

/datum/sequence/proc/table_key(datum/E, list/extras)
	. = "[E.type]"
	var/plan = E.seq_plan_key()
	if(!isnull(plan))
		. += "#[plan]"
	if(length(extras))
		var/list/names = list()
		for(var/datum/X as anything in extras)
			names += "[X.type]"
		. += "|[jointext(names, ",")]"

/// Instance state (beyond the type) that a table proc reads, folded into the table key: a body plan. An entity
/// that changes it calls seq_replan().
/datum/proc/seq_plan_key()
	return null

/// Composes, orders and compiles E's table.
/datum/sequence/proc/build_table(datum/E, list/extras, key)
	var/datum/seq_table/T = new
	T.key = key
	T.seq = src
	/// key -> step; a later declaration of a key replaces the earlier one in place.
	var/list/decls = list()
	/// Keys in declaration order: the node order the validator reports cycles in.
	var/list/declared = list()
	for(var/datum/seq_step/A as anything in anchor_decls)
		seq_collect(T, decls, declared, A, SEQ_TARGET_ENTITY, null, 0)
	if(table_proc)
		seq_collect_list(T, decls, declared, call(E, table_proc)(), SEQ_TARGET_ENTITY, null, 0)
	if(isatom(E))
		for(var/datum/capability/C as anything in caps_of(E))
			if(hascall(C, table_proc))
				seq_collect_list(T, decls, declared, call(C, table_proc)(), SEQ_TARGET_STATIC, C, 0)
	for(var/i in 1 to length(extras))
		var/datum/X = extras[i]
		if(hascall(X, table_proc))
			seq_collect_list(T, decls, declared, call(X, table_proc)(), SEQ_TARGET_EXTRA, X, i)
	var/list/deps = list()
	var/list/anchor_set = list()
	for(var/k in declared)
		var/datum/seq_step/S = decls[k]
		if(S.anchor)
			anchor_set[k] = TRUE
		var/list/mine = list()
		for(var/target in S.after)
			if(decls[target])
				mine |= target
			else
				LAZYOR(T.unresolved, target)
				LAZYSET(unresolved, target, TRUE)
		deps[k] = mine
	var/datum/graph_check/G = graph_validate(declared, deps)
	for(var/problem in G.errors)
		T.error(problem)
	T.order = seq_order_keys(declared, deps, anchor_set)
	T.steps = list()
	T.gated = list()
	T.pos_of = list()
	T.by_key = list()
	for(var/k in T.order)
		var/datum/seq_step/S = decls[k]
		if(S.anchor)
			continue
		T.steps += S
		S.pos = length(T.steps)
		T.pos_of[k] = S.pos
		compile_step(T, S)
		T.gated += (S.cond_req || S.cond_forbid) ? TRUE : FALSE
	T.n = length(T.steps)
	seq_register_reads(E, T)
	return T

/// Compiles one step of `T`: its condition masks, what wakes it, its cost slot and rewake key.
/datum/sequence/proc/compile_step(datum/seq_table/T, datum/seq_step/S)
	var/chans = wake_all
	var/list/keys = list()
	for(var/read in S.reads)
		if(isnum(read))
			chans |= read
		else
			keys |= read
	for(var/name in S.when)
		var/negated = copytext(name, 1, 2) == "!"
		var/cond_name = negated ? copytext(name, 2) : name
		var/i = cond_index[cond_name]
		if(!i)
			T.error("[S.key]: when names unknown condition [cond_name]")
			continue
		var/bit = 1 << (i - 1)
		if(negated)
			S.cond_forbid |= bit
		else
			S.cond_req |= bit
		var/datum/seq_condition/C = conds[i]
		if(length(C.reads))
			S.covered |= bit
			for(var/read in C.reads)
				if(isnum(read))
					chans |= read
				else
					keys |= read
	S.chan_mask = chans
	S.keys = length(keys) ? keys : null
	T.chan_union |= chans
	for(var/k in keys)
		var/list/positions = T.by_key[k]
		if(!positions)
			positions = list()
			T.by_key[k] = positions
		positions += S.pos
	S.slot = slot_for(S.key)
	if(!S.handler)
		T.error("[S.key]: a step needs a handler")

/// The cost slot of step `key` (one per key across the sequence's tables).
/datum/sequence/proc/slot_for(key)
	var/slot = slot_of[key]
	if(slot)
		return slot
	slot_keys += key
	step_ms += 0
	step_calls += 0
	slot = length(slot_keys)
	slot_of[key] = slot
	return slot

/proc/seq_collect_list(datum/seq_table/T, list/decls, list/declared, list/entries, kind, datum/contributor, extra_slot)
	for(var/entry in entries)
		if(!istype(entry, /datum/seq_step))
			T.error("[contributor ? contributor.type : "the entity's table"] returned [entry], not a seq_step()")
			continue
		seq_collect(T, decls, declared, entry, kind, contributor, extra_slot)

/// Adds a compiled copy of `D` to the table being built.
/proc/seq_collect(datum/seq_table/T, list/decls, list/declared, datum/seq_step/D, kind, datum/contributor, extra_slot)
	var/datum/seq_step/S = new
	S.handler = D.handler
	S.after = D.after
	S.when = D.when
	S.reads = D.reads
	S.should_run = D.should_run
	S.rewake = D.rewake
	S.woken_by = D.woken_by
	S.once = D.once
	S.anchor = D.anchor
	S.key = D.key
	if(!S.anchor)
		S.target_kind = kind
		if(kind == SEQ_TARGET_STATIC)
			S.contributor = contributor
		else if(kind == SEQ_TARGET_EXTRA)
			S.extra_slot = extra_slot
		if(isnull(S.key))
			S.key = kind == SEQ_TARGET_ENTITY ? "[S.handler]" : "[contributor.type]:[S.handler]"
	if(!decls[S.key])
		declared += S.key
	decls[S.key] = S

/// The sequence reads its tables' keys: READERS(E, key) holds for them, so TRACKED setters, timed_set and the
/// ownership accessors publish them (and publish_change() reaches seq_publish()).
/proc/seq_register_reads(datum/E, datum/seq_table/T)
	if(!length(T.by_key) || !islist(GLOB?.rx_tables))
		return
	var/datum/rx_table/R = rx_table_of(E)
	if(!R)
		// The type declares no reaction: the table holds only what its sequences read.
		R = new
		R.owner_type = E.type
		GLOB.rx_tables[E.type] = R
	for(var/key in T.by_key)
		R.read_keys[key] = TRUE

// ---------------------------------------------------------------- order

/// Orders `nodes` (keys) by `deps` (key -> keys it runs after). Kahn's algorithm: among the ready nodes a step goes
/// before an anchor (an anchor is a barrier: it is passed only when no step is ready), then the lowest key
/// (sorttextEx). A dep missing from `nodes` orders nothing. Nodes caught in a cycle follow, by key (graph_validate()
/// reports the cycle): a bad table must not silence the entity.
/proc/seq_order_keys(list/nodes, list/deps, list/anchor_set)
	var/list/indegree = list()
	var/list/succ = list()
	for(var/node in nodes)
		indegree[node] = 0
		succ[node] = list()
	for(var/node in nodes)
		for(var/dep in deps[node])
			if(isnull(indegree[dep]) || dep == node)
				continue
			indegree[node] += 1
			var/list/after_dep = succ[dep]
			after_dep += node
	var/list/ready = list()
	var/list/ready_anchors = list()
	for(var/node in nodes)
		if(!indegree[node])
			seq_insert_sorted(anchor_set?[node] ? ready_anchors : ready, node)
	. = list()
	while(length(ready) || length(ready_anchors))
		var/node
		if(length(ready))
			node = ready[1]
			ready.Cut(1, 2)
		else
			node = ready_anchors[1]
			ready_anchors.Cut(1, 2)
		. += node
		for(var/next in succ[node])
			indegree[next] -= 1
			if(!indegree[next])
				seq_insert_sorted(anchor_set?[next] ? ready_anchors : ready, next)
	if(length(.) < length(nodes))
		var/list/stuck = list()
		for(var/node in nodes)
			if(!(node in .))
				seq_insert_sorted(stuck, node)
		. += stuck

/// Inserts `key` into the sorted list `L` (sorttextEx: case-sensitive, deterministic).
/proc/seq_insert_sorted(list/L, key)
	var/i = 1
	while(i <= length(L) && sorttextEx(L[i], key) > 0)
		i++
	L.Insert(i, key)

// ---------------------------------------------------------------- deriving edges (the S3 migration aid)

/**
 * Derives `after` edges that make seq_order_keys() reproduce a known order exactly. Life's stages are ordered today
 * by `order` numbers; life_sequence_edges() feeds this the Life pipeline's plans and S3 writes the result into the
 * step tables.
 *
 * `plans`: lists of step keys, each in today's run order (one per plan: an entity type, its body plan, its extras).
 * Together they must agree on one order. `band_of`: key -> the anchor it runs after. `anchor_chain`: the anchors, in
 * order. Returns key -> list of `after` targets: each anchor after the one before it, each step after its anchor,
 * plus the edges the key tie-break needs. Problems (plans that disagree) go to `errors_out`.
 *
 * Within a band the tie-break (lowest key) already runs d before r when d sorts first; an edge is needed only for an
 * inversion, an earlier d that sorts after r. Every edge is robust to steps missing from a plan: r gets one edge to
 * the latest earlier step present in every plan r is in (it covers every inversion up to that step), and a direct
 * edge to each inversion after it.
 */
/proc/seq_derive_edges(list/plans, list/band_of, list/anchor_chain, list/errors_out)
	. = list()
	for(var/i in 1 to length(anchor_chain))
		.[anchor_chain[i]] = i > 1 ? list(anchor_chain[i - 1]) : list()
	// One order every plan agrees with: consecutive keys of a plan are edges.
	var/list/nodes = list()
	var/list/prec = list()
	var/list/presence = list()
	for(var/p in 1 to length(plans))
		var/list/plan = plans[p]
		for(var/i in 1 to length(plan))
			var/k = plan[i]
			if(!prec[k])
				nodes += k
				prec[k] = list()
				presence[k] = list()
			if(i > 1)
				var/list/before_k = prec[k]
				before_k |= plan[i - 1]
			var/list/in_plans = presence[k]
			in_plans += p
	var/datum/graph_check/G = graph_validate(nodes, prec)
	if(!G.ok())
		if(errors_out)
			errors_out += G.errors
		return
	var/list/total = G.order
	var/list/pos = list()
	for(var/i in 1 to length(total))
		pos[total[i]] = i
	for(var/i in 1 to length(total))
		var/r = total[i]
		var/band = band_of[r]
		var/list/edges = list()
		if(band)
			edges += band
		var/list/mine = presence[r]
		var/cover = 0
		var/list/inversions = list()
		for(var/j in 1 to i - 1)
			var/d = total[j]
			if(band_of[d] != band)
				continue
			var/list/theirs = presence[d]
			if(!length(mine - theirs))
				cover = j
			if(length(mine & theirs) && sorttextEx(d, r) < 0)
				inversions += j
		if(length(inversions))
			if(cover && cover >= inversions[1])
				edges += total[cover]
			for(var/j in inversions)
				if(j > cover)
					edges += total[j]
		.[r] = edges

/// TRUE when seq_order_keys() puts every plan in its own order under `edges` (the anchors dropped). Each plan that
/// comes out differently is described in `errors_out`.
/proc/seq_check_edges(list/plans, list/edges, list/anchor_chain, list/errors_out)
	. = TRUE
	var/list/anchor_set = list()
	for(var/anchor_key in anchor_chain)
		anchor_set[anchor_key] = TRUE
	for(var/p in 1 to length(plans))
		var/list/plan = plans[p]
		var/list/nodes = anchor_chain.Copy()
		nodes += plan
		var/list/deps = list()
		for(var/k in nodes)
			deps[k] = edges[k] || list()
		var/list/got = seq_order_keys(nodes, deps, anchor_set) - anchor_chain
		if(jointext(got, ",") != jointext(plan, ","))
			. = FALSE
			if(errors_out)
				errors_out += "plan [p]: got [jointext(got, ",")]; today [jointext(plan, ",")]"

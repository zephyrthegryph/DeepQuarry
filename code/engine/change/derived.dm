// Declared dependencies (doc/rewrite/dx_conventions.md, "Declared dependencies"; defines in
// code/__defines/derived.dm).
//
// should_run(), draw() (with hidden_verbs()), tgui_data() and push_to_rust() are derived from state.
// A type lists what each reads in derived(), a per-type block built once, like capabilities():
//
//	/obj/item/laser_pointer/derived()
//		. = ..()
//		. += runs_while(nameof(energy))     // should_run(): re-checked when energy changes
//		. += drawn_from(nameof(pointing))   // draw() and hidden_verbs()
//		. += ui_from(nameof(energy))        // tgui_data()
//		. += derive(nameof(power_state), nameof(stat), rel(nameof(power_area), nameof(/area::equip_on)))
//		. += rust_push(nameof(target_pressure), nameof(on))   // push_to_rust()
//
// A read is a var name, a hop through a declared relation (rel(link, remote_var) for a REL / OWN view,
// rel_each(list_link, remote_var) for a REL_LIST / OWN list) or factor_dep(BF_X). derive(var, reads...)
// keeps a cached var, recomputed by derive_<var>() (pure) only when a read changed; it is tracked, so
// other entries can read it. A capability contributes the reads of its own draw / ui_data /
// cap_should_run through derived_reads(holder); the holder declares only what its own code reads.
//
// A tracked write (a TRACKED setter, timed_set, an ownership accessor) names its var:
// state_changed(E, channel, var). A type that declares anything is EXACT: such a change re-derives only the
// outputs that read the var (and marks the dependents that hop to it), and one nobody reads does
// nothing. A type that declares nothing keeps the old rule, any change re-derives everything. A plain
// state_changed(E) (no var named) always re-derives everything. Bits per output are ORed into
// refresh_queued and flushed once per drain; the flush order is derive values, run, draw, ui, push.
//
// Hops are kept by the relation layer: views.dm calls derived_linked() / derived_unlinked() from the
// one place a REF view is indexed, ownership's stamps call derived_var_touched(), so membership needs
// no bookkeeping of its own. tools/ci/derived_reads_lint.py checks that each derived proc body reads
// only what its type declares, and the sampled REFRESH DRIFT audit (refresh.dm) checks the outputs
// against what is applied and names the likely undeclared read.

// ---- entries: what derived() returns (built once per type, shared, never written) ----

/datum/derived_entry
	/// DKIND_*.
	var/kind
	/// derive(): the cached var.
	var/name
	/// Var names (text), /datum/derived_hop and /datum/derived_factor.
	var/list/reads
	/// Contributed by a capability (derived_reads()): adds reads, doesn't make the holder exact.
	var/implicit = FALSE

/// A read through a declared relation: the value of `remote` on what `link` names.
/datum/derived_hop
	var/link
	var/remote
	var/each = FALSE

/// A read of a body factor (BF_*) of a mob, fired when the body's cached factors change.
/datum/derived_factor
	var/id

/// Interned like own entries: a base type's derived() repeated in every subtype's per-type list is one datum.
/// Entries are read-only once returned (derived_entry_implicit() makes the implicit twin instead of writing).
/proc/derived_entry(kind, name, list/reads, implicit = FALSE)
	var/static/list/interned = list()
	var/list/parts = list("[kind]", "[name]", "[!!implicit]")
	for(var/read in reads)
		if(istype(read, /datum/derived_hop))
			var/datum/derived_hop/H = read
			parts += "hop:[H.link]>[H.remote]>[H.each]"
		else if(istype(read, /datum/derived_factor))
			var/datum/derived_factor/F = read
			parts += "factor:[F.id]"
		else
			parts += "[read]"
	var/key = jointext(parts, "|")
	var/datum/derived_entry/E = interned[key]
	if(E)
		return E
	E = new
	E.kind = kind
	E.name = name
	E.reads = reads
	E.implicit = !!implicit
	interned[key] = E
	return E

/// The implicit (capability-contributed) form of `E`.
/proc/derived_entry_implicit(datum/derived_entry/E)
	return E.implicit ? E : derived_entry(E.kind, E.name, E.reads, TRUE)

/// should_run() reads these: a change re-checks it and wakes or parks the cadence.
/proc/runs_while(...)
	return derived_entry(DKIND_RUNS, null, args.Copy())

/// draw() and hidden_verbs() read these: a change re-draws.
/proc/drawn_from(...)
	return derived_entry(DKIND_DRAWN, null, args.Copy())

/// tgui_data() reads these: a change pushes the open windows.
/proc/ui_from(...)
	return derived_entry(DKIND_UI, null, args.Copy())

/// push_to_rust() reads these: a change runs it, once per frame however many of them changed.
/proc/rust_push(...)
	return derived_entry(DKIND_PUSH, null, args.Copy())

/// More reads of the type's on_change() reaction whose handler is `handler` (a PROC_REF): a change of any of them runs
/// that reaction, coalesced with its declared reads. Written by tools/ci/derived_reads_lint.py into
/// code/_generated/reads.dm for the presentation reactions (the HUD, sight and canmove passes of /mob/living), from what
/// their handler procs and helpers read; rx_table_build() merges them into the reaction.
/proc/reaction_reads(handler, ...)
	return derived_entry(DKIND_REACTION, handler, args.Copy(2))

/// A cached var `var_name` (nameof(var)), recomputed by derive_<var_name>() (pure) only when one of
/// `reads` changed. Only the framework writes it; other entries may read it.
/proc/derive(var_name, ...)
	return derived_entry(DKIND_DERIVE, var_name, args.Copy(2))

/// A read of `remote` (nameof(/type::var)) on what the declared relation `link` names.
/proc/rel(link, remote)
	var/datum/derived_hop/H = new
	H.link = link
	H.remote = remote
	return H

/// A read of `remote` on every member of the declared list relation `link`.
/proc/rel_each(link, remote)
	var/datum/derived_hop/H = new
	H.link = link
	H.remote = remote
	H.each = TRUE
	return H

/// A read of body factor `id` (BF_*): fired when the body's cached factors change that factor.
/proc/factor_dep(id)
	var/datum/derived_factor/F = new
	F.id = id
	return F

/// What this type's derived procs read (see the header). Built once per type like capabilities() and
/// shared: `. = ..()` then `. += runs_while(...)` and so on. Pure: read no instance state.
/datum/proc/derived()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

/// Capabilities carry their own reads: what each contributes (its draw / ui_data / cap_should_run
/// read on the holder) is merged in, so a holder declares only what its own code reads.
/atom/derived()
	. = ..()
	for(var/datum/capability/C as anything in caps_of(src))
		var/list/mine = C.derived_reads(src)
		for(var/datum/derived_entry/E as anything in mine)
			. += derived_entry_implicit(E)
	. += present_derived(src) // the reads of the layers and window data the engine's capabilities declare (code/engine/present/outputs.dm)

/// The entries a capability contributes to its holder's derived(): drawn_from / ui_from / runs_while
/// of the holder vars its draw(), ui_data() and cap_should_run() read. Pure.
/datum/capability/proc/derived_reads(atom/holder)
	return null

/// The coalesced Rust sync of a type that declares rust_push(...): runs once per frame after any of
/// its reads state_changed (and after every plain state_changed()). Read state, push it, write nothing.
/datum/proc/push_to_rust()
	SHOULD_NOT_SLEEP(TRUE)
	if(GLOB.derive_side_probing && !derive_called_by_override(callee.caller, "push_to_rust"))
		// The derive probe notes the base was reached directly; it runs only while probing
		GLOB.derive_side_base_reached = TRUE
	return

// ---- the compiled table (one per exact type) ----

/// One derive() value of a type.
/datum/derived_var
	var/name
	var/proc_name
	/// DEP_* bit of this value in refresh_queued.
	var/bit
	/// The plain var reads (text), for ordering values that read other values.
	var/list/local_reads

/// A hop over one relation var to one remote var, and the outputs and values it feeds.
/datum/derived_use
	var/link
	var/remote
	var/mask = 0

/datum/derived_table
	var/owner_type
	/// The type declares something of its own (a capability's contribution alone doesn't).
	var/exact = FALSE
	/// local var name -> outputs and value bits that read it.
	var/list/by_var
	/// derive() values in dependency order.
	var/list/derived_vars
	/// name -> /datum/derived_var.
	var/list/derived_by_name
	/// link var -> list of /datum/derived_use.
	var/list/uses_by_link
	/// factor reads: parallel lists of BF_* and the outputs and values that read it.
	var/list/factor_ids
	var/list/factor_masks

/// Everything below: global registries, filled when a type's table is compiled.
/// type -> /datum/derived_table, or 0 for a type that declares nothing (built on first sight).
GLOBAL_LIST_EMPTY(derived_tables)
/// var name -> TRUE: read locally by some table, or a relation var some table hops over.
GLOBAL_LIST_EMPTY(derived_read_vars)
/// relation var -> TRUE: some table hops over it (the relation layer calls derived_linked()).
GLOBAL_LIST_EMPTY(derived_link_vars)
/// var name -> TRUE: some table reads it through a hop (a change notifies the dependents).
GLOBAL_LIST_EMPTY(derived_remote_vars)
/// BF_* ids some table reads (recompute_factors() reports changes only while this is non-empty).
GLOBAL_LIST_EMPTY(derived_factor_watch)
/// Reverse index of REL views a hop follows: target key (own_key()) -> source key -> link var (or a list
/// of them). Weak keys, so nothing here keeps a datum alive; stale entries are pruned when read.
GLOBAL_LIST_EMPTY(derived_watch)
/// Compile errors (tests read them).
GLOBAL_LIST_EMPTY(derived_errors)
GLOBAL_VAR_INIT(derived_error_expected, FALSE)
/// Depth of output evaluation (test builds: a tracked write while it is above 0 is reported).
GLOBAL_VAR_INIT(derived_evaluating, 0)
/// Test builds: ref text -> var names whose change no output of an exact entity reads (the drift audit
/// names them as the likely undeclared reads).
GLOBAL_LIST_EMPTY(derived_ignored)
/// Test builds: ref text -> times the UI output was flushed for that exact entity.
GLOBAL_LIST_EMPTY(derived_ui_flushes)
/// Test builds: reports of a tracked write inside an output.
GLOBAL_LIST_EMPTY(derived_write_violations)
GLOBAL_VAR_INIT(derived_write_expected, FALSE)

/proc/derived_error(datum/D, message)
	var/text = "DERIVED: [D.type]: [message]"
	GLOB.derived_errors += text
	if(!GLOB.derived_error_expected)
		stack_trace(text)

/// D's table, compiled on the type's first ask; null when the type declares nothing (only a
/// capability's contribution doesn't count).
/proc/derived_table_of(datum/D)
	RETURN_TYPE(/datum/derived_table)
	if(!islist(GLOB?.derived_tables))
		return null // the globals are still being built
	var/known = GLOB.derived_tables[D.type]
	if(!isnull(known))
		return known || null
	var/list/entries = type_list(D, TYPE_PROC_REF(/datum, derived))
	var/datum/derived_table/T = length(entries) ? derived_compile(D, entries) : null
	GLOB.derived_tables[D.type] = T || 0
	return T

/// TRUE when D's type declares its dependencies: a change to a var nobody reads re-derives nothing.
/proc/derived_is_exact(datum/D)
	return !!GLOB?.derived_tables?[D.type]

/// The relation table entry for `link` on D's type when it is a declared OWN or REL var, else null.
/proc/derived_relation_entry(datum/D, link)
	if(!(link in D.vars))
		return null
	var/list/entry = own_table_of(D).entries[link]
	if(entry && (entry[OWNE_KIND] == OWNK_OWN || entry[OWNE_KIND] == OWNK_REL))
		return entry
	return null

/proc/derived_use_of(datum/derived_table/T, datum/derived_hop/H)
	var/list/uses = T.uses_by_link[H.link]
	if(!uses)
		uses = list()
		T.uses_by_link[H.link] = uses
	for(var/datum/derived_use/known as anything in uses)
		if(known.remote == H.remote)
			return known
	var/datum/derived_use/U = new
	U.link = H.link
	U.remote = H.remote
	uses += U
	return U

/proc/derived_entry_label(datum/derived_entry/E)
	switch(E.kind)
		if(DKIND_RUNS)
			return "runs_while"
		if(DKIND_DRAWN)
			return "drawn_from"
		if(DKIND_UI)
			return "ui_from"
		if(DKIND_PUSH)
			return "rust_push"
	return "derive([E.name])"

/// Builds D's table from its derived() entries: every read's consumers (outputs and derive values), the
/// hop uses, the factor reads and the value order. Reports each mistake through derived_error() and
/// drops that read.
/proc/derived_compile(datum/D, list/entries)
	var/datum/derived_table/T = new
	T.owner_type = D.type
	T.by_var = list()
	T.uses_by_link = list()
	// The derive() values first: their bits are what the other entries' reads point at.
	var/list/dvars = list()
	for(var/datum/derived_entry/E as anything in entries)
		if(E.kind != DKIND_DERIVE || dvars[E.name])
			continue
		if(length(dvars) >= DEP_VALUE_MAX)
			derived_error(D, "more than [DEP_VALUE_MAX] derive() values")
			continue
		if(!istext(E.name) || !(E.name in D.vars))
			derived_error(D, "derive([E.name]): not a var of the type")
			continue
		if(!hascall(D, "derive_[E.name]"))
			derived_error(D, "derive([E.name]): the type needs a derive_[E.name]() proc")
			continue
		var/datum/derived_var/V = new
		V.name = E.name
		V.proc_name = "derive_[E.name]"
		V.bit = 1 << (DEP_VALUE_SHIFT + length(dvars))
		V.local_reads = list()
		dvars[E.name] = V
	for(var/datum/derived_entry/E as anything in entries)
		var/bit
		var/datum/derived_var/V
		switch(E.kind)
			if(DKIND_RUNS)
				bit = DEP_RUN
			if(DKIND_DRAWN)
				bit = DEP_DRAW
			if(DKIND_UI)
				bit = DEP_UI
			if(DKIND_PUSH)
				bit = DEP_PUSH
			if(DKIND_DERIVE)
				V = dvars[E.name]
				if(!V)
					continue
				bit = V.bit
		if(!E.implicit)
			T.exact = TRUE
		var/label = derived_entry_label(E)
		for(var/read in E.reads)
			if(istext(read))
				if(!(read in D.vars))
					derived_error(D, "[label] reads [read], which is not a var of the type")
					continue
				T.by_var[read] = (T.by_var[read] || 0) | bit
				GLOB.derived_read_vars[read] = TRUE
				if(V)
					V.local_reads += read
			else if(istype(read, /datum/derived_hop))
				var/datum/derived_hop/H = read
				var/list/entry = derived_relation_entry(D, H.link)
				if(!entry)
					derived_error(D, "[label] hops through [H.link], which is not a declared relation (declare it REL, REL_LIST or OWN: the relation layer is what tells the framework who depends on whom, a plain var can't)")
					continue
				if(entry[OWNE_KIND] == OWNK_REL && H.each != !!entry[OWNE_LIST])
					derived_error(D, "[label] hops through [H.link] with [H.each ? "rel_each()" : "rel()"], but it is a [entry[OWNE_LIST] ? "list" : "single"] relation")
					continue
				var/datum/derived_use/U = derived_use_of(T, H)
				U.mask |= bit
				// The link var itself is read too: it changing (a member added, the view replaced) re-derives
				// what reads through it.
				T.by_var[H.link] = (T.by_var[H.link] || 0) | bit
				GLOB.derived_link_vars[H.link] = TRUE
				GLOB.derived_read_vars[H.link] = TRUE
				GLOB.derived_remote_vars[H.remote] = TRUE
			else if(istype(read, /datum/derived_factor))
				var/datum/derived_factor/F = read
				if(!T.factor_ids)
					T.factor_ids = list()
					T.factor_masks = list()
				var/at = T.factor_ids.Find(F.id)
				if(!at)
					T.factor_ids += F.id
					T.factor_masks += 0
					at = length(T.factor_ids)
				T.factor_masks[at] |= bit
				GLOB.derived_factor_watch |= F.id
			else
				derived_error(D, "[label] reads [read], which is not a var name, rel(), rel_each() or factor_dep()")
	// Values that read other values run after them.
	var/list/todo = list()
	for(var/name in dvars)
		todo += dvars[name]
	var/list/ordered = list()
	var/progressed = TRUE
	while(length(todo) && progressed)
		progressed = FALSE
		for(var/datum/derived_var/V as anything in todo.Copy())
			var/ready = TRUE
			for(var/dep in V.local_reads)
				var/datum/derived_var/other = dvars[dep]
				if(other && !(other in ordered))
					ready = FALSE
					break
			if(ready)
				ordered += V
				todo -= V
				progressed = TRUE
	if(length(todo))
		derived_error(D, "derive() values read each other in a cycle: [jointext(todo, ", ")]")
		ordered += todo
	if(length(ordered))
		T.derived_vars = ordered
		T.derived_by_name = dvars
	return T.exact ? T : null

// ---- attach: the first instance's catch-up ----

/**
 * An entity whose type declares dependencies joins the relation index: what its hop links name right
 * now is indexed (links made before the table existed), and later links are seen by the relation layer.
 * Atoms are attached by caps_init(src) when their type derives deps; a non-atom datum calls this once from
 * New() (and state_changed(src) for its first refresh).
 */
/proc/derived_attach(datum/D)
	var/datum/derived_table/T = derived_table_of(D)
	if(!T)
		return
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	// The second instance of a type rebuilds derived() and compares: it must not read instance state.
	type_list(D, TYPE_PROC_REF(/datum, derived))
#endif
	for(var/link in T.uses_by_link)
		var/value = D.vars[link]
		if(islist(value))
			for(var/datum/target in value)
				derived_index_add(target, D, link)
		else if(isdatum(value))
			derived_index_add(value, D, link)

// ---- the reverse index (REL views), kept by views.dm ----

/proc/derived_index_add(datum/target, datum/source, link)
	var/target_key = OWN_KEY(target)
	var/list/index = GLOB.derived_watch[target_key]
	if(!index)
		index = list()
		GLOB.derived_watch[target_key] = index
	var/source_key = OWN_KEY(source)
	var/current = index[source_key]
	if(isnull(current))
		index[source_key] = link
	else if(islist(current))
		var/list/names = current
		names |= link
	else if(current != link)
		index[source_key] = list(current, link)

/proc/derived_index_remove(datum/target, datum/source, link)
	var/target_key = OWN_KEY(target)
	var/list/index = GLOB.derived_watch[target_key]
	if(!index)
		return
	var/source_key = OWN_KEY(source)
	var/current = index[source_key]
	if(isnull(current))
		return
	if(islist(current))
		var/list/names = current
		names -= link
		if(length(names) == 1)
			index[source_key] = names[1]
		else if(!length(names))
			index -= source_key
	else if(current == link)
		index -= source_key
	if(!length(index))
		GLOB.derived_watch -= target_key

/// The relation layer indexed source.link -> target (_rel_index(), only reached for a relation var some
/// table hops over): index it, and re-derive what reads through that hop.
/proc/derived_linked(datum/source, link, datum/target)
	var/datum/derived_table/T = GLOB.derived_tables[source.type]
	if(!T)
		return
	var/list/uses = T.uses_by_link[link]
	if(!uses)
		return
	derived_index_add(target, source, link)
	derived_touch_link(source, T, link)

/// The relation layer un-indexed source.link -> target.
/proc/derived_unlinked(datum/source, link, datum/target)
	var/datum/derived_table/T = GLOB.derived_tables[source.type]
	if(!T)
		return
	var/list/uses = T.uses_by_link[link]
	if(!uses)
		return
	derived_index_remove(target, source, link)
	derived_touch_link(source, T, link)

/// What reads `link` on `holder`, itself or through a hop (a hop's link var is a read of the type), changed:
/// mark it.
/proc/derived_touch_link(datum/holder, datum/derived_table/T, link)
	if(QDELING(holder))
		return
	var/mask = T.by_var[link] || 0
	if(mask)
		refresh_mark(holder, mask)

/// A framework write changed holder.var_name (an ownership accessor, a relation view, a stamp): the
/// outputs that read it, and that hop over it, re-derive. Callers check GLOB.derived_read_vars first.
/proc/derived_var_touched(datum/holder, var_name)
	var/datum/derived_table/T = GLOB.derived_tables[holder.type]
	if(T)
		derived_touch_link(holder, T, var_name)
	if(GLOB.derived_remote_vars[var_name])
		derived_notify_remote(holder, var_name)

/**
 * `target`'s var_name changed: mark every entity that reads it through a hop. The dependents of an
 * OWN child are its owner; those of a REL view are the sources indexed on it (derived_watch).
 */
/proc/derived_notify_remote(datum/target, var_name)
	if(target.own_holder_ref)
		var/datum/holder = owner_of(target)
		if(holder)
			derived_mark_hop(holder, target.own_slot, var_name)
	var/list/index = GLOB.derived_watch[OWN_KEY(target)]
	if(!index)
		return
	for(var/source_key in index.Copy())
		var/datum/source = own_locate(source_key)
		var/names = index[source_key]
		if(!isdatum(source) || !_rel_source_names(source, names, target))
			index -= source_key // freed without qdel, or no longer names the target
			continue
		for(var/link in (islist(names) ? names : list(names)))
			derived_mark_hop(source, link, var_name)
	if(!length(index))
		GLOB.derived_watch -= OWN_KEY(target)

/// `dependent` reads `remote` through its relation var `link`: mark what that feeds.
/proc/derived_mark_hop(datum/dependent, link, remote)
	if(QDELING(dependent))
		return
	var/datum/derived_table/T = GLOB.derived_tables[dependent.type]
	if(!T)
		return
	var/mask = 0
	for(var/datum/derived_use/U as anything in T.uses_by_link[link])
		if(U.remote == remote)
			mask |= U.mask
	if(mask)
		refresh_mark(dependent, mask)

/**
 * A tracked var of E state_changed (state_changed(E, channel, var_name)): the outputs to re-derive. Dependents that
 * hop to the var are marked first. An exact type answers with the outputs that read var_name (0 when
 * none), any other type with DEP_ALL.
 */
/proc/derived_mask(datum/E, var_name)
	if(!islist(GLOB?.derived_tables))
		return DEP_ALL // the globals are still being built: nothing declares anything yet
	if(GLOB.derived_remote_vars[var_name])
		derived_notify_remote(E, var_name)
	var/datum/derived_table/T = GLOB.derived_tables[E.type]
	if(isnull(T))
		T = derived_table_of(E)
	if(!T)
		return DEP_ALL
	. = T.by_var[var_name] || 0
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	if(!.)
		var/ref_text = REF(E)
		var/list/seen = GLOB.derived_ignored[ref_text]
		if(!seen)
			seen = list()
			GLOB.derived_ignored[ref_text] = seen
		seen |= var_name
#endif

/// Recomputes the derive() values of `mask`, in dependency order; a value that changed is stored (the
/// framework is its only writer), and what reads it, here and through hops, is added to the result.
/proc/derived_recompute(datum/D, datum/derived_table/T, mask)
	. = mask
	for(var/datum/derived_var/V as anything in T.derived_vars)
		if(!(. & V.bit))
			continue
		DERIVED_EVAL_BEGIN
		var/value = call(D, V.proc_name)()
		DERIVED_EVAL_END
		if(D.vars[V.name] == value)
			continue
		D.vars[V.name] = value // ALLOW(api): the derive() value store; the framework is the only writer of a derived var
		. |= (T.by_var[V.name] || 0)
		if(GLOB.derived_remote_vars[V.name])
			derived_notify_remote(D, V.name)
		// A derive() value is tracked: a reaction that reads it (on_change) hears the change like a setter's.
		if(READERS(D, V.name))
			publish_change(D, V.name)

/// The likely undeclared reads behind a drift on A, as text for the audit message.
/proc/derived_drift_hint(atom/A)
	var/list/hint
#if defined(UNIT_TESTS)
	hint = GLOB.derived_ignored[REF(A)]
#endif
	if(length(hint))
		return " (likely an undeclared read of: [jointext(hint, ", ")]; add it to derived())"
	if(derived_is_exact(A))
		return " (its type declares its dependencies: a read missing from derived(), or a var written without its setter)"
	return ""

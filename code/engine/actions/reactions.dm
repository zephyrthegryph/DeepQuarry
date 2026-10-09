// reactions(): what a type reacts to (code/__defines/reactions.dm).
//
//	/obj/machinery/pump/reactions()
//		. = ..()
//		. += before_op(OP_KEY_SET_PRESSURE, PROC_REF(check_pressure_change))
//		. += on_change(list(nameof(target_pressure), nameof(on)), PROC_REF(retune))
//		. += on_notice(/datum/notice/pipe_burst, PROC_REF(burst_seen))
//		. += on_cross(nameof(pressure), list(50, 100), PROC_REF(pressure_band), urgent = TRUE)
//		. += every(1 SECONDS, PROC_REF(pump_step), when = nameof(on))
//		. += drawn_from(nameof(on))            // the existing derived() sugar works here too
//
// The composed table of a type is its own reactions() + each capability's reactions() + the generated
// reads (code/_generated/reads.dm, written by tools/ci/derived_reads_lint.py --fix-generated) + its derived()
// entries, built once per type. It answers READERS(): a key nothing reads publishes nothing.
//
// Delivery contracts (handler is a PROC_REF on the holder, or a GLOBAL_PROC_REF; a global handler is called with the
// holder as its first argument, then the arguments listed here: x(holder, keys), x(holder, ctx), x(holder, dt)):
//   on_change(reads, handler)   handler(list/keys): once per drain (rx_drain) however many reads changed.
//               at_most = N     ... and at most once per N deciseconds per holder: changes inside the window are held
//                               and delivered once, with every key they named, when it ends (rx_at_most_admit()).
//               when = X        a var name truthy on the holder or a PROC_REF answering TRUE, asked when a read is
//                               published: a holder it excludes (a mob without a client) queues nothing.
//   on_notice(type, handler)    handler(datum/notice/N): every occurrence, in publish order, never coalesced.
//   before_op(key|type, handler) handler(ctx): synchronous before commit; a non-null return vetoes (a reason).
//   after_op(key|type, handler)  handler(ctx): synchronous after commit; the return is ignored.
//   on_cross(read, bands, handler, urgent) handler(band, previous_band): when the read moves to another band
//                               (band 0 is below the first threshold). urgent: a kernel_urgent() work item (the
//                               kernel's U phase, deduped per holder, carrying the latest band); else at the drain.
//   every(interval, handler, ...) declared work: a /datum/work_item/reaction on the kernel (work.dm). The handler runs on
//                               each live instance of the declaring type as handler(dt), on each member of `members`
//                               (a capability) as handler(dt), or, when the declaring type is a /datum/system, on the
//                               system as handler(dt) / handler(member, dt). `when` (a var name or a proc) gates it.
//
// on_cross and on_notice register a work item too, so metrics() accounts their cost per reaction (work.dm).

/// One declared reaction. Built by the constructors below, shared per type, never written after.
/datum/reaction
	var/kind
	/// before/after_op: the op key (text) or capability type; on_notice: the notice type; on_cross: the read.
	var/key
	/// on_change: the vars (text) it reads; native() specs are flattened to their keys.
	var/list/reads
	/// PROC_REF on the holder, or a /proc path.
	var/handler
	/// TRUE when `handler` is a /proc path (decided once, in rx_make()); such a handler is called with the holder first.
	var/global_handler = FALSE
	/// A capability's own reaction (cap_rx()): the handler is a proc of this capability, called as handler(holder, ...).
	var/datum/capability/cap
	/// on_cross: ascending thresholds.
	var/list/bands
	var/urgent = FALSE
	/// every(): a capability type; the work runs once per member.
	var/members
	/// every(): the var (text) that must be truthy for it to run.
	var/when
	/// on_change(): TRUE when `when` names a var of the declaring type (decided once, when its table is built): the var
	/// is an implicit read, and its rising edge delivers one catch-up call.
	var/when_var = FALSE
	var/interval
	var/phase
	/// every(): the reaction key or name it must follow in its phase.
	var/after_of
	var/budget
	/// every(): the LANE_* whose share pays for it (null: LANE_SIMULATION).
	var/lane
	/// on_change(): deciseconds; deliveries to one holder are at least this far apart (0: every drain).
	var/at_most = 0
	/// The shared work item this reaction registered (every / urgent on_cross / on_notice, from a type table), or null.
	var/datum/work_item/reaction/work
	/// every(): the type whose reactions() declared it (the work item is keyed by it and the handler), or null.
	var/declared_by
	/// Identity for observe()/unobserve() matching.
	var/sig
	/// True for a read folded in from derived() / generated_reads(): it feeds READERS, nothing runs.
	var/implicit = FALSE

/**
 * Makes R a reaction of capability C: its handler is a PROC_REF on C, called as handler(holder, ...args) (the holder
 * first, then what the reaction's contract passes). A capability's reactions() uses it so its handlers live on the
 * capability, not as procs on every holder type: `. += cap_rx(src, after_op(CAP_EMAG, PROC_REF(committed)))`.
 */
/proc/cap_rx(datum/capability/C, datum/reaction/R)
	R.cap = C
	R.sig = "[R.sig]|cap:[C.type]:[C.key]"
	return R

/// Calls reaction R's handler on holder E with the contract's args: on the capability for a cap_rx() reaction.
/proc/rx_call_reaction(datum/E, datum/reaction/R, ...)
	var/list/rest = length(args) > 2 ? args.Copy(3) : list()
	if(R.cap)
		return call(R.cap, R.handler)(arglist(list(E) + rest))
	if(R.global_handler)
		return call(R.handler)(arglist(list(E) + rest)) // a global handler gets the holder first, like every other handler form
	return call(E, R.handler)(arglist(rest))

/proc/rx_reads_of(reads)
	var/list/out = list()
	if(!islist(reads))
		reads = list(reads)
	for(var/read in reads)
		if(istype(read, /datum/native_read))
			var/datum/native_read/N = read
			out |= N.keys
		else if(read)
			out |= "[read]"
	return out

/proc/rx_make(kind, key, list/reads, handler)
	var/datum/reaction/R = new
	R.kind = kind
	R.key = key
	R.reads = reads
	R.handler = handler
	R.global_handler = deferred_proc_is_global(handler)
	R.sig = "[kind]|[key]|[reads ? jointext(reads, ",") : ""]|[handler]"
	return R

/// Before the operation commits: handler(ctx) may return a reason to veto it. `key_or_type` is an op key
/// (text) or a capability type (every op of that capability).
/proc/before_op(key_or_type, handler)
	return rx_make(RXN_BEFORE_OP, key_or_type, null, handler)

/// After the operation committed: handler(ctx).
/proc/after_op(key_or_type, handler)
	return rx_make(RXN_AFTER_OP, key_or_type, null, handler)

/// Every occurrence of a /datum/notice of `type` (or a subtype) published by the holder: handler(notice).
/proc/reaction_on_notice(type, handler)
	return rx_make(RXN_NOTICE, type, null, handler)

/// One of `reads` (var names, change keys, or native() specs) changed: handler(list/keys), once per drain. `at_most`
/// (deciseconds) coalesces further: after a delivery, changes within that window wait and arrive together, once,
/// when it ends (a HUD refresh needs the latest state, not every step of a walk). `when` (a var name truthy on the
/// holder, or a PROC_REF answering TRUE) is asked when a read is published: a holder it excludes queues nothing and
/// costs one test. A var gate is also an implicit read: when it is published and holds (its rising edge), one delivery
/// carrying the gate's key catches the reaction up on what it skipped; a PROC_REF gate must be covered by the reaction's
/// reads (or generated ones). A static reaction only: observe() delivers every drain whatever its trigger says.
/proc/reaction_on_change(list/reads, handler, at_most = 0, when = null)
	var/datum/reaction/R = rx_make(RXN_CHANGE, null, rx_reads_of(reads), handler)
	if(at_most > 0)
		R.at_most = at_most
		R.sig = "[R.sig]|at_most:[at_most]"
	if(when)
		R.when = when
		R.sig = "[R.sig]|when:[when]"
	return R

/// `read` moved to another band of `bands` (ascending thresholds): handler(band, previous_band).
/proc/on_cross(read, list/bands, handler, urgent = FALSE)
	var/list/reads = rx_reads_of(read)
	var/datum/reaction/R = rx_make(RXN_CROSS, reads[1], reads, handler)
	R.bands = bands
	R.urgent = urgent
	R.sig = "[R.sig]|[jointext(bands, ",")]"
	return R

/// Declared periodic work. `when` names a var that must hold (or a proc that must answer TRUE); `members` (a
/// capability type) runs it once per member; `phase` (KERNEL_PHASE_*), `after` (owner types or item keys) and
/// `lane` order and pay for it; `budget` caps its cost per run. The kernel schedules it (work.dm).
/proc/every(interval, handler, when, members, phase, after, budget, lane)
	// A capability's every(interval, then(...)): periodic work an activation owns (code/engine/actions/every.dm).
	if(istype(handler, /datum/entry) || islist(handler))
		return every_entry(interval, handler, when = when, members = members, phase = phase, lane = lane)
	var/datum/reaction/R = rx_make(RXN_EVERY, null, null, handler)
	// The declaring type is the one whose reactions() calls this: a subtype that re-declares a handler replaces the
	// inherited declaration (rx_table_build) and owns its own work item.
	var/callee/from = callee?.caller
	var/from_proc = from ? "[from.proc]" : null
	if(from_proc && copytext(from_proc, -10) == "/reactions")
		R.declared_by = text2path(copytext(from_proc, 1, -9))
	R.interval = interval
	R.when = when
	R.members = members
	R.phase = phase
	R.after_of = after
	R.budget = budget
	R.lane = lane
	R.sig = "[R.sig]|[interval]|[when]|[members]|[phase]|[lane]"
	return R

/// A read of a Rust-owned value: `native("temperature")`. Usable wherever a read is named; the Rust
/// frame delivers CHANGED(entity, key) into publish_change() under the same key.
/datum/native_read
	var/list/keys

/proc/native(...)
	var/datum/native_read/N = new
	N.keys = list()
	for(var/key in args)
		N.keys += "[key]"
	return N

// ---------------------------------------------------------------- the per-type sources

/// What this type reacts to. Call ..() first, then `. += before_op(...)` and so on. Built once per type
/// (type_list): read no instance state.
/datum/proc/reactions()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

// A capability contributes its reactions by overriding reactions() (it inherits /datum/proc/reactions):
// `/datum/capability/x/reactions()  . = ..()  . += before_op(...)`. Static: read no holder state.

/// The reads the framework generated for this type from its draw / should_run / tgui_data / hidden_verbs /
/// push_to_rust / derive_<x> bodies (code/_generated/reads.dm; never write it by hand). They are implicit:
/// they feed READERS() without making the type's derived() exact.
/datum/proc/generated_reads()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

// ---------------------------------------------------------------- the composed table

/datum/rx_table
	var/owner_type
	/// change key -> list of on_change reactions.
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/by_key = list()
	/// Every key some reaction, generated read or derived() entry reads.
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/read_keys = list()
	/// op key -> reactions; typed (capability) reactions in the *_typed lists.
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/before_keyed = list()
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/after_keyed = list()
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/before_typed = list()
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/after_typed = list()
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/notices = list()
	/// notice type -> TRUE/FALSE: does this table want it (cache).
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/notice_cache = list()
	/// read -> on_cross reactions.
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/crosses = list()
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/everys = list()
	/// The membership keys a holder of this type joins at init for its per-instance every() work (rx_enrol()).
	var/list/holder_keys
	/// sig -> on_change reaction with at_most (a held delivery finds its reaction when its window ends).
	var/list/at_most_by_sig

/// type -> /datum/rx_table, or 0 for a type that reacts to nothing and reads nothing.
GLOBAL_LIST_EMPTY(rx_tables)

/// D's composed reaction table, or null when its type has none. Built once per type.
/proc/rx_table_of(datum/D)
	RETURN_TYPE(/datum/rx_table)
	var/datum/rx_table/T = GLOB.rx_tables?[D.type]
	if(isnull(T))
		T = rx_table_build(D)
	return T

/// Builds and caches D's type table. Null (cached as 0) when the type declares nothing.
/proc/rx_table_build(datum/D)
	RETURN_TYPE(/datum/rx_table)
	if(!islist(GLOB?.rx_tables))
		return null // the globals are still being built
	var/list/own = type_list(D, TYPE_PROC_REF(/datum, reactions))
	var/list/generated = type_list(D, TYPE_PROC_REF(/datum, generated_reads))
	var/list/derived = type_list(D, TYPE_PROC_REF(/datum, derived))
	if(!length(own) && !length(generated) && !length(derived))
		GLOB.rx_tables[D.type] = 0
		return null
	var/datum/rx_table/T = new
	T.owner_type = D.type
	// A subtype that re-declares an every() handler replaces the inherited declaration: the last one of a handler
	// (the subtype's, reactions() chains parent first) is the table's, so a holder never runs one handler twice.
	var/list/last_every = list()
	for(var/datum/reaction/R in own)
		if(R.kind == RXN_EVERY)
			last_every[R.handler] = R
	for(var/datum/reaction/R in own)
		if(R.kind == RXN_EVERY && last_every[R.handler] != R)
			continue
		if(R.kind == RXN_CHANGE && istext(R.when))
			R.when_var = (R.when in D.vars)
		rx_table_add(T, R)
	for(var/datum/derived_entry/E in generated + derived)
		if(E.kind == DKIND_REACTION)
			rx_table_add_reaction_reads(T, own, E)
		else
			rx_table_add_reads(T, E)
	GLOB.rx_tables[D.type] = T
	return T

/// reaction_reads(handler, ...): each read also runs the type's on_change() reactions with that handler (the same
/// reaction datum, so the reads coalesce with its declared ones: one pend per drain).
/proc/rx_table_add_reaction_reads(datum/rx_table/T, list/own, datum/derived_entry/E)
	var/found = FALSE
	for(var/datum/reaction/R in own)
		if(R.kind != RXN_CHANGE || R.handler != E.name)
			continue
		found = TRUE
		for(var/read in E.reads)
			if(!istext(read))
				continue
			LAZYINITLIST(T.by_key[read])
			T.by_key[read] |= R
			T.read_keys[read] = TRUE
	if(!found)
		stack_trace("reaction_reads([E.name]) on [T.owner_type]: no on_change() reaction of the type has that handler")

/proc/rx_table_add_reads(datum/rx_table/T, datum/derived_entry/E)
	for(var/read in E.reads)
		if(istext(read))
			T.read_keys[read] = TRUE
		else if(istype(read, /datum/derived_hop))
			var/datum/derived_hop/H = read
			T.read_keys[H.link] = TRUE

/proc/rx_table_add(datum/rx_table/T, datum/reaction/R)
	switch(R.kind)
		if(RXN_CHANGE)
			for(var/read in R.reads)
				LAZYINITLIST(T.by_key[read])
				T.by_key[read] += R
				T.read_keys[read] = TRUE
			if(R.when_var)
				// A var gate is a read: when it turns true the reaction is owed a catch-up delivery (publish_change()).
				LAZYINITLIST(T.by_key[R.when])
				T.by_key[R.when] |= R
				T.read_keys[R.when] = TRUE
			if(R.at_most)
				// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
				LAZYSET(T.at_most_by_sig, R.sig, R)
		if(RXN_BEFORE_OP)
			rx_table_add_op(T.before_keyed, T.before_typed, R)
		if(RXN_AFTER_OP)
			rx_table_add_op(T.after_keyed, T.after_typed, R)
		if(RXN_NOTICE)
			// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
			T.notices += R
			rx_register_work(T, R)
		if(RXN_CROSS)
			for(var/read in R.reads)
				LAZYINITLIST(T.crosses[read])
				T.crosses[read] += R
				T.read_keys[read] = TRUE
			rx_register_work(T, R)
		if(RXN_EVERY)
			// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
			T.everys += R
			rx_register_work(T, R)
			if(R.when)
				T.read_keys[R.when] = TRUE

/proc/rx_table_add_op(list/keyed, list/typed, datum/reaction/R)
	if(ispath(R.key))
		typed += R
		return
	LAZYINITLIST(keyed[R.key])
	keyed[R.key] += R

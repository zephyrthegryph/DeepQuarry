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
// Delivery contracts (handler is a PROC_REF on the holder, or a GLOBAL_PROC_REF):
//   on_change(reads, handler)   handler(list/keys): once per drain (rx_drain) however many reads changed.
//   on_notice(type, handler)    handler(datum/notice/N): every occurrence, in publish order, never coalesced.
//   before_op(key|type, handler) handler(ctx): synchronous before commit; a non-null return vetoes (a reason).
//   after_op(key|type, handler)  handler(ctx): synchronous after commit; the return is ignored.
//   on_cross(read, bands, handler, urgent) handler(band, previous_band): when the read moves to another band
//                               (band 0 is below the first threshold). urgent: a request_urgent() work item (the
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
	/// on_cross: ascending thresholds.
	var/list/bands
	var/urgent = FALSE
	/// every(): a capability type; the work runs once per member.
	var/members
	/// every(): the var (text) that must be truthy for it to run.
	var/when
	var/interval
	var/phase
	/// every(): the reaction key or name it must follow in its phase.
	var/after_of
	var/budget
	/// every(): the LANE_* whose share pays for it (null: LANE_SIMULATION).
	var/lane
	/// The shared work item this reaction registered (every / urgent on_cross / on_notice, from a type table), or null.
	var/datum/work_item/reaction/work
	/// Identity for observe()/unobserve() matching.
	var/sig
	/// True for a read folded in from derived() / generated_reads(): it feeds READERS, nothing runs.
	var/implicit = FALSE

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
/proc/on_notice(type, handler)
	return rx_make(RXN_NOTICE, type, null, handler)

/// One of `reads` (var names, or native() specs) changed: handler(list/keys), once per drain.
/proc/on_change(list/reads, handler)
	return rx_make(RXN_CHANGE, null, rx_reads_of(reads), handler)

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
	var/datum/reaction/R = rx_make(RXN_EVERY, null, null, handler)
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

/// Capabilities carry their own reactions; an atom's table is its own plus each capability's.
/atom/reactions()
	. = ..()
	for(var/datum/capability/C as anything in caps_of(src))
		var/list/mine = C.reactions()
		if(length(mine))
			. += mine

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
	for(var/datum/reaction/R in own)
		rx_table_add(T, R)
	for(var/datum/derived_entry/E in generated + derived)
		rx_table_add_reads(T, E)
	GLOB.rx_tables[D.type] = T
	return T

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
		if(RXN_BEFORE_OP)
			rx_table_add_op(T.before_keyed, T.before_typed, R)
		if(RXN_AFTER_OP)
			rx_table_add_op(T.after_keyed, T.after_typed, R)
		if(RXN_NOTICE)
			// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
			T.notices += R
			rx_register_work(T, R)
		if(RXN_CROSS)
			for(var/read in R.reads)
				LAZYINITLIST(T.crosses[read])
				T.crosses[read] += R
				T.read_keys[read] = TRUE
			rx_register_work(T, R)
		if(RXN_EVERY)
			// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
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

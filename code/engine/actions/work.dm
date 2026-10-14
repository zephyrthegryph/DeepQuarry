// Reactions on the kernel (doc/rewrite/reactions.md "Work"; the kernel side is controllers/kernel/work_item.dm).
//
// An every() / urgent on_cross() / on_notice() declaration becomes a /datum/work_item/reaction, registered with
// kernel_register_work() under the type whose reaction table declared it, when that table is built. One item per
// reaction signature: the tables of a type and of its subtypes each build their own /datum/reaction, and they all
// point at the one item (`reaction.work`).
//
//   every()                 a scheduled item: interval, phase, `after` edges, budget and lane are the kernel's. It runs
//                           - per member of `members = <capability>` (handler(dt) on the member, or handler(member, dt)
//                             on the system when the declaring type is a /datum/system),
//                           - once per live instance of the declaring type (instances join the membership store under
//                             "rx:<declaring type>:<handler>" at init, rx_enrol(), and leave when they are destroyed),
//                           - or once, on the system, for a memberless every() declared on a /datum/system.
//   on_cross(urgent = TRUE) an urgent item: the crossing is requested with kernel_urgent(holder, item, deadline)
//                           (deduped per holder, run from the kernel's reserved slice, carrying the latest band in the
//                           holder's rx state); the item's perform() calls handler(band, previous_band).
//   on_notice, on_cross     an event item: the declarer still delivers synchronously, in order, and adds the handler's
//                           cost to the item (metrics()); the kernel never schedules it.
//
// The boot pass: tools/ci/derived_reads_lint.py --fix-generated writes rx_boot_types() and rx_boot_members() into
// code/_generated/reads.dm. The kernel reads the members at creation (its holders join at init through
// cap_wanted), and caps_init() enrols an atom only when its type (or one of its capabilities) is listed, so no
// reaction table is built for a type that declares no every().

/// The shared work item of a reaction signature.
GLOBAL_LIST_EMPTY(rx_work_by_sig)

/// The reaction work item: it runs a /datum/reaction's handler for the kernel.
/datum/work_item/reaction
	/// The reaction this item runs (the first table's copy; every copy has the same signature).
	var/datum/reaction/reaction
	/// TRUE when the handler runs on the member (a holder); FALSE when it runs on the owner (a /datum/system).
	var/holder_run = FALSE
	/// The membership key a holder of the declaring type joins (per-instance every()), or null.
	var/enrol_key
	/// Whether `run_when` names a var on the subject (TRUE), a proc (FALSE), or is not known yet (null). Decided on the
	/// first ask: every subject is the declaring type or a subtype (or the one system), so the answer does not change,
	/// and the `in vars` scan (linear in the type's var count) runs once per item instead of once per member per run.
	var/when_is_var

/// Builds the item for `R`, declared by `owner_type` (for an every() on a holder, the type whose reactions() declared it).
/datum/work_item/reaction/New(datum/reaction/R, owner_type)
	// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	reaction = R
	holder_run = !ispath(owner_type, /datum/system)
	system_owned = !holder_run
	var/member_key = R.members
	var/run_every = WORK_EVERY_TICK
	var/run_urgent = FALSE
	var/list/run_after
	switch(R.kind)
		if(RXN_EVERY)
			run_every = R.interval
			if(!isnum(run_every) || run_every < 0)
				CRASH("every() on [owner_type]: interval [run_every] is not a number of deciseconds")
			if(R.after_of)
				run_after = islist(R.after_of) ? R.after_of : list(R.after_of)
			if(!member_key && holder_run)
				enrol_key = "rx:[owner_type]:[R.handler]"
				member_key = enrol_key
		if(RXN_CROSS)
			if(R.urgent)
				// Runs only when requested: the cadence pass skips it (runnable() is FALSE without a pending crossing).
				run_urgent = TRUE
				run_every = 10 MINUTES
				holder_run = TRUE
			else
				event = TRUE
		if(RXN_NOTICE)
			event = TRUE
	// A system's every() that names no phase runs in the system's own (a host system's K or N).
	var/default_phase = KERNEL_PHASE_P
	if(!holder_run)
		var/datum/system/system_proto = owner_type
		default_phase = initial(system_proto.phase)
	..(R.handler, run_every, R.kind == RXN_EVERY ? R.when : null, member_key, R.phase || default_phase, run_after, R.budget || 0, R.lane || LANE_SIMULATION, run_urgent)
	name = "[R.kind == RXN_EVERY ? "every" : (R.kind == RXN_CROSS ? "on_cross" : "on_notice")] [R.handler]"

/datum/work_item/reaction/item_key(owner_type)
	if(reaction.kind == RXN_EVERY)
		return ..()
	return "[owner_type]:[reaction.kind == RXN_CROSS ? "cross" : "notice"]:[handler]:[reaction.key]"

/// A holder item has no singleton owner: the item itself stands in (the kernel needs a live datum). A system item
/// runs on the system's singleton.
/datum/work_item/reaction/owner()
	if(holder_run)
		return src
	return ..()

/// An urgent crossing runs when one is pending on the member; an every() when its `when` holds: a var name (the
/// member's, or the system's for a system item) that is truthy, or a proc answering TRUE.
/datum/work_item/reaction/runnable(datum/owner, datum/member)
	if(reaction.kind == RXN_CROSS)
		return !!member?.rx?.cross_pending?[reaction.sig]
	if(!run_when)
		return TRUE
	var/datum/subject = holder_run ? member : owner
	if(!subject)
		return TRUE
	if(isnull(when_is_var))
		when_is_var = istext(run_when) && (run_when in subject.vars)
	if(when_is_var)
		return !!subject.vars[run_when]
	if(holder_run || !member)
		return !!call(subject, run_when)()
	return !!call(subject, run_when)(member)

/datum/work_item/reaction/perform(datum/owner, datum/member, dt)
	if(reaction.kind == RXN_CROSS)
		return perform_cross(member)
	// rx_call() without its argument copy and arglist (the arity is fixed here); same calls: a global handler gets
	// the holder first, as rx_call() passes it.
	var/is_global = deferred_proc_is_global(handler)
	if(holder_run)
		return is_global ? call(handler)(member, dt) : call(member, handler)(dt)
	if(members)
		return is_global ? call(handler)(owner, member, dt) : call(owner, handler)(member, dt)
	return is_global ? call(handler)(owner, dt) : call(owner, handler)(dt)

/// Delivers the crossing pending on `member`: handler(band, previous_band). A crossing that returned to where it
/// started (its band equals the previous one) delivers nothing.
/datum/work_item/reaction/proc/perform_cross(datum/member)
	var/datum/rx_state/S = member?.rx
	var/list/pending = S?.cross_pending?[reaction.sig]
	if(!pending)
		return STEP_DONE
	S.cross_pending -= reaction.sig
	if(!length(S.cross_pending))
		S.cross_pending = null
	if(pending[1] != pending[2])
		rx_call(member, handler, pending[1], pending[2])
	return STEP_DONE

/// A crossing is a discrete event, not an interval of time: it carries no execution token (last_at) and always
/// reports a positive dt to the urgent runner.
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/reaction/take_dt(datum/member, now = world.time)
	if(reaction.kind == RXN_CROSS)
		return world.tick_lag
	return ..()

// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/reaction/token_current(datum/member, now = world.time)
	if(reaction.kind == RXN_CROSS)
		return FALSE
	return ..()

// ---------------------------------------------------------------- registration

/// Registers the work item of `R` for the table `T` (a type's composed reactions) and links the reaction to it. The
/// first table to declare a signature registers the item under its owner type; the rest share it.
/proc/rx_register_work(datum/rx_table/T, datum/reaction/R)
	// An every() is keyed by (owner type, handler): the declaring type for a holder (a subtype that does not
	// re-declare it shares the item, one that does owns another), the system's own type for a system. The other kinds
	// are one item per signature.
	var/owner = T.owner_type
	var/work_sig = R.sig
	if(R.kind == RXN_EVERY)
		if(R.declared_by && !ispath(T.owner_type, /datum/system))
			owner = R.declared_by
		work_sig = "[owner]|[R.handler]"
	var/datum/work_item/reaction/W = GLOB.rx_work_by_sig[work_sig]
	if(!W)
		W = new(R, owner)
		GLOB.rx_work_by_sig[work_sig] = W
		kernel_register_work(owner, W)
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	R.work = W
	if(W.enrol_key)
		LAZYOR(T.holder_keys, W.enrol_key)
	return W

/// `D` (a holder that declares per-instance every()) joins the membership key of each such reaction, held by
/// RX_ENROL_SOURCE. It leaves them when it is destroyed (member_teardown). Builds D's reaction table.
/proc/rx_enrol(datum/D)
	var/datum/rx_table/T = rx_table_of(D)
	if(!T)
		return
	for(var/key in T.holder_keys)
		join(key, D, RX_ENROL_SOURCE)

/// TRUE when `D` is a member of the every() item `W` (a per-instance reaction item).
/proc/rx_enrolled(datum/D, datum/work_item/reaction/W)
	return !!W.enrol_key && member_is(W.enrol_key, D)

// ---------------------------------------------------------------- the boot list

/// type -> RXB_* kinds its reactions() declare: the generated list plus rx_boot_register() additions.
/proc/rx_boot_flags()
	RETURN_TYPE(/list)
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/flags
	if(!flags)
		flags = rx_boot_types().Copy()
	return flags

/// type -> whether an atom of that type is enrolled at init (cache; cleared by rx_boot_register()).
GLOBAL_LIST_EMPTY(rx_enrol_cache) // ALLOW(cache): a per-type enrolment flag memo, filled on first use, written in place and cleared by rx_boot_register()

/// Adds `type` to the boot list (a type whose reactions() the generator did not see, e.g. a test fixture).
/proc/rx_boot_register(type, kinds = RXB_EVERY)
	var/list/flags = rx_boot_flags()
	flags[type] = (flags[type] || 0) | kinds
	GLOB.rx_enrol_cache.Cut()

/// TRUE when `D` declares per-instance every() work, by its type or (an atom) by one of its capabilities. Cached per
/// type once the cache exists.
/proc/rx_type_enrols(datum/D)
	// The cache is a global list, which may not exist yet while the first atoms initialize: then nothing is cached.
	var/list/cache = GLOB?.rx_enrol_cache
	var/cached = cache?[D.type]
	if(!isnull(cached))
		return cached
	cached = FALSE
	var/list/flags = rx_boot_flags()
	for(var/listed in flags)
		if(!(flags[listed] & RXB_EVERY))
			continue
		if(ispath(D.type, listed))
			cached = TRUE
			break
		if(isatom(D) && ispath(listed, /datum/capability))
			for(var/datum/capability/C as anything in caps_of(D))
				if(ispath(C.type, listed))
					cached = TRUE
					break
			if(cached)
				break
	if(cache)
		cache[D.type] = cached
	return cached

/// Joins every already-initialized holder of capability `key` to its membership key (a work item began to sweep
/// `key` after holders existed). Returns how many joined. Holders that initialize later join in caps_init().
/proc/kernel_backfill_members(key)
	. = 0
	if(!ispath(key, /datum/capability))
		return
	for(var/atom/A in world)
		if(!A.reaction_holder_initialized())
			continue
		for(var/datum/capability/C as anything in caps_all(A))
			if(C.type == key && join(key, A, C))
				.++

// ---------------------------------------------------------------- urgent crossings

/// Asks the kernel to deliver `E`'s crossing of the urgent reaction `R`. The holder's rx state carries the band (the
/// latest band, the first previous one); kernel_urgent() dedups the request. Returns FALSE when the kernel refused
/// (the item is parked): the caller delivers it at once.
/proc/rx_request_cross(datum/E, datum/reaction/R, band, previous)
	var/datum/rx_state/S = rx_of(E)
	var/list/pending = S.cross_pending?[R.sig]
	if(pending)
		pending[1] = band
	else
		LAZYSET(S.cross_pending, R.sig, list(band, previous))
	if(!kernel_urgent(E, R.work, urgent_deadline(RX_URGENT_DEADLINE)))
		S.cross_pending -= R.sig
		if(!length(S.cross_pending))
			S.cross_pending = null
		return FALSE
	return TRUE

/// The lifecycle adapter answers whether a holder can join a newly requested sweep.
/datum/proc/reaction_holder_initialized()
	return TRUE

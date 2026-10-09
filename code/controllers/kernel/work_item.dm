/// Work items: the kernel's one unit of scheduled work (doc/rewrite/kernel.md sec 1.2, "The unit of work").
///
/// A work item is "call `handler` on the owner every `interval`, while `run_when` holds, for each member of
/// `members`". The `every()` / `on_cross()` / `on_notice()` reaction constructors (owner: the state/change
/// framework) produce these and hand them to kernel_register_work(); the kernel owns everything after that:
/// phase, ordering, budget, lane, clock, urgent requests, cost accounting and fault isolation.
///
/// Field names follow every(interval, handler, when=, members=, phase=, after=, budget=): `while` is a
/// reserved word in DM, so the constructor argument is `when` and the field is `run_when`.
///
/// Handler convention (procs on the owner, named with PROC_REF):
///   no members:  handler(dt)            dt in deciseconds since the item's last run (on its clock)
///   members:     handler(member, dt)    once per member, dt since that member's last run
/// A handler returns STEP_DONE (or nothing), STEP_YIELD (resume next tick, from the same member) or
/// STEP_PARK / PROCESS_KILL (leave the schedule until wake_work()).

/datum/work_item
	/// Display name for the profiler; defaults to the handler.
	var/name
	/// "[owner_type]:[handler]", set by kernel_register_work(). `after` may name it.
	var/key
	/// The datum type whose handler this is: a /datum/system type (its singleton is the owner), or any type with a
	/// global singleton the caller resolves through `owner_resolver`.
	var/owner_type
	/// Deciseconds between runs (WORK_EVERY_TICK: every tick). Re-armed from the end of the run.
	var/interval = WORK_EVERY_TICK
	/// The proc, on the owner, that does the work (PROC_REF).
	var/handler
	/// Optional proc on the owner: the item runs only while it returns TRUE. A FALSE answer costs one call.
	var/run_when
	/// A capability or system type: the item runs once per member (membership.dm), not once. Null: runs once.
	var/members
	/// KERNEL_PHASE_* the item runs in. U is reserved for urgent requests.
	var/phase = KERNEL_PHASE_P
	/// What runs before this item in its phase: owner types (every item of that owner) or item keys. A target in an
	/// earlier phase is satisfied already; a target in a later phase is a validation error.
	var/list/after
	/// Percent of a tick one run may take before it yields (0: the phase's own limit).
	var/budget = 0
	/// LANE_* whose share pays for the item in phase P, and whose latency class governs shedding.
	var/lane = LANE_SIMULATION
	/// TRUE when kernel_urgent() may pull one member's run forward.
	var/urgent = FALSE
	/// TRUE for an item that runs ahead of the rest of its phase (or lane) list: the OM scheduler's pieces (sched_items.dm).
	var/first = FALSE
	/// TRUE for an item that belongs to the live graph and to a test's alike (the scheduler's pieces: a test slot runs them on its own scheduler).
	var/shared_graph = FALSE
	/// TRUE when the item's owner is a /datum/system: each memberless run is reported to it (note_run()).
	var/system_owned = FALSE
	/// TRUE for an item its declarer runs itself (an on_notice handler, a non-urgent crossing): it is registered for
	/// cost accounting (metrics(), account()) and never enters a phase list.
	var/event = FALSE
	/// TRUE for an item registered while a test owned the kernel clock (kernel_test_begin()): the live loop never runs it
	/// and a test's injected clock runs only these, so a fixture's every() and the live kernel never meet.
	var/test_owned = FALSE
	/// The clock dt is measured on: CLOCK_WORLD, or CLOCK_BIO on the member (a stasis pause
	/// pauses it). Each clock is a source: the kernel only asks it how much time has passed.
	var/clock = CLOCK_WORLD
	/// Declared reads (a list of field/channel names): what makes runnable() worth re-asking. Informational for
	/// direct items; the stage adapter fills it from the stage.
	var/list/reads

	// ---- runtime state (kernel-owned)
	/// world.time the item is next due.
	var/next_run = 0
	/// Member cursor of a sweep that yielded (or, for a spread item, of the sweep in progress); 0 when no sweep is open.
	var/cursor = 0
	/// TRUE: a member sweep is spread across the interval (each member keeps its phase: the sweep takes the share of
	/// members that is due each pass, not all of them at once), so a large member set never lands in one tick.
	var/spread = FALSE
	/// A spread sweep: when it began (world.time; 0 while none is open).
	var/sweep_began = 0
	/// TRUE when a memberless step returned STEP_YIELD: it resumes next pass ahead of its interval.
	var/yielded = FALSE
	var/parked = FALSE
	var/runs = 0
	/// Runs where run_when answered FALSE.
	var/skips = 0
	var/faults = 0
	var/consecutive_faults = 0
	/// Milliseconds spent in the handler since boot, and an EMA of one run (a full sweep counts once).
	var/total_ms = 0
	var/cost = 0
	var/current_ms = 0
	/// Member handler calls since boot.
	var/member_runs = 0
	/// member (or owner for a memberless item) -> world.time of its last run: the execution token. A cadence pass
	/// and an urgent run share it, so an elapsed stretch of time is applied once, never twice.
	var/list/last_at
	/// Pending urgent requests: member (or owner) -> /datum/urgent_request. Dedup lives here.
	var/list/urgent_pending
	/// Tick of the first sweep run this phase pass (cost accounting for one sweep).
	var/sweep_started_at = 0
	/// The membership store's list for `members` (members_of(members), kept: the store never replaces a key's list),
	/// so the engine can see an empty sweep without a call. Null for a memberless item.
	var/list/member_list
	/// owner()'s system singleton, kept (re-resolved if it is ever deleted).
	var/datum/owner_cache

/datum/work_item/New(handler, interval = WORK_EVERY_TICK, when = null, members = null, phase = KERNEL_PHASE_P, list/after = null, budget = 0, lane = LANE_SIMULATION, urgent = FALSE, clock = CLOCK_WORLD)
	..()
	src.handler = handler
	src.interval = interval
	src.run_when = when
	src.members = members
	src.phase = phase
	src.after = after
	src.budget = budget
	src.lane = lane
	src.urgent = urgent
	src.clock = clock

/// The key the item is filed under: "[owner_type]:[handler]". Adapters and reactions override it.
/datum/work_item/proc/item_key(owner_type)
	return "[owner_type]:[handler]"

/// Adds one run's cost to the item (an event item, whose declarer runs the handler itself).
/datum/work_item/proc/account(ms, faulted = FALSE)
	runs++
	total_ms += ms
	cost = cost ? KERNEL_AVERAGE_FAST(cost, ms) : ms
	if(faulted)
		faults++

/// `member` left the item's membership key: its execution token goes with it (a token holds a reference).
/datum/work_item/proc/forget(datum/member)
	last_at?.Remove(member)

/// The datum whose handler runs: the singleton of `owner_type`. Overridden by adapters.
/datum/work_item/proc/owner()
	if(owner_cache && !QDELETED(owner_cache))
		return owner_cache
	owner_cache = system(owner_type)
	return owner_cache

/// The latency class of this item's lane.
/datum/work_item/proc/latency_class()
	return kernel_lane_class(lane)

/// Whether the item may run at all this pass (a whole-item gate, asked before any member: run levels, say).
/datum/work_item/proc/admitted_now()
	return TRUE

/// Whether the item (or one member) should run now. The default asks `run_when` on the owner.
/datum/work_item/proc/runnable(datum/owner, datum/member)
	if(!run_when)
		return TRUE
	if(member)
		return !!call(owner, run_when)(member)
	return !!call(owner, run_when)()

/// Does the work for one invocation (`member` null for a memberless item). Returns the step protocol.
/datum/work_item/proc/perform(datum/owner, datum/member, dt)
	if(members)
		return call(owner, handler)(member, dt)
	return call(owner, handler)(dt)

/// Deciseconds since this item last ran for `member` (or on its own), on the item's clock, and stamps now as
/// the last run. Returns 0 when it already ran at this instant (a urgent run and the cadence in one tick):
/// nothing to apply twice.
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/proc/take_dt(datum/member, now = world.time)
	var/token = member || src
	now = work_clock_now(clock, member, now)
	var/prev = last_at?[token]
	if(isnull(prev))
		prev = now - max(interval, world.tick_lag)
	LAZYSET(last_at, token, now)
	return max(now - prev, 0)

/// TRUE when this member already ran at the current instant on its clock (its execution token is current).
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/proc/token_current(datum/member, now = world.time)
	var/prev = last_at?[member || src]
	return !isnull(prev) && prev >= work_clock_now(clock, member, now)

/// One run of the item on kernel `K`: a member sweep (spread or whole) or one call. Returns TRUE when done. An item
/// type with its own member loop (a sequence: kernel/sequence.dm) overrides it; the protocol is run_item_spread()'s.
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/proc/sweep(datum/controller/kernel/K, datum/owner, limit_abs, now = world.time)
	if(members)
		return spread ? K.run_item_spread(src, owner, limit_abs, now) : K.run_item_members(src, owner, limit_abs, now)
	return K.run_item_once(src, owner, now)

/// Puts a parked item back on the schedule.
/datum/work_item/proc/wake()
	parked = FALSE
	consecutive_faults = 0
	next_run = 0
	kernel().work_due_reset() // its list may be resting on an earlier walk's due date

/// Telemetry for the profiler (Kernel.metrics()).
/datum/work_item/proc/metrics()
	return alist("key" = key, "phase" = phase, "lane" = lane, "interval" = interval, "runs" = runs, "skips" = skips, "faults" = faults, "member_runs" = member_runs, "total_ms" = total_ms, "cost" = cost, "parked" = parked)

// ---- clocks are sources

/// Now on `clock`, for `member`. CLOCK_WORLD is world.time; an entity clock is the member's own (clock_now()),
/// which stands still while the member is paused. A member without that clock reads world time.
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/proc/work_clock_now(clock, datum/member, now = world.time)
	if(clock == CLOCK_WORLD || !member)
		return now
	return clock_now(member, clock) || now

// ---- registration

/// Registers `W` for `owner_type` and returns it. Called by the reaction constructors (every() and friends) and by
/// adapters. Registering the same key again replaces the earlier item (a type re-declared through a refinement).
/// A capability type named in `members` is remembered so its holders join the membership store when they
/// initialize (caps_init); register before atoms initialize, or call kernel_backfill_members().
/proc/kernel_register_work(owner_type, datum/work_item/W)
	var/datum/controller/kernel/K = kernel()
	return K.register_work(owner_type, W)

/// Removes every item `owner_type` registered.
/proc/kernel_unregister_work(owner_type)
	var/datum/controller/kernel/K = kernel()
	K.unregister_work(owner_type)

/// Wakes a parked item.
/proc/kernel_wake_work(key)
	var/datum/controller/kernel/K = kernel()
	var/datum/work_item/W = K.work_by_key[key]
	W?.wake()
	return !!W

// ---- stages as work items (adapters; the 294 stages are not migrated)

/// The stage vocabulary of the work-item model, on every existing stage: it should run while it is not idle.
/// Stages keep idle()/wake_on/rewake_delay; this is the inverted, declared-reads form the kernel asks.
/datum/work_stage/proc/should_step(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return !idle(E)

/// The declared reads of a stage: its `reads` fields, plus its wake channels as a mask (`wake_mask`).
/datum/work_stage/proc/declared_reads()
	return reads ? reads.Copy() : list()

/// A work item that runs one stage (a family root or variant type) on every entity that has it in `members`:
/// runnable() is the stage's own (!idle), and the work is pipeline_stage_run_now(). The stage stays where it is.
/datum/work_item/stage
	/// The stage family type.
	var/stage_type

/// Builds the adapter for `stage_type`. `owner_type` is what kernel_register_work() files it under.
/proc/stage_work_item(stage_type, members = null, interval = 1 SECONDS, phase = KERNEL_PHASE_P)
	var/datum/work_stage/T = definition_registry().stage_by_type[stage_type]
	if(!T)
		CRASH("stage_work_item: [stage_type] is not a stage")
	var/datum/work_item/stage/W = new(null, interval, null, members, phase)
	W.stage_type = stage_type
	W.name = T.name || "[stage_type]"
	W.reads = T.declared_reads()
	return W

/datum/work_item/stage/owner()
	return src

/datum/work_item/stage/runnable(datum/owner, datum/member)
	var/datum/work_stage/T = definition_registry().stage_by_type[stage_type]
	return T && (!member || T.should_step(member))

/datum/work_item/stage/perform(datum/owner, datum/member, dt)
	if(!member)
		return STEP_DONE
	pipeline_stage_run_now(member, stage_type)
	return STEP_DONE

// Sequences: the kernel's entity-major work (doc/rewrite/life_sequences.md).
//
// A work item runs one handler per member. A sequence runs an ordered list of steps per member that share one frame:
// Mob Life breathes, metabolises, takes the body's status, then runs the steps that read it. One work item per
// sequence (/datum/work_item/sequence, phase P, its sweep spread over the interval like a cadence's) runs the frame
// loop on every member of the sequence's sweep membership:
//
//   - steps are procs on the entity type, declared in a table proc and ordered by `after =` edges (sequence_table.dm)
//   - a step sleeps when its should_run() is FALSE after it ran. A wake clears its sleep bit: publish_change() of a
//     key it reads, state_changed() of a channel it reads, or seq_wake(); the step is asked should_run() again before it
//     runs (FALSE: back to sleep without running). Its rewake (after()) wakes it to run: time, not a read, moved it
//   - conditions gate steps: lazily evaluated, cached per frame. A step blocked only by conditions whose reads wake
//     it sleeps; one blocked by a condition nothing announces stays awake
//   - a member whose steps all sleep for park_after frames in a row leaves the sweep (membership, O(1)); a wake
//     brings it back. A member below the sequence's min_relevance is out of the sweep too
//   - a fixed step with catch-up (max_catchup), the member's clock (CLOCK_BIO: stasis stretches it), run levels,
//     admit(E), STEP_ABORT, run_step_now(), the missed-wake audit and per-step cost slots (profile_stride)
//
// The only writers of a state's sleep bits, parking and sweep membership are the procs in this file
// (tools/ci/check_grep.sh: "idle and park state in one place").

/// Parking off: members stay in the sweep with every step asleep (debugging).
GLOBAL_VAR_INIT(seq_parking_enabled, TRUE)
/// Log every park and unpark (one line per transition; off by default).
GLOBAL_VAR_INIT(seq_trace, FALSE)

// ---------------------------------------------------------------- the definition

/// A sequence: one per type (sequence_def()), never written after it is built.
/datum/sequence
	abstract_type = /datum/sequence
	var/name
	/// Deciseconds between a member's frames (its sweep interval).
	var/interval = 1 SECONDS
	/// Seconds of fixed step per frame. 0: one frame per sweep, covering the elapsed time.
	var/step = 0
	/// At most this many frames for one member in one sweep when it is behind; the rest are dropped.
	var/max_catchup = 1
	/// CLOCK_WORLD, or an entity clock (CLOCK_BIO): the member's elapsed time is read on it, so a
	/// stasis pause stretches its frames. Its step rewakes follow the member's own timer clock.
	var/clock = CLOCK_WORLD
	/// LANE_* whose share pays for the sweep.
	var/lane = LANE_SIMULATION
	/// RUNLEVEL_* bits the sweep runs in. Outside them nothing runs and nothing accumulates.
	var/runlevels = RUNLEVELS_DEFAULT
	/// Frames in a row with every step asleep before a member parks. 0: never parks.
	var/park_after = 2
	/// A member below this relevance (STAT_RELEVANCE) is out of the sweep. RELEVANCE_NONE: always relevant.
	var/min_relevance = RELEVANCE_NONE
	/// Change channels that wake every step (state_changed()).
	var/wake_all = 0
	/// Change keys (PUBLISH_CHANGE, tracked var names) that wake every step.
	var/list/wake_keys
	/// The proc name (PROC_REF) of the table proc, on the entity and on contributors: returns seq_step()s.
	var/table_proc
	var/frame_type = /datum/seq_frame
	/// Time every Nth frame (all members counted together) per step: the per-step cost slots. 0: never.
	var/profile_stride = 0
	/// FALSE: the live kernel does not sweep it (test and bench sequences, which drive their own item).
	var/autoregister = TRUE
	/// TRUE when the sequence overrides admit(): the sweep asks it per member only then.
	var/admit_guard = FALSE
	/// TRUE when the sequence overrides run_step() and ask_step() (a typed dispatch for entities with big proc tables);
	/// otherwise steps are called by name directly.
	var/typed_dispatch = FALSE

	// ---- built
	/// Position in sequence_all(): the index of its state in an entity's seq_states.
	var/idx = 0
	/// The sweep item (null for a sequence nothing registered).
	var/datum/work_item/sequence/work
	/// The frame type is a subtype (it overrides begin() and reset()).
	var/frame_hooks = FALSE
	/// anchors(), built once.
	var/list/anchor_decls
	/// Conditions: index -> /datum/seq_condition, name -> index, index -> check proc.
	var/list/conds
	var/list/cond_index
	var/list/cond_procs
	/// Table key -> /datum/seq_table.
	var/list/tables
	/// Step key -> cost slot; slot -> key, sampled ms, sampled calls.
	var/list/slot_of
	var/list/slot_keys
	var/list/step_ms
	var/list/step_calls
	/// Frames counted for profile_stride.
	var/profile_counter = 0
	/// The membership key of its parked members (the audit's sample space).
	var/parked_key
	var/audit_cursor = 0
	var/audit_awake_cursor = 0
	/// `after` targets some table did not have (key -> TRUE).
	var/list/unresolved
	var/list/errors
	/// Tests expecting a table error: recorded, no stack trace.
	var/expect_errors = FALSE

	// ---- counters (metrics())
	var/frames = 0
	var/parks = 0
	var/unparks = 0
	var/wakes = 0
	var/missed = 0
	var/breaches = 0
	var/aborts = 0

/datum/sequence/New()
	..()
	name ||= "[type]"
	parked_key = "seq_parked:[type]"
	frame_hooks = frame_type != /datum/seq_frame
	tables = list()
	slot_of = list()
	slot_keys = list()
	step_ms = list()
	step_calls = list()
	errors = list()
	anchor_decls = anchors() || list()
	conds = list()
	cond_index = list()
	cond_procs = list()
	for(var/datum/seq_condition/C as anything in conditions())
		if(length(conds) >= SEQ_MAX_CONDITIONS)
			error("more than [SEQ_MAX_CONDITIONS] conditions")
			break
		if(cond_index[C.name])
			error("condition [C.name] declared twice")
			continue
		conds += C
		cond_procs += C.check
		cond_index[C.name] = length(conds)

/// The anchors every table of this sequence has: seq_anchor()s.
/datum/sequence/proc/anchors()
	return list()

/// The conditions steps may gate on: seq_condition()s.
/datum/sequence/proc/conditions()
	return list()

/// Whether `E` runs its frames at all this sweep (a whole-frame guard; set admit_guard). Its elapsed time is spent
/// either way.
/datum/sequence/proc/admit(datum/E)
	return TRUE

/// Whether `E` is relevant enough to be in the sweep.
/datum/sequence/proc/relevant(datum/E)
	return !min_relevance || stat_value(E, STAT_RELEVANCE) >= min_relevance

/// Runs the entity's step proc `name` with frame `F`. By name (call()); a sequence whose entities have big proc tables
/// overrides this with a typed dispatch (a by-name call looks the name up in the entity type's proc table on every call).
/datum/sequence/proc/run_step(datum/E, name, datum/seq_frame/F)
	return call(E, name)(F)

/// Asks the entity's argumentless proc `name` (a step's should_run or rewake). By name; overridable like run_step().
/datum/sequence/proc/ask_step(datum/E, name)
	return call(E, name)()

/datum/sequence/proc/error(msg)
	errors += msg
	if(length(errors) > 200)
		errors.Cut(1, 101)
	if(!expect_errors)
		stack_trace("sequence [name]: [msg]")

/// The shared definition of sequence type `path` (built on first use; safe before the globals exist).
/proc/sequence_def(path)
	RETURN_TYPE(/datum/sequence)
	// A memoized per-type table built once on first call
	var/static/list/defs = list()
	var/datum/sequence/S = defs[path]
	if(S)
		return S
	if(!ispath(path, /datum/sequence) || is_abstract(path))
		CRASH("sequence_def: [path] is not a concrete sequence")
	S = new path
	defs[path] = S
	var/list/all = sequence_all()
	all += S
	S.idx = length(all)
	return S

/// Every sequence built so far, by idx.
/proc/sequence_all()
	RETURN_TYPE(/list)
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/all = list()
	return all

/// Builds every concrete sequence and registers the sweep of each autoregistered one with `K`. Called when the
/// live kernel is created.
/proc/kernel_register_sequences(datum/controller/kernel/K)
	for(var/path in subtypesof(/datum/sequence))
		if(is_abstract(path))
			continue
		var/datum/sequence/S = sequence_def(path)
		if(!S.autoregister)
			continue
		S.work = new /datum/work_item/sequence(S)
		K.register_work(path, S.work)

// ---------------------------------------------------------------- the sweep item

/// A sequence's sweep: one member at a time, spread over the interval (run_item_spread()), each member's elapsed
/// time read on the sequence's clock. The work is sequence.run_member().
/datum/work_item/sequence
	var/datum/sequence/def
	/// The sweep's frame: taken from the pool once and reused member after member (steps never sleep, so frames
	/// never interleave; a nested run takes a scratch frame).
	var/datum/seq_frame/frame
	/// TRUE while outside the sequence's run levels: resuming starts every member afresh, it is no catch-up.
	var/dormant = FALSE
	/// Tests: the RUNLEVEL_* bit to judge the run levels by instead of the live one.
	var/test_runlevel

/datum/work_item/sequence/New(datum/sequence/seq)
	def = seq
	..("run_member", seq.interval, null, seq.type, KERNEL_PHASE_P, null, 0, seq.lane, FALSE, seq.clock)
	name = seq.name
	// A sequence slower than the tick spreads its sweep across the interval, as the ring did: each member keeps its
	// phase, and a big population costs a slice per tick instead of a spike once per interval.
	spread = seq.interval > world.tick_lag

/datum/work_item/sequence/owner()
	return src

/datum/work_item/sequence/admitted_now()
	var/level = test_runlevel || (Kernel.current_runlevel ? (1 << (Kernel.current_runlevel - 1)) : 0)
	if(!(def.runlevels & level))
		dormant = TRUE
		return FALSE
	if(dormant)
		// Nothing ran and nothing accumulated: every member starts again with one interval.
		dormant = FALSE
		for(var/datum/member as anything in members_of(members))
			var/datum/seq_state/state = SEQ_STATE_OF(member, def.idx)
			if(state)
				state.last_at = null
		cursor = 0
		sweep_began = 0
	return TRUE

// The execution token lives on the member's state (one var read) instead of the item's assoc list: the sweep asks
// for it twice per member.
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/sequence/token_current(datum/member, now = world.time)
	var/datum/seq_state/state = SEQ_STATE_OF(member, def.idx)
	var/prev = state?.last_at
	if(isnull(prev))
		return FALSE
	return prev >= (clock == CLOCK_WORLD ? now : work_clock_now(clock, member, now))

// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/sequence/take_dt(datum/member, now = world.time)
	var/datum/seq_state/state = SEQ_STATE_OF(member, def.idx)
	if(!state)
		return 0
	if(clock != CLOCK_WORLD)
		now = work_clock_now(clock, member, now)
	var/prev = state.last_at
	if(isnull(prev))
		prev = now - max(interval, world.tick_lag)
	state.last_at = now
	return max(now - prev, 0)

/datum/work_item/sequence/forget(datum/member)
	var/datum/seq_state/state = SEQ_STATE_OF(member, def.idx)
	if(state)
		state.last_at = null

/datum/work_item/sequence/runnable(datum/owner, datum/member)
	return TRUE

/**
 * The sweep, with the per-member path inlined (the kernel's generic loop costs several proc calls per member: token,
 * runnable, dt, perform). Same protocol as run_item_spread() / run_item_members(): a spread sweep runs the members due
 * by the end of this tick, catches up by at most KERNEL_SPREAD_CATCHUP shares a pass, and looks at a slot again when
 * its member left during its turn (a member that parks swap-removes itself).
 */
// ALLOW(sys_world_time_write): the kernel clock: a per-sweep timestamp of the scheduler itself, not a per-entity expiry
/datum/work_item/sequence/sweep(datum/controller/kernel/K, datum/owner, limit_abs, now = world.time)
	var/list/members_list = members_of(members)
	var/count = length(members_list)
	var/target
	if(spread)
		if(!cursor)
			if(!count)
				next_run = now + interval
				return TRUE
			cursor = 1
			sweep_began = now
		var/span = max(interval, world.tick_lag)
		var/share = CEILING(count * world.tick_lag / span, 1)
		var/due = CEILING(count * min(1, (now - sweep_began + world.tick_lag) / span), 1)
		target = min(due, cursor - 1 + share * KERNEL_SPREAD_CATCHUP, count)
	else
		target = count
		if(!cursor)
			cursor = 1
	var/datum/sequence/seq = def
	var/idx = seq.idx
	var/datum/seq_frame/F = frame
	if(!F)
		F = take(seq.frame_type)
		F.seq = seq
		frame = F
	var/hooks = seq.frame_hooks
	var/world_clock = clock == CLOCK_WORLD
	var/lag_floor = max(interval, world.tick_lag)
	var/i = cursor
	while(i <= target && i <= length(members_list))
		var/datum/M = members_list[i]
		i++
		if(!QDELETED(M))
			var/datum/seq_state/state = SEQ_STATE_OF(M, idx)
			if(!state)
				member_leave(members, M, SEQ_SOURCE)
			else
				var/at = world_clock ? now : work_clock_now(clock, M, now)
				var/prev = state.last_at
				if(isnull(prev) || prev < at)
					if(isnull(prev))
						prev = at - lag_floor
					state.last_at = at
					if(at > prev)
						seq.run_member(M, at - prev, F)
						member_runs++
		if(i - 1 > length(members_list) || members_list[i - 1] != M)
			i--
			target = min(target, length(members_list))
		if(TICK_USAGE > limit_abs && i <= target)
			cursor = i
			seq_frame_clear(F, hooks)
			return FALSE
	seq_frame_clear(F, hooks)
	if(spread && i <= length(members_list))
		cursor = i
		next_run = now
		return TRUE
	if(spread)
		cursor = 0
		next_run = max(sweep_began + max(interval, world.tick_lag), now)
		sweep_began = 0
		return TRUE
	cursor = 0
	next_run = now + interval
	return TRUE

/datum/work_item/sequence/perform(datum/owner, datum/member, dt)
	var/datum/seq_frame/F = frame
	if(!F)
		F = take(def.frame_type)
		F.seq = def
		frame = F
	def.run_member(member, dt, F)
	if(def.frame_hooks)
		F.reset()
	F.entity = null
	F.state = null
	return STEP_DONE

/datum/work_item/sequence/metrics()
	. = ..()
	.["sequence"] = def.metrics()

// ---------------------------------------------------------------- the frame loop

/// A step's work. Locals of the frame loop: E, F, state.
#define SEQ_PERFORM(S) (S.target_kind ? seq_call_contributed(S, E, F, state) : (typed_dispatch ? run_step(E, S.handler, F) : call(E, S.handler)(F)))
/// A step's should_run() (the step has one).
#define SEQ_ASK(S) (S.target_kind ? seq_ask_contributed(S, E, state) : (typed_dispatch ? ask_step(E, S.should_run) : call(E, S.should_run)()))
/// Step `S` at position _i (word _w, bit _bit) falls asleep this frame (tests also note what it read).
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
#define SEQ_SLEEP(_i, _w, _bit) bits[_w] |= _bit; asleep++; LAZYADD(slept, _i); seq_snapshot_note(E, state, S)
#else
#define SEQ_SLEEP(_i, _w, _bit) bits[_w] |= _bit; asleep++; LAZYADD(slept, _i)
#endif

/// Runs step _i inside a frame. A macro so the awake fast path, the word walk and the profiled frame share one
/// body without a proc call per step. `_PERFORM` is the call (timed or not). Locals are few on purpose.
#define SEQ_RUN_STEP(_i, _w, _bit, _PERFORM) \
	S = steps[_i]; \
	if(wk && (wk[_w] & _bit)) { \
		wk[_w] &= ~_bit; \
		if(S.should_run && !SEQ_ASK(S)) { \
			SEQ_SLEEP(_i, _w, _bit); \
			if(S.rewake) { seq_arm_rewake(E, src, S, state); } \
			continue; \
		} \
	} \
	if(gated[_i]) { \
		result = gate(F, S, E, state); \
		if(result) { \
			if(result == 2) { SEQ_SLEEP(_i, _w, _bit); } \
			continue; \
		} \
	} \
	result = _PERFORM; \
	if(result == STEP_ABORT || E.gc_destroyed) { stop = TRUE; break; } \
	if(S.should_run && !SEQ_ASK(S)) { \
		SEQ_SLEEP(_i, _w, _bit); \
		if(S.rewake) { seq_arm_rewake(E, src, S, state); } \
	}

/// The whole frame loop, parameterised by how a step is performed: every step while none sleeps, else a walk over
/// the awake bits of each word.
#define SEQ_RUN_FRAME(_PERFORM) \
	if(!asleep) { \
		for(var/i in 1 to n) { \
			SEQ_RUN_STEP(i, (((i - 1) >> 4) + 1), (1 << ((i - 1) & 15)), _PERFORM) \
		} \
	} else { \
		for(var/w in 1 to length(bits)) { \
			var/base = (w - 1) << 4; \
			var/awake = ~bits[w] & ((1 << min(16, n - base)) - 1); \
			var/b = -1; \
			while(awake) { \
				b++; \
				if(!(awake & 1)) { awake >>= 1; continue; } \
				awake >>= 1; \
				SEQ_RUN_STEP(base + b + 1, w, (1 << b), _PERFORM) \
			} \
			if(stop) { break; } \
		} \
	}

/// The sweep's frame between passes: no member, no typed caches.
/proc/seq_frame_clear(datum/seq_frame/F, hooks)
	if(hooks)
		F.reset()
	F.entity = null
	F.state = null

/// One member's turn in the sweep: `dt` deciseconds on the sequence's clock became frames (fixed step, capped at
/// max_catchup), run with the frame `F`.
/datum/sequence/proc/run_member(datum/E, dt, datum/seq_frame/F)
	var/datum/seq_state/state = SEQ_STATE_OF(E, idx)
	if(!state)
		// A stray member (its state went without leaving): out of the sweep.
		member_leave(type, E, SEQ_SOURCE)
		return
	var/count = 1
	var/frame_dt = dt / 10
	if(step)
		var/acc = state.acc + frame_dt
		count = round(acc / step)
		if(count > max_catchup)
			breaches++
			count = max_catchup
			acc = count * step
		state.acc = acc - count * step
		frame_dt = step
	if(count < 1 || (admit_guard && !admit(E)))
		return
	while(count-- > 0)
		run_frame(E, state, F, frame_dt)
		if(state.parked || QDELETED(E) || SEQ_STATE_OF(E, idx) != state)
			break

/// One frame of `E`: every awake step of its table, in order, sharing `F`.
/datum/sequence/proc/run_frame(datum/E, datum/seq_state/state, datum/seq_frame/F, dt)
	if(profile_stride && !(++profile_counter % profile_stride))
		return run_frame_profiled(E, state, F, dt)
	F.entity = E
	F.state = state
	F.dt = dt
	F.known = 0
	F.values = 0
	F.aborted = FALSE
	if(frame_hooks)
		F.begin()
	frames++
	state.frames++
	state.running = TRUE
	var/datum/seq_table/table = state.table
	var/list/steps = table.steps
	var/list/gated = table.gated
	var/list/bits = state.bits
	var/list/wk = state.woken
	var/asleep = state.asleep
	var/n = table.n
	var/list/slept
	var/stop = FALSE
	var/datum/seq_step/S
	var/result
	SEQ_RUN_FRAME(SEQ_PERFORM(S))
	if(stop || state.pending || state.woken || state.table != table)
		frame_end(E, state, table, asleep, slept, stop)
		return
	// The common end, inline: the sleep count and parking.
	state.running = FALSE
	state.asleep = asleep
	if(!park_after)
		return
	if(asleep >= n)
		if(++state.idle_frames >= park_after)
			seq_park(E, state)
	else if(state.idle_frames)
		state.idle_frames = 0

/// run_frame() for a frame the profiler samples: each step is timed into its cost slot.
/datum/sequence/proc/run_frame_profiled(datum/E, datum/seq_state/state, datum/seq_frame/F, dt)
	F.entity = E
	F.state = state
	F.dt = dt
	F.known = 0
	F.values = 0
	F.aborted = FALSE
	if(frame_hooks)
		F.begin()
	frames++
	state.frames++
	state.running = TRUE
	var/datum/seq_table/table = state.table
	var/list/steps = table.steps
	var/list/gated = table.gated
	var/list/bits = state.bits
	var/list/wk = state.woken
	var/asleep = state.asleep
	var/n = table.n
	var/list/slept
	var/stop = FALSE
	var/datum/seq_step/S
	var/result
	SEQ_RUN_FRAME(timed_step(S, E, F, state))
	frame_end(E, state, table, asleep, slept, stop)

#undef SEQ_RUN_FRAME
#undef SEQ_RUN_STEP
#undef SEQ_SLEEP
#undef SEQ_ASK
#undef SEQ_PERFORM

/// One timed step (profiled frames only).
/datum/sequence/proc/timed_step(datum/seq_step/S, datum/E, datum/seq_frame/F, datum/seq_state/state)
	var/t0 = TICK_USAGE
	. = S.target_kind ? seq_call_contributed(S, E, F, state) : run_step(E, S.handler, F)
	step_ms[S.slot] += TICK_DELTA_TO_MS(TICK_USAGE - t0) * profile_stride
	step_calls[S.slot] += profile_stride

/// The end of a frame: the sleep count, wakes that arrived during it, an abort's undo, and parking.
/datum/sequence/proc/frame_end(datum/E, datum/seq_state/state, datum/seq_table/table, asleep, list/slept, stop)
	state.running = FALSE
	if(state.table != table || QDELETED(E) || SEQ_STATE_OF(E, idx) != state)
		// Replanned, stopped or deleted during the frame: the rest of it ran the old table; nothing is booked.
		return
	state.asleep = asleep
	if(stop)
		// STEP_ABORT: nothing sleeps this frame (the old early return before ..()).
		aborts++
		var/list/bits = state.bits
		for(var/i in slept)
			var/w = SEQ_WORD(i)
			var/bit = SEQ_BIT(i)
			if(bits[w] & bit)
				bits[w] &= ~bit
				state.asleep--
	if(state.pending)
		seq_apply_pending(state)
	if(state.woken)
		seq_prune_woken(state)
	if(stop || !park_after)
		return
	if(state.asleep >= table.n)
		if(++state.idle_frames >= park_after)
			seq_park(E, state)
	else if(state.idle_frames)
		state.idle_frames = 0

/// 0: run the step. 1: skip it and keep it awake (a condition nothing announces blocked it). 2: skip it and let it
/// sleep (only conditions whose reads wake it blocked it, or its should_run() is FALSE anyway).
/datum/sequence/proc/gate(datum/seq_frame/F, datum/seq_step/S, datum/E, datum/seq_state/state)
	var/failed = F.conds_failed(S.cond_req, S.cond_forbid)
	if(!failed)
		return 0
	if(!(failed & ~S.covered))
		return 2
	return (S.should_run && !seq_should_run(S, E, state)) ? 2 : 1

/// A contributed step's work: on its capability, or on the entity's own contributor.
/proc/seq_call_contributed(datum/seq_step/S, datum/E, datum/seq_frame/F, datum/seq_state/state)
	var/datum/target = S.target_kind == SEQ_TARGET_STATIC ? S.contributor : (state ? state.extras[S.extra_slot] : null)
	if(!target)
		return null
	return call(target, S.handler)(E, F)

/proc/seq_ask_contributed(datum/seq_step/S, datum/E, datum/seq_state/state)
	var/datum/target = S.target_kind == SEQ_TARGET_STATIC ? S.contributor : (state ? state.extras[S.extra_slot] : null)
	if(!target)
		return FALSE
	return call(target, S.should_run)(E)

/// Step `S`'s should_run() for `E` (TRUE when it has none).
/proc/seq_should_run(datum/seq_step/S, datum/E, datum/seq_state/state)
	if(!S.should_run)
		return TRUE
	if(S.target_kind == SEQ_TARGET_ENTITY)
		return state ? state.seq.ask_step(E, S.should_run) : call(E, S.should_run)()
	return seq_ask_contributed(S, E, state)

// ---------------------------------------------------------------- joining and leaving

/// Starts `E` on sequence `path`: its table is composed, every step is awake, and it joins the sweep (when relevant).
/// Returns its state. Idempotent.
/proc/seq_start(datum/E, path)
	RETURN_TYPE(/datum/seq_state)
	if(!E || QDELETED(E))
		return null
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(state)
		return state
	state = new
	state.seq = seq
	state.table = seq.table_for(E, null)
	state.bits = seq_words(state.table.n)
	if(!E.seq_states)
		E.seq_states = list()
	if(length(E.seq_states) < seq.idx)
		E.seq_states.len = seq.idx
	E.seq_states[seq.idx] = state
	state.relevant = seq.relevant(E)
	seq_listen(E)
	seq_sync(E, state)
	return state

/// Takes `E` off sequence `path`: out of the sweep and the parked list, its rewakes cancelled, its state dropped.
/proc/seq_stop(datum/E, path)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(!state)
		return FALSE
	seq_drop(E, state)
	if(E.om_rec)
		entity_recompute_listen(E.om_rec)
	return TRUE

/// The state's end: memberships left, rewakes cancelled, the slot emptied.
/proc/seq_drop(datum/E, datum/seq_state/state)
	var/datum/sequence/seq = state.seq
	if(state.in_sweep)
		state.in_sweep = FALSE
		member_leave(seq.type, E, SEQ_SOURCE)
		seq.work?.forget(E)
	if(state.in_parked)
		state.in_parked = FALSE
		member_leave(seq.parked_key, E, SEQ_SOURCE)
	seq_cancel_rewakes(E, state)
	state.extras = null
	if(SEQ_STATE_OF(E, seq.idx) != state)
		return
	E.seq_states[seq.idx] = null
	for(var/other in E.seq_states)
		if(other)
			return
	E.seq_states = null

/// Teardown of a destroyed datum (rx_teardown()): every sequence state goes, with its memberships.
/proc/seq_teardown(datum/D)
	for(var/datum/seq_state/state as anything in D.seq_states?.Copy())
		if(state)
			seq_drop(D, state)
	D.seq_states = null

/// Puts the state in the sweep while it is relevant and not parked, and in the parked list while parked.
/proc/seq_sync(datum/E, datum/seq_state/state)
	var/datum/sequence/seq = state.seq
	var/sweep = state.relevant && !state.parked
	if(sweep != state.in_sweep)
		state.in_sweep = sweep
		if(sweep)
			member_join(seq.type, E, SEQ_SOURCE)
		else
			member_leave(seq.type, E, SEQ_SOURCE)
			// Its execution token goes with it: a member that comes back starts with one interval, not a catch-up.
			seq.work?.forget(E)
	if(state.parked != state.in_parked)
		state.in_parked = state.parked
		if(state.parked)
			member_join(seq.parked_key, E, SEQ_SOURCE)
		else
			member_leave(seq.parked_key, E, SEQ_SOURCE)

/// E's listen mask includes every channel its sequences wake on (state_changed() reaches seq_channels()).
/proc/seq_listen(datum/E)
	E.om_listen |= seq_listen_mask(E)

/// The channels E's sequences listen to: what their steps read, and wake_all.
/proc/seq_listen_mask(datum/E)
	. = 0
	for(var/datum/seq_state/state as anything in E.seq_states)
		if(!state)
			continue
		. |= state.table.chan_union | state.seq.wake_all

/// Adds `contributor` (a datum defining the sequence's table proc: a trait state, a component) to E's table on
/// `path`: its steps run on it with (entity, frame). One contributor per type. Every step wakes (a new table).
/// The caller removes it (seq_extra_remove()) before the contributor goes.
/proc/seq_extra_add(datum/E, path, datum/contributor)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(!state || !contributor)
		return FALSE
	for(var/datum/X as anything in state.extras)
		if(X.type == contributor.type)
			return FALSE
	var/list/extras = state.extras ? state.extras.Copy() : list()
	var/at = 1
	while(at <= length(extras))
		var/datum/before = extras[at]
		if(sorttextEx("[before.type]", "[contributor.type]") <= 0)
			break
		at++
	extras.Insert(at, contributor)
	state.extras = extras
	seq_replan(E, path)
	return TRUE

/proc/seq_extra_remove(datum/E, path, datum/contributor)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(!state || !(contributor in state.extras))
		return FALSE
	var/list/extras = state.extras.Copy()
	extras -= contributor
	state.extras = length(extras) ? extras : null
	seq_replan(E, path)
	return TRUE

/// Rebuilds E's table after something its key covers state_changed (seq_plan_key(), its contributors). Every step of the
/// new table is awake, and a parked member comes back.
/proc/seq_replan(datum/E, path)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(!state)
		return FALSE
	var/datum/seq_table/T = seq.table_for(E, state.extras)
	if(T == state.table)
		return FALSE
	seq_cancel_rewakes(E, state)
	state.table = T
	state.bits = seq_words(T.n)
	state.asleep = 0
	state.idle_frames = 0
	state.woken = null
	state.pending = null
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	state.snaps = null
#endif
	seq_listen(E)
	if(state.parked)
		seq_unpark(E, state, "a new table")
	return TRUE

// ---------------------------------------------------------------- parking

/proc/seq_park(datum/E, datum/seq_state/state)
	if(state.parked || !GLOB.seq_parking_enabled)
		return
	state.parked = TRUE
	state.idle_frames = 0
	// ALLOW(sys_world_time_write): the kernel clock: when the member left the sweep, for the audit's message only
	state.parked_at = world.time
	seq_sync(E, state)
	state.seq.parks++
	if(GLOB.seq_trace)
		log_runtime("SEQ_PARK: [state.seq.name] [E] ([E.type]) parked; [members_total(state.seq.parked_key)] parked")

/// Back in the sweep (while relevant). `reason` is for the trace.
/proc/seq_unpark(datum/E, datum/seq_state/state, reason)
	if(!state.parked)
		return
	state.parked = FALSE
	state.idle_frames = 0
	seq_sync(E, state)
	state.seq.unparks++
	if(GLOB.seq_trace)
		log_runtime("SEQ_PARK: [state.seq.name] [E] ([E.type]) unparked by [reason || "a wake"] after [DisplayTimeText(world.time - state.parked_at)]")

/// The member's relevance moved (SEQ_KEY_RELEVANCE): in or out of the sweep.
/proc/seq_relevance_check(datum/E, datum/seq_state/state)
	var/now_relevant = state.seq.relevant(E)
	if(now_relevant == state.relevant)
		return
	state.relevant = now_relevant
	seq_sync(E, state)

// ---------------------------------------------------------------- wakes

/// Clears the sleep bit of position `i`. With `precheck` the step is asked should_run() before it next runs (a
/// wake by a read: FALSE sends it back to sleep); without, it runs (a rewake: its work drifts with time, which no read
/// announces). While a frame runs the wake waits in `pending` until it ends. Returns TRUE when the step woke now.
/proc/seq_wake_pos(datum/seq_state/state, i, precheck = TRUE)
	var/w = SEQ_WORD(i)
	var/bit = SEQ_BIT(i)
	if(!(state.bits[w] & bit))
		return FALSE
	if(state.running)
		if(!state.pending)
			state.pending = seq_words(state.table.n)
		state.pending[w] |= bit
		return FALSE
	state.bits[w] &= ~bit
	state.asleep--
	if(precheck)
		if(!state.woken)
			state.woken = seq_words(state.table.n)
		state.woken[w] |= bit
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(length(state.snaps) >= i)
		state.snaps[i] = null
#endif
	return TRUE

/// Steps woke on `E`: a parked member comes back.
/proc/seq_woke(datum/E, datum/seq_state/state, reason)
	state.seq.wakes++
	if(state.parked)
		seq_unpark(E, state, reason)

/// Wakes that arrived while a frame ran.
/proc/seq_apply_pending(datum/seq_state/state)
	var/list/P = state.pending
	state.pending = null
	for(var/w in 1 to length(P))
		var/word = P[w]
		if(!word)
			continue
		var/base = (w - 1) << 4
		for(var/b in 0 to 15)
			if(word & (1 << b))
				seq_wake_pos(state, base + b + 1)

/// Drops the woken bits once every one of them has been asked.
/proc/seq_prune_woken(datum/seq_state/state)
	for(var/word in state.woken)
		if(word)
			return
	state.woken = null

/// publish_change() hook: `key` of `E` changed. Wakes every step of E's sequences that reads it.
/proc/seq_publish(datum/E, key)
	for(var/datum/seq_state/state as anything in E.seq_states)
		if(key == SEQ_KEY_RELEVANCE)
			if(state?.seq.min_relevance)
				seq_relevance_check(E, state)
			continue
		// Mid-frame the count is the frame's own: a step that fell asleep this frame is only in the bits.
		if(!state || (!state.asleep && !state.running))
			continue
		var/list/positions = state.table.by_key[key]
		if(!positions)
			continue
		var/woke = FALSE
		var/list/steps = state.table.steps
		for(var/pos in positions)
			var/datum/seq_step/S = steps[pos]
			if(seq_wake_pos(state, pos, !S.once))
				woke = TRUE
		if(woke)
			seq_woke(E, state, "[key]")

/// state_changed() / entity_dispatch_change() hook: channels `bits` of `E` changed. Wakes every step of E's sequences that
/// reads one of them,.
/proc/seq_channels(datum/E, bits)
	for(var/datum/seq_state/state as anything in E.seq_states)
		if(!state)
			continue
		if((!state.asleep && !state.running) || !(bits & state.table.chan_union))
			continue
		var/woke = FALSE
		var/list/steps = state.table.steps
		var/list/sleep_bits = state.bits
		for(var/w in 1 to length(sleep_bits))
			var/word = sleep_bits[w]
			if(!word)
				continue
			var/base = (w - 1) << 4
			for(var/b in 0 to 15)
				if(!(word & (1 << b)))
					continue
				var/datum/seq_step/S = steps[base + b + 1]
				if((S.chan_mask & bits) && seq_wake_pos(state, base + b + 1, !S.once))
					woke = TRUE
		if(woke)
			seq_woke(E, state, "channels [bits]")

/// Wakes every step of `E` on sequence `path` (the explicit wake).
/proc/seq_wake(datum/E, path)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(!state)
		return FALSE
	var/woke = FALSE
	for(var/i in 1 to state.table.n)
		if(seq_wake_pos(state, i))
			woke = TRUE
	if(woke || state.parked)
		seq_woke(E, state, "seq_wake()")
	return TRUE

// ---------------------------------------------------------------- rewakes

/// The time rewakes are reckoned in: the member's own timer clock (what its after() timers run on).
/proc/seq_rewake_now(datum/E)
	return E.om_rec ? E.om_rec.sched.now() : time_scheduler().now()

/// Arms step `S`'s rewake on `E` (it fell asleep). Each step keeps a due time on the member's state; the member has one
/// timer, for the soonest (a TIMER relation keyed by entity and sequence), on its own clock. Falling asleep again moves
/// the step's due time later and touches no timer unless it is now the soonest.
/proc/seq_arm_rewake(datum/E, datum/sequence/seq, datum/seq_step/S, datum/seq_state/state)
	var/delay = S.rewake
	if(!isnum(delay))
		switch(S.target_kind)
			if(SEQ_TARGET_ENTITY)
				delay = seq.ask_step(E, S.rewake)
			if(SEQ_TARGET_STATIC)
				delay = call(S.contributor, S.rewake)(E)
			else
				var/datum/X = state?.extras[S.extra_slot]
				delay = X ? call(X, S.rewake)(E) : 0
	if(!(delay > 0))
		return
	var/due = seq_rewake_now(E) + delay
	if(!state.rewake_at)
		state.rewake_at = new /list(state.table.n)
	state.rewake_at[S.pos] = due
	if(state.rewake_next && state.rewake_next <= due)
		return
	state.rewake_next = due
	rx_after(E, delay, TYPE_PROC_REF(/datum, seq_rewake), "seq:[seq.idx]:rewake", CLOCK_OWN, list(seq.idx))

/// The member's rewake timer went off: every step whose due time has come wakes and runs on its next frame (no
/// should_run() pre-check: a rewake is for work that drifts with time), and the timer is armed for the next one. A parked
/// member comes back and parks again as soon as the step sleeps (it counts as one idle frame already).
/datum/proc/seq_rewake(seq_idx)
	var/datum/seq_state/state = SEQ_STATE_OF(src, seq_idx)
	if(!state)
		return
	state.rewake_next = 0
	var/list/due_at = state.rewake_at
	if(!due_at)
		return
	var/now = seq_rewake_now(src) + 0.001
	var/next = 0
	var/woke = FALSE
	for(var/pos in 1 to length(due_at))
		var/due = due_at[pos]
		if(isnull(due))
			continue
		if(due > now)
			if(!next || due < next)
				next = due
			continue
		due_at[pos] = null
		if(seq_wake_pos(state, pos, FALSE))
			woke = TRUE
	if(next)
		state.rewake_next = next
		rx_after(src, next - seq_rewake_now(src), TYPE_PROC_REF(/datum, seq_rewake), "seq:[seq_idx]:rewake", CLOCK_OWN, list(seq_idx))
	if(!woke)
		return
	state.seq.wakes++
	if(state.parked)
		seq_unpark(src, state, "a step rewake")
		state.idle_frames = max(state.seq.park_after - 1, 0)

/proc/seq_cancel_rewakes(datum/E, datum/seq_state/state)
	state.rewake_at = null
	state.rewake_next = 0
	cancel_after(E, "seq:[state.seq.idx]:rewake")

/// TRUE while step `key`'s rewake is pending on `E`.
/proc/seq_rewake_pending(datum/E, path, key)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	var/pos = state?.table.pos_of[key]
	return pos && length(state.rewake_at) >= pos && !isnull(state.rewake_at[pos])

// ---------------------------------------------------------------- on demand

/// Runs `E`'s step `handler` (its key: the handler's name, or "[contributor type]:[handler]") now, outside the
/// schedule, with a scratch frame (conditions work; dt is the sequence's step). Its sleep bit is unchanged. `path`
/// picks the sequence; without it E's sequences are searched. Returns the handler's result.
/proc/run_step_now(datum/E, handler, path = null)
	if(!E || QDELETED(E))
		return null
	var/key = "[handler]"
	var/datum/sequence/seq
	var/datum/seq_state/state
	var/datum/seq_table/T
	if(path)
		seq = sequence_def(path)
		state = SEQ_STATE_OF(E, seq.idx)
		T = state ? state.table : seq.table_for(E, null)
	else
		for(var/datum/seq_state/candidate as anything in E.seq_states)
			if(candidate?.table.pos_of[key])
				state = candidate
				seq = candidate.seq
				T = candidate.table
				break
	var/pos = T?.pos_of[key]
	if(!pos)
		return null
	var/datum/seq_step/S = T.steps[pos]
	if(S.target_kind == SEQ_TARGET_EXTRA && !state)
		return null
	var/datum/seq_frame/F = take(seq.frame_type)
	F.seq = seq
	F.entity = E
	F.state = state
	F.dt = seq.step || seq.interval / 10
	. = S.target_kind ? seq_call_contributed(S, E, F, state) : seq.run_step(E, S.handler, F)
	F.release()

/// Runs one whole frame of sequence `path` on `E` now (content that must see a frame at once, and tests). A real
/// frame: sleeps, rewakes and parking follow from it. Returns FALSE when E is not on the sequence (or mid-frame).
/proc/seq_run_frame_now(datum/E, path)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	if(!state || state.running)
		return FALSE
	var/datum/seq_frame/F = take(seq.frame_type)
	F.seq = seq
	seq.run_frame(E, state, F, seq.step || seq.interval / 10)
	F.release()
	return TRUE

// ---------------------------------------------------------------- queries

/// TRUE while `E`'s step `key` on sequence `path` is asleep.
/proc/seq_step_asleep(datum/E, path, key)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	var/pos = state?.table.pos_of[key]
	return !!pos && !!(state.bits[SEQ_WORD(pos)] & SEQ_BIT(pos))

/// TRUE while `E` is parked on sequence `path`.
/proc/seq_parked(datum/E, path)
	var/datum/sequence/seq = sequence_def(path)
	var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
	return !!state?.parked

/// Frames sequence `path` has run on `entities`.
/proc/seq_frames(list/entities, path)
	. = 0
	var/datum/sequence/seq = sequence_def(path)
	for(var/datum/E as anything in entities)
		var/datum/seq_state/state = SEQ_STATE_OF(E, seq.idx)
		if(state)
			. += state.frames

/// Telemetry (the sweep item's metrics() carries it into kernel().metrics()): counters and the per-step cost slots.
/datum/sequence/proc/metrics()
	var/list/steps = list()
	for(var/i in 1 to length(slot_keys))
		steps[slot_keys[i]] = alist("calls" = step_calls[i], "ms" = step_ms[i])
	return alist("frames" = frames, "parks" = parks, "unparks" = unparks, "wakes" = wakes, "missed" = missed, \
		"breaches" = breaches, "aborts" = aborts, "tables" = length(tables), "awake" = members_total(type), \
		"parked" = members_total(parked_key), "errors" = length(errors), "steps" = steps)

// ---------------------------------------------------------------- the missed-wake audit

/// The first sleeping step of `E` whose should_run() holds although its conditions pass and no wake or rewake is
/// on its way: a producer changed what it reads without publishing it.
/datum/sequence/proc/missed_wake(datum/E)
	var/datum/seq_state/state = SEQ_STATE_OF(E, idx)
	if(!state || !state.asleep || state.running)
		return null
	var/datum/seq_frame/F = take(frame_type)
	F.seq = src
	F.entity = E
	F.state = state
	F.dt = step || interval / 10
	. = null
	var/datum/seq_table/table = state.table
	for(var/i in 1 to table.n)
		var/w = SEQ_WORD(i)
		var/bit = SEQ_BIT(i)
		if(!(state.bits[w] & bit))
			continue
		if(state.pending && (state.pending[w] & bit))
			continue
		var/datum/seq_step/S = table.steps[i]
		if(length(state.rewake_at) >= i && !isnull(state.rewake_at[i]))
			continue
		if((S.cond_req || S.cond_forbid) && F.conds_failed(S.cond_req, S.cond_forbid))
			continue
		if(seq_should_run(S, E, state))
			. = S
			break
	F.release()

/// Logs a missed wake, fails the unit test run (unless `expected`), and wakes the step. Returns the message.
/datum/sequence/proc/report_missed(datum/E, datum/seq_step/S, expected = FALSE)
	var/datum/seq_state/state = SEQ_STATE_OF(E, idx)
	missed++
	var/changed = null
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	changed = seq_snapshot_diff(E, state, S)
#endif
	var/where = state.parked ? "parked since [DisplayTimeText(world.time - state.parked_at)] ago" : "awake, some steps asleep"
	var/message = "MOB_HIBERNATE_AUDIT: MISSED WAKE [E] ([E.type]) in [name], [where]: step [S.key] has work but slept.[changed ? " Changed without a publish: [changed]." : ""] Woken by: [S.woken_by || "undeclared"]. A producer changed what it reads without publishing it (publish_change() / state_changed())."
	log_runtime(message)
	log_world(message)
#if defined(UNIT_TESTS)
	if(!expected)
		stack_trace(message)
		if(GLOB.current_test)
			GLOB.current_test.Fail(message, __FILE__, __LINE__)
		else
			GLOB.failed_any_test = TRUE
#endif
	if(seq_wake_pos(state, S.pos))
		seq_woke(E, state, "the audit")
	return message

/// Audits a sample of every sequence's parked members and of its awake members with a sleeping step. A miss is
/// logged, fails the unit test run and wakes the step. Returns the messages. Runs with the pipeline audit (same
/// interval, config flag and admin verb: SSbehaviours.audit_step()).
/proc/seq_audit(parked_sample = SEQ_AUDIT_PARKED_SAMPLE, awake_sample = SEQ_AUDIT_AWAKE_SAMPLE, expected = FALSE)
	. = list()
	for(var/datum/sequence/seq as anything in sequence_all())
		var/list/sample = list()
		var/list/parked = members_of(seq.parked_key)
		var/count = length(parked)
		var/cursor = seq.audit_cursor
		for(var/i in 1 to min(count, parked_sample))
			cursor = (cursor % count) + 1
			sample += parked[cursor]
		seq.audit_cursor = cursor
		var/list/awake = members_of(seq.type)
		count = length(awake)
		cursor = seq.audit_awake_cursor
		var/taken = 0
		for(var/i in 1 to count)
			if(taken >= awake_sample)
				break
			cursor = (cursor % count) + 1
			var/datum/member = awake[cursor]
			var/datum/seq_state/state = SEQ_STATE_OF(member, seq.idx)
			if(state?.asleep)
				sample += member
				taken++
		seq.audit_awake_cursor = cursor
		for(var/datum/E as anything in sample)
			if(QDELETED(E))
				continue
			var/datum/seq_step/S = seq.missed_wake(E)
			if(S)
				. += seq.report_missed(E, S, expected)

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Tests: the values of the reads of `S` that are vars of `E`, when it falls asleep.
/proc/seq_snapshot_note(datum/E, datum/seq_state/state, datum/seq_step/S)
	var/list/snap
	for(var/key in S.keys)
		if(!(key in E.vars))
			continue
		if(!snap)
			snap = list()
		snap[key] = seq_snapshot_value(E.vars[key])
	if(!snap)
		return
	if(length(state.snaps) < S.pos)
		if(!state.snaps)
			state.snaps = list()
		state.snaps.len = state.table.n
	state.snaps[S.pos] = snap

/proc/seq_snapshot_value(value)
	if(islist(value))
		return json_encode(value)
	if(isdatum(value))
		return REF(value)
	return value

/// Tests: the reads of `S` that changed since it fell asleep (no publish woke it), or null.
/proc/seq_snapshot_diff(datum/E, datum/seq_state/state, datum/seq_step/S)
	var/list/snap = length(state?.snaps) >= S.pos ? state.snaps[S.pos] : null
	if(!snap)
		return null
	var/list/changed = list()
	for(var/key in snap)
		if(seq_snapshot_value(E.vars[key]) != snap[key])
			changed += key
	return length(changed) ? jointext(changed, ", ") : null
#endif

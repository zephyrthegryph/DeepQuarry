// Sequence frames and per-entity state (doc/rewrite/life_sequences.md). The runner is sequence.dm.

/// Each sequence's state on this datum (a /datum/seq_state), indexed by the sequence's idx. Null until it joins one.
// The kernel's own per-entity sequence records; released by seq_stop()/seq_teardown() (sequence.dm)
/datum/var/tmp/list/seq_states

/// One entity's state in one sequence: what outlives a frame.
/datum/seq_state
	/// The sequence (a shared definition).
	var/datum/sequence/seq
	var/datum/seq_table/table
	/// Sleep bits, one per table position, SEQ_WORD/SEQ_BIT. All zero while every step is awake.
	var/list/bits
	/// Steps whose sleep bit is set.
	var/asleep = 0
	/// Steps woken since they fell asleep (the same layout), or null: each is asked should_run() before it runs.
	var/list/woken
	/// Wakes that arrived while a frame ran (the same layout), or null: applied when the frame ends.
	var/list/pending
	/// Frames in a row that ended with every step asleep (parking hysteresis).
	var/idle_frames = 0
	/// Every step slept for park_after frames: out of the sweep until a wake.
	var/parked = FALSE
	/// Relevant enough for the sequence (min_relevance): out of the sweep while not.
	var/relevant = TRUE
	/// In the sequence's sweep membership (relevant and not parked), and in its parked list.
	var/in_sweep = FALSE
	var/in_parked = FALSE
	/// This entity's own contributors (seq_extra_add()), sorted by type: a contributed step runs on one of them.
	var/list/extras
	/// Fixed-step accumulator, seconds.
	var/acc = 0
	/// The sweep's execution token: when this member last ran, on the sequence's clock (null: start afresh).
	var/last_at
	var/frames = 0
	/// TRUE while one of its frames runs (wakes wait in `pending`).
	var/running = FALSE
	/// world.time it parked (the audit's message).
	var/parked_at = 0
	/// Position -> when that step's rewake is due (seq_rewake_now()), or null; the list is null until a step arms one.
	var/list/rewake_at
	/// When the member's one rewake timer goes off (the soonest due), or 0 when none is armed.
	var/rewake_next = 0
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	/// Tests: position -> (read key -> value) when that step fell asleep, for the audit's diff.
	var/list/snaps
#endif

/// A list of `n` sleep bits, all clear.
/proc/seq_words(n)
	. = new /list(SEQ_WORD(max(n, 1)))
	var/list/L = .
	for(var/w in 1 to length(L))
		L[w] = 0

/**
 * The frame a sequence's steps share for one entity (pooled: take() / release()). A scheduled frame is
 * begin()'s: the sweep reuses one frame for its members; run_step_now(), the audit and seq_run_frame_now() take a
 * scratch one. Typed fields replace the pipeline runner's facts: a subtype adds fields (an environment() cache, a
 * status result a later step reads) and clears them in begin() and reset().
 */
/datum/seq_frame
	parent_type = /datum/pooled
	var/datum/entity
	var/datum/sequence/seq
	var/datum/seq_state/state
	/// Seconds this frame covers: the fixed step, or the elapsed time of a variable-step sequence.
	var/dt = 0
	/// Conditions evaluated this frame (a bit each), and the ones that held.
	var/known = 0
	var/values = 0
	/// TRUE once a step stopped the frame (abort()).
	var/aborted = FALSE

/// Called at the start of every scheduled frame (not for run_step_now() or the audit): per-frame state that must
/// advance exactly once per frame, and clearing the typed caches of the previous one.
/datum/seq_frame/proc/begin()
	return

/// Called when the frame goes back to the pool, and after each member of a sweep: drop typed caches.
/datum/seq_frame/reset()
	. = ..()

/// Stops the frame after the current step: `return F.abort()`. Nothing sleeps this frame.
/datum/seq_frame/proc/abort()
	aborted = TRUE
	return STEP_ABORT

/// Condition `name` this frame (evaluated on first use).
/datum/seq_frame/proc/cond(name)
	var/i = seq.cond_index[name]
	if(!i)
		CRASH("sequence [seq.name] has no condition [name]")
	var/bit = 1 << (i - 1)
	if(!(known & bit))
		known |= bit
		if(call(src, seq.cond_procs[i])())
			values |= bit
		else
			values &= ~bit
	return !!(values & bit)

/// Drops condition `name`'s value: the next read evaluates it again (a step changed what it reads).
/datum/seq_frame/proc/forget(name)
	var/i = seq.cond_index[name]
	if(i)
		known &= ~(1 << (i - 1))

/// The conditions (bits) of `req` that are false and of `forbid` that are true: 0 when all pass.
/datum/seq_frame/proc/conds_failed(req, forbid)
	var/need = (req | forbid) & ~known
	if(need)
		var/list/procs = seq.cond_procs
		for(var/i in 1 to length(procs))
			var/bit = 1 << (i - 1)
			if(!(need & bit))
				continue
			if(call(src, procs[i])())
				values |= bit
			else
				values &= ~bit
		known |= need
	return (req & ~values) | (forbid & values)

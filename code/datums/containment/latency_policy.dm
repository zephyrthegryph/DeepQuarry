// ---- The sweep (containment.md Â§4.7 "Sweep and hysteresis") ----

/// Checks per sweep frame (2 s): 32 per 4 s, as the reactor sweep spent.
#define LATENCY_SWEEP_BUDGET 16
/// Time a sweep frame may spend (ms). A collapse check scans the subtree's references and costs
/// 5-25 ms on a full locker, so an unbounded frame over 16 holders ran ~275 ms in one tick every
/// 2 s on Southern Cross. Past the budget the frame stops and the next frame resumes at the same
/// holder (refused atoms are on cooldown and collapsed ones are gone, so nothing repeats).
#define LATENCY_SWEEP_MS_BUDGET 4
/// References the sweep frame itself holds to the atom it checks (see sweep_step()).
#define LATENCY_SWEEP_FRAME_REFS 2
/// Shortest wait before the sweep re-offers an atom latent_collapse() refused.
#define LATENCY_REFUSAL_BACKOFF_MIN (1 MINUTES)

/// Holders with latent contents that the sweep should look at. Populated by
/// dq_latency_sweep_register() the first time a holder's ledger is built
/// (dq_ledger(), ledger.dm); a holder with nothing left simply contributes no
/// candidates on its turn, rather than being torn out of the list.
GLOBAL_LIST_EMPTY(latency_sweep_holders)

/proc/dq_latency_sweep_register(atom/holder)
	// A sandboxed (unmaterialized) holder isn't in the live world yet: materialize()
	// registers it, so Initialize() never touches this global (lifecycle sandbox).
	if(!(holder.flags & ATOM_MATERIALIZED))
		return
	if(holder?.latent_contents_enabled())
		GLOB.latency_sweep_holders[holder] = TRUE
		GLOB.latency_sweep.set_sweeping(TRUE)

/proc/dq_latency_sweep_unregister(atom/holder)
	GLOB.latency_sweep_holders -= holder

/datum/latency_sweep
	var/cursor = 0
	/// A holder has registered: the every() below runs (it parks until the first one, never at global init).
	var/sweeping = FALSE
TRACKED(/datum/latency_sweep, sweeping)
CAPABILITIES(/datum/latency_sweep)
	every(2 SECONDS, then(PROC_REF(sweep_step)), when = nameof(sweeping))

GLOBAL_DATUM_INIT(latency_sweep, /datum/latency_sweep, new)

// The sweep is an every() of 2 s, not a
// reactor continuous declaration: budgeted collapse over latent holders (C10). It starts
// with the first registered holder (never at global init, before the OM core exists) and
// keeps running; a frame with no holders costs one length check.

/// One sweep frame (every()): spends a fixed budget of checks across the registered
/// holders, round-robin, collapsing whatever passes can_be_latent(). The sweep
/// just spends its budget every frame.
/datum/latency_sweep/proc/sweep_step(datum/act/timer/tick)
	if(!CONFIG_GET(flag/latency_policy_enabled))
		return
	var/list/holders = GLOB.latency_sweep_holders
	var/count = length(holders)
	if(!count)
		return
	var/checked = 0
	var/index = cursor % count
	// Snapshot the keys: deleted holders are pruned after the pass, never mid-iteration,
	// so the indexes below stay valid for the whole frame.
	var/list/keys = holders.Copy()
	var/list/dead
	var/frame_start = TICK_USAGE_REAL
	var/out_of_time = FALSE
	while(checked < LATENCY_SWEEP_BUDGET && checked < count && !out_of_time)
		var/atom/holder = keys[(index % count) + 1]
		index++
		checked++
		if(QDELETED(holder))
			LAZYADD(dead, holder)
			continue
		for(var/atom/movable/A as anything in holder.contents)
			if(COOLDOWN_TIMELEFT(A, latent_refused_until))
				continue
			if(TICK_DELTA_TO_MS(TICK_USAGE_REAL - frame_start) >= LATENCY_SWEEP_MS_BUDGET)
				// Resume at this holder next frame.
				index--
				out_of_time = TRUE
				break
			var/eligible = FALSE
			// References this frame holds to A (dq_latent_pinned()'s caller_refs), measured by
			// dq_latency_sweep_collapses/dq_latency_sweep_outside_ref_blocks: the loop variable and
			// one more inside the try block.
			try
				eligible = can_be_latent(A, LATENCY_SWEEP_FRAME_REFS)
			catch(var/exception/e)
				// One bad atom must not end the whole frame (and with it every
				// other holder's turn): log it with context and back it off.
				COOLDOWN_START(A, latent_refused_until, max(holder?.latent_idle_delay_value(), LATENCY_REFUSAL_BACKOFF_MIN))
				stack_trace("LATENCY_SWEEP: can_be_latent([A.type] in [holder.type]) runtimed: [e.name] at [e.file]:[e.line] -- [e.desc]")
				continue
			if(!eligible)
				continue
			// Through dq_latent_attempt_collapse(): its frame is part of the calibrated held_refs.
			if(dq_latent_attempt_collapse(A, LATENCY_SWEEP_FRAME_REFS))
				break // holder.contents changed; the rest wait for next turn
			// Refused by latent_collapse() itself: back off for the holder's idle
			// delay instead of re-offering it (and re-running its refusal) every frame.
			COOLDOWN_START(A, latent_refused_until, max(holder?.latent_idle_delay_value(), LATENCY_REFUSAL_BACKOFF_MIN))
			log_runtime("LATENCY_SWEEP: [A.type] in [holder.type] refused collapse, retry after [DisplayTimeText(COOLDOWN_TIMELEFT(A, latent_refused_until))]: [GLOB.latent_last_refusal]")
	if(dead)
		holders -= dead
	cursor = index % max(length(holders), 1)

#undef LATENCY_SWEEP_BUDGET
#undef LATENCY_SWEEP_MS_BUDGET
#undef LATENCY_REFUSAL_BACKOFF_MIN
#undef LATENCY_SWEEP_FRAME_REFS

// ---- Admin toggle (containment.md Â§4.7 "Safety") ----

ADMIN_VERB(toggle_latency_policy, R_DEBUG, "Toggle Latency Policy", "Disables or re-enables automatic latent collapse for one holder's contents.", ADMIN_CATEGORY_DEBUG_MISC, atom/holder as obj|turf)
	holder.set_latent_policy_disabled(!holder.latent_policy_disabled())
	log_admin("[key_name(user)] turned the latency policy [holder.latent_policy_disabled() ? "off" : "on"] for [holder] ([COORD(holder)]).")
	message_admins("[key_name_admin(user)] turned the latency policy [holder.latent_policy_disabled() ? "off" : "on"] for [holder].")
	to_chat(user, span_notice("The latency policy is now [holder.latent_policy_disabled() ? "off" : "on"] for [holder]."))

/atom/register_latency_sweep()
	dq_latency_sweep_register(src)

/atom/unregister_latency_sweep()
	dq_latency_sweep_unregister(src)

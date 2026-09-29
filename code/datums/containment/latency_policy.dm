// The latency policy (roadmap C10, doc/rewrite/containment.md §4.7): decides,
// per atom, whether it may collapse into a latent entry right now, and runs
// the budgeted sweep that acts on that decision. Materializing stays
// event-driven (the existing triggers, containment.md §4.3, plus a viewer
// arriving); this only ever collapses.

/// Per-atom idle clock: world.time of the last materialize, move into a
/// holder, or interaction. Reset on every one of those, so the sweep only
/// offers atoms that have genuinely sat untouched.
/atom/movable
	EXPIRY_TMP_DECLARE(latent_touched_at)

/// world.time before which the sweep will not offer this atom again, set when
/// latent_collapse() refused it although can_be_latent() passed. A refusal is a
/// stable fact about the atom (an outside reference, a signal, a slot problem),
/// so retrying every frame only repeats the refusal -- and in test builds each
/// refcount refusal walks the world looking for the holder.
/atom/movable/var/tmp/latent_refused_until = 0

/// A holder's configured idle delay, in deciseconds, before its contents are
/// offered to the sweep. Holders may override for a shorter or longer delay
/// (a busy vending machine vs. a crate in a mothballed cargo bay).
/atom/var/latent_idle_delay = 2 MINUTES

/// Per-holder admin toggle (containment.md §4.7 "Safety"): independent of the
/// global kill switch, disables the policy just for this holder's contents.
/atom/var/latency_policy_disabled = FALSE

/**
 * Marks `A` as touched now, giving it a fresh idle timer. This is the one
 * seam idle tracking goes through -- called only from the ledger's own move
 * path (note_enter(), ledger.dm), which already covers an ordinary move, a
 * slot transaction (move_into()/slot_transfer(), api.dm) and adoption on
 * sync() (which is what a materialized atom's arrival goes through, since
 * dq_latent_create() makes it straight into the holder). Nothing else calls
 * this directly, so when DQ Medical's joint ledger before/after-move
 * transaction hook lands (medical_frameworks.md), swapping this one call
 * site onto it is the whole migration -- see containment.md §4.7.
 */
/proc/dq_latent_touch(atom/movable/A)
	if(A)
		EXPIRY_STAMP(A, latent_touched_at, CLOCK_WORLD)

// ---- Policy ----

/**
 * Whether `A` may be latent right now (containment.md §4.7). Composes:
 *   - the global kill switch;
 *   - its type is verified storable (dq_latent_eligible());
 *   - it is not pinned (dq_latent_pinned(): no explicit pin, an empty
 *     state_collapse_blockers(), not sitting directly on a turf);
 *   - nobody has an open tgui/browse window on its holder;
 *   - it is not in a holder's CONTAINER_SLOT_STOCK slot (C9's own
 *     collapse, not this one);
 *   - it has been idle at least its holder's configured delay;
 *   - neither the holder nor `A` itself opted out (latency_policy_disabled).
 * Does not check latent_collapse_refusal()'s slot/ledger bookkeeping; the
 * caller (dq_latent_attempt_collapse()) still goes through latent_collapse(),
 * which re-checks everything atomically.
 */
/// Why the last can_be_latent() call refused, for diagnostics and test failure messages.
GLOBAL_VAR_INIT(latency_last_ineligible, "")

/// `caller_refs`: references to A in the frames above (dq_latent_pinned()); 1 for a caller's variable.
/proc/can_be_latent(atom/movable/A, caller_refs = 1)
	. = FALSE
	if(!CONFIG_GET(flag/latency_policy_enabled))
		GLOB.latency_last_ineligible = "policy disabled"
		return
	if(!A || QDELETED(A) || !A.loc)
		GLOB.latency_last_ineligible = "gone or loc-less"
		return
	if(A.latency_policy_disabled || A.loc.latency_policy_disabled)
		GLOB.latency_last_ineligible = "policy disabled for [A.type] or its holder"
		return
	if(!A.loc.latent_contents)
		GLOB.latency_last_ineligible = "[A.loc.type] holds no latent contents"
		return
	if(!dq_latent_eligible(A.type))
		GLOB.latency_last_ineligible = "[A.type] is not latent-eligible"
		return
	if(dq_latent_pinned(A, caller_refs + 1))
		GLOB.latency_last_ineligible = "[A.type] is pinned ([GLOB.latency_last_pin_reason])"
		return
	if(LAZYLEN(A.loc.open_tguis))
		GLOB.latency_last_ineligible = "[A.loc.type] has an open UI"
		return
	// The stock slot (C9) is stock.dm's own: a vended item with unique
	// state lives in /datum/stored_item.instances, a bespoke collapse
	// the generic latent_entry API (latent_add()) doesn't know about.
	// /obj/machinery now sets latent_contents = TRUE for C6's machine
	// internals, and vending/smartfridge are machinery, so this can't
	// be a holder-level exclusion any more -- it has to be per slot.
	var/datum/ledger/L = dq_ledger_peek(A.loc)
	var/list/record = L?.entries[A]
	if(record && record[LEDGER_E_SLOT] == CONTAINER_SLOT_STOCK)
		GLOB.latency_last_ineligible = "[A.type] is in a stock slot"
		return
	var/delay = A.loc.latent_idle_delay
	var/idle = ELAPSED(A, latent_touched_at, CLOCK_WORLD)
	if(idle < delay)
		GLOB.latency_last_ineligible = "[A.type] idle [idle] of [delay]"
		return
	GLOB.latency_last_ineligible = ""
	return TRUE

// ---- Logging (containment.md §4.7 "Safety") ----

#define LATENCY_POLICY_LOG_MAX 200

GLOBAL_LIST_EMPTY(latency_policy_log)

/// Logs one collapse or materialize, by type paths rather than live refs (a
/// collapse's subject is deleted by the time this is useful to read).
/proc/dq_latency_log(action, type, holder_type, atom/holder)
	if(holder && !(holder.flags & ATOM_MATERIALIZED))
		return // sandboxed: not a live-world event
	var/line = "[worldtime2text()] [action] [type] ([holder_type ? "in [holder_type]" : "no holder"])"
	GLOB.latency_policy_log += line
	if(length(GLOB.latency_policy_log) > LATENCY_POLICY_LOG_MAX)
		GLOB.latency_policy_log.Cut(1, length(GLOB.latency_policy_log) - LATENCY_POLICY_LOG_MAX + 1)

#undef LATENCY_POLICY_LOG_MAX

// ---- Round-trip audit (containment.md §4.7 "Safety") ----

/// Whether the round-trip audit runs: always in test builds, else only with
/// the config flag (same gating shape as SSmobs.hibernation_audit_enabled()).
/proc/dq_latency_audit_enabled()
#if defined(UNIT_TESTS) || defined(TESTING)
	return TRUE
#else
	return CONFIG_GET(flag/latency_round_trip_audit)
#endif

/**
 * Checks a just-materialized atom against `before`, the full state its entry
 * carried from its last collapse (latent.dm's latent_collapse()/
 * latent_materialize() thread this through /datum/latent_entry.audit_blob).
 * Any mismatch is either a CRASH (test builds, which fails the running unit
 * test) or a logged runtime (live servers) -- either way it should never
 * happen if collapse and materialization are exact inverses.
 */
/proc/dq_latency_audit_check(atom/movable/A, list/before)
	if(!dq_latency_audit_enabled())
		return
	var/list/errors = list()
	var/list/after = state_serialize(A, STATE_FULL, errors)
	var/mismatch = !after || (state_hash(after) != state_hash(before))
	if(!mismatch)
		return
	var/message = "LATENCY_ROUND_TRIP_AUDIT: [A.type] materialized with different state than it collapsed with[length(errors) ? ": [jointext(errors, "; ")]" : ""]"
#if defined(UNIT_TESTS) || defined(TESTING)
	CRASH(message)
#else
	log_runtime(message)
#endif

// ---- Collapse attempt, wired to latent_collapse() ----

/// Tries to collapse `A` under the policy. Logging and the audit blob are
/// latent_collapse()'s own job (latent.dm), so every collapse is covered,
/// not just sweep-triggered ones. Returns TRUE if it collapsed (src deleted).
/proc/dq_latent_attempt_collapse(atom/movable/A, caller_refs = 1)
	if(!can_be_latent(A, caller_refs + 1))
		return FALSE
	return A.latent_collapse(caller_refs + 1)

// ---- The sweep (containment.md §4.7 "Sweep and hysteresis") ----

/// Checks per PERIODIC_SLOW frame (2 s): 32 per 4 s, as the reactor sweep spent.
#define LATENCY_SWEEP_BUDGET 16
/// Time a sweep frame may spend (ms). A collapse check scans the subtree's references and costs
/// 5-25 ms on a full locker, so an unbounded frame over 16 holders ran ~275 ms in one tick every
/// 2 s on Southern Cross. Past the budget the frame stops and the next frame resumes at the same
/// holder (refused atoms are on cooldown and collapsed ones are gone, so nothing repeats).
#define LATENCY_SWEEP_MS_BUDGET 4
/// References the sweep frame itself holds to the atom it checks (see periodic_step()).
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
	if(holder.latent_contents)
		GLOB.latency_sweep_holders[holder] = TRUE
		if(!om_task_periodic_running(GLOB.latency_sweep))
			om_task_periodic(GLOB.latency_sweep, PERIODIC_SLOW)

/proc/dq_latency_sweep_unregister(atom/holder)
	GLOB.latency_sweep_holders -= holder

/datum/latency_sweep
	var/cursor = 0

GLOBAL_DATUM_INIT(latency_sweep, /datum/latency_sweep, new)

// The sweep is a periodic lane member (object_model_core.md §4.10, PERIODIC_SLOW), not a
// reactor continuous declaration: budgeted collapse over latent holders (C10). It starts
// with the first registered holder (never at global init, before the OM core exists) and
// keeps running; a frame with no holders costs one length check.

/// One lane frame: spends a fixed budget of checks across the registered
/// holders, round-robin, collapsing whatever passes can_be_latent(). `delta`
/// only matters for rate models; the sweep itself just spends its budget
/// every frame.
/datum/latency_sweep/periodic_step(delta)
	if(!CONFIG_GET(flag/latency_policy_enabled))
		return
	var/list/holders = GLOB.latency_sweep_holders
	var/count = length(holders)
	if(!count)
		return
	var/checked = 0
	var/collapsed = 0
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
				COOLDOWN_START(A, latent_refused_until, max(holder.latent_idle_delay, LATENCY_REFUSAL_BACKOFF_MIN))
				stack_trace("LATENCY_SWEEP: can_be_latent([A.type] in [holder.type]) runtimed: [e.name] at [e.file]:[e.line] -- [e.desc]")
				continue
			if(!eligible)
				continue
			// Through dq_latent_attempt_collapse(): its frame is part of the calibrated held_refs.
			if(dq_latent_attempt_collapse(A, LATENCY_SWEEP_FRAME_REFS))
				collapsed++
				break // holder.contents changed; the rest wait for next turn
			// Refused by latent_collapse() itself: back off for the holder's idle
			// delay instead of re-offering it (and re-running its refusal) every frame.
			COOLDOWN_START(A, latent_refused_until, max(holder.latent_idle_delay, LATENCY_REFUSAL_BACKOFF_MIN))
			log_runtime("LATENCY_SWEEP: [A.type] in [holder.type] refused collapse, retry after [DisplayTimeText(COOLDOWN_TIMELEFT(A, latent_refused_until))]: [GLOB.latent_last_refusal]")
	if(dead)
		holders -= dead
	cursor = index % max(length(holders), 1)

#undef LATENCY_SWEEP_BUDGET
#undef LATENCY_SWEEP_MS_BUDGET
#undef LATENCY_REFUSAL_BACKOFF_MIN
#undef LATENCY_SWEEP_FRAME_REFS

// ---- Admin toggle (containment.md §4.7 "Safety") ----

ADMIN_VERB(toggle_latency_policy, R_DEBUG, "Toggle Latency Policy", "Disables or re-enables automatic latent collapse for one holder's contents.", ADMIN_CATEGORY_DEBUG_MISC, atom/holder as obj|turf)
	holder.latency_policy_disabled = !holder.latency_policy_disabled
	log_admin("[key_name(user)] turned the latency policy [holder.latency_policy_disabled ? "off" : "on"] for [holder] ([COORD(holder)]).")
	message_admins("[key_name_admin(user)] turned the latency policy [holder.latency_policy_disabled ? "off" : "on"] for [holder].")
	to_chat(user, span_notice("The latency policy is now [holder.latency_policy_disabled ? "off" : "on"] for [holder]."))

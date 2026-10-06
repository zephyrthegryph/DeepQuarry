// World actions: ACT_TRY, act_done, act_cancel (doc/rewrite/final_api.html, section 8 "World actions", "Outcomes and notices"; section 19 "E4").
//
// `ACTION()` (code/engine/_generated/actions.dm) writes the act type, `act_<name>()` and the notice of each action. act_<name>() is
// what ACT_TRY(src, name, fields...) calls, and it does three things in this order:
//
//   1. act_wanted(): nothing hooks the action and nothing listens for its notice, for any outcome -> ACT_PASS (nothing allocated).
//   2. act_begin(): nested actions stop at depth ACT_MAX_DEPTH (a ninth nested action ends ACT_REFUSED, "too deeply nested", logged chain,
//      and fails a test build); otherwise the pooled act is taken and its holder and target set.
//   3. act_resolve(): needs refuse, the first instead in order takes over (ACT_REPLACED), every adjusts applies in order. What comes back
//      is the final act (the caller reads its fields with ACT_FINAL and ends it with act_done()), or null when it was refused or taken over.
//
// act_done(A) ends it ACT_COMMITTED, delivers the past-tense notice to the listeners that asked for that outcome, and releases the context;
// act_cancel(A) ends it ACT_REFUSED. The depth counter is GLOB.act_depth: the number of handlers running right now. A handler that starts an
// action or publishes a notice is one deeper.

/// Handlers running right now (hook parts, notice handlers): the synchronous nesting depth.
GLOBAL_VAR_INIT(act_depth, 0)
/// How many times the kernel backstop had to reset a leaked depth.
GLOBAL_VAR_INIT(act_backstops, 0)
/// Counters (metrics, and what a test reads): contexts taken, notices taken, notices queued past the depth cap, actions refused for depth.
GLOBAL_VAR_INIT(act_taken, 0)
GLOBAL_VAR_INIT(notice_taken, 0)
GLOBAL_VAR_INIT(notice_late, 0)
GLOBAL_VAR_INIT(act_too_deep, 0)
/// The chain of what is running, innermost last: logged when the depth cap trips.
GLOBAL_LIST_EMPTY(act_chain)
/// A test that provokes a depth report on purpose sets this to a list; the report goes there instead of failing the run.
GLOBAL_VAR(act_report_capture)

MSG_DEF_SELF(act/too_deeply_nested, "too deeply nested")

/// A depth report (an action refused, a notice queued): the capture list when a test set one, else a runtime that fails a test build.
/proc/act_report(rule, message)
	var/list/capture = GLOB.act_report_capture
	if(islist(capture))
		capture += "[rule]: [message]"
		return
	stack_trace("ACT: [rule]: [message]")

/// The chain of nested handlers as text, for a report.
/proc/act_chain_text()
	return length(GLOB.act_chain) ? jointext(GLOB.act_chain, " > ") : "(top level)"

/// Who does the next action and under what authority: a caller that starts a world action for an actor (slot_transfer()) sets these just
/// before ACT_TRY() and clears them after; act_begin() consumes them, so only that one action carries them (a nested action starts clean).
/// An action begun under AUTH_ADMIN skips its needs() hooks (the forced transfer): its instead() and adjusts() still run.
GLOBAL_VAR(act_next_actor)
GLOBAL_VAR(act_next_authority)

/// Puts the nesting depth and the chain back to what they were when a handler began, after it runtimed. Without it each runtime in a hook leaks one level
/// of GLOB.act_depth for the rest of the round, and after ACT_MAX_DEPTH of them every action is refused and every notice queued late.
/proc/act_unwind(depth, chain_len, what, exception/fault)
	if(GLOB.act_depth != depth)
		log_world("ACT: unwound the depth from [GLOB.act_depth] to [depth] after a runtime in [what]: [fault?.name] ([fault?.file]:[fault?.line])")
	GLOB.act_depth = depth
	if(length(GLOB.act_chain) > chain_len)
		GLOB.act_chain.len = chain_len

/// The kernel's backstop (phase K, each tick): no handler is running between ticks, so a non-zero depth or a left-over chain is a leak. Reset and logged.
/// Returns TRUE when it had to reset something.
/proc/act_backstop_reset()
	if(!GLOB.act_depth && !length(GLOB.act_chain))
		return FALSE
	log_world("ACT: kernel backstop reset act_depth [GLOB.act_depth] and a chain of [length(GLOB.act_chain)] at the start of a tick (a handler leaked it): [act_chain_text()]")
	GLOB.act_depth = 0
	GLOB.act_chain.len = 0
	GLOB.act_backstops++
	return TRUE

/// A pooled act of `type`, with its holder and target set; null when nesting is at the cap (the action is refused and reported).
/proc/act_begin(act_type, datum/holder)
	if(GLOB.act_depth >= ACT_MAX_DEPTH)
		GLOB.act_too_deep++
		GLOB.act_last_outcome = ACT_REFUSED
		GLOB.act_last_reply = null
		var/chain = act_chain_text()
		TEST_REC_OUTCOME("[act_type]", ACT_REFUSED, /datum/msg/act/too_deeply_nested, null)
		log_world("ACT: [act_type] on [holder?.type] refused: nested deeper than [ACT_MAX_DEPTH] ([chain])")
		act_report(RULE_ACT_DEPTH, "[act_type] on [holder?.type] ended ACT_REFUSED (too deeply nested; the depth cap is [ACT_MAX_DEPTH]): [chain]")
		return null
	var/datum/act/action/A = take(act_type)
	GLOB.act_taken++
	A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.target = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.actor = GLOB.act_next_actor // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.authority = GLOB.act_next_authority
	GLOB.act_next_actor = null
	GLOB.act_next_authority = null
	return A

/// Runs the hooks of the action: needs, instead, adjusts. Returns the act (the caller goes on), or null (refused or taken over: the act is
/// ended and released here).
/proc/act_resolve(datum/act/action/A)
	var/datum/act_plan/P = act_plan_for(A.holder, A.type)
	var/forced = isnum(A.authority) && (A.authority & AUTH_ADMIN)
	for(var/datum/hook/H as anything in P.needs)
		if(forced)
			break // an admin authority skips requirements (a forced slot transfer), never the takeovers and adjustments below
		if(!hook_conditions_hold(H, A.holder))
			continue
		var/datum/entered_from = hook_enter(A, H)
		if(!entered_from)
			continue
		var/reason = act_needs_refusal(A, H)
		A.holder = entered_from // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		if(reason)
			A.reason = reason
			act_end(A, ACT_REFUSED)
			return null
	for(var/datum/hook/H as anything in P.instead)
		if(!hook_conditions_hold(H, A.holder))
			continue
		var/datum/entered_from = hook_enter(A, H)
		if(!entered_from)
			continue
		hook_context(A, H)
		var/depth = GLOB.act_depth
		var/chain_len = length(GLOB.act_chain)
		GLOB.act_chain += "[A.type]:[H.cap_key || H.activation?.def.key || "type"]"
		var/took
		try
			took = hook_run_parts(H, A, H.entry.children)
		catch(var/exception/fault)
			act_unwind(depth, chain_len, "instead hook of [A.type]", fault)
			throw fault
		GLOB.act_chain.len--
		A.holder = entered_from // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		if(took)
			act_end(A, ACT_REPLACED)
			return null
	for(var/datum/hook/H as anything in P.adjusts)
		if(!hook_conditions_hold(H, A.holder))
			continue
		var/datum/entered_from = hook_enter(A, H)
		if(!entered_from)
			continue
		hook_context(A, H)
		act_apply_adjust(A, H)
		A.holder = entered_from // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.activation = null // ALLOW(ownership): an engine record the one teardown path drops
	A.cap = null
	A.source = null // ALLOW(ownership): an engine record the one teardown path drops
	return A

/// An observe() hook (on_listener) runs its parts on the listener: A.holder is the listener while the hook runs and A.target stays the observed entity. Returns
/// the holder to put back afterwards (A.holder itself for an ordinary hook), or null when the listener is gone and the hook is skipped.
/proc/hook_enter(datum/act/A, datum/hook/H)
	if(!H.on_listener)
		return A.holder
	var/datum/listener = H.activation?.source
	if(!isdatum(listener) || QDELETED(listener))
		return null
	var/datum/was = A.holder
	A.holder = listener // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	return was

/// Sets the entry-level fields of the context for hook H: the activation running it, its capability and its source.
/proc/hook_context(datum/act/A, datum/hook/H)
	A.activation = H.activation // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	if(H.activation)
		A.cap = H.activation.def
		A.source = H.activation.source // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	else
		A.cap = H.cap_key ? table_of(A.holder).caps[H.cap_key] : null
		A.source = A.holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release

/// A static hook declared inside when() blocks applies while every one of them holds on the holder.
/proc/hook_conditions_hold(datum/hook/H, datum/holder)
	for(var/datum/entry/W as anything in H.whens)
		if(!condition_holds(holder, W.args["cond"]))
			return FALSE
	return TRUE

/// One adjusts(): scale first, then by, on the named field of the act ("packet.amount" walks through the packet).
/proc/act_apply_adjust(datum/act/A, datum/hook/H)
	var/list/opts = H.entry.args
	if(opts["when"] && !hook_gate(H, A, opts["when"]))
		return
	if(opts["with"])
		hook_call(H, opts["with"], A) // adjusts_with(): the handler writes the act's fields itself
		return
	var/list/path = splittext(opts["field"], ".")
	var/datum/walk = A
	for(var/i in 1 to length(path) - 1)
		walk = walk.vars[path[i]]
		if(!walk)
			return
	var/field = path[length(path)]
	var/current = walk.vars[field]
	if(islist(current))
		// A list of amounts (packet.amounts): scale and by apply to every positive entry, which never goes below zero.
		var/list/amounts = current
		for(var/i in 1 to length(amounts))
			var/entry = amounts[i]
			if(!isnum(entry) || entry <= 0)
				continue
			if(!isnull(opts["scale"]))
				entry *= opts["scale"]
			if(!isnull(opts["by"]))
				entry += opts["by"]
			amounts[i] = max(0, entry)
		return
	if(!isnum(current))
		declare_report("adjusts([opts["field"]]) on [A.type]: the field is not a number ([current])")
		return
	if(!isnull(opts["scale"]))
		current *= opts["scale"]
	if(!isnull(opts["by"]))
		current += opts["by"]
	walk.vars[field] = current // ALLOW(api): adjusts() names a typed field of the action by its declared path

/// How the last action that ended (act_end) ended and why: ACT_TRY returns null for a refused action and a taken-over one alike, and the op engine's
/// put_in() reports the two differently (OP_REFUSED, OP_REPLACED).
GLOBAL_VAR(act_last_outcome)
GLOBAL_VAR(act_last_reason)
/// What the hook that took the last ended action over answered (the value its then() handler returned, or what it set in A.reply): the payload of a
/// veto. Read it right after ACT_TRY returned null with ACT_TAKEN_OVER.
GLOBAL_VAR(act_last_reply)

/// Ends the act with `outcome`, delivers its notice to the listeners that asked for that outcome, and releases it.
/proc/act_end(datum/act/action/A, outcome)
	A.outcome = outcome
	GLOB.act_last_outcome = outcome
	GLOB.act_last_reason = A.reason
	GLOB.act_last_reply = A.reply
	var/notice_type = act_notice_type(A.type)
	var/datum/holder = A.holder
	if(notice_type && !QDELETED(holder) && notice_wanted(holder, notice_type, outcome))
		var/datum/notice/N = A.make_notice()
		notice_publish(holder, N, outcome)
	A.release()

/// Ends an action ACT_COMMITTED: publishes its notice and releases the context. A no-op for ACT_PASS.
/proc/act_done(datum/act/A)
	if(A == ACT_PASS || !A)
		return
	act_end(A, ACT_COMMITTED)

/// A path that decides not to finish: releases the context and ends it ACT_REFUSED, publishing to nobody who has not asked.
/proc/act_cancel(datum/act/A)
	if(A == ACT_PASS || !A)
		return
	act_end(A, ACT_REFUSED)

/// Maps an act's outcome to an op effect report: committed is OP_OK, refused OP_REFUSED, replaced OP_REPLACED.
/proc/act_outcome_to_op(datum/act/action/A)
	var/outcome = A?.outcome
	if(isnull(outcome))
		return OP_FAILED
	if(outcome & ACT_COMMITTED)
		return OP_OK
	if(outcome & ACT_REPLACED)
		return OP_REPLACED
	if(outcome & ACT_REFUSED)
		return OP_REFUSED
	return OP_FAILED

/// The notice of this action's outcome, filled from the act's final fields: ACTION() writes it for each action.
/datum/act/action/proc/make_notice()
	return null

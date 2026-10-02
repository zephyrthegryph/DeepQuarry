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

/// A pooled act of `type`, with its holder and target set; null when nesting is at the cap (the action is refused and reported).
/proc/act_begin(act_type, datum/holder)
	if(GLOB.act_depth >= ACT_MAX_DEPTH)
		GLOB.act_too_deep++
		var/chain = act_chain_text()
		TEST_REC_OUTCOME("[act_type]", ACT_REFUSED, /datum/msg/act/too_deeply_nested, null)
		log_world("ACT: [act_type] on [holder?.type] refused: nested deeper than [ACT_MAX_DEPTH] ([chain])")
		act_report(RULE_ACT_DEPTH, "[act_type] on [holder?.type] ended ACT_REFUSED (too deeply nested; the depth cap is [ACT_MAX_DEPTH]): [chain]")
		return null
	var/datum/act/action/A = take(act_type)
	GLOB.act_taken++
	A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.target = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	return A

/// Runs the hooks of the action: needs, instead, adjusts. Returns the act (the caller goes on), or null (refused or taken over: the act is
/// ended and released here).
/proc/act_resolve(datum/act/action/A)
	var/datum/act_plan/P = act_plan_for(A.holder, A.type)
	for(var/datum/hook/H as anything in P.needs)
		if(!hook_conditions_hold(H, A.holder))
			continue
		var/reason = act_needs_refusal(A, H)
		if(reason)
			A.reason = reason
			act_end(A, ACT_REFUSED)
			return null
	for(var/datum/hook/H as anything in P.instead)
		if(!hook_conditions_hold(H, A.holder))
			continue
		hook_context(A, H)
		GLOB.act_chain += "[A.type]:[H.cap_key || H.activation?.def.key || "type"]"
		var/took = hook_run_parts(H, A, H.entry.children)
		GLOB.act_chain.len--
		if(took)
			act_end(A, ACT_REPLACED)
			return null
	for(var/datum/hook/H as anything in P.adjusts)
		if(!hook_conditions_hold(H, A.holder))
			continue
		hook_context(A, H)
		act_apply_adjust(A, H)
	A.activation = null // ALLOW(ownership): an engine record the one teardown path drops
	A.cap = null
	A.source = null // ALLOW(ownership): an engine record the one teardown path drops
	return A

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

/// Ends the act with `outcome`, delivers its notice to the listeners that asked for that outcome, and releases it.
/proc/act_end(datum/act/action/A, outcome)
	A.outcome = outcome
	GLOB.act_last_outcome = outcome
	GLOB.act_last_reason = A.reason
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

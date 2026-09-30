// Operation contexts (doc/rewrite/dx_conventions.md, "Operations").
//
// One /datum/op_ctx describes one attempt at one operation: who (actor), on what (target), with
// what (held), which operation (op), through which provider (the slot that gives the actor the
// affordance the op needs; active hand first), over which route, and on whose authority. Contexts
// are pooled: take them with op_ctx_take(), give them back with release(); a released context is
// poisoned in test builds (any use CRASHes).
//
// check() runs the requirement stages in one fixed order, and stops at the first failure:
//   1 provider           the actor has a slot providing the affordance (op.by)
//   2 route              the op accepts this route, the target is reachable that way, the bay's
//                        compartment lets the route through
//   3 actor state        conscious and capable (OP_EMERGENCY: alive); skipped for legacy presets
//   4 target contract    the target's own gating (behind/locked/broken/powered/needs/cooldown)
//   5 capability         every cap_require() of the target that names this op or its kind
//     contracts
//   6 op needs           the op's own needs (requirements)
// The same check() runs before the wait, again when the wait ends and again at commit (the
// interaction machinery calls it through why_not()), so a wait never commits a stale answer.
// A pending (waiting) operation also watches the reads of its requirements and cancels early when
// one is published (op_reads_changed()).
//
// Reactions: op_before(ctx) runs just before the commit (FALSE stops it) and op_after(ctx) right
// after; W1's before_op/after_op reactions attach to these two procs.

GLOBAL_VAR_INIT(op_ctx_seq, 0)
/// Free contexts, reused by op_ctx_take().
GLOBAL_LIST_EMPTY(op_ctx_pool)
/// Contexts alive right now (taken, not released): id -> ctx. The pool's leak check reads it.
GLOBAL_LIST_EMPTY(op_ctx_live)
/// How many free contexts the pool keeps.
#define OP_CTX_POOL_MAX 32

/datum/op_ctx
	/// The mob acting.
	var/mob/actor
	var/datum/target
	var/obj/item/held
	var/datum/op_def/op
	/// The interaction entry running this op, when it came through the resolver.
	var/datum/interaction/capability/entry
	/// The slot decl that provides the affordance (a hand), and the ledger id of the actor's slot.
	var/datum/om/relation/slot/provider
	/// ROUTE_*: how this attempt reaches the target.
	var/route = ROUTE_PHYSICAL
	/// Who authorizes it when route is ROUTE_AUTHORITY (an admin mob, a console); else null.
	var/datum/authority
	/// Unique per take: the handle a pending wait carries instead of the context itself.
	var/id = 0
	/// Text detail for a reason that has a %DETAIL% slot.
	var/detail
	/// The reason (a /datum/msg type) the last check() failed with, and the stage it failed at.
	var/reason
	var/failed_stage = 0
	/// (datum, key) pairs a pending wait watches: list(list(datum, key), ...).
	var/list/watch
	/// Set once release() ran; touching a released context is a bug (CRASH in test builds).
	var/released = FALSE

/// A pooled context for one attempt.
/proc/op_ctx_take(mob/actor, datum/target, obj/item/held, datum/op_def/op, route = ROUTE_PHYSICAL, datum/authority)
	RETURN_TYPE(/datum/op_ctx)
	var/datum/op_ctx/ctx
	if(length(GLOB.op_ctx_pool))
		ctx = GLOB.op_ctx_pool[length(GLOB.op_ctx_pool)]
		GLOB.op_ctx_pool.len--
	else
		ctx = new
	ctx.released = FALSE
	ctx.id = ++GLOB.op_ctx_seq
	ctx.actor = actor
	ctx.target = target
	ctx.held = held
	ctx.op = op
	ctx.route = route
	ctx.authority = authority
	GLOB.op_ctx_live["[ctx.id]"] = ctx
	return ctx

/// Gives the context back: every field returns to its initial value, and the context waits in the pool.
/datum/op_ctx/proc/release()
	if(released)
#ifdef UNIT_TESTS
		CRASH("op_ctx released twice")
#else
		return
#endif
	op_pending_forget(src)
	GLOB.op_ctx_live -= "[id]"
	actor = null
	target = null
	held = null
	op = null
	entry = null
	provider = null
	authority = null
	route = initial(route)
	detail = null
	reason = null
	failed_stage = 0
	watch = null
	id = 0
	released = TRUE
	if(length(GLOB.op_ctx_pool) < OP_CTX_POOL_MAX)
		GLOB.op_ctx_pool += src

/// The test-build poison: reading a released context stops the test that did.
/datum/op_ctx/proc/assert_live()
#ifdef UNIT_TESTS
	if(released)
		CRASH("use of a released op_ctx")
#endif

/// The atom the provider stands for: the item held in it, else the actor.
/datum/op_ctx/proc/provider_atom()
	if(provider && actor)
		var/obj/item/in_slot = actor.get_equipped_item(provider.slot_id)
		if(in_slot)
			return in_slot
	return actor

/// The reason text for the last failure, for the player.
/datum/op_ctx/proc/reason_text()
	return req_reason_text(reason, src)

/// Records a failure and returns the reason.
/datum/op_ctx/proc/fail(reason_type, stage)
	reason = reason_type
	failed_stage = stage
	return reason_type

/// null when the operation may run now, else the reason (a /datum/msg type). Runs the stages in
/// order up to and including `upto`.
/datum/op_ctx/proc/check(upto = OP_STAGE_ALL)
	assert_live()
	reason = null
	failed_stage = 0
	if(!op)
		return null
	var/why
	if(upto >= OP_STAGE_PROVIDER)
		why = stage_provider()
		if(why)
			return fail(why, OP_STAGE_PROVIDER)
	if(upto >= OP_STAGE_ROUTE)
		why = stage_route()
		if(why)
			return fail(why, OP_STAGE_ROUTE)
	if(upto >= OP_STAGE_ACTOR)
		why = stage_actor()
		if(why)
			return fail(why, OP_STAGE_ACTOR)
	if(upto >= OP_STAGE_TARGET)
		why = stage_target()
		if(why)
			return fail(why, OP_STAGE_TARGET)
	if(upto >= OP_STAGE_CAPS)
		why = stage_caps()
		if(why)
			return fail(why, OP_STAGE_CAPS)
	if(upto >= OP_STAGE_NEEDS)
		why = stage_needs()
		if(why)
			return fail(why, OP_STAGE_NEEDS)
	return null

/datum/op_ctx/proc/stage_provider()
	provider = null
	if(!op.by)
		return null
	if(route == ROUTE_AUTHORITY || route == ROUTE_MIND || !ismob(actor))
		return null
	provider = ops_provider(actor, op.by)
	return provider ? null : /datum/msg/req_no_provider

/datum/op_ctx/proc/stage_route()
	if(!(op.via & route))
		return /datum/msg/req_no_route
	if(route == ROUTE_PHYSICAL && isatom(target) && !GLOB.interaction_entry_actors[actor] && !dq_interaction_reach(actor, target, held))
		return /datum/msg/req_out_of_reach
	if(op.at && isatom(target))
		var/datum/capability/compartment/bay = compartment_of(target, op.at)
		if(!bay)
			return /datum/msg/req_sealed
		if(!bay.passes(route, src))
			return reason || /datum/msg/req_sealed
	return null

/datum/op_ctx/proc/stage_actor()
	if(op.legacy || route == ROUTE_AUTHORITY || !ismob(actor))
		return null
	if(QDELETED(actor) || actor.stat == DEAD)
		return /datum/msg/req_not_capable
	if(op.kind == OP_EMERGENCY)
		return null
	if(actor.stat != CONSCIOUS || actor.incapacitated())
		return /datum/msg/req_not_capable
	return null

/datum/op_ctx/proc/stage_target()
	if(!entry || !isatom(target))
		return null
	var/why = cap_gate_reason(target, actor, held, entry)
	if(!why)
		return null
	detail = why
	return /datum/msg/req_refused

/datum/op_ctx/proc/stage_caps()
	if(!isatom(target))
		return null
	var/atom/A = target
	for(var/datum/capability/require/C as anything in caps_all_of_type(A, /datum/capability/require))
		if(!C.covers(op))
			continue
		for(var/datum/req/R as anything in C.reqs)
			var/why = R.test(src)
			if(why)
				return why
	return null

/datum/op_ctx/proc/stage_needs()
	for(var/datum/req/R as anything in op.needs)
		var/why = R.test(src)
		if(why)
			return why
	return null

/// Every (datum, key) pair the requirements of this attempt read, for a pending wait to watch.
/datum/op_ctx/proc/collect_reads()
	. = list()
	if(!op)
		return
	for(var/datum/req/R as anything in op.needs)
		var/list/mine = R.reads(src)
		if(mine)
			. += mine
	for(var/datum/req/R as anything in op.gating)
		var/list/mine = R.reads(src)
		if(mine)
			. += mine
	if(isatom(target))
		for(var/datum/capability/require/C as anything in caps_all_of_type(target, /datum/capability/require))
			if(!C.covers(op))
				continue
			for(var/datum/req/R as anything in C.reqs)
				var/list/mine = R.reads(src)
				if(mine)
					. += mine

/// The capabilities of A that are of `type`.
/proc/caps_all_of_type(atom/A, type)
	. = list()
	for(var/datum/capability/C as anything in caps_all(A))
		if(istype(C, type))
			. += C

// ---- the slot providers ----

/// The slot of `actor` that provides every bit of `affordance`: the active hand first, then the
/// rest in slot order. Null when there is none (no hands, hands busy being absent).
/proc/ops_provider(mob/actor, affordance)
	RETURN_TYPE(/datum/om/relation/slot)
	if(!affordance)
		return null
	var/list/defs = dq_slot_defs_for(actor)
	if(!length(defs))
		return null
	var/active = actor.active_hand_slot_id()
	var/datum/om/relation/slot/found
	for(var/datum/om/relation/slot/def as anything in defs)
		if((def.provides & affordance) != affordance)
			continue
		if(!ops_slot_usable(actor, def))
			continue
		if(def.slot_id == active)
			return def
		found ||= def
	return found

/// Whether `def` works for `actor` right now (a hand slot needs hands).
/proc/ops_slot_usable(mob/actor, datum/om/relation/slot/def)
	var/mob/living/L = actor
	if(istype(def, /datum/om/relation/slot/body) && istype(L))
		return !L.body_slot_refusal(def)
	return TRUE

/// The SLOT_ID_* of the hand this mob acts with, or null.
/mob/proc/active_hand_slot_id()
	return null

/mob/living/active_hand_slot_id()
	return hand ? SLOT_ID_HAND_L : SLOT_ID_HAND_R

// ---- pending operations: the wait, and the early cancel ----

/// "[id]" -> ctx for every operation waiting on a timer.
GLOBAL_LIST_EMPTY(op_pending)
/// "[REF(datum)]|[key]" -> list of pending contexts watching that read.
GLOBAL_LIST_EMPTY(op_watchers)

/// Registers ctx as waiting and watching its reads.
/proc/op_pending_add(datum/op_ctx/ctx)
	GLOB.op_pending["[ctx.id]"] = ctx
	ctx.watch = ctx.collect_reads()
	for(var/list/pair as anything in ctx.watch)
		var/index = "[REF(pair[1])]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			on = list()
			GLOB.op_watchers[index] = on
		on |= ctx

/// Drops ctx from the pending set and the watch index.
/proc/op_pending_forget(datum/op_ctx/ctx)
	if(!GLOB.op_pending["[ctx.id]"])
		return
	GLOB.op_pending -= "[ctx.id]"
	for(var/list/pair as anything in ctx.watch)
		var/index = "[REF(pair[1])]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			continue
		on -= ctx
		if(!length(on))
			GLOB.op_watchers -= index
	ctx.watch = null

/// A read (E, key) was published: every pending operation watching it re-checks now and cancels
/// if a requirement no longer holds. Cheap when nothing is pending. W1's publish_change() calls
/// this; cap_set() calls it for OP_KEY_CAP_STATE.
/proc/op_reads_changed(datum/E, key)
	if(!length(GLOB.op_watchers))
		return
	var/list/on = GLOB.op_watchers["[REF(E)]|[key]"]
	if(!length(on))
		return
	for(var/datum/op_ctx/ctx as anything in on.Copy())
		if(ctx.released)
			continue
		var/why = ctx.check()
		if(why)
			op_cancel(ctx, why)

/// Stops a waiting operation: the timer is cancelled, the actor told why, the context released.
/proc/op_cancel(datum/op_ctx/ctx, reason_type)
	var/mob/actor = ctx.actor
	var/text = req_reason_text(reason_type || /datum/msg/req_cancelled, ctx)
	if(actor)
		om_cancel_timer_slot(actor, "op_wait")
		to_chat(actor, span_warning(text))
	if(ctx.op)
		GLOB.op_cancelled_log += "[ctx.op.key]|[reason_type]"
	ctx.release()

/// Test builds read this: "[op key]|[reason type]" per early cancel.
GLOBAL_LIST_EMPTY(op_cancelled_log)

/// The wait timer fired for pending context `id`.
/proc/op_wait_done(id)
	var/datum/op_ctx/ctx = GLOB.op_pending["[id]"]
	if(!ctx || ctx.released)
		return
	var/datum/interaction/capability/E = ctx.entry
	var/mob/actor = ctx.actor
	var/datum/target = ctx.target
	var/obj/item/held = ctx.held
	var/route = ctx.route
	ctx.release()
	if(!E || QDELETED(actor) || QDELETED(target))
		return
	// The wait is over: the requirements are checked again inside cost_paid() -> finish_attempt(),
	// over the route the attempt started with.
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	E.cost_paid(actor, target, held)
	GLOB.op_route_now = saved

/// The reactions' hook points. op_before(ctx) runs just before an operation commits and returns
/// FALSE to stop it; op_after(ctx) runs right after it committed. W1's before_op/after_op
/// reactions are wired to these two procs at integration; until then they only trace in tests.
/proc/op_before(datum/op_ctx/ctx)
#ifdef UNIT_TESTS
	GLOB.op_hook_trace += "before|[ctx.op?.key]"
#endif
	return TRUE

/proc/op_after(datum/op_ctx/ctx)
#ifdef UNIT_TESTS
	GLOB.op_hook_trace += "after|[ctx.op?.key]"
#endif
	return

/// Declared in every build so the linter, which reads tests without UNIT_TESTS, resolves it.
GLOBAL_LIST_EMPTY(op_hook_trace)

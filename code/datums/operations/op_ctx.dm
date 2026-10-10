// Operation contexts (doc/rewrite/dx_conventions.md, "Operations").
//
// One /datum/op_ctx describes one attempt at one operation: who (actor), on what (target), with
// what (held), which operation (op), through which provider (the slot that gives the actor the
// affordance the op needs; active hand first), over which route, and on whose authority. Contexts
// are pooled (/datum/pooled): take them with op_ctx_take(), give them back with release(); a released
// context is poisoned in test builds (any use CRASHes).
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
// Reactions: op_before(ctx) runs just before the commit and returns a refusal reason (or null); op_after(ctx)
// runs right after. They call the target's before_op / after_op reactions (reactions/delivery.dm).

GLOBAL_VAR_INIT(op_ctx_seq, 0)

/datum/op_ctx
	parent_type = /datum/operation_context
	var/datum/op_def/op
	var/datum/interaction/capability/entry
	var/datum/relation_definition/slot/provider

/// A pooled context for one attempt (a /datum/pooled: released fields return to their initial values).
/proc/op_ctx_take(mob/actor, datum/target, obj/item/held, datum/op_def/op, route = ROUTE_PHYSICAL, datum/authority)
	RETURN_TYPE(/datum/op_ctx)
	var/datum/op_ctx/ctx = take(/datum/op_ctx)
	ctx.released = FALSE
	ctx.id = ++GLOB.op_ctx_seq
	// flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.actor = actor
	// flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.target = target
	// flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.held = held
	// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.op = op
	ctx.route = route
	// flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.authority = authority
	return ctx

/// How many contexts are taken and not yet released (the pool's own accounting; a leak check reads it).
/proc/op_ctx_live_count()
	var/datum/object_pool/pool = GLOB.object_pools[/datum/op_ctx]
	return pool ? pool.out : 0

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
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	provider = null
	// ROUTE_TK: the provider is the telekinesis affordance (mob/has_telegrip()), not a slot. It stands in for manipulating
	// and working controls (AFF_TK_PROVIDES); it holds nothing.
	if(route == ROUTE_TK)
		var/mob/M = actor
		if(!istype(M) || !M.has_telegrip())
			return /datum/msg/req_no_provider
		return (op.by & ~AFF_TK_PROVIDES) ? /datum/msg/req_no_provider : null
	if(!op.by)
		return null
	if(route == ROUTE_AUTHORITY || route == ROUTE_MIND || !ismob(actor))
		return null
	// A silicon works a control through its interface (its empty-handed click, a window): the interface is the provider
	// of manipulating and working controls (AFF_INTERFACE_PROVIDES); it holds nothing.
	if((route & (ROUTE_INTERFACE | ROUTE_UI)) && issilicon(actor))
		return (op.by & ~AFF_INTERFACE_PROVIDES) ? /datum/msg/req_no_provider : null
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	provider = ops_provider(actor, op.by)
	return provider ? null : /datum/msg/req_no_provider

/datum/op_ctx/proc/stage_route()
	if(!(op.via & route))
		return /datum/msg/req_no_route
	if(route == ROUTE_PHYSICAL && isatom(target) && !dq_interaction_reach(actor, target, held))
		return /datum/msg/req_out_of_reach
	if(route == ROUTE_TK && isatom(target) && !op_tk_reach(actor, target))
		return /datum/msg/req_out_of_reach
	if(op.at && isatom(target))
		return op_at_reason(target, op.at, src)
	return null

/// Whether `actor` reaches `target` telekinetically: in sight on its own z-level, within TK_MAXRANGE, not while viewing
/// remotely (the ranged click's own rules, mob/living/carbon/human/RangedAttack()).
/proc/op_tk_reach(mob/actor, atom/target)
	var/turf/origin = get_turf(actor)
	var/turf/destination = get_turf(target)
	if(!origin || !destination || origin.z != destination.z)
		return FALSE
	if(get_dist(origin, destination) > TK_MAXRANGE)
		return FALSE
	return !actor.is_remote_viewing()

/datum/op_ctx/proc/stage_actor()
	if(op.legacy || route == ROUTE_AUTHORITY || !ismob(actor))
		return null
	// An observer is never alive or capable: what it may do its route and its adapter already limit (ROUTE_UI, the ghost
	// adapter's observer ops).
	if(isobserver(actor))
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
	RETURN_TYPE(/datum/relation_definition/slot)
	if(!affordance)
		return null
	var/list/defs = dq_slot_defs_for(actor)
	if(!length(defs))
		return null
	var/active = actor.active_hand_slot_id()
	var/datum/relation_definition/slot/found
	for(var/datum/relation_definition/slot/def as anything in defs)
		if((def.provides & affordance) != affordance)
			continue
		if(!ops_slot_usable(actor, def))
			continue
		if(def.slot_id == active)
			return def
		found ||= def
	return found

/// Whether `def` works for `actor` right now (a hand slot needs hands).
/proc/ops_slot_usable(mob/actor, datum/relation_definition/slot/def)
	var/mob/living/L = actor
	if(istype(def, /datum/relation_definition/slot/body) && istype(L))
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

/// Registers ctx as waiting: it watches its requirements' reads (each counts as a dynamic reader of its key, so
/// publish_change() reaches op_reads_changed()) and is registered on every datum it is about, so that one
/// being deleted cancels it (rx_teardown). Datums that never wait on an operation carry nothing.
/proc/op_pending_add(datum/op_ctx/ctx)
	GLOB.op_pending["[ctx.id]"] = ctx
	ctx.watch = ctx.collect_reads()
	var/list/ends = list()
	for(var/datum/D in list(ctx.actor, ctx.target, ctx.held, ctx.provider_atom()))
		ends |= D
	for(var/list/pair as anything in ctx.watch)
		var/datum/watched = pair[1]
		if(!QDELETED(watched))
			ends |= watched
			rx_watch_adjust(watched, pair[2], 1)
		var/index = "[REF(watched)]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			on = list()
			GLOB.op_watchers[index] = on
		on |= ctx
	for(var/datum/D as anything in ends)
		if(QDELING(D))
			ends -= D
			continue
		LAZYADD(rx_of(D).pending_ops, ctx)
	ctx.ends = ends

/// Drops ctx from the pending set, the watch index and every datum it was registered on.
/proc/op_pending_forget(datum/op_ctx/ctx)
	if(!GLOB.op_pending["[ctx.id]"])
		return
	GLOB.op_pending -= "[ctx.id]"
	for(var/list/pair as anything in ctx.watch)
		var/datum/watched = pair[1]
		if(!QDELETED(watched))
			rx_watch_adjust(watched, pair[2], -1)
		var/index = "[REF(watched)]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			continue
		on -= ctx
		if(!length(on))
			GLOB.op_watchers -= index
	for(var/datum/D as anything in ctx.ends)
		var/datum/rx_state/S = D.rx
		if(S)
			LAZYREMOVE(S.pending_ops, ctx)
	ctx.ends = null
	ctx.watch = null

/// Stops a waiting operation: the timer is cancelled, the actor told why, the context released.
/proc/op_cancel(datum/op_ctx/ctx, reason_type)
	var/mob/actor = ctx.actor
	var/text = req_reason_text(reason_type || /datum/msg/req_cancelled, ctx)
	if(actor)
		cancel_after(actor, "op_wait")
		if(!QDELETED(actor))
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

/// The capability type that owns the context's op (what before_op / after_op reactions of a capability
/// type match): the capability that built its entry, else null (a key match still works).
/datum/op_ctx/proc/capability_type()
	return entry?.cap?.type

/**
 * The reactions' hook points. op_before(ctx) runs just before an operation commits: the target's
 * before_op reactions (by op key, then by capability type) and its observers. Returns null to proceed, or the
 * first non-null answer, a reason (a /datum/msg type or text), which stops the commit. op_after(ctx)
 * runs right after it committed.
 */
/proc/op_before(datum/op_ctx/ctx)
	if(!ctx.op || !ctx.target)
		return null
	return rx_before_op(ctx.target, ctx.op.key, ctx.capability_type(), ctx)

/proc/op_after(datum/op_ctx/ctx)
	if(!ctx.op || !ctx.target || QDELETED(ctx.target))
		return
	rx_after_op(ctx.target, ctx.op.key, ctx.capability_type(), ctx)

/// Tells the actor why a before_op reaction stopped the operation (`reason`: a /datum/msg type or text).
/proc/op_refusal_told(datum/op_ctx/ctx, reason)
	var/text = ispath(reason) ? req_reason_text(reason, ctx) : "[reason]"
	if(text && ctx.actor)
		to_chat(ctx.actor, span_warning(text))

/datum/op_ctx/forget_wait()
	op_pending_forget(src)

/datum/op_ctx/reads_changed()
	var/why = check()
	if(why)
		op_cancel(src, why)

/datum/op_ctx/cancel_deleted()
	op_cancel(src, /datum/msg/req_cancelled)

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
//   3 actor state        conscious and capable (OP_EMERGENCY: alive)
//   5 capability         every cap_require() of the target that names this op or its kind
//     contracts
//   6 op needs           the op's own needs (requirements)
// The same check() runs before the wait, again when the wait ends and again at commit, so a wait never commits a
// stale answer.
// A pending (waiting) operation also watches the reads of its requirements and cancels early when
// one is published (op_reads_changed()).


GLOBAL_VAR_INIT(op_ctx_seq, 0)

/datum/op_ctx
	parent_type = /datum/operation_context
	var/datum/op_def/op
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
	if(route == ROUTE_AUTHORITY || !ismob(actor))
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

/datum/op_ctx/forget_wait()
	op_pending_forget(src)

/datum/op_ctx/reads_changed()
	var/why = check()
	if(why)
		op_cancel(src, why)

/datum/op_ctx/cancel_deleted()
	op_cancel(src, /datum/msg/req_cancelled)

// ---- the op definition ----

/// The definition of one operation a context checks: who can do it, with what, how, and what it needs.
/datum/op_def
	/// Unique per type: cap_require(ops =) names it.
	var/key
	var/name
	/// OP_CONTROL / OP_STRUCTURAL / OP_EMERGENCY.
	var/kind = OP_CONTROL
	/// ACT_*: the action this op answers.
	var/action = ACT_USE
	/// Higher first among the ops answering one action (OP_PRIORITY_*).
	var/priority = 0
	/// The stances (I_* values) the op answers, or null for any.
	var/list/stances
	/// What it is used with: null (bare hand), a TOOL_* quality, an item type (or list), or a /datum/req.
	var/using
	/// AFF_* bits the actor's provider slot must give (NONE for none).
	var/by = NONE
	/// ROUTE_* bits this op accepts.
	var/via = ROUTE_PHYSICAL
	/// BAY_*: the compartment of the target this op works through, or null.
	var/at
	/// Deciseconds it takes.
	var/delay = 0
	/// Tool resource (fuel, charge) it uses.
	var/cost = 0
	/// A /datum/msg shown when a timed op starts.
	var/start_msg
	/// PROC_REF on the holder.
	var/handler
	/// The op's own requirements (a list of /datum/req), the last stage.
	var/list/needs
	/// What makes the op meant at all: while one fails the input falls through, as if the op were not there.
	var/list/offered
	/// Gating requirements (behind, blocked_by, locked_by): reads for early cancel.
	var/list/gating
	/// Item types (a list) that a plain click must hold to reach this op. Null: no such rule.
	var/list/click_with

// ---- cap_require ----

/// An additive contract on the operations of its holder: every op it covers (by key or by kind,
/// or all ops when `ops` is null) also needs these requirements, checked in the capability stage.
/datum/capability/require
	/// Op keys and OP_* kinds it covers; null covers every op.
	var/list/ops
	var/list/reqs

/datum/capability/require/proc/covers(datum/op_def/op)
	if(!length(ops))
		return TRUE
	return (op.key in ops) || (op.kind in ops)

/// ops: an op key, an OP_* kind, a list of either, or null (every op). needs: a requirement or list.
/proc/cap_require(ops, needs)
	var/datum/capability/require/C = new
	if(!isnull(ops))
		C.ops = islist(ops) ? ops : list(ops)
	C.reqs = req_list(needs)
	C.key = "require:[md5(datum_signature(list(C.ops, C.reqs)))]"
	return C

/// The route the current check reaches the target by (a context-less requirement check reads it).
GLOBAL_VAR_INIT(op_route_now, ROUTE_PHYSICAL)

/// Whether a phrase from a reason type reads inside "Name: <reason>.".
/proc/req_reason_phrase(reason_type, datum/op_ctx/ctx)
	var/text = req_reason_text(reason_type, ctx)
	if(!text)
		return text
	if(copytext(text, length(text)) == ".")
		text = copytext(text, 1, length(text))
	if(reason_type != /datum/msg/req_refused && length(text) > 1)
		text = lowertext(copytext(text, 1, 2)) + copytext(text, 2)
	return text

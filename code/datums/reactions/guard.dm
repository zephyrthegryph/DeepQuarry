// Guards: "may this proceed?" for something that is not an operation (doc/rewrite/reactions.md section 3a).
//
// One mechanism: before_op() takes an op key, a capability type, or a GUARD_* key (code/__defines/reactions.dm). An
// operation runs its before_op reactions through the op requirement pipeline (op_before(), operations/op_ctx.dm); a
// non-operation call site that may be refused (a move, a fall, a thrown hit, a crossing) asks guard() instead, which
// runs the same before_op reactions of that guard key, static (the holder's composed reactions table, capabilities
// included) then observers (observe(source, before_op(GUARD_X), listener, handler)), and returns the first refusal.
// It replaces the om `before/*` veto events (om_emit() == EVENT_VETO).
//
//	/mob/living/reactions()
//		. = ..()
//		. += before_op(GUARD_STUMBLED_INTO, GLOBAL_PROC_REF(spont_vore_stumble))
//
//	if(guard(src, GUARD_STUMBLED_INTO, M))   // stumblevore.dm: somebody ate the stumble
//		return
//
// A handler gets the guard context (/datum/guard_ctx: key, target, actor, item, data; pooled, never kept) and returns
// null to let it proceed or a reason (a /datum/msg type, text, or TRUE) to refuse. A GLOBAL_PROC_REF handler gets the
// holder first, then the context (x(holder, ctx)). Handlers do not sleep. Nothing is allocated unless something guards the
// key on that holder (guarded()).

/// What a guard handler sees: an act context (code/contracts/acts/context.dm), pooled and released when guard() returns, so handlers never
/// keep it. `target` (the holder being asked, the one that may refuse) and `actor` (who does it) are the act's own fields.
/datum/guard_ctx
	parent_type = /datum/act/action
	/// The GUARD_* key being asked.
	var/key
	/// What it is done with (the thrown item, the crossing movable ...), when there is one.
	var/datum/item
	/// Anything else the call site passes (a list or a value).
	var/data

/// TRUE when something guards `key` on `E` (a static before_op of its type, or an observer): call sites test this
/// before building anything a guard needs.
/proc/guarded(datum/E, key)
	if(!E)
		return FALSE
	var/datum/rx_table/T = GLOB.rx_tables?[E.type]
	if(isnull(T))
		T = rx_table_build(E)
	if(T && T.before_keyed[key])
		return TRUE
	for(var/datum/rx_listener/L as anything in E.rx?.listeners)
		var/datum/reaction/R = L.trigger
		if(R.kind == RXN_BEFORE_OP && R.key == key)
			return TRUE
	return FALSE

/// Asks `E`'s guards of `key` whether this may proceed. Returns null (go ahead) or the first refusal (a reason).
/// `actor`, `item` and `data` are handed to the handlers in the context.
/proc/guard(datum/E, key, datum/actor, datum/item, data)
	if(!guarded(E, key) || QDELETED(E))
		return null
	var/datum/guard_ctx/ctx = take(/datum/guard_ctx)
	ctx.key = key

	ctx.target = E

	ctx.actor = actor
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.item = item
	ctx.data = data
	. = rx_before_op(E, key, null, ctx)
	ctx.release()

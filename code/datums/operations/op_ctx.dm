// Requirement contexts (doc/rewrite/dx_conventions.md, "Operations").
//
// One /datum/op_ctx is what a requirement (/datum/req, req.dm) is asked about: who (actor), on what (target), with
// what (held), over which route and on whose authority. cap_needs_reason() and a compartment boundary's passes() ask
// through one. Contexts are pooled (/datum/pooled): take them with op_ctx_take(), give them back with release(); a
// released context is poisoned in test builds (any use CRASHes).

GLOBAL_VAR_INIT(op_ctx_seq, 0)

/datum/op_ctx
	parent_type = /datum/operation_context

/// A pooled context for one check (a /datum/pooled: released fields return to their initial values).
/proc/op_ctx_take(mob/actor, datum/target, obj/item/held, route = ROUTE_PHYSICAL, datum/authority)
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
	ctx.route = route
	// flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.authority = authority
	return ctx

/// How many contexts are taken and not yet released (the pool's own accounting; a leak check reads it).
/proc/op_ctx_live_count()
	var/datum/object_pool/pool = GLOB.object_pools[/datum/op_ctx]
	return pool ? pool.out : 0

/// The atom a requirement of OP_PROVIDER reads: a context resolves no provider slot, so the actor.
/datum/op_ctx/proc/provider_atom()
	return actor

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

/// The route a context-less requirement check reaches the target by.
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

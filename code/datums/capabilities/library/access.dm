// The credential providers every access check shares (doc/rewrite/migration_guide.md A4, archive/framework_fixes.md §9.5;
// operations_and_actions.md "Credentials"). The access asked is the holder's own req_access / req_one_access when either is
// set (map edits, design review H1), else a caller's default; with neither, nothing is asked. A credential is a PROVIDER,
// found the way a hand is (access_credential()): the card held in the active hand (when it is one of `id_types`), then what
// the actor carries (a worn ID or PDA, through GetAccess()), then the actor themself (a silicon's own access). The lock
// (code/library/access/lock.dm) asks the same providers. The authority route (map spawn, admin) is never asked.

// ---- what is required ----

/// list(all, one): the access holder requires. Its own req_access / req_one_access when either is set, else the defaults.
/proc/access_needs(atom/holder, list/default_all, list/default_one)
	var/obj/O = isobj(holder) ? holder : null
	if(O && (length(O.req_access) || length(O.req_one_access)))
		return list(O.req_access, O.req_one_access)
	return list(default_all, default_one)

/// Whether `accesses` satisfies need_all / need_one. Nothing required: TRUE.
/proc/access_grants(list/need_all, list/need_one, list/accesses)
	if(!length(need_all) && !length(need_one))
		return TRUE
	if(!length(accesses))
		return FALSE
	return has_access(need_all, need_one, accesses)

// ---- credential providers ----

/**
 * The credential provider that grants `actor` holder's access (need_all / need_one, already resolved by access_needs()),
 * or null. Tried like hands, in order: the card held in the hand (when it is one of `id_types`), then the actor's own
 * access (a worn ID or PDA, a silicon's internal access: GetAccess()). The first that grants is the provider: the held
 * card, or the actor. Nothing required: the actor.
 */
/proc/access_credential(atom/holder, mob/actor, obj/item/held, list/need_all, list/need_one, list/id_types)
	if(!actor)
		return null
	if(!length(need_all) && !length(need_one))
		return actor
	if(held && (!id_types || is_type_in_list(held, id_types)) && access_grants(need_all, need_one, held.GetAccess()))
		return held
	if(access_grants(need_all, need_one, actor.GetAccess()))
		return actor
	return null

// ---- the requirement ----

/// The actor has a credential provider granting the target's access (access_credential()).
/datum/req/credential
	reason = /datum/msg/req_no_access
	of = OP_TARGET
	var/list/req_access
	var/list/req_one_access
	var/list/id_types

/datum/req/credential/test(datum/op_ctx/ctx)
	var/atom/A = ctx.target
	if(!istype(A) || !ctx.actor || ctx.route == ROUTE_AUTHORITY)
		return null
	var/list/needs = access_needs(A, req_access, req_one_access)
	return access_credential(A, ctx.actor, ctx.held, needs[1], needs[2], id_types) ? null : reason

/// A credential requirement: the holder's own access, else these defaults (shared, interned).
/proc/req_credential(list/access, list/req_one_access, list/id_types)
	RETURN_TYPE(/datum/req)
	var/datum/req/credential/R = new
	R.req_access = access
	R.req_one_access = req_one_access
	R.id_types = id_types
	return req_intern(R)

/// Whether `actor` (with `held` in hand) has a credential for holder's own access. From code that asks outside an op
/// (a UI's status, a button).
/proc/access_allowed(atom/holder, mob/actor, obj/item/held)
	var/list/needs = access_needs(holder, null, null)
	return !!access_credential(holder, actor, held, needs[1], needs[2], null)

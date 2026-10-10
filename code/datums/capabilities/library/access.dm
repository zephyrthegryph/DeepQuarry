// cap_access(): access-gated operations without lock state, and the credential providers every access check shares
// (doc/rewrite/migration_guide.md A4, archive/framework_fixes.md §9.5; operations_and_actions.md "Credentials").
//
//	CAPABILITY(/obj/machinery/computer/drone_control, cap_access(ops = "open_console"))              // the holder's req_access (a map may vary it per instance)
//	CAPABILITY(/obj/machinery/computer/drone_control, cap_access(list(ACCESS_ENGINE), ops = OP_CONTROL))  // a type default, used while the holder sets none
//
// cap_access() is a contract (a cap_require() subtype): every op it covers (`ops`: op keys and/or OP_* kinds; null:
// every op) also needs a credential that grants the access. The access asked is the holder's own req_access /
// req_one_access when either is set (map edits, design review H1), else the capability's type default; with neither,
// nothing is asked. A credential is a PROVIDER, found the way a hand is (access_credential()): the card held in the
// active hand (when it is one of `id_types`), then what the actor carries (a worn ID or PDA, through GetAccess()), then
// the actor themself (a silicon's own access). The lock (cap_lock()) asks the same providers; it only adds lock state.
// The authority route (map spawn, admin) is never asked.

/datum/capability/require/access
	/// Type default: every one required (has_access()).
	var/list/req_access
	/// Type default: at least one required.
	var/list/req_one_access
	/// Cards a held item may be to count as the credential in hand.
	var/list/id_types

/// Ops `ops` (keys and/or OP_* kinds, null: all) need a credential granting the holder's access (its own req_access /
/// req_one_access, else `access` / `req_one_access` here).
/proc/cap_access(list/access, list/req_one_access, ops = OP_CONTROL, list/id_types = list(/obj/item/card/id, /obj/item/pda))
	var/datum/capability/require/access/C = new
	C.req_access = access
	C.req_one_access = req_one_access
	C.id_types = id_types
	if(!isnull(ops))
		C.ops = islist(ops) ? ops : list(ops)
	C.reqs = list(req_credential(access, req_one_access, id_types))
	C.key = "access:[md5(datum_signature(list(C.ops, access, req_one_access, id_types)))]"
	return C

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

/// Whether `actor` (with `held` in hand) has a credential for holder's cap_access() contract (any covering op). From
/// code that asks outside an op (a UI's status, a button).
/proc/access_allowed(atom/holder, mob/actor, obj/item/held)
	var/datum/capability/require/access/C = cap_of(holder, /datum/capability/require/access)
	var/list/needs = access_needs(holder, C?.req_access, C?.req_one_access)
	return !!access_credential(holder, actor, held, needs[1], needs[2], C?.id_types)

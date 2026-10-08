// ---- legacy requirements read by the new engine ----
// The requirement constructors req_empty_hand(), req_self_held(), req_access(), req_stance() and req_heard() keep their legacy datums (hundreds
// of legacy ops hold them); the new engine reads those datums through holds(A), which the legacy classes below implement. A legacy
// requirement with no form here is refused at build time (op_part_report), never silently passed.

/datum/req/empty_hand/holds(datum/act/op/A)
	return isnull(A.held)

/datum/req/self_held/holds(datum/act/op/A)
	return !isnull(A.held) && A.held == A.target

/datum/req/access/holds(datum/act/op/A)
	var/obj/O = A.target
	if(!istype(O) || !A.actor)
		return TRUE
	if(A.authority & AUTH_ADMIN)
		return TRUE
	return O.allowed(A.actor)

/datum/req/stance/holds(datum/act/op/A)
	var/mob/M = A.actor
	return istype(M) && (M.input_stance() in stances)

/datum/req/heard/holds(datum/act/op/A)
	return op_notice_wanted(A.target, notice_type)

/datum/req/of_type/holds(datum/act/op/A)
	var/datum/D = null
	switch(of)
		if(OP_ACTOR)
			D = A.actor
		if(OP_HELD)
			D = A.held
		else
			D = A.target
	if(!D)
		return FALSE
	for(var/path in (islist(types) ? types : list(types)))
		if(istype(D, path))
			return TRUE
	return FALSE

/datum/requirement_composer/all(list/parts)
	return legacy_all_of(arglist(parts))

/datum/requirement_composer/any(list/parts)
	return legacy_any_of(arglist(parts))

/// Does a legacy requirement class implement holds() for the new engine?
/proc/op_legacy_req_has_form(datum/req/R)
	var/static/list/known = list()
	var/found = known["[R.type]"]
	if(!isnull(found))
		return found
	// A class has a form when its own holds() is not the base one: the base is the proc declared on /datum/req itself.
	found = (R.type == /datum/req) ? FALSE : !!(R.type in GLOB.OP_LEGACY_REQ_FORMS)
	known["[R.type]"] = found
	return found

GLOBAL_LIST_INIT(OP_LEGACY_REQ_FORMS, list(/datum/req/empty_hand, /datum/req/self_held, /datum/req/access, /datum/req/stance, /datum/req/heard, /datum/req/of_type))


/datum/req/supports_native()
	return op_legacy_req_has_form(src)

/mob/living/operation_actor_capable(ignoring)
	return !!stat_value(src, STAT_CAN_ACT) || ignoring

/client/operation_rights(required)
	return check_rights_for(src, required)

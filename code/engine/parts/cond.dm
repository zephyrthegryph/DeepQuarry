// Conditions and requirements (doc/rewrite/final_api.html, section 9 "Conditions and requirements"; section 21 "Conditions, requirements and the
// one signature"; section 19 "E2, parts": "the requirement protocol (conditions, req_* constructors, reasons from MSG_DEF)").
//
// A CONDITION is a boolean with no reason: nameof(v) (a truthy var), a stat or capability key id, cond_not()/cond_all()/cond_any(), a
// PROC_REF(x) whose proc takes (datum/act/A) and returns TRUE or FALSE, or a library requirement read as a boolean. It is what when() takes.
// A REQUIREMENT is a condition plus a reason: it is what needs() takes, and a requirement with no resolvable reason is a build error.
// Library constructors carry a default reason; the generic ones (req_is, req_at_least, req) take because =, a /datum/msg type or a
// PROC_REF(reason_proc) whose proc returns one.
//
// Requirements and conditions never write, publish or message (purity); test builds guard that around every evaluation (op_pure_begin).

// ---- messages the engine itself gives ----

MSG_DEF_SELF(op/no_binding, "You can't do that that way.")
MSG_DEF_SELF(op/busy, "You're already busy doing something.")
MSG_DEF_SELF(op/claimed, "Someone is already working on that.")
MSG_DEF_SELF(op/stopped, "You stop what you were doing.")
MSG_DEF_SELF(op/too_many_pending, "You have too many things going on at once: finish or cancel one first.")
MSG_DEF_SELF(op/cancelled, "You stop.")
MSG_DEF_SELF(op/target_gone, "It's gone.")
MSG_DEF_SELF(op/changed, "It changed while you were deciding.")
MSG_DEF_SELF(op/not_available, "You can't do that right now.")
MSG_DEF_SELF(op/no_hands, "You can't do that without hands.")
MSG_DEF_SELF(op/unreachable, "You can't reach that.")
MSG_DEF_SELF(op/failed, "That didn't work.")
MSG_DEF_SELF(op/unknown, "There is no such thing to do.")
MSG_DEF_SELF(op/bad_args, "That isn't something you can enter.")
MSG_DEF_SELF(op/topic_gate, "You cannot use that link right now.")
MSG_DEF_SELF(op/too_deep, "That is nested too deeply.")
MSG_DEF_SELF(op/no_resource, "You don't have enough for that.")
MSG_DEF_SELF(op/cooling_down, "It isn't ready yet.")
MSG_DEF_SELF(op/answer_no, "You decide against it.")
MSG_DEF_SELF(op/timed_out, "You took too long.")
MSG_DEF_SELF(op/hopper_full, "It's full.")
MSG_DEF_SELF(op/not_a_slot, "There is nowhere to put that.")
MSG_DEF_SELF(op/wrong_actor, "That isn't something you can do.")

/// The text of a refusal reason: a /datum/msg type, or the text itself.
/proc/reason_text(reason)
	if(isnull(reason))
		return null
	if(istext(reason))
		return reason
	if(!ispath(reason, /datum/msg))
		return "[reason]"
	var/datum/msg/def = msg_def(reason)
	return def.self

// ---- evaluating conditions ----

/// A condition evaluated in an op's context. The forms are section 9's: nameof(v) (a truthy var of the holder), a stat or capability key id,
/// cond_not/cond_all/cond_any, a PROC_REF(x) (x(datum/act/A) returns TRUE or FALSE; "cap:x" runs on the capability), a library requirement.
/proc/op_cond(datum/act/op/A, cond)
	op_pure_begin()
	. = op_cond_eval(A, cond)
	op_pure_end()

/proc/op_cond_eval(datum/act/op/A, cond)
	if(isnull(cond))
		return TRUE
	if(islist(cond))
		var/list/L = cond
		switch(L[1])
			if("not")
				return !op_cond(A, L[2])
			if("all")
				for(var/i in 2 to length(L))
					if(!op_cond(A, L[i]))
						return FALSE
				return TRUE
			if("any")
				for(var/i in 2 to length(L))
					if(op_cond(A, L[i]))
						return TRUE
				return FALSE
		return FALSE
	if(istype(cond, /datum/entry/part/req) || istype(cond, /datum/requirement))
		return op_req_holds(A, cond)
	if(isnum(cond))
		return condition_id_holds(A.holder, cond)
	if(istext(cond))
		var/datum/holder = A.holder
		if(holder && (cond in holder.vars))
			return !!holder.vars[cond]
		return !!op_call(A, cond)
	return !!cond

/// Runs a handler: a proc name on the holder (PROC_REF), or "cap:name" on the capability datum (A.cap). `extra` arguments follow the context.
/proc/op_call(datum/act/op/A, handler, ...)
	return op_call_list(A, handler, args.Copy(3))

/// op_call() with the extra arguments as a list.
/proc/op_call_list(datum/act/op/A, handler, list/extra)
	if(!istext(handler))
		return null
	var/list/call_args = list(A) + (extra || list()) // ALLOW(handlers): the engine builds the argument list of a call it is making: A is passed on, not kept
	if(copytext(handler, 1, 5) == "cap:")
		var/datum/capability/def = A.cap
		if(!def)
			stack_trace("op handler [handler] names a capability proc, but the entry belongs to no capability")
			return null
		return call(def, copytext(handler, 5))(arglist(call_args))
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return null
	return call(holder, handler)(arglist(call_args))

// ---- requirements ----

/// A requirement: a condition plus a reason. `holds(A)` is its boolean view.
/datum/entry/part/req
	part_name = "req"
	stages = PART_STAGE_REQUIRE
	/// The reason when the entry names none.
	var/default_reason = /datum/msg/req_failed

/// The boolean view: the requirement as a condition.
/datum/entry/part/req/proc/holds(datum/act/op/A)
	return TRUE

/datum/entry/part/req/require(datum/act/op/A)
	return holds(A)

/datum/entry/part/req/reason(datum/act/op/A)
	return refusal(A)

/// The /datum/msg type shown when it fails: because = MSG(x), a dynamic because = PROC_REF(r), else the constructor's default.
/datum/entry/part/req/proc/refusal(datum/act/op/A)
	var/because = src.args ? src.args["because"] : null
	if(ispath(because, /datum/msg))
		return because
	if(istext(because))
		var/answer = op_call(A, because)
		if(ispath(answer, /datum/msg))
			return answer
		if(istext(answer))
			return answer
	return default_reason

/// The (entity, key) reads of the requirement, as list(datum, key) rows: what a waiting op subscribes to. Default: none.
/datum/entry/part/req/proc/read_keys(datum/act/op/A)
	return list()

/// The id a subtype can relax this requirement by: extend("cover.open", drop = "x").
/datum/entry/part/req/proc/req_id()
	return src.args ? src.args["id"] : null

/// The datum a requirement examines: ON_TARGET (default), ON_HOLDER, ON_ACTOR, ON_HELD.
/proc/op_subject(datum/act/op/A, on)
	switch(on)
		if(ON_HOLDER)
			return A.holder
		if(ON_ACTOR)
			return A.actor
		if(ON_HELD)
			return A.held_provider()
	return A.target

/proc/req_make(req_type, list/named)
	return part_make(req_type, named)

/// req(T, of = ON_HELD): the participant is of type T. req(PROC_REF(x), because = ...): x(datum/act/A) returns TRUE or FALSE.
/// silent = TRUE refuses without telling the actor anything (a guard the old code refused with a bare return FALSE): the reason is the empty message.
/proc/req(what, of = ON_HELD, because = null, id = null, silent = FALSE)
	if(silent && isnull(because))
		because = /datum/msg/req_silent
	return part_make(/datum/entry/part/req/generic, list("what" = what, "of" = of, "because" = because, "id" = id))

/datum/entry/part/req/generic
	part_name = "req"

/datum/entry/part/req/generic/holds(datum/act/op/A)
	var/what = src.args["what"]
	if(ispath(what))
		var/datum/D = op_subject(A, src.args["of"])
		return !isnull(D) && istype(D, what)
	if(islist(what))
		var/datum/D2 = op_subject(A, src.args["of"])
		for(var/path in what)
			if(istype(D2, path))
				return TRUE
		return FALSE
	return !!op_call(A, what)

/datum/entry/part/req/generic/read_keys(datum/act/op/A)
	. = list()
	var/what = src.args["what"]
	if(istext(what) && copytext(what, 1, 5) != "cap:")
		for(var/key in change_read_keys(A.holder, what))
			. += list(list(A.holder, key))

/datum/entry/part/req/generic/refusal(datum/act/op/A)
	if(src.args["because"])
		return ..()
	return ispath(src.args["what"]) || islist(src.args["what"]) ? /datum/msg/req_wrong_item : /datum/msg/req_failed

/// A test of a key's value: a tracked var (nameof(v)), a stat id or a capability key id, read on the holder (of = ON_TARGET for the target).
/datum/entry/part/req/is
	part_name = "req_is"

/// req_is(KEY, value = TRUE, because =): the key's value is `value` (a boolean key is truthy or not).
/proc/req_is(key, value = TRUE, because = null, of = ON_HOLDER, id = null)
	return part_make(/datum/entry/part/req/is, list("key" = key, "value" = value, "because" = because, "of" = of, "id" = id))

/// The current value of a key on an entity: a var name, a stat id or a capability key id.
/proc/op_key_value(datum/D, key)
	if(isnull(D))
		return null
	if(istext(key))
		return (key in D.vars) ? D.vars[key] : null
	if(isnum(key))
		if(key >= STAT_ID_BASE && key < CAPKEY_ID_BASE)
			return stat_value(D, key)
		if(key > 255)
			return cap_key_get(D, key)
	return null

/datum/entry/part/req/is/holds(datum/act/op/A)
	var/datum/D = op_subject(A, src.args["of"])
	var/current = op_key_value(D, src.args["key"])
	var/wanted = src.args["value"]
	if(wanted == TRUE || wanted == FALSE)
		return !!current == !!wanted
	return current == wanted

/datum/entry/part/req/is/read_keys(datum/act/op/A)
	. = list()
	var/datum/D = op_subject(A, src.args["of"])
	if(D)
		for(var/key in change_read_keys(D, src.args["key"]))
			. += list(list(D, key))

/datum/entry/part/req/is/refusal(datum/act/op/A)
	if(src.args["because"])
		return ..()
	// A capability key's declared reason, for the test the capability usually makes.
	var/key = src.args["key"]
	if(isnum(key) && key > 255 && src.args["value"] == TRUE)
		return GLOB.cap_key_reasons["[key]"] || /datum/msg/req_wrong_state
	return /datum/msg/req_wrong_state

/// req_at_least(KEY, n, because =): the key's number is at least n.
/proc/req_at_least(key, n, because = null, of = ON_HOLDER, id = null)
	return part_make(/datum/entry/part/req/at_least, list("key" = key, "n" = n, "because" = because, "of" = of, "id" = id))

/datum/entry/part/req/at_least
	part_name = "req_at_least"

/datum/entry/part/req/at_least/holds(datum/act/op/A)
	var/current = op_key_value(op_subject(A, src.args["of"]), src.args["key"])
	return isnum(current) && current >= src.args["n"]

/datum/entry/part/req/at_least/read_keys(datum/act/op/A)
	. = list()
	var/datum/D = op_subject(A, src.args["of"])
	if(D)
		for(var/key in change_read_keys(D, src.args["key"]))
			. += list(list(D, key))

/datum/entry/part/req/at_least/refusal(datum/act/op/A)
	if(src.args["because"])
		return ..()
	return /datum/msg/req_wrong_state

/// carried(): the item is held, worn or in a container the actor carries (wider than in_hand()).
/proc/carried()
	return part_make(/datum/entry/part/req/carried)

/datum/entry/part/req/carried
	part_name = "carried"

/datum/entry/part/req/carried/holds(datum/act/op/A)
	var/atom/movable/AM = A.target
	if(!istype(AM) || !A.actor)
		return FALSE
	for(var/atom/up = AM.loc; up; up = up.loc)
		if(up == A.actor)
			return TRUE
		if(isturf(up))
			return FALSE
	return FALSE

/// req_tag(TAG): the target carries the tag.
/proc/req_tag(tag_id)
	return part_make(/datum/entry/part/req/tagged, list("tag" = tag_id))

/datum/entry/part/req/tagged
	part_name = "req_tag"
	default_reason = /datum/msg/req_wrong_state

/datum/entry/part/req/tagged/holds(datum/act/op/A)
	return op_has_tag(A.target, src.args["tag"])

/// req_capable(ignoring = ...): the actor can act now (no stun, restraint, absorption).
/proc/req_capable(ignoring = 0)
	return part_make(/datum/entry/part/req/capable, list("ignoring" = ignoring))

/datum/entry/part/req/capable
	part_name = "req_capable"
	default_reason = /datum/msg/req_not_capable

/datum/entry/part/req/capable/read_keys(datum/act/op/A)
	. = list()
	if(A.actor)
		for(var/key in change_read_keys(A.actor, STAT_CAN_ACT))
			. += list(list(A.actor, key))

/datum/entry/part/req/capable/holds(datum/act/op/A)
	return !A.actor || A.actor.operation_actor_capable(src.args["ignoring"])

/proc/req_conscious()
	return part_make(/datum/entry/part/req/conscious)

/datum/entry/part/req/conscious
	part_name = "req_conscious"
	default_reason = /datum/msg/req_not_capable

/datum/entry/part/req/conscious/read_keys(datum/act/op/A)
	return A.actor ? list(list(A.actor, "stat")) : list()

/datum/entry/part/req/conscious/holds(datum/act/op/A)
	var/mob/M = A.actor
	return !istype(M) || M.stat == CONSCIOUS

/proc/req_alive()
	return part_make(/datum/entry/part/req/alive)

/datum/entry/part/req/alive
	part_name = "req_alive"
	default_reason = /datum/msg/req_not_capable

/datum/entry/part/req/alive/read_keys(datum/act/op/A)
	return A.actor ? list(list(A.actor, "stat")) : list()

/datum/entry/part/req/alive/holds(datum/act/op/A)
	var/mob/M = A.actor
	return !istype(M) || M.stat != DEAD

/// req_self(): the actor is the holder itself (a window or a link only its own mob uses).
/proc/req_self()
	return part_make(/datum/entry/part/req/self)

/datum/entry/part/req/self
	part_name = "req_self"
	default_reason = /datum/msg/req_silent

/datum/entry/part/req/self/read_keys(datum/act/op/A)
	return list()

/datum/entry/part/req/self/holds(datum/act/op/A)
	return !A.actor || A.actor == A.holder

/// req_actor_kind(types, because =, not = FALSE): the actor is one of the given kinds (a type or a list of types: /mob/living/silicon, /mob/observer).
/// With not = TRUE it refuses those kinds instead ("a cyborg can't do this"). In a when() it picks the op by who is acting; in needs() it
/// refuses everyone else with `because` (default: "That isn't something you can do."). The actor is the clicking mob, so it is never read from a var.
/proc/req_actor_kind(types, because = null, not = FALSE, id = null)
	return part_make(/datum/entry/part/req/actor_kind, list("types" = types, "because" = because, "not" = not, "id" = id))

/datum/entry/part/req/actor_kind
	part_name = "req_actor_kind"
	default_reason = /datum/msg/op/wrong_actor

/datum/entry/part/req/actor_kind/holds(datum/act/op/A)
	var/datum/D = A.actor
	var/types = src.args["types"]
	var/match = FALSE
	if(!isnull(D))
		if(islist(types))
			for(var/path in types)
				if(istype(D, path))
					match = TRUE
					break
		else
			match = istype(D, types)
	return src.args["not"] ? !match : match

/// req_mutation(M, of = ON_ACTOR, because =): the participant (the actor by default) is a mob with mutation M (HULK, TK, ...): a hulk's smash,
/// a telekinetic's reach. In a when() it picks the op only for such an actor; in needs() it refuses everyone else. It reads the mob's conditions
/// key (MOB_KEY_CONDITIONS, published by add_mutation()/remove_mutation()), so a waiting op re-checks when the mutation comes or goes.
/proc/req_mutation(mutation, of = ON_ACTOR, because = null, id = null)
	return part_make(/datum/entry/part/req/mutation, list("mutation" = mutation, "of" = of, "because" = because, "id" = id))

/datum/entry/part/req/mutation
	part_name = "req_mutation"
	default_reason = /datum/msg/req_failed

/datum/entry/part/req/mutation/read_keys(datum/act/op/A)
	var/datum/D = op_subject(A, src.args["of"])
	return D ? list(list(D, MOB_KEY_CONDITIONS)) : list()


/// req_adjacent(): the actor is next to the target.
/proc/req_adjacent()
	return part_make(/datum/entry/part/req/adjacent)

/datum/entry/part/req/adjacent
	part_name = "req_adjacent"
	default_reason = /datum/msg/op/unreachable

/datum/entry/part/req/adjacent/read_keys(datum/act/op/A)
	. = list()
	if(A.actor)
		. += list(list(A.actor, OP_KEEP_MOVED))
	if(A.target)
		. += list(list(A.target, OP_KEEP_MOVED))

/datum/entry/part/req/adjacent/holds(datum/act/op/A)
	var/atom/T = A.target
	return !istype(T) || !A.actor || A.actor.Adjacent(T)

/// req_on_origin(origins, req = null): with one argument tests the origin of the input; with two, req applies only for those origins.
/proc/req_on_origin(origins, datum/entry/part/req/then_req = null)
	return part_make(/datum/entry/part/req/on_origin, list("origins" = origins), then_req ? list(then_req) : null)

/datum/entry/part/req/on_origin
	part_name = "req_on_origin"

/datum/entry/part/req/on_origin/holds(datum/act/op/A)
	var/origins = src.args["origins"]
	if(!length(children))
		return !!(A.origin & origins)
	if(!(A.origin & origins))
		return TRUE
	var/datum/entry/part/req/R = children[1]
	return R.holds(A)

/datum/entry/part/req/on_origin/refusal(datum/act/op/A)
	if(length(children))
		var/datum/entry/part/req/R = children[1]
		return R.refusal(A)
	return /datum/msg/op/no_binding

/// req_on_authority(authorities, req = null): the authority of the input.
/proc/req_on_authority(authorities, datum/entry/part/req/then_req = null)
	return part_make(/datum/entry/part/req/on_authority, list("authorities" = authorities), then_req ? list(then_req) : null)

/datum/entry/part/req/on_authority
	part_name = "req_on_authority"

/datum/entry/part/req/on_authority/holds(datum/act/op/A)
	var/auth = src.args["authorities"]
	if(!length(children))
		return !!(A.authority & auth)
	if(!(A.authority & auth))
		return TRUE
	var/datum/entry/part/req/R = children[1]
	return R.holds(A)

/datum/entry/part/req/on_authority/refusal(datum/act/op/A)
	if(length(children))
		var/datum/entry/part/req/R = children[1]
		return R.refusal(A)
	return /datum/msg/op/no_binding

/// req_rights(R_X): the actor has the admin right (an admin authority datum satisfies it).
/proc/req_rights(rights)
	return part_make(/datum/entry/part/req/rights, list("rights" = rights))

/datum/entry/part/req/rights
	part_name = "req_rights"
	default_reason = /datum/msg/req_no_rights

/datum/entry/part/req/rights/holds(datum/act/op/A)
	if(A.authority & AUTH_ADMIN)
		return TRUE
	return !!A.actor?.client?.operation_rights(src.args["rights"])

/// req_full(nameof(rel)) / req_empty(nameof(rel)): a relation or list var is full (non-empty) or empty.
/proc/req_full(var_name, because = null)
	return part_make(/datum/entry/part/req/rel_state, list("var" = var_name, "want_full" = TRUE, "because" = because))

/proc/req_empty(var_name, because = null)
	return part_make(/datum/entry/part/req/rel_state, list("var" = var_name, "want_full" = FALSE, "because" = because))

/datum/entry/part/req/rel_state
	part_name = "req_rel"
	default_reason = /datum/msg/req_wrong_state

/datum/entry/part/req/rel_state/read_keys(datum/act/op/A)
	return A.holder ? list(list(A.holder, src.args["var"])) : list()

/datum/entry/part/req/rel_state/holds(datum/act/op/A)
	var/datum/D = A.holder
	var/value = (D && (src.args["var"] in D.vars)) ? D.vars[src.args["var"]] : null
	var/full = islist(value) ? length(value) > 0 : !isnull(value)
	return full == src.args["want_full"]

/// req_not(r, because =): the negation of a requirement.
/proc/req_not(datum/entry/part/req/inner, because = null)
	return part_make(/datum/entry/part/req/negation, list("because" = because), list(inner))

/datum/entry/part/req/negation
	part_name = "not"

/datum/entry/part/req/negation/read_keys(datum/act/op/A)
	var/datum/entry/part/req/R = children[1]
	return R.read_keys(A)

/datum/entry/part/req/negation/holds(datum/act/op/A)
	var/datum/entry/part/req/R = children[1]
	return !R.holds(A)

/// all_of(r...): every requirement holds; the first failing one's reason is reported. A legacy /datum/requirement list stays the legacy form.
/proc/all_of(...)
	for(var/value in args)
		if(istype(value, /datum/entry) || (islist(value) && length(value) && istype(value[1], /datum/entry)))
			return part_make(/datum/entry/part/req/all, null, entry_flatten(args))
	return requirement_composer().all(args)

/datum/entry/part/req/all
	part_name = "all_of"

/datum/entry/part/req/all/read_keys(datum/act/op/A)
	. = list()
	for(var/datum/entry/part/req/R as anything in children)
		. += R.read_keys(A)

/datum/entry/part/req/all/holds(datum/act/op/A)
	for(var/datum/entry/part/req/R as anything in children)
		if(!R.holds(A))
			return FALSE
	return TRUE

/datum/entry/part/req/all/refusal(datum/act/op/A)
	for(var/datum/entry/part/req/R as anything in children)
		if(!R.holds(A))
			return R.refusal(A)
	return default_reason

/// any_of(r...): at least one holds; the reasons are joined ("needs a wrench or a welder").
/proc/any_of(...)
	for(var/value in args)
		if(istype(value, /datum/entry) || (islist(value) && length(value) && istype(value[1], /datum/entry)))
			return part_make(/datum/entry/part/req/any, null, entry_flatten(args))
	return requirement_composer().any(args)

/datum/entry/part/req/any
	part_name = "any_of"

/datum/entry/part/req/any/read_keys(datum/act/op/A)
	. = list()
	for(var/datum/entry/part/req/R as anything in children)
		. += R.read_keys(A)

/datum/entry/part/req/any/holds(datum/act/op/A)
	for(var/datum/entry/part/req/R as anything in children)
		if(R.holds(A))
			return TRUE
	return FALSE

/datum/entry/part/req/any/refusal(datum/act/op/A)
	var/list/texts = list()
	for(var/datum/entry/part/req/R as anything in children)
		var/why = reason_text(R.refusal(A))
		if(why && !(why in texts))
			texts += why
	return length(texts) ? jointext(texts, " or ") : default_reason

/// Does the entity carry the tag (a TAG_X): TAG_UI and TAG_TOPIC are on every op, others are declared by tag().
/proc/op_has_tag(datum/D, tag_id)
	for(var/datum/op_plan/P as anything in op_plans_of(D))
		if(tag_id in P.tags)
			return TRUE
	return FALSE

/// Does anything of `holder` listen for `notice_type`? (req_heard(): an op that only publishes a notice is offered only where a hook hears it.)
/proc/op_notice_wanted(datum/D, notice_type)
	return notice_wanted(D, notice_type)

/// A requirement (new, or a legacy /datum/requirement that has a new-engine form) as a boolean in an op's context.
/proc/op_req_holds(datum/act/op/A, requirement)
	op_pure_begin()
	. = op_req_holds_eval(A, requirement)
	op_pure_end()

/proc/op_req_holds_eval(datum/act/op/A, requirement)
	if(istype(requirement, /datum/entry/part/req))
		var/datum/entry/part/req/R = requirement
		return R.holds(A)
	if(istype(requirement, /datum/requirement))
		var/datum/requirement/L = requirement
		return L.holds(A)
	return !!requirement

/// The /datum/msg type (or text) a failed requirement reports.
/proc/op_req_refusal(datum/act/op/A, requirement)
	op_pure_begin()
	. = op_req_refusal_eval(A, requirement)
	op_pure_end()

/proc/op_req_refusal_eval(datum/act/op/A, requirement)
	if(istype(requirement, /datum/entry/part/req))
		var/datum/entry/part/req/R = requirement
		return R.refusal(A)
	if(istype(requirement, /datum/requirement))
		var/datum/requirement/L = requirement
		return L.refusal(A)
	return /datum/msg/req_failed

/// The id a requirement may be relaxed by (extend(key, drop = "id")).
/proc/op_req_id(requirement)
	if(istype(requirement, /datum/entry/part/req))
		var/datum/entry/part/req/R = requirement
		return R.req_id()
	return null

/mob/proc/op_has_mutation(mutation)
	return FALSE
/datum/entry/part/req/mutation/holds(datum/act/op/A)
	var/mob/M = op_subject(A, src.args["of"])
	return istype(M) && M.op_has_mutation(src.args["mutation"])

/// Sample admission state without subscribing to it. Immediate requirements sample on each
/// input, and menus containing a sample are rebuilt on each read. For a question which
/// waits, only sample state effectively fixed while it is open; mutable waiting conditions
/// need TRACKED state or an accessor with READS_AS so they can be rechecked when changed.
/proc/read_once(value)
	READS_FROM() // by design: nothing inside the call subscribes (sem/reads mutes its argument)
	// The menu is an admission read too. A non-subscribing input cannot use its generation cache.
	// Mark enclosing menu reads: a requirement may inspect another menu transitively.
	var/list/frame = GLOB.op_menu_read_frame
	while(frame)
		frame[2] = TRUE
		frame = frame[1]
	return value

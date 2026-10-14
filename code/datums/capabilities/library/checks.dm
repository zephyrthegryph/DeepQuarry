// The shared `needs` check library (plan §2.10, doc/rewrite/migration_guide.md A11/B4).
//
// Calling convention: GLOBAL procs with the signature (mob/user, atom/holder, obj/item/held), used as
//	needs = GLOBAL_PROC_REF(chk_conscious)   or   needs = list(GLOBAL_PROC_REF(chk_capable), GLOBAL_PROC_REF(chk_held))
// cap_needs_reason() calls a /proc/ ref as call(proc_ref)(user, holder, held) and any other ref as a
// holder proc, call(holder, proc_ref)(user, held). Each check returns TRUE or the player-facing refusal.
// Pure: none of them writes anything. They mirror the ASK_* / PROMPT_* checks in om/ask.dm typed_recheck
// (same predicates, same reasons), so an ask_* re-check refuses exactly as the old flags did.

/proc/chk_alive(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || user.stat == DEAD)
		return "you are dead"
	return TRUE

/proc/chk_conscious(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || user.stat != CONSCIOUS)
		return "you are not conscious"
	return TRUE

/// Not incapacitated (stunned, restrained, unconscious...).
/proc/chk_capable(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || user.stat != CONSCIOUS || user.incapacitated())
		return "you can't do that right now"
	return TRUE

/proc/chk_unrestrained(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || user.restrained())
		return "you are restrained"
	return TRUE

/// The user is adjacent to the holder.
/proc/chk_adjacent(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || !istype(holder) || !user.Adjacent(holder))
		return "you are too far away"
	return TRUE

/// The user is adjacent to the holder's subject: the held item's target if held, else the holder.
/proc/chk_near_subject(mob/user, atom/holder, obj/item/held)
	var/atom/subject = held || holder
	if(!ismob(user) || !istype(subject) || !user.Adjacent(subject))
		return "you are too far away"
	return TRUE

/// The holder is in one of the user's hands.
/proc/chk_held(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || !holder || (user.get_active_hand() != holder && user.get_inactive_hand() != holder))
		return "you are not holding it"
	return TRUE

/// The holder is somewhere on the user (hands, pockets, a worn container).
/proc/chk_carried(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || !istype(holder, /atom/movable))
		return "you are not carrying it"
	for(var/atom/where = holder.loc; where; where = where.loc)
		if(where == user)
			return TRUE
	return "you are not carrying it"

/// The user has a hand with nothing in it.
/proc/chk_hand_free(mob/user, atom/holder, obj/item/held)
	if(!ismob(user) || (user.get_active_hand() && user.get_inactive_hand()))
		return "your hands are full"
	return TRUE

/// The holder lies directly on a turf, not in a container or a hand.
/proc/chk_on_turf(mob/user, atom/holder, obj/item/held)
	if(!istype(holder) || !isturf(holder.loc))
		return "it has to be on the ground"
	return TRUE

/**
 * Runs `needs` (one ref or a list) for `user` on `holder`: null when all pass, else the refusal text
 * (a check's own text, or `else_say` / a default for a bare FALSE). Global proc refs (/proc/...) are
 * called (user, holder, held); anything else is a holder proc called (user, held).
 */
/proc/cap_needs_reason(atom/holder, mob/user, obj/item/held, needs, else_say)
	if(!needs)
		return null
	var/list/refs = islist(needs) ? needs : list(needs)
	for(var/proc_ref in refs)
		var/result
		if(istype(proc_ref, /datum/req))
			// A requirement (req_*: operations/req.dm) asked of a short-lived context of this attempt.
			var/datum/req/R = proc_ref
			var/datum/op_ctx/asked = op_ctx_take(user, holder, held, GLOB.op_route_now)
			var/why = R.test(asked)
			var/phrase = why ? req_reason_phrase(why, asked) : null
			asked.release()
			if(why)
				return phrase || else_say || "you can't do that right now"
			continue
		if(copytext("[proc_ref]", 1, 7) == "/proc/")
			result = call(proc_ref)(user, holder, held)
		else
			result = call(holder, proc_ref)(user, held)
		if(istext(result))
			return result
		if(!result)
			return else_say || "you can't do that right now"
	return null

// Requirements about who acts and what they hold: the native parts of the old /datum/req constructors.
// Each is a /datum/entry/part/req (code/engine/parts/cond.dm): holds() is the boolean view, refusal() the reason.
// Actorless checks (a conveyor, a system mover): parts gated on the actor hold when there is none.

/// req_empty_hand(): the actor holds nothing (a bare-hand click).
/proc/req_empty_hand(because = null)
	return part_make(/datum/entry/part/req/empty_hand, list("because" = because))

/datum/entry/part/req/empty_hand
	part_name = "req_empty_hand"
	default_reason = /datum/msg/req_hand_full

/datum/entry/part/req/empty_hand/holds(datum/act/op/A)
	return isnull(A.held)

/// req_self_held(): the target is the held item itself: a self-use (attack_self, the Z key, GESTURE_SELF). Offered by an item's
/// self-use ops, so a click on the item (held is something else, or nothing) never means them, though both answer ACT_USE.
/proc/req_self_held(because = null)
	return part_make(/datum/entry/part/req/self_held, list("because" = because))

/datum/entry/part/req/self_held
	part_name = "req_self_held"
	default_reason = /datum/msg/req_wrong_item

/datum/entry/part/req/self_held/holds(datum/act/op/A)
	return !isnull(A.held) && A.held == A.target

/// req_access(): the actor has access to the target (an /obj's allowed()); a target that is not an /obj has none to check, an admin
/// authority and an actorless check pass.
/proc/req_access(because = null)
	return part_make(/datum/entry/part/req/access, list("because" = because))

/datum/entry/part/req/access
	part_name = "req_access"
	default_reason = /datum/msg/req_no_access

/datum/entry/part/req/access/holds(datum/act/op/A)
	var/obj/O = A.target
	if(!istype(O) || !A.actor)
		return TRUE
	if(A.authority & AUTH_ADMIN)
		return TRUE
	return O.allowed(A.actor)

MSG_DEF_SELF(req_wrong_stance, "Not like that.")

/// req_stance(stances): the actor's input is one of `stances` (I_HELP, I_DISARM, I_GRAB, I_HURT), a stance or a list of them: an op
/// declared for some stances offers this, so another stance falls through to the next op.
/proc/req_stance(stances, because = null)
	return part_make(/datum/entry/part/req/stance, list("stances" = islist(stances) ? stances : list(stances), "because" = because))

/datum/entry/part/req/stance
	part_name = "req_stance"
	default_reason = /datum/msg/req_wrong_stance

/datum/entry/part/req/stance/holds(datum/act/op/A)
	var/mob/M = A.actor
	return istype(M) && (M.input_stance() in src.args["stances"])

MSG_DEF_SELF(harm_click_only, "That would destroy it. Use harm intent if you mean it.")

/// For an op that destroys what is held or its target: a click must be on harm intent (anything else is refused with MSG(harm_click_only), never
/// a fall-through to the bare-hand op); a menu pick is deliberate and passes. Use as needs(req(TYPE_PROC_REF(/atom, harm_click_only), because = MSG(harm_click_only))).
/atom/proc/harm_click_only(datum/act/op/A)
	if(A.origin == ORIGIN_MENU)
		return null
	var/mob/M = A.actor
	return (istype(M) && click_stance_of(M) == I_HURT) ? null : MSG(harm_click_only)

/// The stance of the actor's click now. A click is decided once, so nothing subscribes to the combat mode it reads.
/proc/click_stance_of(mob/M)
	READS_FROM()
	return M.input_stance()

/// Whether someone has subverted this atom (req_not_subverted()): emagged by default; a holder that can be
/// taken over another way (an AI hack) adds it.
/atom/proc/is_subverted()
	return is_emagged(src)

/// Non-living actors have no living action-state gate. Living providers supply it.
/datum/proc/operation_actor_capable(ignoring)
	return TRUE

/// Authority is provided by the client role implementation.
/client/proc/operation_rights(required)
	return FALSE

/// The actor can act: a living mob's STAT_CAN_ACT (req_capable()), or ignoring it. Non-living actors have no action-state gate.
/mob/living/operation_actor_capable(ignoring)
	return !!stat_value(src, STAT_CAN_ACT) || ignoring

/client/operation_rights(required)
	return check_rights_for(src, required)

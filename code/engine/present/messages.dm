// Message templates runtime (doc/rewrite/systems.md §15). See code/__defines/messages.dm.

MSG_DEF_SELF(req_failed, "You can't do that.")

/// The /datum/msg singletons, by type.
GLOBAL_LIST_EMPTY(msg_defs)

/**
 * A declared message template (a DEF singleton: never mutated, shared by every sender).
 * `self` goes to the actor, `others` to the people who see it, `blind` to those who can't.
 * Each is wrapped in `span_class` when shown ("notice" -> span_notice); null leaves it raw.
 * Subtypes whose wording depends on the call override texts().
 */
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/msg)
/datum/msg
	var/self
	var/others
	var/blind
	var/span_class = "notice"
	/// Range for the others line.
	var/range
	/// MSG_DISPLAY_*: how a refusal is shown to the actor (MSG_BALLOON declares a balloon alert).
	var/display = MSG_DISPLAY_CHAT

/// A refusal whose text carries detail ("too big: 3 > 2", "the gloves are in the way"): a message instance, not a DEF singleton (admission.md D1,
/// the instance form). A pure requirement makes one with msg_reason(); it is read and shown like a type (reason_text(), op_tell()), and kept by
/// nothing, so it goes when its refusal is dropped.
/datum/msg/instance

/// msg_reason(self_text, display =): the message instance for one refusal's text.
/proc/msg_reason(self_text, display = MSG_DISPLAY_CHAT)
	RETURN_TYPE(/datum/msg/instance)
	var/datum/msg/instance/M = new
	M.self = self_text
	M.display = display
	return M

/// The singleton for a template type.
/proc/msg_def(msg_type)
	var/datum/msg/def = GLOB.msg_defs[msg_type]
	if(!def)
		if(!ispath(msg_type, /datum/msg))
			CRASH("msg_def: [msg_type] is not a /datum/msg type")
		def = new msg_type
		GLOB.msg_defs[msg_type] = def
	return def

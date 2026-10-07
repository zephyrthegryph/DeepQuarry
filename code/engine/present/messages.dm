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
/datum/msg
	var/self
	var/others
	var/blind
	var/span_class = "notice"
	/// Range for the others line.
	var/range

/// The singleton for a template type.
/proc/msg_def(msg_type)
	var/datum/msg/def = GLOB.msg_defs[msg_type]
	if(!def)
		if(!ispath(msg_type, /datum/msg))
			CRASH("msg_def: [msg_type] is not a /datum/msg type")
		def = new msg_type
		GLOB.msg_defs[msg_type] = def
	return def

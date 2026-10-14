/// Administrative and headless callers request the same next ticker-step behavior.
/datum/system/ticker/proc/request_immediate_start(enabled)
	start_immediately = enabled

/datum/system/ticker/proc/request_round_ending(reason)
	force_ending = reason

/datum/system/ticker/proc/set_round_end_delay(enabled)
	delay_end = enabled

/datum/system/ticker/proc/toggle_round_end_delay()
	delay_end = !delay_end

/// The roster uses its existing relation; repeated additions retain rel_add semantics.
/datum/system/ticker/proc/remember_mind(datum/mind/mind)
	rel_add(src, nameof(minds), mind)

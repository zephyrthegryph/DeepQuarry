/// A mob picking its own name for a role (rename_self()).
/datum/prompt/text/rename_self
	title = "Name change"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	timeout = 0
	var/role
	var/allow_numbers
	var/attempt
	var/started_at = 0

/datum/prompt/text/rename_self/prepare(datum/act/A)
	. = ..()
	question = "You are \a [role]. Would you like to change your name to something else?"

/// The question a borg is asked to choose which active AI to link to (open_request(borg, /datum/prompt/choice/ai_selection, ..., answerer = borg, choices = active_ais())).
/datum/prompt/choice/ai_selection
	question = "AI signals detected:"
	title = "AI selection"

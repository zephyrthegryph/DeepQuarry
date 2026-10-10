MSG_DEF_SELF(req_protocol/blocked, "The protocol fixture is blocked.")
MSG_DEF_SELF(req_protocol/override, "The override wins.")

/obj/req_protocol_fixture
	name = "requirement protocol fixture"
	var/mode = 0
	var/commits = 0
	var/static/datum/msg/refusal_message = new /datum/msg/req_protocol/blocked

TRACKED(/obj/req_protocol_fixture, mode)
TRACKED(/obj/req_protocol_fixture, commits)

CAPABILITIES(/obj/req_protocol_fixture)
	op("boolean_when", menu(), label("Boolean condition"), when(req_bool(PROC_REF(boolean_ready))), then(PROC_REF(commit)))
	op("protocol", menu(), label("Protocol"), needs(req(PROC_REF(check_ready))), then(PROC_REF(commit)))
	op("override", menu(), label("Override"), needs(req(PROC_REF(check_ready), because = MSG(req_protocol/override))), then(PROC_REF(commit)))
	op("silent", menu(), label("Silent"), needs(req(PROC_REF(check_ready), because = "")), then(PROC_REF(commit)))
	op("boolean", menu(), label("Boolean"), needs(req_bool(PROC_REF(boolean_ready), because = MSG(req_protocol/blocked))), then(PROC_REF(commit)))

/obj/req_protocol_fixture/proc/check_ready(datum/act/op/A)
	switch(mode)
		if(1)
			return "A custom reason."
		if(2)
			return MSG(req_protocol/blocked)
		if(3)
			return read_once(refusal_message)
		if(4)
			return ""
	return null

/obj/req_protocol_fixture/proc/boolean_ready(datum/act/op/A)
	if(mode == 5)
		return FALSE
	if(mode == 6)
		return TRUE
	return !mode

/obj/req_protocol_fixture/proc/check_other(datum/act/op/A)
	return mode ? "Another reason." : null

/obj/req_protocol_fixture/proc/check_always(datum/act/op/A)
	return null

/obj/req_protocol_fixture/proc/commit(datum/act/op/A)
	set_commits(commits + 1)

/// A downstream compatibility requirement keeps its existing boolean view.
/datum/requirement/req_protocol_fixture
	var/allowed = TRUE

/datum/requirement/req_protocol_fixture/holds(datum/act/op/A)
	return allowed

/datum/requirement/req_protocol_fixture/refusal(datum/act/op/A)
	return "A compatibility reason."

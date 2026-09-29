// Player poll TGUI dialogs.
//
// Two short-lived datums replace the legacy browse() windows on
// /mob/new_player: the privacy poll (a single-choice consent screen
// surfaced on login) and the player poll browser (a list + detail
// view over the erro_poll_* tables).
//
// Each datum is owned by the mob; we keep a strong ref on the mob so
// the TGUI window stays alive until explicitly closed. Topic-based
// dispatch is gone — every action goes through tgui_act, and the DB
// writes call the same helper procs the upstream code already
// defined on /mob/new_player.

#define PRIVACY_OPTION_SIGNED    "signed"
#define PRIVACY_OPTION_ANONYMOUS "anonymous"
#define PRIVACY_OPTION_NOSTATS   "nostats"
#define PRIVACY_OPTION_LATER     "later"
#define PRIVACY_OPTION_ABSTAIN   "abstain"

// ============================================================
// Privacy poll
// ============================================================

/datum/privacy_poll_dialog
	var/mob/new_player/owner
	var/answered = FALSE

/datum/privacy_poll_dialog/New(mob/new_player/owner)
	rel_set(src, "owner", owner)

// The new player owns this dialog (privacy_poll_dialog); owner is a plain relation back.

DECLARE_UI_STATE(/datum/privacy_poll_dialog, GLOB.tgui_always_state)

UI_DATA_REPLACE(/datum/privacy_poll_dialog, "merge:ui_data_datum_privacy_poll_dialog{answered:num}")

/// The computed part of /datum/privacy_poll_dialog's window data (declared on its UI_DATA row).
/datum/privacy_poll_dialog/proc/ui_data_datum_privacy_poll_dialog(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list("answered" = answered)

DECLARE_UI(/datum/privacy_poll_dialog, "PrivacyPoll", UI_TITLE("Player Poll — Privacy"))

/datum/privacy_poll_dialog/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

UI_ACT(/datum/privacy_poll_dialog, "vote", ui_act_vote, UI_ARG_CHOICE("choice", list(PRIVACY_OPTION_LATER, PRIVACY_OPTION_SIGNED, PRIVACY_OPTION_ANONYMOUS, PRIVACY_OPTION_NOSTATS, PRIVACY_OPTION_ABSTAIN)))
UI_ACT_PROC(/datum/privacy_poll_dialog, ui_act_vote)
	var/choice = params["choice"]
	if(!owner || !choice)
		return
	if(!SSdbcore.IsConnected())
		return
	if(choice == PRIVACY_OPTION_LATER)
		SStgui.close_uis(src)
		qdel(src)
		return TRUE
	var/option
	switch(choice)
		if(PRIVACY_OPTION_SIGNED)
			option = "SIGNED"
		if(PRIVACY_OPTION_ANONYMOUS)
			option = "ANONYMOUS"
		if(PRIVACY_OPTION_NOSTATS)
			option = "NOSTATS"
		if(PRIVACY_OPTION_ABSTAIN)
			option = "ABSTAIN"
	record_vote(option)
	return TRUE

/// A prompt flow (flow_io.dm): the check and the insert each re-run it when answered.
/datum/privacy_poll_dialog/proc/record_vote(option)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(record_vote), args)
	if(!owner || answered)
		return
	var/voted = FALSE
	var/datum/db_query/check = SSdbcore.NewQuery(
		"SELECT 1 FROM erro_privacy WHERE ckey = :t_ckey",
		list("t_ckey" = owner.ckey),
	)
	check.Execute()
	while(check.NextRow())
		voted = TRUE
		break
	qdel(check)

	if(!voted)
		flow_sql("INSERT INTO erro_privacy VALUES (null, Now(), :t_ckey, :t_option)", list("t_ckey" = owner.ckey, "t_option" = option))
		to_chat(owner, span_bold("Thank you for your vote!"))

	answered = TRUE
	SStgui.close_uis(src)
	qdel(src)

// ============================================================
// Player poll browser
// ============================================================

/datum/poll_browser_dialog
	var/mob/new_player/owner
	var/list/poll_ids
	var/list/poll_meta
	var/selected_pollid
	var/list/selected_detail

/datum/poll_browser_dialog/New(mob/new_player/owner)
	rel_set(src, "owner", owner)
	poll_ids = list()
	poll_meta = list()
	refresh_poll_list()

// The new player owns this dialog (poll_browser_dialog); owner is a plain relation back.

DECLARE_UI_STATE(/datum/poll_browser_dialog, GLOB.tgui_always_state)

DECLARE_UI(/datum/poll_browser_dialog, "PollBrowser", UI_TITLE("Player Polls"))

/datum/poll_browser_dialog/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/// A prompt flow (flow_io.dm): the list is replaced when the rows arrive.
/datum/poll_browser_dialog/proc/refresh_poll_list()
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(refresh_poll_list), args)
	if(!SSdbcore.IsConnected() || !owner?.client)
		poll_ids.Cut()
		poll_meta.Cut()
		return
	var/isadmin = check_rights_for(owner.client, R_HOLDER) ? 1 : 0
	// Adminonly clause is a static fragment of the query selected at
	// build-time � not user input. The Now() BETWEEN comparison takes no
	// parameters. Parameterised queries below for any user-derived value.
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, question FROM erro_poll_question WHERE [(isadmin ? "" : "adminonly = false AND")] Now() BETWEEN starttime AND endtime",
	)
	q.Execute()
	poll_ids.Cut()
	poll_meta.Cut()
	while(q.NextRow())
		var/id_str = "[q.item[1]]"
		var/question = q.item[2]
		poll_ids += id_str
		poll_meta[id_str] = list("id" = text2num(id_str), "question" = question)
	qdel(q)

UI_DATA_REPLACE(/datum/poll_browser_dialog, "merge:ui_data_datum_poll_browser_dialog{polls:list,selected:list}")

/// The computed part of /datum/poll_browser_dialog's window data (declared on its UI_DATA row).
/datum/poll_browser_dialog/proc/ui_data_datum_poll_browser_dialog(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["polls"] = list()
	for(var/id_str in poll_ids)
		var/list/meta = poll_meta[id_str]
		data["polls"] += list(list("id" = meta["id"], "question" = meta["question"]))
	data["selected"] = (selected_pollid && selected_detail) ? selected_detail : null
	return data

/// Loads the selected poll's detail as a prompt flow (flow_io.dm): build_poll_detail()'s reads
/// each re-run it, and the detail shows once they have all arrived.
/datum/poll_browser_dialog/proc/load_poll_detail(pollid)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(load_poll_detail), args)
	if(selected_pollid != pollid)
		return
	selected_detail = build_poll_detail(pollid)
	SStgui.update_uis(src)

/// Runs inside load_poll_detail()'s flow.
/datum/poll_browser_dialog/proc/build_poll_detail(pollid)
	. = list()
	.["id"] = pollid
	.["error"] = null
	.["voted"] = FALSE

	if(!SSdbcore.IsConnected() || !owner?.ckey)
		.["error"] = "Database unavailable."
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT starttime, endtime, question, polltype, multiplechoiceoptions FROM erro_poll_question WHERE id = :t_pollid",
		list("t_pollid" = pollid),
	)
	q.Execute()
	var/found = FALSE
	var/start_time = ""
	var/end_time = ""
	var/question = ""
	var/poll_type = ""
	var/multi_max = 0
	while(q.NextRow())
		start_time = q.item[1]
		end_time = q.item[2]
		question = q.item[3]
		poll_type = q.item[4]
		multi_max = text2num("[q.item[5]]") || 0
		found = TRUE
		break
	qdel(q)
	if(!found)
		.["error"] = "Poll question details not found."
		return

	.["start_time"] = start_time
	.["end_time"] = end_time
	.["question"] = question
	.["poll_type"] = poll_type
	.["multi_max"] = multi_max

	switch(poll_type)
		if("OPTION")
			.["voted_option_id"] = null
			.["options"] = build_option_list(pollid)

			var/datum/db_query/v = SSdbcore.NewQuery(
				"SELECT optionid FROM erro_poll_vote WHERE pollid = :t_pollid AND ckey = :t_ckey",
				list("t_pollid" = pollid, "t_ckey" = owner.ckey),
			)
			v.Execute()
			while(v.NextRow())
				.["voted"] = TRUE
				.["voted_option_id"] = text2num("[v.item[1]]")
				break
			qdel(v)

		if("MULTICHOICE")
			.["options"] = build_option_list(pollid)

			var/list/voted_for = list()
			var/datum/db_query/v = SSdbcore.NewQuery(
				"SELECT optionid FROM erro_poll_vote WHERE pollid = :t_pollid AND ckey = :t_ckey",
				list("t_pollid" = pollid, "t_ckey" = owner.ckey),
			)
			v.Execute()
			while(v.NextRow())
				voted_for += text2num("[v.item[1]]")
			qdel(v)
			if(length(voted_for))
				.["voted"] = TRUE
			.["voted_options"] = voted_for

		if("TEXT")
			var/datum/db_query/v = SSdbcore.NewQuery(
				"SELECT replytext FROM erro_poll_textreply WHERE pollid = :t_pollid AND ckey = :t_ckey",
				list("t_pollid" = pollid, "t_ckey" = owner.ckey),
			)
			v.Execute()
			while(v.NextRow())
				.["voted"] = TRUE
				.["vote_text"] = "[v.item[1]]"
				break
			qdel(v)

		if("NUMVAL")
			.["options"] = build_numval_options(pollid)
			.["voted_ratings"] = list()
			var/datum/db_query/v = SSdbcore.NewQuery(
				"SELECT o.text, v.rating FROM erro_poll_option o, erro_poll_vote v WHERE o.pollid = :t_pollid AND v.ckey = :t_ckey AND o.id = v.optionid",
				list("t_pollid" = pollid, "t_ckey" = owner.ckey),
			)
			v.Execute()
			while(v.NextRow())
				.["voted"] = TRUE
				.["voted_ratings"] += list(list("text" = "[v.item[1]]", "rating" = "[v.item[2]]"))
			qdel(v)

/datum/poll_browser_dialog/proc/build_option_list(pollid)
	var/list/out = list()
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, text FROM erro_poll_option WHERE pollid = :t_pollid",
		list("t_pollid" = pollid),
	)
	q.Execute()
	while(q.NextRow())
		out += list(list("id" = text2num("[q.item[1]]"), "text" = "[q.item[2]]"))
	qdel(q)
	return out

/datum/poll_browser_dialog/proc/build_numval_options(pollid)
	var/list/out = list()
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, text, minval, maxval, descmin, descmid, descmax FROM erro_poll_option WHERE pollid = :t_pollid",
		list("t_pollid" = pollid),
	)
	q.Execute()
	while(q.NextRow())
		var/optionid = text2num("[q.item[1]]")
		var/optiontext = "[q.item[2]]"
		var/minvalue = text2num("[q.item[3]]")
		var/maxvalue = text2num("[q.item[4]]")
		var/descmin = "[q.item[5]]"
		var/descmid = "[q.item[6]]"
		var/descmax = "[q.item[7]]"
		if(isnull(minvalue) || isnull(maxvalue) || minvalue == maxvalue)
			continue
		var/midvalue = round((maxvalue + minvalue) / 2)
		var/list/scale = list()
		scale += list(list("value" = "abstain", "label" = "abstain"))
		for(var/i = minvalue, i <= maxvalue, i++)
			var/label = "[i]"
			if(i == minvalue && length(descmin))
				label = "[i] ([descmin])"
			else if(i == midvalue && length(descmid))
				label = "[i] ([descmid])"
			else if(i == maxvalue && length(descmax))
				label = "[i] ([descmax])"
			scale += list(list("value" = "[i]", "label" = label))
		out += list(list(
			"id" = optionid,
			"text" = optiontext,
			"min" = minvalue,
			"max" = maxvalue,
			"scale" = scale,
		))
	qdel(q)
	return out

/datum/poll_browser_dialog/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!owner)
		return FALSE
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_refresh)
	refresh_poll_list()
	if(selected_pollid)
		load_poll_detail(selected_pollid)
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "select", ui_act_select, UI_ARG_NUM("id"))
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_select)
	var/id = params["id"]
	if(!isnum(id))
		return
	selected_pollid = id
	selected_detail = null
	load_poll_detail(id)
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "back", ui_act_back)
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_back)
	selected_pollid = null
	selected_detail = null
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "vote_option", ui_act_vote_option, UI_ARG_NUM("optionid"), UI_ARG_NUM("pollid"))
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_vote_option)
	var/pollid = params["pollid"]
	var/optionid = params["optionid"]
	if(isnum(pollid) && isnum(optionid))
		owner.vote_on_poll(pollid, optionid)
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "vote_text", ui_act_vote_text, UI_ARG_NUM("pollid"), UI_ARG_TEXT("replytext"))
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_vote_text)
	var/pollid = params["pollid"]
	var/replytext = "[params["replytext"]]"
	if(isnum(pollid) && length(replytext))
		owner.log_text_poll_reply(pollid, replytext)
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "vote_text_abstain", ui_act_vote_text_abstain, UI_ARG_NUM("pollid"))
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_vote_text_abstain)
	var/pollid = params["pollid"]
	if(isnum(pollid))
		owner.log_text_poll_reply(pollid, "ABSTAIN")
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "vote_numval", ui_act_vote_numval, UI_ARG_NUM("pollid"), UI_ARG_LIST("ratings"))
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_vote_numval)
	var/pollid = params["pollid"]
	if(!isnum(pollid))
		return
	var/list/ratings = params["ratings"]
	if(!islist(ratings))
		return
	for(var/optionid_str in ratings)
		var/optionid = text2num("[optionid_str]")
		if(!isnum(optionid))
			continue
		var/raw = "[ratings[optionid_str]]"
		var/rating
		if(raw == "abstain" || !length(raw))
			rating = null
		else
			rating = text2num(raw)
			if(!isnum(rating))
				continue
		owner.vote_on_numval_poll(pollid, optionid, rating)
	return TRUE

UI_ACT(/datum/poll_browser_dialog, "vote_multi", ui_act_vote_multi, UI_ARG_LIST("optionids"), UI_ARG_NUM("pollid"))
UI_ACT_PROC(/datum/poll_browser_dialog, ui_act_vote_multi)
	var/pollid = params["pollid"]
	if(!isnum(pollid))
		return
	var/list/choices = params["optionids"]
	if(!islist(choices))
		return
	for(var/choice in choices)
		var/optionid = text2num("[choice]")
		if(isnum(optionid))
			owner.vote_on_poll(pollid, optionid, 1)
	return TRUE

// ============================================================
// /mob/new_player extensions (re-open type to add per-mob refs)
// ============================================================

/mob/new_player
	var/datum/privacy_poll_dialog/privacy_poll_dialog
	var/datum/poll_browser_dialog/poll_browser_dialog

#undef PRIVACY_OPTION_SIGNED
#undef PRIVACY_OPTION_ANONYMOUS
#undef PRIVACY_OPTION_NOSTATS
#undef PRIVACY_OPTION_LATER
#undef PRIVACY_OPTION_ABSTAIN

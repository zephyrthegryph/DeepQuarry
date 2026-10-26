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
	rel_set(src, nameof(owner), owner)

// The new player owns this dialog (privacy_poll_dialog); owner is a plain relation back.

/// /datum/privacy_poll_dialog's window data.
/datum/privacy_poll_dialog/ui_data(datum/act/eval/A)
	return list("answered" = answered)

CAPABILITIES(/datum/privacy_poll_dialog)
	interface("PrivacyPoll", title = "Player Poll — Privacy", state = nameof(GLOB.tgui_always_state))
	op("vote", ui_act("vote", arg("choice")), then(PROC_REF(ui_act_vote)))
	ref_one(nameof(owner))

/datum/privacy_poll_dialog/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/datum/privacy_poll_dialog/proc/ui_act_vote(datum/act/op/A, choice_arg)
	if(!isnull(choice_arg) && !(choice_arg in list(PRIVACY_OPTION_LATER, PRIVACY_OPTION_SIGNED, PRIVACY_OPTION_ANONYMOUS, PRIVACY_OPTION_NOSTATS, PRIVACY_OPTION_ABSTAIN)))
		return FALSE
	var/choice = choice_arg
	if(!owner || !choice)
		return
	if(!SSdbcore.IsConnected())
		return
	if(choice == PRIVACY_OPTION_LATER)
		SStgui.close_uis(src)
		spent(src)
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

/// Records the vote unless this player already voted: the check is a read on the I/O lane, and the vote is written in its callback.
/datum/privacy_poll_dialog/proc/record_vote(option)
	if(!owner || answered)
		return
	sql_ask(src, "SELECT 1 FROM erro_privacy WHERE ckey = :t_ckey", list("t_ckey" = owner.ckey), PROC_REF(vote_checked), option)

/datum/privacy_poll_dialog/proc/vote_checked(list/result, error, option)
	if(!owner || answered)
		return
	var/list/check_rows = sql_answer_rows(result, error, "privacy poll: earlier vote of [owner.ckey]")
	var/voted = FALSE
	if(length(check_rows))
		voted = TRUE

	if(!voted)
		sql_write("INSERT INTO erro_privacy VALUES (null, Now(), :t_ckey, :t_option)", list("t_ckey" = owner.ckey, "t_option" = option))
		to_chat(owner, span_bold("Thank you for your vote!"))

	set_answered(TRUE)
	SStgui.close_uis(src)
	spent(src)

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
	rel_set(src, nameof(owner), owner)
	poll_ids = list()
	poll_meta = list()
	refresh_poll_list()

// The new player owns this dialog (poll_browser_dialog); owner is a plain relation back.

CAPABILITIES(/datum/poll_browser_dialog)
	interface("PollBrowser", title = "Player Polls", state = nameof(GLOB.tgui_always_state))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("select", ui_act("select", arg("id", num())), then(PROC_REF(ui_act_select)))
	op("back", ui_act("back"), then(PROC_REF(ui_act_back)))
	op("vote_option", ui_act("vote_option", arg("optionid", num()), arg("pollid", num())), then(PROC_REF(ui_act_vote_option)))
	op("vote_text", ui_act("vote_text", arg("pollid", num()), arg("replytext", schema_text(4096))), then(PROC_REF(ui_act_vote_text)))
	op("vote_text_abstain", ui_act("vote_text_abstain", arg("pollid", num())), then(PROC_REF(ui_act_vote_text_abstain)))
	op("vote_numval", ui_act("vote_numval", arg("pollid", num()), arg("ratings")), then(PROC_REF(ui_act_vote_numval)))
	op("vote_multi", ui_act("vote_multi", arg("optionids"), arg("pollid", num())), then(PROC_REF(ui_act_vote_multi)))
	ref_one(nameof(owner))

/datum/poll_browser_dialog/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/// Reloads the poll list: the read is on the I/O lane, and the list is replaced when the rows arrive.
/datum/poll_browser_dialog/proc/refresh_poll_list()
	if(!SSdbcore.IsConnected() || !owner?.client)
		clear_poll_ids()
		clear_poll_meta()
		return
	var/isadmin = check_rights_for(owner.client, R_HOLDER) ? 1 : 0
	// Adminonly clause is a static fragment of the query selected at
	// build-time, not user input. The Now() BETWEEN comparison takes no
	// parameters. Parameterised queries below for any user-derived value.
	sql_ask(src, "SELECT id, question FROM erro_poll_question WHERE [(isadmin ? "" : "adminonly = false AND")] Now() BETWEEN starttime AND endtime", null, PROC_REF(poll_list_loaded))

/datum/poll_browser_dialog/proc/poll_list_loaded(list/result, error)
	var/list/question_rows = sql_answer_rows(result, error, "poll list")
	clear_poll_ids()
	clear_poll_meta()
	for(var/list/question_row as anything in question_rows)
		var/id_str = "[question_row[1]]"
		var/question = question_row[2]
		add_poll_ids(id_str)
		set_poll_meta_at(id_str, list("id" = text2num(id_str), "question" = question))

/// /datum/poll_browser_dialog's window data.
/datum/poll_browser_dialog/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["polls"] = list()
	for(var/id_str in poll_ids)
		var/list/meta = poll_meta[id_str]
		data["polls"] += list(list("id" = meta["id"], "question" = meta["question"]))
	data["selected"] = (selected_pollid && selected_detail) ? selected_detail : null
	return data

/// Loads the selected poll's detail: the question, then (by its type) its options and this player's earlier vote are read on the I/O
/// lane, one after another, and the detail shows once they have all arrived. Each answer is dropped if another poll was selected meanwhile.
/datum/poll_browser_dialog/proc/load_poll_detail(pollid)
	if(selected_pollid != pollid)
		return
	if(!SSdbcore.IsConnected() || !owner?.ckey)
		poll_detail_done(pollid, list("id" = pollid, "error" = "Database unavailable.", "voted" = FALSE))
		return
	sql_ask(src, "SELECT starttime, endtime, question, polltype, multiplechoiceoptions FROM erro_poll_question WHERE id = :t_pollid", list("t_pollid" = pollid), PROC_REF(poll_detail_loaded), pollid)

/// The detail is complete (or failed): it is shown.
/datum/poll_browser_dialog/proc/poll_detail_done(pollid, list/detail)
	if(selected_pollid != pollid)
		return
	set_selected_detail(detail)
	SStgui.update_uis(src)

/datum/poll_browser_dialog/proc/poll_detail_loaded(list/result, error, pollid)
	if(selected_pollid != pollid)
		return
	var/list/detail = list("id" = pollid, "error" = null, "voted" = FALSE)
	var/list/detail_rows = sql_answer_rows(result, error, "poll detail: question [pollid]")
	if(!length(detail_rows))
		detail["error"] = "Poll question details not found."
		poll_detail_done(pollid, detail)
		return
	var/list/detail_row = detail_rows[1]
	var/poll_type = detail_row[4]
	detail["start_time"] = detail_row[1]
	detail["end_time"] = detail_row[2]
	detail["question"] = detail_row[3]
	detail["poll_type"] = poll_type
	detail["multi_max"] = text2num("[detail_row[5]]") || 0

	switch(poll_type)
		if("OPTION")
			detail["voted_option_id"] = null
			sql_ask(src, "SELECT id, text FROM erro_poll_option WHERE pollid = :t_pollid", list("t_pollid" = pollid), PROC_REF(poll_detail_options_loaded), pollid, detail)
		if("MULTICHOICE")
			sql_ask(src, "SELECT id, text FROM erro_poll_option WHERE pollid = :t_pollid", list("t_pollid" = pollid), PROC_REF(poll_detail_options_loaded), pollid, detail)
		if("TEXT")
			sql_ask(src, "SELECT replytext FROM erro_poll_textreply WHERE pollid = :t_pollid AND ckey = :t_ckey", list("t_pollid" = pollid, "t_ckey" = owner.ckey), PROC_REF(poll_detail_reply_loaded), pollid, detail)
		if("NUMVAL")
			sql_ask(src, "SELECT id, text, minval, maxval, descmin, descmid, descmax FROM erro_poll_option WHERE pollid = :t_pollid", list("t_pollid" = pollid), PROC_REF(poll_detail_numval_options_loaded), pollid, detail)
		else
			poll_detail_done(pollid, detail)

/// An option or multichoice poll's options arrived: this player's earlier votes are next.
/datum/poll_browser_dialog/proc/poll_detail_options_loaded(list/result, error, pollid, list/detail)
	if(selected_pollid != pollid)
		return
	detail["options"] = option_list_from_rows(sql_answer_rows(result, error, "poll detail: options of [pollid]"))
	sql_ask(src, "SELECT optionid FROM erro_poll_vote WHERE pollid = :t_pollid AND ckey = :t_ckey", list("t_pollid" = pollid, "t_ckey" = owner?.ckey), PROC_REF(poll_detail_votes_loaded), pollid, detail)

/datum/poll_browser_dialog/proc/poll_detail_votes_loaded(list/result, error, pollid, list/detail)
	if(selected_pollid != pollid)
		return
	var/list/voted_rows = sql_answer_rows(result, error, "poll detail: votes on [pollid]")
	if(detail["poll_type"] == "OPTION")
		if(length(voted_rows))
			var/list/voted_row = voted_rows[1]
			detail["voted"] = TRUE
			detail["voted_option_id"] = text2num("[voted_row[1]]")
	else
		var/list/voted_for = list()
		for(var/list/voted_row as anything in voted_rows)
			voted_for += text2num("[voted_row[1]]")
		if(length(voted_for))
			detail["voted"] = TRUE
		detail["voted_options"] = voted_for
	poll_detail_done(pollid, detail)

/// A text poll's earlier reply arrived.
/datum/poll_browser_dialog/proc/poll_detail_reply_loaded(list/result, error, pollid, list/detail)
	if(selected_pollid != pollid)
		return
	var/list/reply_rows = sql_answer_rows(result, error, "poll detail: reply to [pollid]")
	if(length(reply_rows))
		var/list/reply_row = reply_rows[1]
		detail["voted"] = TRUE
		detail["vote_text"] = "[reply_row[1]]"
	poll_detail_done(pollid, detail)

/// A rating poll's options arrived: this player's earlier ratings are next.
/datum/poll_browser_dialog/proc/poll_detail_numval_options_loaded(list/result, error, pollid, list/detail)
	if(selected_pollid != pollid)
		return
	detail["options"] = numval_options_from_rows(sql_answer_rows(result, error, "poll detail: rating options of [pollid]"))
	detail["voted_ratings"] = list()
	sql_ask(src, "SELECT o.text, v.rating FROM erro_poll_option o, erro_poll_vote v WHERE o.pollid = :t_pollid AND v.ckey = :t_ckey AND o.id = v.optionid", list("t_pollid" = pollid, "t_ckey" = owner?.ckey), PROC_REF(poll_detail_ratings_loaded), pollid, detail)

/datum/poll_browser_dialog/proc/poll_detail_ratings_loaded(list/result, error, pollid, list/detail)
	if(selected_pollid != pollid)
		return
	var/list/rating_rows = sql_answer_rows(result, error, "poll detail: ratings on [pollid]")
	for(var/list/rating_row as anything in rating_rows)
		detail["voted"] = TRUE
		detail["voted_ratings"] += list(list("text" = "[rating_row[1]]", "rating" = "[rating_row[2]]"))
	poll_detail_done(pollid, detail)

/datum/poll_browser_dialog/proc/option_list_from_rows(list/option_rows)
	var/list/out = list()
	for(var/list/option_row as anything in option_rows)
		out += list(list("id" = text2num("[option_row[1]]"), "text" = "[option_row[2]]"))
	return out

/datum/poll_browser_dialog/proc/numval_options_from_rows(list/numval_rows)
	var/list/out = list()
	for(var/list/numval_row as anything in numval_rows)
		var/optionid = text2num("[numval_row[1]]")
		var/optiontext = "[numval_row[2]]"
		var/minvalue = text2num("[numval_row[3]]")
		var/maxvalue = text2num("[numval_row[4]]")
		var/descmin = "[numval_row[5]]"
		var/descmid = "[numval_row[6]]"
		var/descmax = "[numval_row[7]]"
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
	return out

/datum/poll_browser_dialog/proc/ui_gate(datum/act/op/A)
	if(!owner)
		return FALSE
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_refresh(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	refresh_poll_list()
	if(selected_pollid)
		load_poll_detail(selected_pollid)
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_select(datum/act/op/A, id_arg)
	if(!ui_gate(A))
		return FALSE
	var/id = id_arg
	if(!isnum(id))
		return
	set_selected_pollid(id)
	set_selected_detail(null)
	load_poll_detail(id)
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_back(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	set_selected_pollid(null)
	set_selected_detail(null)
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_vote_option(datum/act/op/A, optionid_arg, pollid_arg)
	if(!ui_gate(A))
		return FALSE
	var/pollid = pollid_arg
	var/optionid = optionid_arg
	if(isnum(pollid) && isnum(optionid))
		owner.vote_on_poll(pollid, optionid)
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_vote_text(datum/act/op/A, pollid_arg, replytext_arg)
	if(!ui_gate(A))
		return FALSE
	var/pollid = pollid_arg
	var/replytext = "[replytext_arg]"
	if(isnum(pollid) && length(replytext))
		owner.log_text_poll_reply(pollid, replytext)
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_vote_text_abstain(datum/act/op/A, pollid_arg)
	if(!ui_gate(A))
		return FALSE
	var/pollid = pollid_arg
	if(isnum(pollid))
		owner.log_text_poll_reply(pollid, "ABSTAIN")
	return TRUE

/datum/poll_browser_dialog/proc/ui_act_vote_numval(datum/act/op/A, pollid_arg, ratings_arg)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ratings_arg) && !islist(ratings_arg))
		return FALSE
	var/pollid = pollid_arg
	if(!isnum(pollid))
		return
	var/list/ratings = ratings_arg
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

/datum/poll_browser_dialog/proc/ui_act_vote_multi(datum/act/op/A, optionids, pollid_arg)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(optionids) && !islist(optionids))
		return FALSE
	var/pollid = pollid_arg
	if(!isnum(pollid))
		return
	var/list/choices = optionids
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

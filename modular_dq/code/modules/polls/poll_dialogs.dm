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
	src.owner = owner

/datum/privacy_poll_dialog/Destroy()
	if(owner && owner.privacy_poll_dialog == src)
		owner.privacy_poll_dialog = null
	owner = null
	return ..()

/datum/privacy_poll_dialog/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/privacy_poll_dialog/tgui_data(mob/user)
	return list("answered" = answered)

/datum/privacy_poll_dialog/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PrivacyPoll", "Player Poll — Privacy")
		ui.open()

/datum/privacy_poll_dialog/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/privacy_poll_dialog/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return

	if(action != "vote" || !owner)
		return

	var/choice = params["choice"]
	if(!choice)
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
		else
			return

	var/voted = FALSE
	var/datum/db_query/check = SSdbcore.NewQuery("SELECT 1 FROM erro_privacy WHERE ckey='[owner.ckey]'")
	check.Execute()
	while(check.NextRow())
		voted = TRUE
		break
	qdel(check)

	if(!voted)
		var/datum/db_query/ins = SSdbcore.NewQuery("INSERT INTO erro_privacy VALUES (null, Now(), '[owner.ckey]', '[option]')")
		ins.Execute()
		qdel(ins)
		to_chat(owner, span_bold("Thank you for your vote!"))

	answered = TRUE
	SStgui.close_uis(src)
	qdel(src)
	return TRUE


// ============================================================
// Player poll browser
// ============================================================

/datum/poll_browser_dialog
	var/mob/new_player/owner
	var/list/poll_ids
	var/list/poll_meta
	var/selected_pollid
	var/list/cached_detail

/datum/poll_browser_dialog/New(mob/new_player/owner)
	src.owner = owner
	poll_ids = list()
	poll_meta = list()
	refresh_poll_list()

/datum/poll_browser_dialog/Destroy()
	if(owner && owner.poll_browser_dialog == src)
		owner.poll_browser_dialog = null
	owner = null
	poll_ids = null
	poll_meta = null
	cached_detail = null
	return ..()

/datum/poll_browser_dialog/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/poll_browser_dialog/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PollBrowser", "Player Polls")
		ui.open()

/datum/poll_browser_dialog/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/poll_browser_dialog/proc/refresh_poll_list()
	poll_ids.Cut()
	poll_meta.Cut()
	if(!SSdbcore.IsConnected() || !owner?.client)
		return
	var/isadmin = check_rights_for(owner.client, R_HOLDER) ? 1 : 0
	var/datum/db_query/q = SSdbcore.NewQuery("SELECT id, question FROM erro_poll_question WHERE [(isadmin ? "" : "adminonly = false AND")] Now() BETWEEN starttime AND endtime")
	q.Execute()
	while(q.NextRow())
		var/id_str = "[q.item[1]]"
		var/question = q.item[2]
		poll_ids += id_str
		poll_meta[id_str] = list("id" = text2num(id_str), "question" = question)
	qdel(q)

/datum/poll_browser_dialog/tgui_data(mob/user)
	var/list/data = list()
	data["polls"] = list()
	for(var/id_str in poll_ids)
		var/list/meta = poll_meta[id_str]
		data["polls"] += list(list("id" = meta["id"], "question" = meta["question"]))
	data["selected"] = (selected_pollid && cached_detail) ? cached_detail : null
	return data

/datum/poll_browser_dialog/proc/build_poll_detail(pollid)
	. = list()
	.["id"] = pollid
	.["error"] = null
	.["voted"] = FALSE

	if(!SSdbcore.IsConnected() || !owner?.ckey)
		.["error"] = "Database unavailable."
		return

	var/datum/db_query/q = SSdbcore.NewQuery("SELECT starttime, endtime, question, polltype, multiplechoiceoptions FROM erro_poll_question WHERE id = [pollid]")
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

			var/datum/db_query/v = SSdbcore.NewQuery("SELECT optionid FROM erro_poll_vote WHERE pollid = [pollid] AND ckey = '[owner.ckey]'")
			v.Execute()
			while(v.NextRow())
				.["voted"] = TRUE
				.["voted_option_id"] = text2num("[v.item[1]]")
				break
			qdel(v)

		if("MULTICHOICE")
			.["options"] = build_option_list(pollid)

			var/list/voted_for = list()
			var/datum/db_query/v = SSdbcore.NewQuery("SELECT optionid FROM erro_poll_vote WHERE pollid = [pollid] AND ckey = '[owner.ckey]'")
			v.Execute()
			while(v.NextRow())
				voted_for += text2num("[v.item[1]]")
			qdel(v)
			if(length(voted_for))
				.["voted"] = TRUE
			.["voted_options"] = voted_for

		if("TEXT")
			var/datum/db_query/v = SSdbcore.NewQuery("SELECT replytext FROM erro_poll_textreply WHERE pollid = [pollid] AND ckey = '[owner.ckey]'")
			v.Execute()
			while(v.NextRow())
				.["voted"] = TRUE
				.["vote_text"] = "[v.item[1]]"
				break
			qdel(v)

		if("NUMVAL")
			.["options"] = build_numval_options(pollid)
			.["voted_ratings"] = list()
			var/datum/db_query/v = SSdbcore.NewQuery("SELECT o.text, v.rating FROM erro_poll_option o, erro_poll_vote v WHERE o.pollid = [pollid] AND v.ckey = '[owner.ckey]' AND o.id = v.optionid")
			v.Execute()
			while(v.NextRow())
				.["voted"] = TRUE
				.["voted_ratings"] += list(list("text" = "[v.item[1]]", "rating" = "[v.item[2]]"))
			qdel(v)

/datum/poll_browser_dialog/proc/build_option_list(pollid)
	var/list/out = list()
	var/datum/db_query/q = SSdbcore.NewQuery("SELECT id, text FROM erro_poll_option WHERE pollid = [pollid]")
	q.Execute()
	while(q.NextRow())
		out += list(list("id" = text2num("[q.item[1]]"), "text" = "[q.item[2]]"))
	qdel(q)
	return out

/datum/poll_browser_dialog/proc/build_numval_options(pollid)
	var/list/out = list()
	var/datum/db_query/q = SSdbcore.NewQuery("SELECT id, text, minval, maxval, descmin, descmid, descmax FROM erro_poll_option WHERE pollid = [pollid]")
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

/datum/poll_browser_dialog/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!owner)
		return

	switch(action)
		if("refresh")
			refresh_poll_list()
			if(selected_pollid)
				cached_detail = build_poll_detail(selected_pollid)
			return TRUE

		if("select")
			var/id = text2num("[params["id"]]")
			if(!isnum(id))
				return
			selected_pollid = id
			cached_detail = build_poll_detail(id)
			return TRUE

		if("back")
			selected_pollid = null
			cached_detail = null
			return TRUE

		if("vote_option")
			var/pollid = text2num("[params["pollid"]]")
			var/optionid = text2num("[params["optionid"]]")
			if(isnum(pollid) && isnum(optionid))
				owner.vote_on_poll(pollid, optionid)
			if(selected_pollid)
				cached_detail = build_poll_detail(selected_pollid)
			return TRUE

		if("vote_text")
			var/pollid = text2num("[params["pollid"]]")
			var/replytext = "[params["replytext"]]"
			if(isnum(pollid) && length(replytext))
				owner.log_text_poll_reply(pollid, replytext)
			if(selected_pollid)
				cached_detail = build_poll_detail(selected_pollid)
			return TRUE

		if("vote_text_abstain")
			var/pollid = text2num("[params["pollid"]]")
			if(isnum(pollid))
				owner.log_text_poll_reply(pollid, "ABSTAIN")
			if(selected_pollid)
				cached_detail = build_poll_detail(selected_pollid)
			return TRUE

		if("vote_numval")
			var/pollid = text2num("[params["pollid"]]")
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
			if(selected_pollid)
				cached_detail = build_poll_detail(selected_pollid)
			return TRUE

		if("vote_multi")
			var/pollid = text2num("[params["pollid"]]")
			if(!isnum(pollid))
				return
			var/list/choices = params["optionids"]
			if(!islist(choices))
				return
			for(var/choice in choices)
				var/optionid = text2num("[choice]")
				if(isnum(optionid))
					owner.vote_on_poll(pollid, optionid, 1)
			if(selected_pollid)
				cached_detail = build_poll_detail(selected_pollid)
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

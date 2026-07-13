// poll system fully migrated to TGUI.
// Entry-point procs now spawn /datum/privacy_poll_dialog or
// /datum/poll_browser_dialog (code/modules/polls/poll_dialogs.dm).
// The DB-write helpers below (vote_on_poll, log_text_poll_reply,
// vote_on_numval_poll) are still called from those datums.

/mob/new_player/proc/handle_privacy_poll()
	if(!SSdbcore.IsConnected())
		return
	var/voted = 0

	var/datum/db_query/query = SSdbcore.NewQuery("SELECT * FROM erro_privacy WHERE ckey=:ckey", list("ckey" = src.ckey))
	query.Execute()
	while(query.NextRow())
		voted = 1
		break
	qdel(query)
	if(!voted)
		privacy_poll()

/mob/new_player/proc/privacy_poll()
	if(!client)
		return
	if(!privacy_poll_dialog)
		privacy_poll_dialog = new(src)
	privacy_poll_dialog.tgui_interact(src)

/datum/polloption
	var/optionid
	var/optiontext

/mob/new_player/proc/handle_player_polling()
	if(!SSdbcore.IsConnected() || !client)
		return
	if(!poll_browser_dialog)
		poll_browser_dialog = new(src)
	else
		poll_browser_dialog.refresh_poll_list()
	poll_browser_dialog.tgui_interact(src)

/mob/new_player/proc/poll_player(pollid = -1)
	// Kept as a legacy entry point; just opens the browser and selects
	// the given poll. Vote actions now flow through poll_browser_dialog.
	if(!client)
		return
	if(!poll_browser_dialog)
		poll_browser_dialog = new(src)
	if(isnum(pollid) && pollid > 0)
		poll_browser_dialog.selected_pollid = pollid
	poll_browser_dialog.tgui_interact(src)

/mob/new_player/proc/vote_on_poll(pollid = -1, optionid = -1, multichoice = 0)
	if(pollid == -1 || optionid == -1)
		return

	if(!isnum(pollid) || !isnum(optionid))
		return
	if(SSdbcore.IsConnected())

		var/datum/db_query/select_query = SSdbcore.NewQuery("SELECT starttime, endtime, question, polltype, multiplechoiceoptions FROM erro_poll_question WHERE id = [pollid] AND Now() BETWEEN starttime AND endtime")
		select_query.Execute()

		var/validpoll = 0
		var/multiplechoiceoptions = 0

		while(select_query.NextRow())
			if(select_query.item[4] != "OPTION" && select_query.item[4] != "MULTICHOICE")
				return
			validpoll = 1
			if(select_query.item[5])
				multiplechoiceoptions = text2num(select_query.item[5])
			break
		qdel(select_query)
		if(!validpoll)
			to_chat(src, span_red("Poll is not valid."))
			return

		var/datum/db_query/select_query2 = SSdbcore.NewQuery("SELECT id FROM erro_poll_option WHERE id = [optionid] AND pollid = [pollid]")
		select_query2.Execute()

		var/validoption = 0

		while(select_query2.NextRow())
			validoption = 1
			break

		qdel(select_query2)
		if(!validoption)
			to_chat(src, span_red("Poll option is not valid."))
			return

		var/alreadyvoted = 0

		var/datum/db_query/voted_query = SSdbcore.NewQuery("SELECT id FROM erro_poll_vote WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = pollid, "ckey" = src.ckey))
		voted_query.Execute()

		while(voted_query.NextRow())
			alreadyvoted += 1
			if(!multichoice)
				break
		qdel(voted_query)
		if(!multichoice && alreadyvoted)
			to_chat(src, span_red("You already voted in this poll."))
			return

		if(multichoice && (alreadyvoted >= multiplechoiceoptions))
			to_chat(src, span_red("You already have more than [multiplechoiceoptions] logged votes on this poll. Enough is enough. Contact the database admin if this is an error."))
			return

		var/adminrank = "Player"
		if(client && client.holder)
			adminrank = client.holder.rank_names()


		var/datum/db_query/insert_query = SSdbcore.NewQuery("INSERT INTO erro_poll_vote (id ,datetime ,pollid ,optionid ,ckey ,ip ,adminrank) VALUES (null, Now(), :pollid, :optionid, :ckey, :ip, :adminrank)",
			list("pollid" = pollid, "optionid" = optionid, "ckey" = src.ckey, "ip" = client.address, "adminrank" = adminrank))
		insert_query.Execute()

		to_chat(src, span_blue("Vote successful."))
		qdel(insert_query)


/mob/new_player/proc/log_text_poll_reply(pollid = -1, replytext = "")
	if(pollid == -1 || replytext == "")
		return

	if(!isnum(pollid) || !istext(replytext))
		return
	if(SSdbcore.IsConnected())

		var/datum/db_query/select_query = SSdbcore.NewQuery("SELECT starttime, endtime, question, polltype FROM erro_poll_question WHERE id = [pollid] AND Now() BETWEEN starttime AND endtime")
		select_query.Execute()

		var/validpoll = 0

		while(select_query.NextRow())
			if(select_query.item[4] != "TEXT")
				return
			validpoll = 1
			break
		qdel(select_query)
		if(!validpoll)
			to_chat(src, span_red("Poll is not valid."))
			return

		var/alreadyvoted = 0

		var/datum/db_query/voted_query = SSdbcore.NewQuery("SELECT id FROM erro_poll_textreply WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = pollid, "ckey" = src.ckey))
		voted_query.Execute()

		while(voted_query.NextRow())
			alreadyvoted = 1
			break
		qdel(voted_query)
		if(alreadyvoted)
			to_chat(src, span_red("You already sent your feedback for this poll."))
			return

		var/adminrank = "Player"
		if(client && client.holder)
			adminrank = client.holder.rank_names()


		replytext = replacetext(replytext, "%BR%", "")
		replytext = replacetext(replytext, "\n", "%BR%")
		var/text_pass = reject_bad_text(replytext,8000)
		replytext = replacetext(replytext, "%BR%", "<BR>")

		if(!text_pass)
			to_chat(src, "The text you entered was blank, contained illegal characters or was too long. Please correct the text and submit again.")
			return

		var/datum/db_query/insert_query = SSdbcore.NewQuery("INSERT INTO erro_poll_textreply (id ,datetime ,pollid ,ckey ,ip ,replytext ,adminrank) VALUES (null, Now(), :pollid, :ckey, :ip, :replytext, :adminrank)",
			list("pollid" = pollid, "ckey" = src.ckey, "ip" = client.address, "replytext" = replytext, "adminrank" = adminrank))
		insert_query.Execute()

		to_chat(src, span_blue("Feedback logging successful."))
		qdel(insert_query)


/mob/new_player/proc/vote_on_numval_poll(pollid = -1, optionid = -1, rating = null)
	if(pollid == -1 || optionid == -1)
		return

	if(!isnum(pollid) || !isnum(optionid))
		return
	if(SSdbcore.IsConnected())

		var/datum/db_query/select_query = SSdbcore.NewQuery("SELECT starttime, endtime, question, polltype FROM erro_poll_question WHERE id = [pollid] AND Now() BETWEEN starttime AND endtime")
		select_query.Execute()

		var/validpoll = 0

		while(select_query.NextRow())
			if(select_query.item[4] != "NUMVAL")
				return
			validpoll = 1
			break
		qdel(select_query)
		if(!validpoll)
			to_chat(src, span_red("Poll is not valid."))
			return

		var/datum/db_query/select_query2 = SSdbcore.NewQuery("SELECT id FROM erro_poll_option WHERE id = [optionid] AND pollid = [pollid]")
		select_query2.Execute()

		var/validoption = 0

		while(select_query2.NextRow())
			validoption = 1
			break
		qdel(select_query2)
		if(!validoption)
			to_chat(src, span_red("Poll option is not valid."))
			return

		var/alreadyvoted = 0

		var/datum/db_query/voted_query = SSdbcore.NewQuery("SELECT id FROM erro_poll_vote WHERE optionid = :optionid AND ckey = :ckey", list("optionid" = optionid, "ckey" = src.ckey))
		voted_query.Execute()

		while(voted_query.NextRow())
			alreadyvoted = 1
			break
		qdel(voted_query)
		if(alreadyvoted)
			to_chat(src, span_red("You already voted in this poll."))
			return

		var/adminrank = "Player"
		if(client && client.holder)
			adminrank = client.holder.rank_names()


		var/datum/db_query/insert_query = SSdbcore.NewQuery("INSERT INTO erro_poll_vote (id ,datetime ,pollid ,optionid ,ckey ,ip ,adminrank, rating) VALUES (null, Now(), :pollid, :optionid, :ckey, :ip, :adminrank, :rating)",
			list("pollid" = pollid, "optionid" = optionid, "ckey" = src.ckey, "ip" = client.address, "adminrank" = adminrank, "rating" = rating))
		insert_query.Execute()

		to_chat(src, span_blue("Vote successful."))
		qdel(insert_query)


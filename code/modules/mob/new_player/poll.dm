// poll system fully migrated to TGUI.
// Entry-point procs now spawn /datum/privacy_poll_dialog or
// /datum/poll_browser_dialog (code/modules/polls/poll_dialogs.dm).
// The DB-write helpers below (vote_on_poll, log_text_poll_reply,
// vote_on_numval_poll) are still called from those datums.
//
// Every read is a sql_ask() on the I/O lane (code/engine/io/db.dm): the answer arrives in a
// callback on the mob, which carries on with the next read, and the write goes last. A mob that is
// deleted meanwhile drops the answer.

/// Shows the privacy poll unless this player already answered it.
/mob/new_player/proc/handle_privacy_poll()
	if(!SSdbcore.IsConnected())
		return
	sql_ask(src, "SELECT * FROM [format_table_name("erro_privacy")] WHERE ckey=:ckey", list("ckey" = src.ckey), PROC_REF(privacy_poll_checked))

/mob/new_player/proc/privacy_poll_checked(list/result, error)
	var/list/privacy_rows = sql_answer_rows(result, error, "privacy poll check")
	if(!length(privacy_rows))
		privacy_poll()

/mob/new_player/proc/privacy_poll()
	if(!client)
		return
	if(!privacy_poll_dialog)
		rel_set(src, nameof(privacy_poll_dialog), new /datum/privacy_poll_dialog(src))
	privacy_poll_dialog.tgui_interact(src)

/datum/polloption
	var/optionid
	var/optiontext

/mob/new_player/proc/handle_player_polling()
	if(!SSdbcore.IsConnected() || !client)
		return
	if(!poll_browser_dialog)
		rel_set(src, nameof(poll_browser_dialog), new /datum/poll_browser_dialog(src))
	else
		poll_browser_dialog.refresh_poll_list()
	poll_browser_dialog.tgui_interact(src)

/mob/new_player/proc/poll_player(pollid = -1)
	// Kept as a legacy entry point; just opens the browser and selects
	// the given poll. Vote actions now flow through poll_browser_dialog.
	if(!client)
		return
	if(!poll_browser_dialog)
		rel_set(src, nameof(poll_browser_dialog), new /datum/poll_browser_dialog(src))
	if(isnum(pollid) && pollid > 0)
		poll_browser_dialog.selected_pollid = pollid
	poll_browser_dialog.tgui_interact(src)

/// A vote on an option poll: the poll, the option and the player's earlier votes are read in that order, then the vote is written.
/mob/new_player/proc/vote_on_poll(pollid = -1, optionid = -1, multichoice = 0)
	if(pollid == -1 || optionid == -1)
		return

	if(!isnum(pollid) || !isnum(optionid))
		return
	if(SSdbcore.IsConnected())
		sql_ask(src, "SELECT starttime, endtime, question, polltype, multiplechoiceoptions FROM [format_table_name("erro_poll_question")] WHERE id = :pollid AND Now() BETWEEN starttime AND endtime", list("pollid" = pollid), PROC_REF(vote_poll_question_loaded), pollid, optionid, multichoice)

/mob/new_player/proc/vote_poll_question_loaded(list/result, error, pollid, optionid, multichoice)
	var/list/question_rows = sql_answer_rows(result, error, "poll vote: question [pollid]")

	var/validpoll = 0
	var/multiplechoiceoptions = 0

	if(length(question_rows))
		var/list/question_row = question_rows[1]
		if(question_row[4] != "OPTION" && question_row[4] != "MULTICHOICE")
			return
		validpoll = 1
		if(question_row[5])
			multiplechoiceoptions = text2num(question_row[5])
	if(!validpoll)
		to_chat(src, span_red("Poll is not valid."))
		return

	sql_ask(src, "SELECT id FROM [format_table_name("erro_poll_option")] WHERE id = :optionid AND pollid = :pollid", list("optionid" = optionid, "pollid" = pollid), PROC_REF(vote_poll_option_loaded), pollid, optionid, multichoice, multiplechoiceoptions)

/mob/new_player/proc/vote_poll_option_loaded(list/result, error, pollid, optionid, multichoice, multiplechoiceoptions)
	var/list/option_rows = sql_answer_rows(result, error, "poll vote: option [optionid]")

	var/validoption = 0

	if(length(option_rows))
		validoption = 1

	if(!validoption)
		to_chat(src, span_red("Poll option is not valid."))
		return

	sql_ask(src, "SELECT id FROM [format_table_name("erro_poll_vote")] WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = pollid, "ckey" = src.ckey), PROC_REF(vote_poll_earlier_votes_loaded), pollid, optionid, multichoice, multiplechoiceoptions)

/mob/new_player/proc/vote_poll_earlier_votes_loaded(list/result, error, pollid, optionid, multichoice, multiplechoiceoptions)
	var/list/voted_rows = sql_answer_rows(result, error, "poll vote: earlier votes on [pollid]")
	var/alreadyvoted = multichoice ? length(voted_rows) : min(length(voted_rows), 1)
	if(!multichoice && alreadyvoted)
		to_chat(src, span_red("You already voted in this poll."))
		return

	if(multichoice && (alreadyvoted >= multiplechoiceoptions))
		to_chat(src, span_red("You already have more than [multiplechoiceoptions] logged votes on this poll. Enough is enough. Contact the database admin if this is an error."))
		return

	var/adminrank = "Player"
	if(client && client.holder)
		adminrank = client.holder.rank_names()


	if(!client)
		return
	sql_ask(src, "INSERT INTO [format_table_name("erro_poll_vote")] (id ,datetime ,pollid ,optionid ,ckey ,ip ,adminrank) VALUES (null, Now(), :pollid, :optionid, :ckey, :ip, :adminrank)",
		list("pollid" = pollid, "optionid" = optionid, "ckey" = src.ckey, "ip" = client.address, "adminrank" = adminrank), PROC_REF(poll_vote_written), pollid)

/// A poll vote's insert answered (an option, multichoice or rating vote): the voter is told and the poll window reloads.
/mob/new_player/proc/poll_vote_written(list/result, error, pollid)
	if(error)
		log_sql("[error] | poll vote insert on [pollid] by [ckey]")
		return
	to_chat(src, span_blue("Vote successful."))
	if(poll_browser_dialog)
		after(poll_browser_dialog, 0.1 SECONDS, TYPE_PROC_REF(/datum/poll_browser_dialog, load_poll_detail), with = list(pollid))

/// A text reply to a poll: the poll and the player's earlier reply are read, then the reply is written.
/mob/new_player/proc/log_text_poll_reply(pollid = -1, replytext = "")
	if(pollid == -1 || replytext == "")
		return

	if(!isnum(pollid) || !istext(replytext))
		return
	if(SSdbcore.IsConnected())
		sql_ask(src, "SELECT starttime, endtime, question, polltype FROM [format_table_name("erro_poll_question")] WHERE id = :pollid AND Now() BETWEEN starttime AND endtime", list("pollid" = pollid), PROC_REF(text_reply_question_loaded), pollid, replytext)

/mob/new_player/proc/text_reply_question_loaded(list/result, error, pollid, replytext)
	var/list/question_rows = sql_answer_rows(result, error, "poll reply: question [pollid]")

	var/validpoll = 0

	if(length(question_rows))
		var/list/question_row = question_rows[1]
		if(question_row[4] != "TEXT")
			return
		validpoll = 1
	if(!validpoll)
		to_chat(src, span_red("Poll is not valid."))
		return

	sql_ask(src, "SELECT id FROM [format_table_name("erro_poll_textreply")] WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = pollid, "ckey" = src.ckey), PROC_REF(text_reply_earlier_loaded), pollid, replytext)

/mob/new_player/proc/text_reply_earlier_loaded(list/result, error, pollid, replytext)
	var/list/voted_rows = sql_answer_rows(result, error, "poll reply: earlier reply on [pollid]")
	var/alreadyvoted = 0
	if(length(voted_rows))
		alreadyvoted = 1
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

	if(!client)
		return
	sql_ask(src, "INSERT INTO [format_table_name("erro_poll_textreply")] (id ,datetime ,pollid ,ckey ,ip ,replytext ,adminrank) VALUES (null, Now(), :pollid, :ckey, :ip, :replytext, :adminrank)",
		list("pollid" = pollid, "ckey" = src.ckey, "ip" = client.address, "replytext" = replytext, "adminrank" = adminrank), PROC_REF(text_reply_written), pollid)

/mob/new_player/proc/text_reply_written(list/result, error, pollid)
	if(error)
		log_sql("[error] | poll text reply insert on [pollid] by [ckey]")
		return
	to_chat(src, span_blue("Feedback logging successful."))
	if(poll_browser_dialog)
		after(poll_browser_dialog, 0.1 SECONDS, TYPE_PROC_REF(/datum/poll_browser_dialog, load_poll_detail), with = list(pollid))

/// A rating on a numeric-scale poll: the poll, the option and the player's earlier rating are read, then the rating is written.
/mob/new_player/proc/vote_on_numval_poll(pollid = -1, optionid = -1, rating = null)
	if(pollid == -1 || optionid == -1)
		return

	if(!isnum(pollid) || !isnum(optionid))
		return
	if(SSdbcore.IsConnected())
		sql_ask(src, "SELECT starttime, endtime, question, polltype FROM [format_table_name("erro_poll_question")] WHERE id = :pollid AND Now() BETWEEN starttime AND endtime", list("pollid" = pollid), PROC_REF(numval_question_loaded), pollid, optionid, rating)

/mob/new_player/proc/numval_question_loaded(list/result, error, pollid, optionid, rating)
	var/list/question_rows = sql_answer_rows(result, error, "poll rating: question [pollid]")

	var/validpoll = 0

	if(length(question_rows))
		var/list/question_row = question_rows[1]
		if(question_row[4] != "NUMVAL")
			return
		validpoll = 1
	if(!validpoll)
		to_chat(src, span_red("Poll is not valid."))
		return

	sql_ask(src, "SELECT id FROM [format_table_name("erro_poll_option")] WHERE id = :optionid AND pollid = :pollid", list("optionid" = optionid, "pollid" = pollid), PROC_REF(numval_option_loaded), pollid, optionid, rating)

/mob/new_player/proc/numval_option_loaded(list/result, error, pollid, optionid, rating)
	var/list/option_rows = sql_answer_rows(result, error, "poll rating: option [optionid]")

	var/validoption = 0

	if(length(option_rows))
		validoption = 1
	if(!validoption)
		to_chat(src, span_red("Poll option is not valid."))
		return

	sql_ask(src, "SELECT id FROM [format_table_name("erro_poll_vote")] WHERE optionid = :optionid AND ckey = :ckey", list("optionid" = optionid, "ckey" = src.ckey), PROC_REF(numval_earlier_loaded), pollid, optionid, rating)

/mob/new_player/proc/numval_earlier_loaded(list/result, error, pollid, optionid, rating)
	var/list/voted_rows = sql_answer_rows(result, error, "poll rating: earlier rating on option [optionid]")
	var/alreadyvoted = 0
	if(length(voted_rows))
		alreadyvoted = 1
	if(alreadyvoted)
		to_chat(src, span_red("You already voted in this poll."))
		return

	var/adminrank = "Player"
	if(client && client.holder)
		adminrank = client.holder.rank_names()


	if(!client)
		return
	sql_ask(src, "INSERT INTO [format_table_name("erro_poll_vote")] (id ,datetime ,pollid ,optionid ,ckey ,ip ,adminrank, rating) VALUES (null, Now(), :pollid, :optionid, :ckey, :ip, :adminrank, :rating)",
		list("pollid" = pollid, "optionid" = optionid, "ckey" = src.ckey, "ip" = client.address, "adminrank" = adminrank, "rating" = rating), PROC_REF(poll_vote_written), pollid)

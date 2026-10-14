#define MEMOFILE "data/memo.sav"	//where the memos are saved
#define ENABLE_MEMOS // this is so stupid

//switch verb so we don't spam up the verb lists with like, 3 verbs for this feature.
ADMIN_VERB(admin_memo, R_ADMIN|R_MOD|R_EVENT, "Memo", "Manage admin memos.", ADMIN_CATEGORY_SERVER_ADMIN)
	#ifndef ENABLE_MEMOS
	return
	#endif

	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_memo_menu, PROC_REF(memo_action_answered), answerer = answerer)

/datum/admin_verb/admin_memo/proc/memo_action_answered(datum/act/request/A)
	memo_action_chosen(A)

/datum/admin_verb/admin_memo/proc/memo_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	var/task = A.request.value

	switch(task)
		if("write")
			user.admin_memo_write()
		if("show")
			user.admin_memo_show()
		if("delete")
			user.admin_memo_delete()

//write a message
/client/proc/admin_memo_write(memo = null, answered = FALSE)
	var/savefile/F = new(MEMOFILE)
	if(F)
		if(!answered)
			var/mob/answerer = mob
			if(QDELETED(answerer))
				return
			var/datum/admin_memo_review/review = new
			rel_set(review, nameof(review.actor), answerer)
			review.client_ckey = ckey
			review.writing = TRUE
			open_request(review, /datum/prompt/text/admin_memo_write, TYPE_PROC_REF(/datum/admin_memo_review, answered), answerer = answerer)
			return
		if(isnull(memo))
			return
		switch(memo)
			if(null)
				return
			if("")
				F.dir.Remove(ckey)
				to_chat(src, span_filter_adminlog(span_bold("Memo removed")))
				return
		if( findtext(memo,"<script",1,0) )
			return
		F[ckey] = "[key] on [time2text(world.realtime,"(DDD) DD MMM hh:mm")]<br>[memo]"
		message_admins("[key] set an admin memo:<br>[memo]")

//show all memos
/client/proc/admin_memo_show()
	#ifndef ENABLE_MEMOS
	return
	#endif
	var/savefile/F = new(MEMOFILE)
	if(F)
		for(var/ckey in F.dir)
			to_chat(src, span_filter_adminlog("<center><span class='motd'><b>Admin Memo</b><i> by [F[ckey]]</i></span></center>"))

//delete your own or somebody else's memo
/client/proc/admin_memo_delete(selected_ckey = null, answered = FALSE)
	var/savefile/F = new(MEMOFILE)
	if(F)
		var/ckey
		if(memo_can_delete_others())	//high ranking admins can delete other admin's memos
			if(!answered)
				var/mob/answerer = mob
				if(QDELETED(answerer))
					return
				var/datum/admin_memo_review/review = new
				rel_set(review, nameof(review.actor), answerer)
				review.client_ckey = src.ckey
				open_request(review, /datum/prompt/choice/admin_memo_delete, TYPE_PROC_REF(/datum/admin_memo_review, answered), answerer = answerer, choices = F.dir)
				return
			if(isnull(selected_ckey))
				return
			ckey = selected_ckey
		else
			ckey = src.ckey
		if(ckey)
			F.dir.Remove(ckey)
			to_chat(src, span_filter_adminlog(span_bold("Removed Memo created by [ckey].")))

/datum/prompt/choice/admin_memo_menu
	title = "Select the Memo Action."
	question = "Select Action"
	choices = list("write", "show", "delete")
	rights = R_ADMIN|R_MOD|R_EVENT
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/admin_memo_write
	question = "Type your memo\n(Leaving it blank will delete your current memo):"
	title = "Write Memo"
	multiline = TRUE
	max_len = MAX_TGUI_INPUT
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admin_memo_delete
	question = "Whose memo shall we remove?"
	title = "Remove Memo"
	timeout = 0
	recheck_on_open = TRUE

/client/proc/memo_can_delete_others()
	return admin_require(src, R_SERVER, "check_rights in [caller?.proc]", FALSE)

/datum/admin_memo_review
	var/mob/actor
	var/client_ckey
	var/writing = FALSE

CAPABILITIES(/datum/admin_memo_review)
	ref_one(nameof(actor), /mob)

/datum/admin_memo_review/proc/refusal()
	return QDELETED(actor) || !GLOB.directory[client_ckey] ? "participant is gone" : null

/datum/admin_memo_review/proc/retire()
	spent(src)

/datum/admin_memo_review/proc/answered(datum/act/request/A)
	finish(A)
	retire()

/datum/admin_memo_review/proc/finish(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = GLOB.directory[client_ckey]
	if(writing)
		user.admin_memo_write(A.request.value, TRUE)
	else
		user.admin_memo_delete(A.request.value, TRUE)

/datum/prompt/text/admin_memo_write/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_memo_review/review = owner
	return review.refusal()

/datum/prompt/choice/admin_memo_delete/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_memo_review/review = owner
	return review.refusal()

#undef MEMOFILE
#undef ENABLE_MEMOS

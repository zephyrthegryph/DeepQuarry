#define MEMOFILE "data/memo.sav"	//where the memos are saved
#define ENABLE_MEMOS // this is so stupid

//switch verb so we don't spam up the verb lists with like, 3 verbs for this feature.
ADMIN_VERB(admin_memo, R_ADMIN|R_MOD|R_EVENT, "Memo", "Manage admin memos.", ADMIN_CATEGORY_SERVER_ADMIN)
	#ifndef ENABLE_MEMOS
	return
	#endif

	var/task = verb_prompt(user, "a1", list("kind" = "list", "message" = "Select Action", "title" = "Select the Memo Action.", "choices" = list("write","show","delete")), args)
	if(isnull(task))
		return
	if(!task)
		return

	switch(task)
		if("write")
			user.admin_memo_write()
		if("show")
			user.admin_memo_show()
		if("delete")
			user.admin_memo_delete()

//write a message
/client/proc/admin_memo_write()
	var/savefile/F = new(MEMOFILE)
	if(F)
		var/memo = client_prompt("a1", list("kind" = "text", "message" = "Type your memo\n(Leaving it blank will delete your current memo):", "title" = "Write Memo", "multiline" = TRUE), PROC_REF(admin_memo_write), args, 0)
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
/client/proc/admin_memo_delete()
	var/savefile/F = new(MEMOFILE)
	if(F)
		var/ckey
		if(check_rights(R_SERVER,0))	//high ranking admins can delete other admin's memos
			var/_answer_a1 = client_prompt("a1", list("kind" = "list", "message" = "Whose memo shall we remove?", "title" = "Remove Memo", "choices" = F.dir), PROC_REF(admin_memo_delete), args, 0)
			if(isnull(_answer_a1))
				return
			ckey = _answer_a1
		else
			ckey = src.ckey
		if(ckey)
			F.dir.Remove(ckey)
			to_chat(src, span_filter_adminlog(span_bold("Removed Memo created by [ckey].")))

#undef MEMOFILE
#undef ENABLE_MEMOS

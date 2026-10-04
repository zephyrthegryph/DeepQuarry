//By Carnwennan

//This system was made as an alternative to all the in-game lists and variables used to log stuff in-game.
//lists and variables are great. However, they have several major flaws:
//Firstly, they use memory. TGstation has one of the highest memory usage of all the ss13 branches.
//Secondly, they are usually stored in an object. This means that they aren't centralised. It also means that
//the data is lost when the object is deleted! This is especially annoying for things like the singulo engine!
#define INVESTIGATE_DIR "data/investigate/"

//SYSTEM
/proc/investigate_subject2file(subject)
	return file("[INVESTIGATE_DIR][subject].html")

/hook/startup/proc/resetInvestigate()
	investigate_reset()
	return 1

/proc/investigate_reset()
	if(fdel(INVESTIGATE_DIR))	return 1
	return 0

/atom/proc/investigate_log(message, subject)
	if(!message)	return
	var/F = investigate_subject2file(subject)
	if(!F)	return
	to_file(F, span_filter_adminlog("<small>[time2text(world.timeofday,"hh:mm")] \ref[src] ([x],[y],[z])</small> || [src] [message]<br>"))

//ADMINVERBS
ADMIN_VERB(investigate_show, R_ADMIN|R_MOD|R_SERVER, "Investigate", "Check hrefs, notes or singulo and telesci logs.", ADMIN_CATEGORY_INVESTIGATE)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_investigation, PROC_REF(investigation_subject_chosen), answerer = answerer, choices = list("hrefs","notes","singulo","telesci"))

/datum/admin_verb/investigate_show/proc/investigation_subject_chosen(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(investigation_subject_answered), A)
	if(!result.ok)
		stack_trace("om flow investigate_show answer investigation_subject_answered: [result.error]")

/datum/admin_verb/investigate_show/proc/investigation_subject_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	var/subject = A.request.answer_value
	if(!subject)
		return

	switch(subject)
		if("singulo", "telesci")			//general one-round-only stuff
			var/F = investigate_subject2file(subject)
			if(!F)
				to_chat(user, span_filter_adminlog(span_warning("Error: admin_investigate: [INVESTIGATE_DIR][subject] is an invalid path or cannot be accessed.")))
				return
			// log viewer now opens a structured TGUI panel.
			var/datum/dq_investigate_panel/panel = new(subject, "[F]")
			panel.tgui_interact(user.mob)

		if("hrefs")				//persistant logs and stuff
			if(config && CONFIG_GET(flag/log_hrefs))
				if(GLOB.href_logfile)
					// log viewer now opens a structured TGUI panel.
					var/datum/dq_investigate_panel/panel = new("hrefs", "[GLOB.href_logfile]")
					panel.tgui_interact(user.mob)
				else
					to_chat(user, span_filter_adminlog(span_warning("Error: admin_investigate: No href logfile found.")))
					return
			else
				to_chat(user, span_filter_adminlog(span_warning("Error: admin_investigate: Href Logging is not on.")))
				return

/datum/prompt/choice/admin_investigation
	question = "Select Subject"
	title = "Select the subject to investigate."
	rights = R_ADMIN|R_MOD|R_SERVER
	timeout = 0

/datum/prompt/choice/admin_investigation/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

#undef INVESTIGATE_DIR

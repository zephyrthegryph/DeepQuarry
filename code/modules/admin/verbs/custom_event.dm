// verb for admins to set custom event
ADMIN_VERB(cmd_admin_change_custom_event, R_ADMIN|R_FUN|R_SERVER|R_EVENT, "Change Custom Event", "Change custom event message.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/text/admin_custom_event, PROC_REF(event_description_answered), answerer = answerer, default = GLOB.custom_event_msg)

/datum/admin_verb/cmd_admin_change_custom_event/proc/event_description_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(apply_event_description), context)
	if(!result.ok)
		stack_trace("om flow cmd_admin_change_custom_event answer event_description_answered: [result.error]")

/datum/admin_verb/cmd_admin_change_custom_event/proc/apply_event_description(datum/act/request/context)
	var/client/user = context.request.answerer.client
	var/input = context.request.answer_value
	if(input == "")
		GLOB.custom_event_msg = null
		log_and_message_admins("has cleared the custom event text.", user)
		return

	log_and_message_admins("has changed the custom event text.", user)

	GLOB.custom_event_msg = input

	to_chat(world, span_filter_system("<h1>[span_alert("Custom Event")]</h1>"))
	to_chat(world, span_filter_system("<h2>[span_alert("A custom event is starting. OOC Info:")]</h2>"))
	to_chat(world, span_filter_system(span_alert("[GLOB.custom_event_msg]")))
	to_chat(world, span_filter_system("<br>"))

// normal verb for players to view info
/client/verb/cmd_view_custom_event()
	set category = VERB_CAT_OOC_GAME
	set name = "Custom Event Info"

	if(!GLOB.custom_event_msg || GLOB.custom_event_msg == "")
		to_chat(src, span_filter_notice("There currently is no known custom event taking place."))
		to_chat(src, span_filter_notice("Keep in mind: it is possible that an admin has not properly set this."))
		return

	to_chat(src, "<h1>[span_filter_notice(span_alert("Custom Event"))]</h1>")
	to_chat(src, "<h2>[span_filter_notice(span_alert("A custom event is taking place. OOC Info:"))]</h2>")
	to_chat(src, span_filter_notice(span_alert("[GLOB.custom_event_msg]<br>")))

/datum/prompt/text/admin_custom_event
	rights = R_ADMIN|R_FUN|R_SERVER|R_EVENT
	timeout = 0
	question = "Enter the description of the custom event. Be descriptive. To cancel the event, make this blank or hit cancel."
	title = "Custom Event"
	max_len = MAX_PAPER_MESSAGE_LEN
	multiline = TRUE

/datum/prompt/text/admin_custom_event/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

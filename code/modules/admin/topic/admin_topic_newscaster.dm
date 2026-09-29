// Admin newscaster href actions. The ac_ prefix stands for AdminCaster; every action re-opens
// the admin news network panel when it is done.

TOPIC_ACTION(/datum/admins, "ac_view_wanted", PROC_REF(topic_ac_view_wanted))
TOPIC_ACTION(/datum/admins, "ac_set_channel_name", PROC_REF(topic_ac_set_channel_name))
TOPIC_ACTION(/datum/admins, "ac_set_channel_lock", PROC_REF(topic_ac_set_channel_lock))
TOPIC_ACTION(/datum/admins, "ac_submit_new_channel", PROC_REF(topic_ac_submit_new_channel))
TOPIC_ACTION(/datum/admins, "ac_set_channel_receiving", PROC_REF(topic_ac_set_channel_receiving))
TOPIC_ACTION(/datum/admins, "ac_set_new_title", PROC_REF(topic_ac_set_new_title))
TOPIC_ACTION(/datum/admins, "ac_set_new_message", PROC_REF(topic_ac_set_new_message))
TOPIC_ACTION(/datum/admins, "ac_submit_new_message", PROC_REF(topic_ac_submit_new_message))
TOPIC_ACTION(/datum/admins, "ac_create_channel", PROC_REF(topic_ac_create_channel))
TOPIC_ACTION(/datum/admins, "ac_create_feed_story", PROC_REF(topic_ac_create_feed_story))
TOPIC_ACTION(/datum/admins, "ac_menu_censor_story", PROC_REF(topic_ac_menu_censor_story))
TOPIC_ACTION(/datum/admins, "ac_menu_censor_channel", PROC_REF(topic_ac_menu_censor_channel))
TOPIC_ACTION(/datum/admins, "ac_menu_wanted", PROC_REF(topic_ac_menu_wanted))
TOPIC_ACTION(/datum/admins, "ac_set_wanted_name", PROC_REF(topic_ac_set_wanted_name))
TOPIC_ACTION(/datum/admins, "ac_set_wanted_desc", PROC_REF(topic_ac_set_wanted_desc))
TOPIC_ACTION(/datum/admins, "ac_submit_wanted", PROC_REF(topic_ac_submit_wanted), TOPIC_NUM("ac_submit_wanted"))
TOPIC_ACTION(/datum/admins, "ac_cancel_wanted", PROC_REF(topic_ac_cancel_wanted))
TOPIC_ACTION(/datum/admins, "ac_censor_channel_author", PROC_REF(topic_ac_censor_channel_author), TOPIC_REF("ac_censor_channel_author", /datum/feed_channel))
TOPIC_ACTION(/datum/admins, "ac_censor_channel_story_author", PROC_REF(topic_ac_censor_channel_story_author), TOPIC_REF("ac_censor_channel_story_author", /datum/feed_message))
TOPIC_ACTION(/datum/admins, "ac_censor_channel_story_body", PROC_REF(topic_ac_censor_channel_story_body), TOPIC_REF("ac_censor_channel_story_body", /datum/feed_message))
TOPIC_ACTION(/datum/admins, "ac_pick_d_notice", PROC_REF(topic_ac_pick_d_notice), TOPIC_REF("ac_pick_d_notice", /datum/feed_channel))
TOPIC_ACTION(/datum/admins, "ac_toggle_d_notice", PROC_REF(topic_ac_toggle_d_notice), TOPIC_REF("ac_toggle_d_notice", /datum/feed_channel))
TOPIC_ACTION(/datum/admins, "ac_view", PROC_REF(topic_ac_view))
TOPIC_ACTION(/datum/admins, "ac_setScreen", PROC_REF(topic_ac_setscreen), TOPIC_NUM("ac_setScreen"))
TOPIC_ACTION(/datum/admins, "ac_show_channel", PROC_REF(topic_ac_show_channel), TOPIC_REF("ac_show_channel", /datum/feed_channel))
TOPIC_ACTION(/datum/admins, "ac_pick_censor_channel", PROC_REF(topic_ac_pick_censor_channel), TOPIC_REF("ac_pick_censor_channel", /datum/feed_channel))
TOPIC_ACTION(/datum/admins, "ac_refresh", PROC_REF(topic_ac_refresh))
TOPIC_ACTION(/datum/admins, "ac_set_signature", PROC_REF(topic_ac_set_signature))

/// Re-opens the admin news network panel after an admincaster action.
/datum/admins/proc/admincaster_refresh(mob/user)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/access_news_network)

/// Switches the admincaster to `screen` and refreshes.
/datum/admins/proc/admincaster_goto(mob/user, screen)
	admincaster_screen = screen
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_view_wanted(mob/user, list/args)
	admincaster_goto(user, 18)

/datum/admins/proc/topic_ac_set_channel_name(mob/user, list/args)
	var/answer = topic_ask(user, args, "a35", /datum/om/prompt/text, message = "Provide a Feed Channel Name", title = "Network Channel Handler", encode = FALSE)
	if(isnull(answer))
		return
	admincaster_feed_channel().channel_name = sanitizeSafe(answer)
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_channel_lock(mob/user, list/args)
	admincaster_feed_channel().locked = !admincaster_feed_channel().locked
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_submit_new_channel(mob/user, list/args)
	var/check = 0
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == admincaster_feed_channel().channel_name)
			check = 1
			break
	if(admincaster_feed_channel().channel_name == "" || admincaster_feed_channel().channel_name == "\[REDACTED\]" || check)
		admincaster_screen = 7
	else
		var/choice = topic_ask(user, args, "a36", /datum/om/prompt/choice/alert, message = "Please confirm Feed channel creation", title = "Network Channel Handler", choices = list("Confirm","Cancel"))
		if(isnull(choice))
			return
		if(choice == "Confirm")
			GLOB.news_network.CreateFeedChannel(admincaster_feed_channel().channel_name, admincaster_signature, admincaster_feed_channel().locked, 1)
			feedback_inc("newscaster_channels",1)                  //Adding channel to the global network
			log_admin("[key_name_admin(user)] created command feed channel: [admincaster_feed_channel().channel_name]!")
			admincaster_screen = 5
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_channel_receiving(mob/user, list/args)
	var/list/available_channels = list()
	for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
		available_channels += F.channel_name
	var/answer = topic_ask(user, args, "a37", /datum/om/prompt/choice, message = "Choose receiving Feed Channel", title = "Network Channel Handler", choices = available_channels)
	if(isnull(answer))
		return
	admincaster_feed_channel().channel_name = answer
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_new_title(mob/user, list/args)
	var/answer = topic_ask(user, args, "a38", /datum/om/prompt/text, message = "Enter the Feed title", title = "Network Channel Handler")
	if(isnull(answer))
		return
	admincaster_feed_message.title = answer
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_new_message(mob/user, list/args)
	var/answer = topic_ask(user, args, "a39", /datum/om/prompt/text, message = "Write your Feed story", title = "Network Channel Handler", multiline = TRUE)
	if(isnull(answer))
		return
	admincaster_feed_message.body = answer
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_submit_new_message(mob/user, list/args)
	if(admincaster_feed_message.body == "" || admincaster_feed_message.title == "" || admincaster_feed_message.body == "\[REDACTED\]" || admincaster_feed_channel().channel_name == "")
		admincaster_screen = 6
	else
		feedback_inc("newscaster_stories",1)
		GLOB.news_network.SubmitArticle(admincaster_feed_message.body, admincaster_signature, admincaster_feed_channel().channel_name, null, 1, "", admincaster_feed_message.title)
		admincaster_screen = 4

	log_admin("[key_name_admin(user)] submitted a feed story to channel: [admincaster_feed_channel().channel_name]!")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_create_channel(mob/user, list/args)
	admincaster_goto(user, 2)

/datum/admins/proc/topic_ac_create_feed_story(mob/user, list/args)
	admincaster_goto(user, 3)

/datum/admins/proc/topic_ac_menu_censor_story(mob/user, list/args)
	admincaster_goto(user, 10)

/datum/admins/proc/topic_ac_menu_censor_channel(mob/user, list/args)
	admincaster_goto(user, 11)

/datum/admins/proc/topic_ac_menu_wanted(mob/user, list/args)
	var/datum/feed_message/wanted = GLOB.news_network.wanted_issue()
	if(wanted)
		admincaster_feed_message.author = wanted.author
		admincaster_feed_message.body = wanted.body
	admincaster_goto(user, 14)

/datum/admins/proc/topic_ac_set_wanted_name(mob/user, list/args)
	var/answer = topic_ask(user, args, "a40", /datum/om/prompt/text, message = "Provide the name of the Wanted person", title = "Network Security Handler")
	if(isnull(answer))
		return
	admincaster_feed_message.author = answer
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_wanted_desc(mob/user, list/args)
	var/answer = topic_ask(user, args, "a41", /datum/om/prompt/text, message = "Provide the a description of the Wanted person and any other details you deem important", title = "Network Security Handler")
	if(isnull(answer))
		return
	admincaster_feed_message.body = answer
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_submit_wanted(mob/user, list/args)
	var/input_param = args["ac_submit_wanted"]
	if(admincaster_feed_message.author == "" || admincaster_feed_message.body == "")
		admincaster_screen = 16
	else
		var/choice = topic_ask(user, args, "a42", /datum/om/prompt/choice/alert, message = "Please confirm Wanted Issue [(input_param==1) ? ("creation.") : ("edit.")]", title = "Network Security Handler", choices = list("Confirm","Cancel"))
		if(isnull(choice))
			return
		if(choice == "Confirm")
			if(input_param == 1)          //If input_param == 1 we're submitting a new wanted issue. At 2 we're just editing an existing one. See the else below
				var/datum/feed_message/WANTED = new /datum/feed_message
				WANTED.author = admincaster_feed_message.author               //Wanted name
				WANTED.body = admincaster_feed_message.body                   //Wanted desc
				WANTED.backup_author = admincaster_signature                  //Submitted by
				WANTED.is_admin_message = 1
				own_set(GLOB.news_network, "wanted_issue_owned", WANTED)
				for(var/obj/machinery/newscaster/NEWSCASTER in REGISTRY_MEMBERS(REGISTRY_CASTERS))
					NEWSCASTER.newsAlert()
					NEWSCASTER.update_icon()
				admincaster_screen = 15
			else
				var/datum/feed_message/wanted = GLOB.news_network.wanted_issue()
				if(wanted)
					wanted.author = admincaster_feed_message.author
					wanted.body = admincaster_feed_message.body
					wanted.backup_author = admincaster_feed_message.backup_author
				admincaster_screen = 19
			log_admin("[key_name_admin(user)] issued a Station-wide Wanted Notification for [admincaster_feed_message.author]!")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_cancel_wanted(mob/user, list/args)
	var/choice = topic_ask(user, args, "a43", /datum/om/prompt/choice/alert, message = "Please confirm Wanted Issue removal", title = "Network Security Handler", choices = list("Confirm","Cancel"))
	if(isnull(choice))
		return
	if(choice == "Confirm")
		own_clear(GLOB.news_network, "wanted_issue_owned", OWN_DELETE)
		for(var/obj/machinery/newscaster/NEWSCASTER in REGISTRY_MEMBERS(REGISTRY_CASTERS))
			NEWSCASTER.update_icon()
		admincaster_screen = 17
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_censor_channel_author(mob/user, list/args)
	var/datum/feed_channel/FC = args["ac_censor_channel_author"]
	if(FC.author != span_bold("\[REDACTED\]"))
		FC.backup_author = FC.author
		FC.author = span_bold("\[REDACTED\]")
	else
		FC.author = FC.backup_author
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_censor_channel_story_author(mob/user, list/args)
	var/datum/feed_message/MSG = args["ac_censor_channel_story_author"]
	if(MSG.author != span_bold("\[REDACTED\]"))
		MSG.backup_author = MSG.author
		MSG.author = span_bold("\[REDACTED\]")
	else
		MSG.author = MSG.backup_author
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_censor_channel_story_body(mob/user, list/args)
	var/datum/feed_message/MSG = args["ac_censor_channel_story_body"]
	if(MSG.body != span_bold("\[REDACTED\]"))
		MSG.backup_body = MSG.body
		MSG.body = span_bold("\[REDACTED\]")
	else
		MSG.body = MSG.backup_body
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_pick_d_notice(mob/user, list/args)
	rel_set(src, "admincaster_feed_channel", args["ac_pick_d_notice"])
	admincaster_goto(user, 13)

/datum/admins/proc/topic_ac_toggle_d_notice(mob/user, list/args)
	var/datum/feed_channel/FC = args["ac_toggle_d_notice"]
	FC.censored = !FC.censored
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_view(mob/user, list/args)
	admincaster_goto(user, 1)

/// Brings us to the main menu and resets all fields.
/datum/admins/proc/topic_ac_setscreen(mob/user, list/args)
	admincaster_screen = args["ac_setScreen"]
	if(admincaster_screen == 0)
		if(admincaster_feed_channel())
			rel_clear(src, "admincaster_feed_channel")
			own_set(src, "admincaster_scratch_channel", new /datum/feed_channel)
		if(admincaster_feed_message)
			own_set(src, "admincaster_feed_message", new /datum/feed_message)
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_show_channel(mob/user, list/args)
	rel_set(src, "admincaster_feed_channel", args["ac_show_channel"])
	admincaster_goto(user, 9)

/datum/admins/proc/topic_ac_pick_censor_channel(mob/user, list/args)
	rel_set(src, "admincaster_feed_channel", args["ac_pick_censor_channel"])
	admincaster_goto(user, 12)

/datum/admins/proc/topic_ac_refresh(mob/user, list/args)
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_signature(mob/user, list/args)
	var/answer = topic_ask(user, args, "a44", /datum/om/prompt/text, message = "Provide your desired signature", title = "Network Identity Handler")
	if(isnull(answer))
		return
	admincaster_signature = answer
	admincaster_refresh(user)

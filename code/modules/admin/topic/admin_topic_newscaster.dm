// Admin newscaster href actions. The ac_ prefix stands for AdminCaster; every action re-opens
// the admin news network panel when it is done.


MSG_DEF_SELF(admin_topic/channel_unsubmittable, "A Feed channel needs a name that no other channel has.")
MSG_DEF_SELF(admin_topic/wanted_unsubmittable, "A Wanted issue needs a name and a description.")

/// Requirement: the channel being drafted can be created.
/datum/admins/proc/ac_channel_ready(datum/act/op/A)
	return (admincaster_channel_ready) ? null : MSG(admin_topic/channel_unsubmittable)

/// Requirement: the Wanted draft can be issued.
/datum/admins/proc/ac_wanted_ready(datum/act/op/A)
	return (admincaster_wanted_ready) ? null : MSG(admin_topic/wanted_unsubmittable)

/// Brings the tracked readiness of the channel and the Wanted draft in line with the drafts and the network.
/datum/admins/proc/admincaster_resync()
	set_admincaster_channel_ready(ac_channel_submittable())
	set_admincaster_wanted_ready(ac_wanted_submittable())

/// Re-opens the admin news network panel after an admincaster action.
/datum/admins/proc/admincaster_refresh(mob/user)
	admincaster_resync()
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/access_news_network)

/// Switches the admincaster to `screen` and refreshes.
/datum/admins/proc/admincaster_goto(mob/user, screen)
	admincaster_screen = screen
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_view_wanted(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_goto(user, 18)

/datum/admins/proc/topic_ac_set_channel_name(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_channel().channel_name = sanitizeSafe(A.step_value("answer"))
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_channel_lock(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_channel().locked = !admincaster_feed_channel().locked
	admincaster_refresh(user)

/// A new channel can be created when it has a name no other channel has.
/datum/admins/proc/ac_channel_submittable()
	var/channel_name = admincaster_feed_channel().channel_name
	if(channel_name == "" || channel_name == "\[REDACTED\]")
		return FALSE
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == channel_name)
			return FALSE
	return TRUE

/datum/admins/proc/topic_ac_submit_new_channel(datum/act/op/A)
	var/mob/user = A.actor
	if(!ac_channel_submittable())
		admincaster_screen = 7
	else if(A.step_value("confirm") == "Confirm")
		GLOB.news_network.CreateFeedChannel(admincaster_feed_channel().channel_name, admincaster_signature, admincaster_feed_channel().locked, 1)
		feedback_inc("newscaster_channels",1)                  //Adding channel to the global network
		log_admin("[key_name_admin(user)] created command feed channel: [admincaster_feed_channel().channel_name]!")
		admincaster_screen = 5
	admincaster_refresh(user)

/// The names of the channels on the network (the choices of the receiving-channel question).
/datum/admins/proc/ac_channel_names(datum/act/op/A)
	var/list/available_channels = list()
	for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
		available_channels += F.channel_name
	return available_channels

/datum/admins/proc/topic_ac_set_channel_receiving(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_channel().channel_name = A.step_value("answer")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_new_title(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_message.title = A.step_value("answer")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_new_message(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_message.body = A.step_value("answer")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_submit_new_message(datum/act/op/A)
	var/mob/user = A.actor
	if(admincaster_feed_message.body == "" || admincaster_feed_message.title == "" || admincaster_feed_message.body == "\[REDACTED\]" || admincaster_feed_channel().channel_name == "")
		admincaster_screen = 6
	else
		feedback_inc("newscaster_stories",1)
		GLOB.news_network.SubmitArticle(admincaster_feed_message.body, admincaster_signature, admincaster_feed_channel().channel_name, null, 1, "", admincaster_feed_message.title)
		admincaster_screen = 4

	log_admin("[key_name_admin(user)] submitted a feed story to channel: [admincaster_feed_channel().channel_name]!")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_create_channel(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_goto(user, 2)

/datum/admins/proc/topic_ac_create_feed_story(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_goto(user, 3)

/datum/admins/proc/topic_ac_menu_censor_story(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_goto(user, 10)

/datum/admins/proc/topic_ac_menu_censor_channel(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_goto(user, 11)

/datum/admins/proc/topic_ac_menu_wanted(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/feed_message/wanted = GLOB.news_network.wanted_issue()
	if(wanted)
		admincaster_feed_message.author = wanted.author
		admincaster_feed_message.body = wanted.body
	admincaster_goto(user, 14)

/datum/admins/proc/topic_ac_set_wanted_name(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_message.author = A.step_value("answer")
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_wanted_desc(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_feed_message.body = A.step_value("answer")
	admincaster_refresh(user)

/// A Wanted issue can be issued when it has a name and a description.
/datum/admins/proc/ac_wanted_submittable()
	return !(admincaster_feed_message.author == "" || admincaster_feed_message.body == "")

/datum/admins/proc/ac_wanted_question(datum/act/op/A)
	return "Please confirm Wanted Issue [(A.args["ac_submit_wanted"] == 1) ? ("creation.") : ("edit.")]"

/datum/admins/proc/topic_ac_submit_wanted(datum/act/op/A, href_ac_submit_wanted)
	var/mob/user = A.actor
	var/input_param = href_ac_submit_wanted
	if(!ac_wanted_submittable())
		admincaster_screen = 16
	else if(A.step_value("confirm") == "Confirm")
		if(input_param == 1)          //If input_param == 1 we're submitting a new wanted issue. At 2 we're just editing an existing one. See the else below
			var/datum/feed_message/WANTED = new /datum/feed_message
			WANTED.author = admincaster_feed_message.author               //Wanted name
			WANTED.body = admincaster_feed_message.body                   //Wanted desc
			WANTED.backup_author = admincaster_signature                  //Submitted by
			WANTED.is_admin_message = 1
			rel_set(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), WANTED)
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

/datum/admins/proc/topic_ac_cancel_wanted(datum/act/op/A)
	var/mob/user = A.actor
	if(A.step_value("confirm") == "Confirm")
		own_clear(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), OWN_DELETE)
		for(var/obj/machinery/newscaster/NEWSCASTER in REGISTRY_MEMBERS(REGISTRY_CASTERS))
			NEWSCASTER.update_icon()
		admincaster_screen = 17
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_censor_channel_author(datum/act/op/A, href_ac_censor_channel_author)
	var/mob/user = A.actor
	var/datum/feed_channel/FC = href_ac_censor_channel_author
	if(FC.author != span_bold("\[REDACTED\]"))
		FC.backup_author = FC.author
		FC.author = span_bold("\[REDACTED\]")
	else
		FC.author = FC.backup_author
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_censor_channel_story_author(datum/act/op/A, href_ac_censor_channel_story_author)
	var/mob/user = A.actor
	var/datum/feed_message/MSG = href_ac_censor_channel_story_author
	if(MSG.author != span_bold("\[REDACTED\]"))
		MSG.backup_author = MSG.author
		MSG.author = span_bold("\[REDACTED\]")
	else
		MSG.author = MSG.backup_author
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_censor_channel_story_body(datum/act/op/A, href_ac_censor_channel_story_body)
	var/mob/user = A.actor
	var/datum/feed_message/MSG = href_ac_censor_channel_story_body
	if(MSG.body != span_bold("\[REDACTED\]"))
		MSG.backup_body = MSG.body
		MSG.body = span_bold("\[REDACTED\]")
	else
		MSG.body = MSG.backup_body
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_pick_d_notice(datum/act/op/A, href_ac_pick_d_notice)
	var/mob/user = A.actor
	rel_set(src, nameof(admincaster_feed_channel), href_ac_pick_d_notice)
	admincaster_goto(user, 13)

/datum/admins/proc/topic_ac_toggle_d_notice(datum/act/op/A, href_ac_toggle_d_notice)
	var/mob/user = A.actor
	var/datum/feed_channel/FC = href_ac_toggle_d_notice
	FC.censored = !FC.censored
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_view(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_goto(user, 1)

/// Brings us to the main menu and resets all fields.
/datum/admins/proc/topic_ac_setscreen(datum/act/op/A, href_ac_setscreen)
	var/mob/user = A.actor
	admincaster_screen = href_ac_setscreen
	if(admincaster_screen == 0)
		if(admincaster_feed_channel())
			rel_clear(src, nameof(admincaster_feed_channel))
			rel_set(src, nameof(admincaster_scratch_channel), new /datum/feed_channel)
		if(admincaster_feed_message)
			rel_set(src, nameof(admincaster_feed_message), new /datum/feed_message)
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_show_channel(datum/act/op/A, href_ac_show_channel)
	var/mob/user = A.actor
	rel_set(src, nameof(admincaster_feed_channel), href_ac_show_channel)
	admincaster_goto(user, 9)

/datum/admins/proc/topic_ac_pick_censor_channel(datum/act/op/A, href_ac_pick_censor_channel)
	var/mob/user = A.actor
	rel_set(src, nameof(admincaster_feed_channel), href_ac_pick_censor_channel)
	admincaster_goto(user, 12)

/datum/admins/proc/topic_ac_refresh(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_refresh(user)

/datum/admins/proc/topic_ac_set_signature(datum/act/op/A)
	var/mob/user = A.actor
	admincaster_signature = A.step_value("answer")
	admincaster_refresh(user)

/datum/prompt/text/admincaster_topic
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/admincaster_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/text/admincaster_topic/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admincaster_topic
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admincaster_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/choice/admincaster_topic/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admincaster_topic/refusal(given)
	return null

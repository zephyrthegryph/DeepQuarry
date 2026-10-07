//##############################################
//################### NEWSCASTERS BE HERE! ####
//###-Agouri###################################

/datum/feed_message
	var/author =""
	var/title
	var/body =""
	var/message_type ="Story"
	var/datum/feed_channel/parent_channel
	var/is_admin_message = 0
	var/img = null
	var/caption = ""
	var/time_stamp = ""
	var/backup_body = ""
	var/backup_author = ""
	var/backup_img = null
	var/backup_caption = ""
	var/post_time = 0

/datum/feed_channel
	var/channel_name=""
	var/list/datum/feed_message/messages = list() // ALLOW(instance_list): d: newscaster channel posts
	var/locked=0
	var/author=""
	var/backup_author=""
	var/censored=0
	var/is_admin_channel=0
	EXPIRY_DECLARE(updated)
	var/announcement = ""

CAPABILITIES(/datum/feed_channel)
	owns_many(nameof(messages))

/datum/feed_message/proc/clear()
	src.author = ""
	src.body = ""
	src.caption = ""
	src.img = null
	src.time_stamp = ""
	src.backup_body = ""
	src.backup_author = ""
	src.backup_caption = ""
	src.backup_img = null
	parent_channel().update()

/datum/feed_channel/proc/update()
	EXPIRY_STAMP(src, updated, CLOCK_WORLD)

/datum/feed_channel/proc/clear()
	src.channel_name = ""
	rel_set(src, nameof(messages), list())
	src.locked = 0
	src.author = ""
	src.backup_author = ""
	src.censored = 0
	src.is_admin_channel = 0
	src.announcement = ""
	update()

/datum/feed_network
	var/list/datum/feed_channel/network_channels
	var/datum/feed_message/wanted_issue_owned

CAPABILITIES(/datum/feed_network)
	owns_one(nameof(wanted_issue_owned), /datum/feed_message)
	owns_many(nameof(network_channels), /datum/feed_channel)

/datum/feed_network/proc/CreateFeedChannel(channel_name, author, locked, adminChannel = 0, announcement_message)
	var/datum/feed_channel/newChannel = new /datum/feed_channel
	newChannel.channel_name = channel_name
	newChannel.author = author
	newChannel.locked = locked
	newChannel.is_admin_channel = adminChannel
	if(announcement_message)
		newChannel.announcement = announcement_message
	else
		newChannel.announcement = "Breaking news from [channel_name]!"
	rel_add(src, nameof(network_channels), newChannel)

/datum/feed_network/proc/SubmitArticle(msg, author, channel_name, obj/item/photo/photo, adminMessage = 0, message_type = "", title)
	var/datum/feed_message/newMsg = new /datum/feed_message
	newMsg.author = author
	newMsg.body = msg
	newMsg.time_stamp = "[stationtime2text()]"
	newMsg.is_admin_message = adminMessage
	if(title)
		newMsg.title = title
	else
		newMsg.title = "News Update"
	newMsg.post_time = round_duration_in_ds // Should be almost universally unique
	if(message_type)
		newMsg.message_type = message_type
	if(photo)
		newMsg.img = photo.img
		newMsg.caption = photo.scribble
	for(var/datum/feed_channel/FC in network_channels)
		if(FC.channel_name == channel_name)
			insert_message_in_channel(FC, newMsg) //Adding message to the network's appropriate feed_channel
			break

/datum/feed_network/proc/insert_message_in_channel(datum/feed_channel/FC, datum/feed_message/newMsg)
	rel_add(FC, nameof(FC.messages), newMsg)
	rel_set(newMsg, nameof(newMsg.parent_channel), FC)
	FC.update()
	alert_readers(FC.announcement)

/datum/feed_network/proc/alert_readers(annoncement)
	for(var/obj/machinery/newscaster/NEWSCASTER in REGISTRY_MEMBERS(REGISTRY_CASTERS))
		NEWSCASTER.newsAlert(annoncement)
		NEWSCASTER.update_icon()

/obj/machinery/newscaster
	name = "newscaster"
	desc = "A standard newsfeed handler for use on commercial space stations. All the news you absolutely have no use for, in one place!"
	icon = 'icons/obj/terminals_vr.dmi'
	icon_state = "newscaster_normal"
	layer = ABOVE_WINDOW_LAYER
	blocks_emissive = NONE
	light_power = 0.9
	light_range = 2
	light_color = "#00ff00"
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = WALL_ITEM
	integrity_failure = 0.5
	var/ispowered = 1 //starts powered, changes with power_change()
	//var/list/datum/feed_channel/channel_list = list() //This list will contain the names of the feed channels. Each name will refer to a data region where the messages of the feed channels are stored.
	//OBSOLETE: We're now using a global news network
	var/paper_remaining = 0
	var/securityCaster = 0
		// 0 = Caster cannot be used to issue wanted posters
		// 1 = the opposite
	var/static/unit_no_cur = 0 //Each newscaster has a unit number
	var/unit_no
	//var/datum/feed_message/wanted //We're gonna use a feed_message to store data of the wanted person because fields are similar
	//var/wanted_issue = 0          //OBSOLETE
		// 0 = there's no WANTED issued, we don't need a special icon_state
		// 1 = Guess what.
	var/alert_delay = 500
	var/alert = 0
		// 0 = there hasn't been a news/wanted update in the last alert_delay
		// 1 = there has
	var/scanned_user = "Unknown" //Will contain the name of the person who currently uses the newscaster
	var/msg = "";                //Feed message
	var/title = "";				// Feed title
	var/datum/news_photo/photo_data = null
	var/channel_name = ""; //the feed channel which will be receiving the feed, or being created
	var/c_locked=0;        //Will our new channel be locked to public submissions?
	var/hitstaken = 0      //Death at 3 hits from an item with force>=15
	var/datum/feed_channel/viewing_channel
	light_range = 0
	anchored = TRUE
	var/obj/machinery/exonet_node/node
	circuit = /obj/item/circuitboard/newscaster
	// TGUI
	var/list/temp = null

CAPABILITIES(/obj/machinery/newscaster)
	after_init(0, then(PROC_REF(connect_exonet)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("set_channel_lock", ui_act("set_channel_lock"), then(PROC_REF(ui_act_set_channel_lock)))
	op("set_attachment", ui_act("set_attachment"), then(PROC_REF(ui_act_set_attachment)))
	owns_one(nameof(photo_data), /datum/news_photo)
	interface("Newscaster")
	op("set_channel_name", ui_act("set_channel_name", arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_channel_name)))
	op("submit_new_channel", ui_act("submit_new_channel"), asks(/datum/prompt/yes_no/news_channel_create, fields = list("title" = "Network Channel Handler", "question" = "Please confirm Feed channel creation", "author" = computed(PROC_REF(channel_author)), "channel" = nameof(channel_name), "locked" = nameof(c_locked), "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0), when = PROC_REF(new_channel_ready)), then(PROC_REF(ui_act_submit_new_channel)))
	op("set_channel_receiving", ui_act("set_channel_receiving"), asks(/datum/prompt/choice, fields = list("title" = "Network Channel Handler", "question" = "Choose receiving Feed Channel", "choices" = computed(PROC_REF(receivable_channels)), "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0)), then(PROC_REF(ui_act_set_channel_receiving)))
	op("set_new_message", ui_act("set_new_message"), asks(/datum/prompt/text, fields = list("title" = "Network Channel Handler", "question" = "Write your Feed story", "default" = "", "max_len" = MAX_MESSAGE_LEN, "multiline" = TRUE, "encode" = FALSE, "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0)), then(PROC_REF(ui_act_set_new_message)))
	op("set_new_title", ui_act("set_new_title"), asks(/datum/prompt/text, fields = list("title" = "Network Channel Handler", "question" = "Enter your Feed title", "default" = "", "max_len" = MAX_KEYPAD_INPUT_LEN, "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0)), then(PROC_REF(ui_act_set_new_title)))
	op("submit_new_message", ui_act("submit_new_message"), then(PROC_REF(ui_act_submit_new_message)))
	op("print_paper", ui_act("print_paper"), then(PROC_REF(ui_act_print_paper)))
	op("set_wanted_desc", ui_act("set_wanted_desc", arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_wanted_desc)))
	op("submit_wanted", ui_act("submit_wanted"), asks(/datum/prompt/yes_no, fields = list("title" = "Network Security Handler", "question" = "Please confirm Wanted Issue change.", "yes_text" = "Confirm", "no_text" = "Cancel", "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0), when = PROC_REF(wanted_ready)), then(PROC_REF(ui_act_submit_wanted)))
	op("cancel_wanted", ui_act("cancel_wanted"), asks(/datum/prompt/yes_no, fields = list("title" = "Network Security Handler", "question" = "Please confirm Wanted Issue removal", "yes_text" = "Confirm", "no_text" = "Cancel", "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0), when = PROC_REF(wanted_removable)), then(PROC_REF(ui_act_cancel_wanted)))
	op("censor_channel_author", ui_act("censor_channel_author", arg("ref")), then(PROC_REF(ui_act_censor_channel_author)))
	op("censor_channel_story_author", ui_act("censor_channel_story_author", arg("ref")), then(PROC_REF(ui_act_censor_channel_story_author)))
	op("censor_channel_story_body", ui_act("censor_channel_story_body", arg("ref")), then(PROC_REF(ui_act_censor_channel_story_body)))
	op("toggle_d_notice", ui_act("toggle_d_notice", arg("ref")), then(PROC_REF(ui_act_toggle_d_notice)))
	op("show_channel", ui_act("show_channel", arg("show_channel")), then(PROC_REF(ui_act_show_channel)))
	op("open", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open)))
	op("as_touch", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(TYPE_PROC_REF(/atom, op_as_touch)))
	display_disconnect_op()

/obj/machinery/newscaster/security_unit                   //Security unit
	name = "Security Newscaster"
	securityCaster = 1

REGISTRY_MEMBERSHIP(/obj/machinery/newscaster, REGISTRY_CASTERS)

// ALLOW(init/INSTANCE_STATE): numbers each unit as it is made and fills its paper tray
/obj/machinery/newscaster/Initialize(mapload)
	. = ..()
	unit_no = ++unit_no_cur
	paper_remaining = 15
	update_icon()

/// Joins the exonet node, once the map around it exists.
/obj/machinery/newscaster/proc/connect_exonet(datum/act/timer/A)
	rel_set(src, nameof(node), get_exonet_node())
	update_icon()

DECLARE_APPEARANCE_PROC(/obj/machinery/newscaster, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/newscaster/appearance_overlays()
	. = list()
	if(!ispowered || (broken_now()))
		icon_state = "newscaster_off"
		if(broken_now()) //If the thing is smashed, add crack overlay on top of the unpowered sprite.
			. += "crack3"
		set_light(0)
		set_light_on(FALSE)
		return .

	if(GLOB.news_network.wanted_issue()) //wanted icon state, there can be no overlays on it as it's a priority message
		icon_state = "newscaster_wanted"
		. += mutable_appearance(icon, "newscaster_wanted_ov")
		. += emissive_appearance(icon, "newscaster_wanted_ov")
		return .

	if(alert) //new message alert overlay
		. += "newscaster_alert"
		. += mutable_appearance(icon, "newscaster_alert")
		. += emissive_appearance(icon, "newscaster_alert")

	if(hitstaken > 0) //Cosmetic damage overlay
		. += "crack[hitstaken]"

	icon_state = "newscaster_normal"
	. += emissive_appearance(icon, "newscaster_normal_ov")
	. += mutable_appearance(icon, "newscaster_normal_ov")
	set_light(2)
	set_light_on(TRUE)
	return .

/obj/machinery/newscaster/power_change()
	if(broken_now()) //Broken shit can't be powered.
		return
	. = ..()
	if(!power_lost())
		ispowered = 1
	else
		after(src, rand(0 SECONDS, 1.5 SECONDS), PROC_REF(lose_power))

/obj/machinery/newscaster/tgui_status(mob/user)
	if(!ispowered || (broken_now()))
		return STATUS_CLOSE
	. = ..()

/obj/machinery/newscaster/proc/interaction_open(datum/act/op/A)
	var/mob/user = A.actor
	if(!ispowered || (broken_now()))
		return OP_OK

	if(!node())
		rel_set(src, nameof(node), get_exonet_node())

	if(!node() || !node().on || !node().allow_external_newscasters)
		to_chat(user, span_danger("Error: Cannot connect to external content.  Please try again in a few minutes.  If this error persists, please \
		contact the system administrator."))
		return OP_OK

	if(!user.IsAdvancedToolUser())
		return OP_OK

	tgui_interact(user)
	return OP_OK

/obj/machinery/newscaster/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/**
 * Sets a temporary message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * style - The style of the message: (color name), info, success, warning, danger, virus
 */
/obj/machinery/newscaster/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

/obj/machinery/newscaster/ui_title(mob/user)
	return "Newscaster Unit #[unit_no]"

/obj/machinery/newscaster/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	// Main menu

	data["user"] = tgui_user_name(user)

	var/list/wanted_issue = null
	if(GLOB.news_network.wanted_issue())
		wanted_issue = list(
			"author" = GLOB.news_network.wanted_issue().backup_author,
			"criminal" = GLOB.news_network.wanted_issue().author,
			"desc" = GLOB.news_network.wanted_issue().body,
			"img" = null
		)
		if(GLOB.news_network.wanted_issue().img)
			wanted_issue["img"] = icon2base64(GLOB.news_network.wanted_issue().img)

	data["wanted_issue"] = wanted_issue

	data["securityCaster"] = !!securityCaster

	var/list/network_channels = list()
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		network_channels.Add(list(list(
			"admin" = FC.is_admin_channel,
			"ref" = REF(FC),
			"name" = FC.channel_name,
			"censored" = FC.censored,
		)))
	data["channels"] = network_channels

	// Creating Channels

	// Creating Messages
	// data["channel_name"] = channel_name
	data["photo_data"] = !!photo_data

	// Printing menu
	var/total_num = LAZYLEN(GLOB.news_network.network_channels)
	var/active_num = total_num
	var/message_num = 0
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		if(!FC.censored)
			message_num += length(FC.messages)    //Dont forget, datum/feed_channel's var messages is a list of datum/feed_message
		else
			active_num--
	data["total_num"] = total_num
	data["active_num"] = active_num
	data["message_num"] = message_num

	// Viewing a specific channel
	var/list/viewing = null
	if(viewing_channel())
		var/list/messages = list()
		viewing = list(
			"name" = viewing_channel().channel_name,
			"author" = viewing_channel().author,
			"censored" = viewing_channel().censored,
			"messages" = messages,
			"ref" = REF(viewing_channel()),
		)
		if(!viewing_channel().censored)
			for(var/datum/feed_message/M in viewing_channel().messages)
				var/list/msgdata = list(
					"title" = M.title,
					"body" = M.body,
					"img" = null,
					"type" = M.message_type,
					"caption" = null,
					"author" = M.author,
					"timestamp" = M.time_stamp,
					"ref" = REF(M),
				)
				if(M.img)
					msgdata["img"] = icon2base64(M.img)
					msgdata["caption"] = M.caption

				messages.Add(list(msgdata))
	data["viewing_channel"] = viewing

	// Censorship
	data["company"] = using_map.company_name

	data["temp"] = temp
	data["unit_no"] = unit_no
	data["channel_name"] = channel_name
	data["c_locked"] = c_locked
	data["msg"] = msg
	data["title"] = title
	data["paper_remaining"] = paper_remaining
	return data

/obj/machinery/newscaster/proc/ui_act_cleartemp(datum/act/op/A)
	temp = null
	return OP_OK

/obj/machinery/newscaster/proc/ui_act_set_channel_name(datum/act/op/A, val)
	channel_name = sanitizeSafe(val, MAX_LNAME_LEN)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_set_channel_lock(datum/act/op/A)
	c_locked = !c_locked
	return OP_OK

/obj/machinery/newscaster/proc/ui_act_submit_new_channel(datum/act/op/A)
	var/mob/user = A.actor
	var/proposed_name = A.captured(nameof(channel_name))
	var/list/existing_authors = list()
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.author == "\[REDACTED\]")
			existing_authors += FC.backup_author
		else
			existing_authors  +=FC.author
	var/check = 0
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == proposed_name)
			check = 1
			break
	var/our_user = tgui_user_name(user)
	if(proposed_name == "" || proposed_name == "\[REDACTED\]")
		set_temp("Error: Could not submit feed channel to network: Invalid Channel Name.", "danger", FALSE)
		return TRUE
	if(our_user == "Unknown")
		set_temp("Error: Could not submit feed channel to network: Channel author unverified.", "danger", FALSE)
		return TRUE
	if(check)
		set_temp("Error: Could not submit feed channel to network: Channel name already in use.", "danger", FALSE)
		return TRUE
	if(our_user in existing_authors)
		set_temp("Error: Could not submit feed channel to network: A feed channel already exists under your name.", "danger", FALSE)
		return TRUE

	channel_creation_confirmed(A)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_set_channel_receiving(datum/act/op/A)
	receiving_channel_chosen(A)
	return OP_OK

/obj/machinery/newscaster/proc/ui_act_set_new_message(datum/act/op/A)
	var/mob/user = A.actor
	story_written(A)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_set_new_title(datum/act/op/A)
	var/mob/user = A.actor
	title_written(A)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_set_attachment(datum/act/op/A)
	AttachPhoto(A.actor)
	return OP_OK

/obj/machinery/newscaster/proc/ui_act_submit_new_message(datum/act/op/A)
	var/mob/user = A.actor
	var/our_user = tgui_user_name(user)
	if(msg == "" || msg == "\[REDACTED\]")
		set_temp("Error: Could not submit feed message to network: Invalid Message.", "danger", FALSE)
		return TRUE
	if(our_user == "Unknown")
		set_temp("Error: Could not submit feed message to network: Channel author unverified.", "danger", FALSE)
		return TRUE
	if(channel_name == "")
		set_temp("Error: Could not submit feed message to network: No feed channel selected.", "danger", FALSE)
		return TRUE
	if(title == "")
		set_temp("Error: Invalid Title.", "danger", FALSE)
		return TRUE

	var/image = photo_data ? photo_data.photo() : null
	feedback_inc("newscaster_stories",1)
	GLOB.news_network.SubmitArticle(msg, our_user, channel_name, image, 0, "", title)
	set_temp("Feed message created successfully.", "success", FALSE)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_print_paper(datum/act/op/A)
	if(!paper_remaining)
		set_temp("Unable to print newspaper. Insufficient paper. Please notify maintenance personnel to refill machine storage.", "danger", FALSE)
		return TRUE

	print_paper()
	set_temp("Printing successful. Please receive your newspaper from the bottom of the machine.", "success", FALSE)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_set_wanted_desc(datum/act/op/A, val)
	msg = sanitize(val)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_submit_wanted(datum/act/op/A)
	var/mob/user = A.actor
	if(!securityCaster)
		return FALSE
	var/our_user = tgui_user_name(user)
	if(channel_name == "")
		set_temp("Error: Could not submit wanted issue to network: Invalid Criminal Name.", "danger", FALSE)
		return TRUE
	if(msg == "")
		set_temp("Error: Could not submit wanted issue to network: Invalid Description.", "danger", FALSE)
		return TRUE
	if(our_user == "Unknown")
		set_temp("Error: Could not submit wanted issue to network: Author unverified.", "danger", FALSE)
		return TRUE

	wanted_change_confirmed(A)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_cancel_wanted(datum/act/op/A)
	var/mob/user = A.actor
	if(!securityCaster)
		return FALSE
	if(GLOB.news_network.wanted_issue().is_admin_message)
		tgui_alert_async(user, "The wanted issue has been distributed by a [using_map.company_name] higherup. You cannot take it down.")
		return
	wanted_removal_confirmed(A)
	return TRUE

/obj/machinery/newscaster/proc/ui_act_censor_channel_author(datum/act/op/A, raw_ref)
	var/mob/user = A.actor
	if(!securityCaster)
		return FALSE
	var/datum/feed_channel/FC = ui_ref(raw_ref, null, /datum/feed_channel)
	if(!FC)
		return
	if(FC.is_admin_channel)
		tgui_alert_async(user, "This channel was created by a [using_map.company_name] Officer. You cannot censor it.")
		return
	if(FC.author != "\[REDACTED\]")
		FC.backup_author = FC.author
		FC.author = "\[REDACTED\]"
	else
		FC.author = FC.backup_author
	FC.update()
	return TRUE

/obj/machinery/newscaster/proc/ui_act_censor_channel_story_author(datum/act/op/A, raw_ref)
	var/mob/user = A.actor
	if(!securityCaster)
		return FALSE
	var/datum/feed_message/MSG = ui_ref(raw_ref, null, /datum/feed_message)
	if(!MSG)
		return
	if(MSG.is_admin_message)
		tgui_alert_async(user, "This message was created by a [using_map.company_name] Officer. You cannot censor its author.")
		return
	if(MSG.author != "\[REDACTED\]")
		MSG.backup_author = MSG.author
		MSG.author = "\[REDACTED\]"
	else
		MSG.author = MSG.backup_author
	MSG.parent_channel().update()
	return TRUE

/obj/machinery/newscaster/proc/ui_act_censor_channel_story_body(datum/act/op/A, raw_ref)
	var/mob/user = A.actor
	if(!securityCaster)
		return FALSE
	var/datum/feed_message/MSG = ui_ref(raw_ref, null, /datum/feed_message)
	if(!MSG)
		return
	if(MSG.is_admin_message)
		tgui_alert_async(user, "This channel was created by a [using_map.company_name] Officer. You cannot censor it.")
		return
	if(MSG.body != "\[REDACTED\]")
		MSG.backup_body = MSG.body
		MSG.backup_caption = MSG.caption
		MSG.backup_img = MSG.img
		MSG.body = "\[REDACTED\]"
		MSG.caption = "\[REDACTED\]"
		MSG.img = null
	else
		MSG.body = MSG.backup_body
		MSG.caption = MSG.caption
		MSG.img = MSG.backup_img

	MSG.parent_channel().update()
	return TRUE

/obj/machinery/newscaster/proc/ui_act_toggle_d_notice(datum/act/op/A, raw_ref)
	var/mob/user = A.actor
	if(!securityCaster)
		return FALSE
	var/datum/feed_channel/FC = ui_ref(raw_ref, null, /datum/feed_channel)
	if(!FC)
		return
	if(FC.is_admin_channel)
		tgui_alert_async(user, "This channel was created by a [using_map.company_name] Officer. You cannot place a D-Notice upon it.")
		return
	FC.censored = !FC.censored
	FC.update()
	return TRUE

/obj/machinery/newscaster/proc/ui_act_show_channel(datum/act/op/A, show_channel)
	var/datum/feed_channel/FC = ui_ref(show_channel, null, /datum/feed_channel)
	rel_set(src, nameof(/obj/machinery/newscaster::viewing_channel), FC)
	return TRUE

/datum/prompt/yes_no/news_channel_create
	yes_text = "Confirm"
	no_text = "Cancel"
	var/author
	var/channel
	var/locked = FALSE

/// Re-checked: the person is still next to the newscaster and able.
/obj/machinery/newscaster/proc/caster_valid(datum/request/R)
	return answerer_holds(R, ANSWER_NEAR_SUBJECT | ANSWER_CAPABLE, src)

/obj/machinery/newscaster/proc/channel_creation_confirmed(datum/act/op/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/yes_no/news_channel_create/R = A.answer
	GLOB.news_network.CreateFeedChannel(R.channel, R.author, R.locked)
	set_temp("Feed channel [R.channel] created successfully.", "success", FALSE)
	SStgui.update_uis(src)

/obj/machinery/newscaster/proc/receiving_channel_chosen(datum/act/op/A)
	if(!A.answer)
		return
	var/new_channel_name = A.answer.value
	channel_name = new_channel_name
	SStgui.update_uis(src)

/obj/machinery/newscaster/proc/story_written(datum/act/op/A)
	if(!A.answer)
		return
	msg = sanitize(A.answer.value, MAX_MESSAGE_LEN, FALSE, FALSE, TRUE)
	SStgui.update_uis(src)

/obj/machinery/newscaster/proc/title_written(datum/act/op/A)
	if(!A.answer)
		return
	title = A.answer.value
	SStgui.update_uis(src)

/obj/machinery/newscaster/proc/wanted_change_confirmed(datum/act/op/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/user = A.actor
	if(GLOB.news_network.wanted_issue())
		if(GLOB.news_network.wanted_issue() && GLOB.news_network.wanted_issue().is_admin_message)
			tgui_alert_async(user, "The wanted issue has been distributed by a [using_map.company_name] higherup. You cannot edit it.")
			return
		GLOB.news_network.wanted_issue().author = channel_name
		GLOB.news_network.wanted_issue().body = msg
		GLOB.news_network.wanted_issue().backup_author = scanned_user
		if(photo_data)
			GLOB.news_network.wanted_issue().img = photo_data.photo().img
		set_temp("Wanted issue for [channel_name] successfully edited.", "success", FALSE)
		SStgui.update_uis(src)
		return

	var/datum/feed_message/WANTED = new /datum/feed_message
	WANTED.author = channel_name
	WANTED.body = msg
	WANTED.backup_author = scanned_user //I know, a bit wacky
	if(photo_data)
		WANTED.img = photo_data.photo().img
	rel_set(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), WANTED)
	GLOB.news_network.alert_readers()
	set_temp("Wanted issue for [channel_name] is now in Network Circulation.", "success", FALSE)
	SStgui.update_uis(src)

/obj/machinery/newscaster/proc/wanted_removal_confirmed(datum/act/op/A)
	if(!A.answer || !A.answer.value)
		return
	if(GLOB.news_network.wanted_issue() && !GLOB.news_network.wanted_issue().is_admin_message)
		own_clear(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), OWN_DELETE)
		for(var/obj/machinery/newscaster/NEWSCASTER in REGISTRY_MEMBERS(REGISTRY_CASTERS))
			NEWSCASTER.update_icon()
		set_temp("Wanted issue taken down.", "success", FALSE)
		SStgui.update_uis(src)

/datum/news_photo
	var/is_synth = 0
	var/obj/item/photo/photo

/datum/news_photo/New(obj/item/photo/p, synth)
	is_synth = synth
	rel_set(src, nameof(photo), p)

/obj/machinery/newscaster/proc/AttachPhoto(mob/user)
	var/obj/item/photo/incoming
	if(istype(user.get_active_hand(), /obj/item/photo))
		incoming = user.get_active_hand()
		if(!own_bring_in(src, nameof(photo_data), incoming, null, user, TRUE, null, FALSE))
			return
	if(photo_data)
		if(!photo_data.is_synth)
			photo_data.photo().forceMove(src.loc)
			if(!issilicon(user))
				user.put_in_inactive_hand(photo_data.photo())
		rel_clear(src, nameof(photo_data))

	if(incoming)
		rel_set(src, nameof(photo_data), new /datum/news_photo(incoming, 0))
	else if(istype(user,/mob/living/silicon))
		var/mob/living/silicon/tempAI = user
		var/obj/item/photo/selection = tempAI.GetPicture()
		if(!selection)
			return

		rel_set(src, nameof(photo_data), new /datum/news_photo(selection, 1))

////////////////////////////////////helper procs
/obj/machinery/newscaster/proc/tgui_user_name(mob/user)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/card/id/I = H.GetIdCard()
		if(I)
			return GetNameAndAssignmentFromId(I)

	if(issilicon(user))
		var/mob/living/silicon/S = user
		return "[S.name] ([S.job])"

	return "Unknown"

/obj/machinery/newscaster/proc/scan_user(mob/living/user)
	if(ishuman(user))                       //User is a human
		var/mob/living/carbon/human/human_user = user
		var/obj/item/card/id/I = human_user.GetIdCard()
		if(I)
			scanned_user = GetNameAndAssignmentFromId(I)
		else
			scanned_user = "Unknown"
	else
		var/mob/living/silicon/ai_user = user
		scanned_user = "[ai_user.name] ([ai_user.job])"

/obj/machinery/newscaster/proc/print_paper()
	feedback_inc("newscaster_newspapers_printed",1)
	var/obj/item/newspaper/NEWSPAPER = new /obj/item/newspaper
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		rel_add(NEWSPAPER, nameof(NEWSPAPER.news_content), FC) // the paper names the network's channels
	if(GLOB.news_network.wanted_issue())
		rel_set(NEWSPAPER, nameof(NEWSPAPER.important_message), GLOB.news_network.wanted_issue())
	NEWSPAPER.forceMove(get_turf(src))
	paper_remaining--
	return

/obj/machinery/newscaster/proc/newsAlert(news_call)
	if(!node() || !node().on || !node().allow_external_newscasters) //The messages will still be there once the connection returns.
		return
	var/turf/T = get_turf(src)
	if(news_call)
		for(var/mob/O in hearers(world.view-1, T))
			O.show_message(span_newscaster("<EM>[name]</EM> beeps, \"[news_call]\""),2)
		alert = 1
		update_icon()
		after(src, 30 SECONDS, PROC_REF(clear_alert))
// playsound(src.loc, 'sound/machines/twobeep.ogg', 75, 1) // less peeps pls
	else
		for(var/mob/O in hearers(world.view-1, T))
			O.show_message(span_newscaster("<EM>[name]</EM> beeps, \"Attention! Wanted issue distributed!\""),2)
		play_sfx(src, SFX_MACHINES_WARNING_BUZZER, 1.5, vary = TRUE)
	return

/obj/machinery/newscaster/proc/lose_power()
	ispowered = 0
	update_icon()

/obj/machinery/newscaster/proc/clear_alert()
	alert = 0
	update_icon()

/// parent channel (a relation view: it reads null once the target is deleted).
/datum/feed_message/proc/parent_channel() as /datum/feed_channel
	return parent_channel

/// DECLARE_REF(..., OWNED): created for and owned by this holder; deleted with it.
/datum/feed_network/proc/wanted_issue() as /datum/feed_message
	return wanted_issue_owned

/// viewing channel (a relation view: it reads null once the target is deleted).
/obj/machinery/newscaster/proc/viewing_channel() as /datum/feed_channel
	return viewing_channel

/// node (a relation view: it reads null once the target is deleted).
/obj/machinery/newscaster/proc/node() as /obj/machinery/exonet_node
	return node

/// photo (a relation view: it reads null once the target is deleted).
/datum/news_photo/proc/photo() as /obj/item/photo
	return photo

/obj/machinery/newscaster/proc/channel_author(datum/act/op/A)
	return tgui_user_name(A.actor)

/obj/machinery/newscaster/proc/new_channel_ready(datum/act/op/A)
	var/author = channel_author(A)
	if(channel_name == "" || channel_name == "\[REDACTED\]" || author == "Unknown")
		return FALSE
	for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
		if(F.channel_name == channel_name || (F.author == "\[REDACTED\]" ? F.backup_author : F.author) == author)
			return FALSE
	return TRUE

/obj/machinery/newscaster/proc/receivable_channels(datum/act/op/A)
	var/list/channels = list()
	for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
		if((!F.locked || F.author == scanned_user) && !F.censored)
			channels += F.channel_name
	return channels

/obj/machinery/newscaster/proc/wanted_ready(datum/act/op/A)
	return securityCaster && channel_name != "" && msg != "" && tgui_user_name(A.actor) != "Unknown"

/obj/machinery/newscaster/proc/wanted_removable(datum/act/op/A)
	return securityCaster && !GLOB.news_network.wanted_issue().is_admin_message

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
	var/updated = 0
	var/announcement = ""

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
	updated = world.time

/datum/feed_channel/proc/clear()
	src.channel_name = ""
	own_set(src, "messages", list())
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
	own_add(src, "network_channels", newChannel)

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
	own_add(FC, "messages", newMsg)
	rel_set(newMsg, "parent_channel", FC)
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

/obj/machinery/newscaster/security_unit                   //Security unit
	name = "Security Newscaster"
	securityCaster = 1

REGISTRY_MEMBERSHIP(/obj/machinery/newscaster, REGISTRY_CASTERS)

/obj/machinery/newscaster/Initialize(mapload)
	..()
	unit_no = ++unit_no_cur
	paper_remaining = 15
	update_icon()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/newscaster/LateInitialize()
	rel_set(src, "node", get_exonet_node())
	update_icon()

/obj/machinery/newscaster/update_icon()
	cut_overlays()
	if(!ispowered || (stat & BROKEN))
		icon_state = "newscaster_off"
		if(stat & BROKEN) //If the thing is smashed, add crack overlay on top of the unpowered sprite.
			add_overlay("crack3")
		set_light(0)
		set_light_on(FALSE)
		return

	if(GLOB.news_network.wanted_issue()) //wanted icon state, there can be no overlays on it as it's a priority message
		icon_state = "newscaster_wanted"
		add_overlay(mutable_appearance(icon, "newscaster_wanted_ov"))
		add_overlay(emissive_appearance(icon, "newscaster_wanted_ov"))
		return

	if(alert) //new message alert overlay
		add_overlay("newscaster_alert")
		add_overlay(mutable_appearance(icon, "newscaster_alert"))
		add_overlay(emissive_appearance(icon, "newscaster_alert"))

	if(hitstaken > 0) //Cosmetic damage overlay
		add_overlay("crack[hitstaken]")

	icon_state = "newscaster_normal"
	add_overlay(emissive_appearance(icon, "newscaster_normal_ov"))
	add_overlay(mutable_appearance(icon, "newscaster_normal_ov"))
	set_light(2)
	set_light_on(TRUE)
	return

/obj/machinery/newscaster/power_change()
	if(stat & BROKEN) //Broken shit can't be powered.
		return
	..()
	if(!(stat & NOPOWER))
		ispowered = 1
		update_icon()
	else
		om_after(src, rand(0, 15), PROC_REF(lose_power))

/obj/machinery/newscaster/tgui_status(mob/user)
	if(!ispowered || (stat & BROKEN))
		return STATUS_CLOSE
	. = ..()

/obj/machinery/newscaster/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/newscaster_open,
		/datum/interaction/machine_item/newscaster_item_open,
	)
	..()

/// Old attack_hand (never called ..()): open the newscaster's interface.
/datum/interaction/machine_hand/ungated/newscaster_open
	id = "newscaster_open"
	name = "Use"
	effect = /obj/machinery/newscaster/proc/interaction_open

/obj/machinery/newscaster/proc/interaction_open(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ispowered || (stat & BROKEN))
		return TRUE

	if(!node())
		rel_set(src, "node", get_exonet_node())

	if(!node() || !node().on || !node().allow_external_newscasters)
		to_chat(user, span_danger("Error: Cannot connect to external content.  Please try again in a few minutes.  If this error persists, please \
		contact the system administrator."))
		return TRUE

	if(!user.IsAdvancedToolUser())
		return TRUE

	tgui_interact(user)
	return TRUE

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

/obj/machinery/newscaster/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Newscaster", "Newscaster Unit #[unit_no]")
		ui.open()

/obj/machinery/newscaster/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	// Main menu
	data["temp"] = temp

	data["user"] = tgui_user_name(user)
	data["unit_no"] = unit_no

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
	data["channel_name"] = channel_name
	data["c_locked"] = c_locked

	// Creating Messages
	// data["channel_name"] = channel_name
	data["msg"] = msg
	data["title"] = title
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
	data["paper_remaining"] = paper_remaining

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

	return data

/obj/machinery/newscaster/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	switch(action)
		if("cleartemp")
			temp = null
			return TRUE

		if("set_channel_name")
			channel_name = sanitizeSafe(params["val"], MAX_LNAME_LEN)
			return TRUE

		if("set_channel_lock")
			c_locked = !c_locked
			return TRUE

		if("submit_new_channel")
			var/list/existing_authors = list()
			for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
				if(FC.author == "\[REDACTED\]")
					existing_authors += FC.backup_author
				else
					existing_authors  +=FC.author
			var/check = 0
			for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
				if(FC.channel_name == channel_name)
					check = 1
					break
			var/our_user = tgui_user_name(ui.user)
			if(channel_name == "" || channel_name == "\[REDACTED\]")
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

			om_ask(ui.user, /datum/om/prompt/confirm/news_channel_create, PROC_REF(channel_creation_confirmed), message = "Please confirm Feed channel creation", title = "Network Channel Handler", requires = PROMPT_USABLE, yes_text = "Confirm", no_text = "Cancel", author = our_user, channel = channel_name, locked = c_locked)
			return TRUE

		if("set_channel_receiving")
			var/list/available_channels = list()
			for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
				if((!F.locked || F.author == scanned_user) && !F.censored)
					available_channels += F.channel_name
			om_ask(ui.user, /datum/om/prompt/choice, PROC_REF(receiving_channel_chosen), message = "Choose receiving Feed Channel", title = "Network Channel Handler", choices = available_channels, requires = PROMPT_USABLE)
			return TRUE

		if("set_new_message")
			om_ask(ui.user, /datum/om/prompt/text, PROC_REF(story_written), message = "Write your Feed story", title = "Network Channel Handler", default = "", max_length = MAX_MESSAGE_LEN, multiline = TRUE, encode = FALSE, requires = PROMPT_USABLE, ui_refresh = src)
			return TRUE

		if("set_new_title")
			om_ask(ui.user, /datum/om/prompt/text, PROC_REF(title_written), message = "Enter your Feed title", title = "Network Channel Handler", default = "", max_length = MAX_KEYPAD_INPUT_LEN, requires = PROMPT_USABLE, ui_refresh = src)
			return TRUE

		if("set_attachment")
			AttachPhoto(ui.user)
			return TRUE

		if("submit_new_message")
			var/our_user = tgui_user_name(ui.user)
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

		if("print_paper")
			if(!paper_remaining)
				set_temp("Unable to print newspaper. Insufficient paper. Please notify maintenance personnel to refill machine storage.", "danger", FALSE)
				return TRUE

			print_paper()
			set_temp("Printing successful. Please receive your newspaper from the bottom of the machine.", "success", FALSE)
			return TRUE

		if("set_wanted_desc")
			msg = sanitize(params["val"])
			return TRUE

		if("submit_wanted")
			if(!securityCaster)
				return FALSE
			var/our_user = tgui_user_name(ui.user)
			if(channel_name == "")
				set_temp("Error: Could not submit wanted issue to network: Invalid Criminal Name.", "danger", FALSE)
				return TRUE
			if(msg == "")
				set_temp("Error: Could not submit wanted issue to network: Invalid Description.", "danger", FALSE)
				return TRUE
			if(our_user == "Unknown")
				set_temp("Error: Could not submit wanted issue to network: Author unverified.", "danger", FALSE)
				return TRUE

			om_ask(ui.user, /datum/om/prompt/confirm, PROC_REF(wanted_change_confirmed), message = "Please confirm Wanted Issue change.", title = "Network Security Handler", requires = PROMPT_USABLE, yes_text = "Confirm", no_text = "Cancel")
			return TRUE

		if("cancel_wanted")
			if(!securityCaster)
				return FALSE
			if(GLOB.news_network.wanted_issue().is_admin_message)
				tgui_alert_async(ui.user, "The wanted issue has been distributed by a [using_map.company_name] higherup. You cannot take it down.")
				return
			om_ask(ui.user, /datum/om/prompt/confirm, PROC_REF(wanted_removal_confirmed), message = "Please confirm Wanted Issue removal", title = "Network Security Handler", requires = PROMPT_USABLE, yes_text = "Confirm", no_text = "Cancel")
			return TRUE

		if("censor_channel_author")
			if(!securityCaster)
				return FALSE
			var/datum/feed_channel/FC = locate(params["ref"])
			if(FC.is_admin_channel)
				tgui_alert_async(ui.user, "This channel was created by a [using_map.company_name] Officer. You cannot censor it.")
				return
			if(FC.author != "\[REDACTED\]")
				FC.backup_author = FC.author
				FC.author = "\[REDACTED\]"
			else
				FC.author = FC.backup_author
			FC.update()
			return TRUE

		if("censor_channel_story_author")
			if(!securityCaster)
				return FALSE
			var/datum/feed_message/MSG = locate(params["ref"])
			if(MSG.is_admin_message)
				tgui_alert_async(ui.user, "This message was created by a [using_map.company_name] Officer. You cannot censor its author.")
				return
			if(MSG.author != "\[REDACTED\]")
				MSG.backup_author = MSG.author
				MSG.author = "\[REDACTED\]"
			else
				MSG.author = MSG.backup_author
			MSG.parent_channel().update()
			return TRUE

		if("censor_channel_story_body")
			if(!securityCaster)
				return FALSE
			var/datum/feed_message/MSG = locate(params["ref"])
			if(MSG.is_admin_message)
				tgui_alert_async(ui.user, "This channel was created by a [using_map.company_name] Officer. You cannot censor it.")
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

		if("toggle_d_notice")
			if(!securityCaster)
				return FALSE
			var/datum/feed_channel/FC = locate(params["ref"])
			if(FC.is_admin_channel)
				tgui_alert_async(ui.user, "This channel was created by a [using_map.company_name] Officer. You cannot place a D-Notice upon it.")
				return
			FC.censored = !FC.censored
			FC.update()
			return TRUE

		if("show_channel")
			var/datum/feed_channel/FC = locate(params["show_channel"])
			rel_set(src, "viewing_channel", FC)
			return TRUE

/datum/om/prompt/confirm/news_channel_create
	var/author
	var/channel
	var/locked = FALSE

/obj/machinery/newscaster/proc/channel_creation_confirmed(datum/om/prompt/confirm/news_channel_create/ask)
	var/our_user = ask.author
	var/channel_name = ask.channel
	var/c_locked = ask.locked
	GLOB.news_network.CreateFeedChannel(channel_name, our_user, c_locked)
	set_temp("Feed channel [channel_name] created successfully.", "success", FALSE)
	return TRUE

/obj/machinery/newscaster/proc/receiving_channel_chosen(datum/om/prompt/choice/ask)
	var/new_channel_name = ask.choice
	channel_name = new_channel_name
	SStgui.update_uis(src)
	if(new_channel_name)
		channel_name = new_channel_name
	return TRUE

/obj/machinery/newscaster/proc/story_written(datum/om/prompt/text/ask)
	var/text = ask.text
	msg = sanitize(text, MAX_MESSAGE_LEN, FALSE, FALSE, TRUE)

/obj/machinery/newscaster/proc/title_written(datum/om/prompt/text/ask)
	var/text = ask.text
	title = text

/obj/machinery/newscaster/proc/wanted_change_confirmed(datum/om/prompt/confirm/ask)
	var/mob/user = ask.answerer
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
		return TRUE

	var/datum/feed_message/WANTED = new /datum/feed_message
	WANTED.author = channel_name
	WANTED.body = msg
	WANTED.backup_author = scanned_user //I know, a bit wacky
	if(photo_data)
		WANTED.img = photo_data.photo().img
	rel_set(GLOB.news_network, "wanted_issue_owned", WANTED)
	GLOB.news_network.alert_readers()
	set_temp("Wanted issue for [channel_name] is now in Network Circulation.", "success", FALSE)
	return TRUE

/obj/machinery/newscaster/proc/wanted_removal_confirmed(datum/om/prompt/confirm/ask)
	if(GLOB.news_network.wanted_issue() && !GLOB.news_network.wanted_issue().is_admin_message)
		rel_clear(GLOB.news_network, "wanted_issue_owned")
		for(var/obj/machinery/newscaster/NEWSCASTER in REGISTRY_MEMBERS(REGISTRY_CASTERS))
			NEWSCASTER.update_icon()
		set_temp("Wanted issue taken down.", "success", FALSE)
	return TRUE

/// Old attackby: any item used on the newscaster just forwarded to attack_hand().
/datum/interaction/machine_item/newscaster_item_open
	id = "newscaster_item_open"
	name = "Use"
	held_type = /obj/item
	effect = /atom/proc/interaction_as_touch

/obj/machinery/newscaster/screwdriver_act(mob/user, obj/item/tool)
	return deconstruct_display(user, tool)

/datum/news_photo
	var/is_synth = 0
	var/obj/item/photo/photo

/datum/news_photo/New(obj/item/photo/p, synth)
	is_synth = synth
	rel_set(src, "photo", p)

/obj/machinery/newscaster/proc/AttachPhoto(mob/user)
	if(photo_data)
		if(!photo_data.is_synth)
			photo_data.photo().forceMove(src.loc)
			if(!issilicon(user))
				user.put_in_inactive_hand(photo_data.photo())
		qdel(photo_data)

	if(istype(user.get_active_hand(), /obj/item/photo))
		var/obj/item/photo = user.get_active_hand()
		user.drop_item()
		photo.forceMove(src)
		own_set(src, "photo_data", new /datum/news_photo(photo, 0))
	else if(istype(user,/mob/living/silicon))
		var/mob/living/silicon/tempAI = user
		var/obj/item/photo/selection = tempAI.GetPicture()
		if(!selection)
			return

		own_set(src, "photo_data", new /datum/news_photo(selection, 1))

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
		rel_add(NEWSPAPER, "news_content", FC) // the paper names the network's channels
	if(GLOB.news_network.wanted_issue())
		rel_set(NEWSPAPER, "important_message", GLOB.news_network.wanted_issue())
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
		om_after(src, 30 SECONDS, PROC_REF(clear_alert))
// playsound(src.loc, 'sound/machines/twobeep.ogg', 75, 1) // less peeps pls
	else
		for(var/mob/O in hearers(world.view-1, T))
			O.show_message(span_newscaster("<EM>[name]</EM> beeps, \"Attention! Wanted issue distributed!\""),2)
		playsound(src, 'sound/machines/warning-buzzer.ogg', 75, 1)
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


// Admin Newscaster — structured TGUI replacement for the 19-screen HTML panel.
//
// All clicks act() back to /datum/admins.Topic via _src_=holder so the
// existing ac_* href handlers stay in charge of state transitions, channel
// creation, censorship, etc. The panel exposes the relevant slice of state
// per screen.
//
// Image previews on wanted issues / message attachments are *not* rendered:
// the legacy panel relied on `user << browse_rsc(img, "tmp_photo.png")`,
// whose served file isn't reachable from the TGUI iframe. The screens that
// previously showed inline previews now show a "(photo attached)" notice
// instead. Wiring this up to TGUI assets is a follow-up.

/datum/admins/proc/dq_open_newscaster_panel()
	if(!owner)
		return
	if(!dq_newscaster_panel)
		dq_newscaster_panel = new(src)
	dq_newscaster_panel.tgui_interact(owner)

/datum/admins
	var/datum/newscaster_panel/dq_newscaster_panel

/datum/newscaster_panel
	var/datum/admins/holder

/datum/newscaster_panel/New(datum/admins/owner_holder)
	..()
	holder = owner_holder

/datum/newscaster_panel/Destroy(force, ...)
	if(holder)
		holder.dq_newscaster_panel = null
	holder = null
	return ..()

/datum/newscaster_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT)

/datum/newscaster_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AdminNewscaster", "Admin Newscaster")
		ui.open()

/datum/newscaster_panel/proc/pack_channel(datum/feed_channel/CHANNEL)
	if(!CHANNEL)
		return null
	return list(
		"ref" = "[REF(CHANNEL)]",
		"name" = CHANNEL.channel_name,
		"author" = CHANNEL.author,
		"locked" = !!CHANNEL.locked,
		"censored" = !!CHANNEL.censored,
		"is_admin_channel" = !!CHANNEL.is_admin_channel,
	)

/datum/newscaster_panel/proc/pack_message(datum/feed_message/MSG)
	if(!MSG)
		return null
	return list(
		"ref" = "[REF(MSG)]",
		"title" = MSG.title,
		"body" = MSG.body,
		"author" = MSG.author,
		"time_stamp" = MSG.time_stamp,
		"has_image" = !!MSG.img,
	)

/datum/newscaster_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!holder)
		return data
	data["screen"] = holder.admincaster_screen
	data["signature"] = holder.admincaster_signature
	data["company_name"] = using_map.company_name
	data["has_wanted"] = !!GLOB.news_network.wanted_issue
	data["channel"] = pack_channel(holder.admincaster_feed_channel)
	data["message"] = pack_message(holder.admincaster_feed_message)

	// Channel listing for the screens that need it.
	var/list/channels = list()
	for(var/datum/feed_channel/CHANNEL in GLOB.news_network.network_channels)
		channels += list(pack_channel(CHANNEL))
	data["channels"] = channels

	// Active channel's messages (screens 9, 12, 13).
	var/list/channel_messages = list()
	if(holder.admincaster_feed_channel)
		for(var/datum/feed_message/MSG in holder.admincaster_feed_channel.messages)
			channel_messages += list(pack_message(MSG))
	data["channel_messages"] = channel_messages

	// Wanted issue (screen 18).
	if(GLOB.news_network.wanted_issue)
		var/datum/feed_message/W = GLOB.news_network.wanted_issue
		data["wanted_issue"] = list(
			"author" = W.author,
			"body" = W.body,
			"backup_author" = W.backup_author,
			"has_image" = !!W.img,
		)
	else
		data["wanted_issue"] = null

	return data

/datum/newscaster_panel/proc/forward_topic(mob/user, qs)
	if(!user)
		return
	forward_holder_topic(holder, qs)

/datum/newscaster_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !holder)
		return
	switch(action)
		if("set_screen")
			var/screen = "[params["screen"]]"
			forward_topic(ui.user, "ac_setScreen=[screen]")
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
			forward_topic(ui.user, "ac_refresh=1")
			SStgui.update_uis(src)
			return TRUE
		if("close")
			SStgui.close_uis(src)
			return TRUE
		// Main menu / channel actions.
		if("view_wanted")
			forward_topic(ui.user, "ac_view_wanted=1")
			SStgui.update_uis(src)
			return TRUE
		if("create_channel")
			forward_topic(ui.user, "ac_create_channel=1")
			SStgui.update_uis(src)
			return TRUE
		if("view_channels")
			forward_topic(ui.user, "ac_view=1")
			SStgui.update_uis(src)
			return TRUE
		if("create_story")
			forward_topic(ui.user, "ac_create_feed_story=1")
			SStgui.update_uis(src)
			return TRUE
		if("menu_wanted")
			forward_topic(ui.user, "ac_menu_wanted=1")
			SStgui.update_uis(src)
			return TRUE
		if("menu_censor_story")
			forward_topic(ui.user, "ac_menu_censor_story=1")
			SStgui.update_uis(src)
			return TRUE
		if("menu_censor_channel")
			forward_topic(ui.user, "ac_menu_censor_channel=1")
			SStgui.update_uis(src)
			return TRUE
		if("set_signature")
			forward_topic(ui.user, "ac_set_signature=1")
			SStgui.update_uis(src)
			return TRUE
		// Channel selection.
		if("show_channel")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_show_channel=[ref]")
			SStgui.update_uis(src)
			return TRUE
		if("pick_censor_channel")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_pick_censor_channel=[ref]")
			SStgui.update_uis(src)
			return TRUE
		if("pick_d_notice")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_pick_d_notice=[ref]")
			SStgui.update_uis(src)
			return TRUE
		// Channel create form.
		if("set_channel_name")
			forward_topic(ui.user, "ac_set_channel_name=1")
			SStgui.update_uis(src)
			return TRUE
		if("set_channel_lock")
			forward_topic(ui.user, "ac_set_channel_lock=1")
			SStgui.update_uis(src)
			return TRUE
		if("submit_new_channel")
			forward_topic(ui.user, "ac_submit_new_channel=1")
			SStgui.update_uis(src)
			return TRUE
		// Story create form.
		if("set_channel_receiving")
			forward_topic(ui.user, "ac_set_channel_receiving=1")
			SStgui.update_uis(src)
			return TRUE
		if("set_new_message")
			forward_topic(ui.user, "ac_set_new_message=1")
			SStgui.update_uis(src)
			return TRUE
		if("submit_new_message")
			forward_topic(ui.user, "ac_submit_new_message=1")
			SStgui.update_uis(src)
			return TRUE
		// Censorship.
		if("censor_channel_author")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_censor_channel_author=[ref]")
			SStgui.update_uis(src)
			return TRUE
		if("censor_story_body")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_censor_channel_story_body=[ref]")
			SStgui.update_uis(src)
			return TRUE
		if("censor_story_author")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_censor_channel_story_author=[ref]")
			SStgui.update_uis(src)
			return TRUE
		if("toggle_d_notice")
			var/ref = "[params["ref"]]"
			forward_topic(ui.user, "ac_toggle_d_notice=[ref]")
			SStgui.update_uis(src)
			return TRUE
		// Wanted issue.
		if("set_wanted_name")
			forward_topic(ui.user, "ac_set_wanted_name=1")
			SStgui.update_uis(src)
			return TRUE
		if("set_wanted_desc")
			forward_topic(ui.user, "ac_set_wanted_desc=1")
			SStgui.update_uis(src)
			return TRUE
		if("submit_wanted")
			var/end = "[params["end_param"]]"
			forward_topic(ui.user, "ac_submit_wanted=[end]")
			SStgui.update_uis(src)
			return TRUE
		if("cancel_wanted")
			forward_topic(ui.user, "ac_cancel_wanted=1")
			SStgui.update_uis(src)
			return TRUE

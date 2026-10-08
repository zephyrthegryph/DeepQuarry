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
	if(!owner()?.mob)
		return
	if(!dq_newscaster_panel)
		rel_set(src, nameof(dq_newscaster_panel), new /datum/newscaster_panel(src))
	dq_newscaster_panel.tgui_interact(owner().mob)

/datum/admins
	var/datum/newscaster_panel/dq_newscaster_panel

/datum/newscaster_panel
	var/datum/admins/holder

/datum/newscaster_panel/New(datum/admins/owner_holder)
	..()
	rel_set(src, nameof(holder), owner_holder)

// The admin holder owns this panel (dq_newscaster_panel); holder is a plain relation back.

CAPABILITIES(/datum/newscaster_panel)
	ref_one(nameof(holder), /datum/admins)
	extend(TAG_UI, needs(req(PROC_REF(ui_gate), silent = TRUE)))
	interface("AdminNewscaster", title = "Admin Newscaster", rights = R_ADMIN|R_EVENT)
	op("set_screen", ui_act("set_screen", arg("screen", schema_text(4096))), then(PROC_REF(ui_act_set_screen)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("close", ui_act("close"), then(PROC_REF(ui_act_close)))
	op("view_wanted", ui_act("view_wanted"), then(PROC_REF(ui_act_view_wanted)))
	op("create_channel", ui_act("create_channel"), then(PROC_REF(ui_act_create_channel)))
	op("view_channels", ui_act("view_channels"), then(PROC_REF(ui_act_view_channels)))
	op("create_story", ui_act("create_story"), then(PROC_REF(ui_act_create_story)))
	op("menu_wanted", ui_act("menu_wanted"), then(PROC_REF(ui_act_menu_wanted)))
	op("menu_censor_story", ui_act("menu_censor_story"), then(PROC_REF(ui_act_menu_censor_story)))
	op("menu_censor_channel", ui_act("menu_censor_channel"), then(PROC_REF(ui_act_menu_censor_channel)))
	op("set_signature", ui_act("set_signature"), then(PROC_REF(ui_act_set_signature)))
	op("show_channel", ui_act("show_channel", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_show_channel)))
	op("pick_censor_channel", ui_act("pick_censor_channel", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_pick_censor_channel)))
	op("pick_d_notice", ui_act("pick_d_notice", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_pick_d_notice)))
	op("set_channel_name", ui_act("set_channel_name"), then(PROC_REF(ui_act_set_channel_name)))
	op("set_channel_lock", ui_act("set_channel_lock"), then(PROC_REF(ui_act_set_channel_lock)))
	op("submit_new_channel", ui_act("submit_new_channel"), then(PROC_REF(ui_act_submit_new_channel)))
	op("set_channel_receiving", ui_act("set_channel_receiving"), then(PROC_REF(ui_act_set_channel_receiving)))
	op("set_new_message", ui_act("set_new_message"), then(PROC_REF(ui_act_set_new_message)))
	op("submit_new_message", ui_act("submit_new_message"), then(PROC_REF(ui_act_submit_new_message)))
	op("censor_channel_author", ui_act("censor_channel_author", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_censor_channel_author)))
	op("censor_story_body", ui_act("censor_story_body", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_censor_story_body)))
	op("censor_story_author", ui_act("censor_story_author", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_censor_story_author)))
	op("toggle_d_notice", ui_act("toggle_d_notice", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_toggle_d_notice)))
	op("set_wanted_name", ui_act("set_wanted_name"), then(PROC_REF(ui_act_set_wanted_name)))
	op("set_wanted_desc", ui_act("set_wanted_desc"), then(PROC_REF(ui_act_set_wanted_desc)))
	op("submit_wanted", ui_act("submit_wanted", arg("end_param", schema_text(4096))), then(PROC_REF(ui_act_submit_wanted)))
	op("cancel_wanted", ui_act("cancel_wanted"), then(PROC_REF(ui_act_cancel_wanted)))

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

/datum/newscaster_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!holder)
		return data
	data["screen"] = holder.admincaster_screen
	data["signature"] = holder.admincaster_signature
	data["company_name"] = using_map.company_name
	data["has_wanted"] = !!GLOB.news_network.wanted_issue()
	data["channel"] = pack_channel(holder.admincaster_feed_channel())
	data["message"] = pack_message(holder.admincaster_feed_message)

	// Channel listing for the screens that need it.
	var/list/channels = list()
	for(var/datum/feed_channel/CHANNEL in GLOB.news_network.network_channels)
		channels += list(pack_channel(CHANNEL))
	data["channels"] = channels

	// Active channel's messages (screens 9, 12, 13).
	var/list/channel_messages = list()
	if(holder.admincaster_feed_channel())
		for(var/datum/feed_message/MSG in holder.admincaster_feed_channel().messages)
			channel_messages += list(pack_message(MSG))
	data["channel_messages"] = channel_messages

	// Wanted issue (screen 18).
	if(GLOB.news_network.wanted_issue())
		var/datum/feed_message/W = GLOB.news_network.wanted_issue()
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

/// The answer to a question a button asked still counts (its window is still open and interactive for the one who answers).
/datum/newscaster_panel/proc/request_usable(datum/request/R)
	return window_request_usable(src, R)

/// The admin this refers to (a relation view: null once that is deleted).
/datum/newscaster_panel/proc/holder() as /datum/admins
	return holder

/// A panel whose admin is gone answers nothing (silently).
/datum/newscaster_panel/proc/ui_gate(datum/act/op/A)
	return !!holder()

/datum/newscaster_panel/proc/ui_act_set_screen(datum/act/op/A, screen_arg)
	var/mob/user = A.actor
	var/screen = "[screen_arg]"
	forward_topic(user, "ac_setScreen=[screen]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_refresh(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_refresh=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_close(datum/act/op/A)
	SStgui.close_uis(src)
	return TRUE

// Main menu / channel actions.

/datum/newscaster_panel/proc/ui_act_view_wanted(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_view_wanted=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_create_channel(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_create_channel=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_view_channels(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_view=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_create_story(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_create_feed_story=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_menu_wanted(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_menu_wanted=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_menu_censor_story(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_menu_censor_story=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_menu_censor_channel(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_menu_censor_channel=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_set_signature(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_signature=1")
	return TRUE

// Channel selection.

/datum/newscaster_panel/proc/ui_act_show_channel(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_show_channel=[ref]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_pick_censor_channel(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_pick_censor_channel=[ref]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_pick_d_notice(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_pick_d_notice=[ref]")
	return TRUE
// Channel create form.

/datum/newscaster_panel/proc/ui_act_set_channel_name(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_channel_name=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_set_channel_lock(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_channel_lock=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_submit_new_channel(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_submit_new_channel=1")
	return TRUE

// Story create form.

/datum/newscaster_panel/proc/ui_act_set_channel_receiving(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_channel_receiving=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_set_new_message(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_new_message=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_submit_new_message(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_submit_new_message=1")
	return TRUE

// Censorship.

/datum/newscaster_panel/proc/ui_act_censor_channel_author(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_censor_channel_author=[ref]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_censor_story_body(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_censor_channel_story_body=[ref]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_censor_story_author(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_censor_channel_story_author=[ref]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_toggle_d_notice(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	var/ref = "[ref_arg]"
	forward_topic(user, "ac_toggle_d_notice=[ref]")
	return TRUE
// Wanted issue.

/datum/newscaster_panel/proc/ui_act_set_wanted_name(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_wanted_name=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_set_wanted_desc(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_set_wanted_desc=1")
	return TRUE

/datum/newscaster_panel/proc/ui_act_submit_wanted(datum/act/op/A, end_param)
	var/mob/user = A.actor
	var/end = "[end_param]"
	forward_topic(user, "ac_submit_wanted=[end]")
	return TRUE

/datum/newscaster_panel/proc/ui_act_cancel_wanted(datum/act/op/A)
	var/mob/user = A.actor
	forward_topic(user, "ac_cancel_wanted=1")
	return TRUE

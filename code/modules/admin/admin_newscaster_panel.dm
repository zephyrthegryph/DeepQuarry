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

DECLARE_UI_STATE(/datum/newscaster_panel, ADMIN_STATE(R_ADMIN|R_EVENT))

DECLARE_UI(/datum/newscaster_panel, "AdminNewscaster", UI_TITLE("Admin Newscaster"))

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

UI_DATA_REPLACE(/datum/newscaster_panel, "merge:ui_data_datum_newscaster_panel{screen:num,signature:unknown,company_name:text,has_wanted:bool,channel:unknown,message:unknown,channels:list,channel_messages:list,wanted_issue:list}")

/// The computed part of /datum/newscaster_panel's window data (declared on its UI_DATA row).
/datum/newscaster_panel/proc/ui_data_datum_newscaster_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/newscaster_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!holder)
		return FALSE
	return TRUE

UI_ACT(/datum/newscaster_panel, "set_screen", ui_act_set_screen, UI_ARG_TEXT("screen"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_set_screen)
	var/screen = "[params["screen"]]"
	forward_topic(ui.user, "ac_setScreen=[screen]")
	SStgui.update_uis(src)
	return TRUE

CAPABILITIES(/datum/newscaster_panel)
	op("refresh", ui_act(), then(PROC_REF(native_admincaster_ui_refresh)))
	op("close", ui_act(), then(PROC_REF(native_admincaster_ui_close)))
	op("view_wanted", ui_act(), then(PROC_REF(native_admincaster_ui_view_wanted)))
	op("create_channel", ui_act(), then(PROC_REF(native_admincaster_ui_create_channel)))
	op("view_channels", ui_act(), then(PROC_REF(native_admincaster_ui_view_channels)))
	op("create_story", ui_act(), then(PROC_REF(native_admincaster_ui_create_story)))
	op("menu_wanted", ui_act(), then(PROC_REF(native_admincaster_ui_menu_wanted)))
	op("menu_censor_story", ui_act(), then(PROC_REF(native_admincaster_ui_menu_censor_story)))
	op("menu_censor_channel", ui_act(), then(PROC_REF(native_admincaster_ui_menu_censor_channel)))
	op("set_signature", ui_act(), then(PROC_REF(native_admincaster_ui_set_signature)))
	op("set_channel_name", ui_act(), then(PROC_REF(native_admincaster_ui_set_channel_name)))
	op("set_channel_lock", ui_act(), then(PROC_REF(native_admincaster_ui_set_channel_lock)))
	op("submit_new_channel", ui_act(), then(PROC_REF(native_admincaster_ui_submit_new_channel)))
	op("set_channel_receiving", ui_act(), then(PROC_REF(native_admincaster_ui_set_channel_receiving)))
	op("set_new_message", ui_act(), then(PROC_REF(native_admincaster_ui_set_new_message)))
	op("submit_new_message", ui_act(), then(PROC_REF(native_admincaster_ui_submit_new_message)))
	op("set_wanted_name", ui_act(), then(PROC_REF(native_admincaster_ui_set_wanted_name)))
	op("set_wanted_desc", ui_act(), then(PROC_REF(native_admincaster_ui_set_wanted_desc)))
	op("cancel_wanted", ui_act(), then(PROC_REF(native_admincaster_ui_cancel_wanted)))

/datum/newscaster_panel/proc/native_admincaster_ui_refresh(datum/act/op/A)
	forward_topic(A.actor, "ac_refresh=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_close(datum/act/op/A)
	SStgui.close_uis(src)
	return OP_OK
// Main menu / channel actions.

/datum/newscaster_panel/proc/native_admincaster_ui_view_wanted(datum/act/op/A)
	forward_topic(A.actor, "ac_view_wanted=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_create_channel(datum/act/op/A)
	forward_topic(A.actor, "ac_create_channel=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_view_channels(datum/act/op/A)
	forward_topic(A.actor, "ac_view=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_create_story(datum/act/op/A)
	forward_topic(A.actor, "ac_create_feed_story=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_menu_wanted(datum/act/op/A)
	forward_topic(A.actor, "ac_menu_wanted=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_menu_censor_story(datum/act/op/A)
	forward_topic(A.actor, "ac_menu_censor_story=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_menu_censor_channel(datum/act/op/A)
	forward_topic(A.actor, "ac_menu_censor_channel=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_set_signature(datum/act/op/A)
	forward_topic(A.actor, "ac_set_signature=1")
	SStgui.update_uis(src)
	return OP_OK
// Channel selection.

UI_ACT(/datum/newscaster_panel, "show_channel", ui_act_show_channel, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_show_channel)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_show_channel=[ref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/newscaster_panel, "pick_censor_channel", ui_act_pick_censor_channel, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_pick_censor_channel)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_pick_censor_channel=[ref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/newscaster_panel, "pick_d_notice", ui_act_pick_d_notice, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_pick_d_notice)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_pick_d_notice=[ref]")
	SStgui.update_uis(src)
	return TRUE
// Channel create form.

/datum/newscaster_panel/proc/native_admincaster_ui_set_channel_name(datum/act/op/A)
	forward_topic(A.actor, "ac_set_channel_name=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_set_channel_lock(datum/act/op/A)
	forward_topic(A.actor, "ac_set_channel_lock=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_submit_new_channel(datum/act/op/A)
	forward_topic(A.actor, "ac_submit_new_channel=1")
	SStgui.update_uis(src)
	return OP_OK
// Story create form.

/datum/newscaster_panel/proc/native_admincaster_ui_set_channel_receiving(datum/act/op/A)
	forward_topic(A.actor, "ac_set_channel_receiving=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_set_new_message(datum/act/op/A)
	forward_topic(A.actor, "ac_set_new_message=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_submit_new_message(datum/act/op/A)
	forward_topic(A.actor, "ac_submit_new_message=1")
	SStgui.update_uis(src)
	return OP_OK
// Censorship.

UI_ACT(/datum/newscaster_panel, "censor_channel_author", ui_act_censor_channel_author, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_censor_channel_author)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_censor_channel_author=[ref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/newscaster_panel, "censor_story_body", ui_act_censor_story_body, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_censor_story_body)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_censor_channel_story_body=[ref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/newscaster_panel, "censor_story_author", ui_act_censor_story_author, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_censor_story_author)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_censor_channel_story_author=[ref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/newscaster_panel, "toggle_d_notice", ui_act_toggle_d_notice, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_toggle_d_notice)
	var/ref = "[params["ref"]]"
	forward_topic(ui.user, "ac_toggle_d_notice=[ref]")
	SStgui.update_uis(src)
	return TRUE
// Wanted issue.

/datum/newscaster_panel/proc/native_admincaster_ui_set_wanted_name(datum/act/op/A)
	forward_topic(A.actor, "ac_set_wanted_name=1")
	SStgui.update_uis(src)
	return OP_OK

/datum/newscaster_panel/proc/native_admincaster_ui_set_wanted_desc(datum/act/op/A)
	forward_topic(A.actor, "ac_set_wanted_desc=1")
	SStgui.update_uis(src)
	return OP_OK

UI_ACT(/datum/newscaster_panel, "submit_wanted", ui_act_submit_wanted, UI_ARG_TEXT("end_param"))
UI_ACT_PROC(/datum/newscaster_panel, ui_act_submit_wanted)
	var/end = "[params["end_param"]]"
	forward_topic(ui.user, "ac_submit_wanted=[end]")
	SStgui.update_uis(src)
	return TRUE

/datum/newscaster_panel/proc/native_admincaster_ui_cancel_wanted(datum/act/op/A)
	forward_topic(A.actor, "ac_cancel_wanted=1")
	SStgui.update_uis(src)
	return OP_OK

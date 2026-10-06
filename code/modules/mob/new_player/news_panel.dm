// Latest News (station newspaper for new players) — structured TGUI.
// Image attachments (browse_rsc) are dropped in this view; the legacy panel
// served them inline but TGUI assets aren't wired for per-news-page images.

/mob/new_player
	var/datum/news_panel/dq_news_panel_cache

CAPABILITIES(/mob/new_player)
	owns_one(nameof(dq_news_panel_cache), /datum/news_panel)
	owns_one(nameof(late_choices_dialog), /datum/tgui_module/late_choices)
	owns_one(nameof(lobby_window), /datum/tgui_window)
	owns_one(nameof(manifest_dialog), /datum/tgui_module/crew_manifest/new_player)
	owns_one(nameof(poll_browser_dialog), /datum/poll_browser_dialog)
	owns_one(nameof(privacy_poll_dialog), /datum/privacy_poll_dialog)
	interface("LobbyMenu", state = nameof(GLOB.tgui_always_state), pinned = TRUE, preinitialized = TRUE)
	without("ui_open")
	op("character_setup", ui_act("character_setup"), then(PROC_REF(ui_act_character_setup)))
	op("ready", ui_act("ready"), then(PROC_REF(ui_act_ready)))
	op("manifest", ui_act("manifest"), then(PROC_REF(ui_act_manifest)))
	op("late_join", ui_act("late_join"), then(PROC_REF(ui_act_late_join)))
	op("observe", ui_act("observe"), asks(/datum/prompt/choice/lobby_observe, fields = list("title" = "Observe Round?", "question" = "Are you sure you wish to observe? If you do, make sure to not use any knowledge gained from observing if you decide to join later."), step = "observe", when = PROC_REF(round_observable)), then(PROC_REF(ui_act_observe)))
	op("give_feedback", ui_act("give_feedback"), then(PROC_REF(ui_act_give_feedback)))
	op("open_station_news", ui_act("open_station_news"), then(PROC_REF(ui_act_open_station_news)))
	op("open_changelog", ui_act("open_changelog"), then(PROC_REF(ui_act_open_changelog)))
	op("keyboard", ui_act("keyboard"), then(PROC_REF(ui_act_keyboard)))
	op("start_immediately", ui_act("start_immediately"), then(PROC_REF(ui_act_start_immediately)))

/datum/news_panel
	var/mob/new_player/host
	var/datum/feed_channel/channel

/datum/news_panel/New(mob/new_player/host_mob, datum/feed_channel/CHANNEL)
	rel_set(src, nameof(host), host_mob)
	rel_set(src, nameof(channel), CHANNEL)

CAPABILITIES(/datum/news_panel)
	interface("LatestNews", title = "Latest News", state = nameof(GLOB.tgui_always_state))
	op("next", ui_act("next"), then(PROC_REF(ui_act_next)))
	op("prev", ui_act("prev"), then(PROC_REF(ui_act_prev)))

/datum/news_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

/// /datum/news_panel's window data.
/datum/news_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!host || !channel)
		return data
	data["channel_name"] = channel.channel_name
	data["page"] = host.current_news_page || 0
	data["total"] = length(channel.messages)
	data["has_messages"] = length(channel.messages) > 0
	if(host.current_news_page && length(channel.messages))
		var/datum/feed_message/M = channel.messages[host.current_news_page]
		data["title"] = M.title
		data["author"] = M.author
		data["body"] = M.body
	return data

/datum/news_panel/proc/ui_gate(datum/act/op/A)
	if(!host || !channel)
		return FALSE
	return TRUE

/datum/news_panel/proc/ui_act_next(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!host.current_news_page || !channel.messages || host.current_news_page == channel.messages.len)
		return TRUE
	host.current_news_page++
	play_sfx(host.loc, SFX_PAGETURN)
	SStgui.update_uis(src)
	return TRUE

/datum/news_panel/proc/ui_act_prev(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!host.current_news_page || !channel.messages || host.current_news_page <= 1)
		return TRUE
	host.current_news_page--
	play_sfx(host.loc, SFX_PAGETURN)
	SStgui.update_uis(src)
	return TRUE

/mob/new_player/proc/show_latest_news(datum/feed_channel/CHANNEL)
	if(!GLOB.news_data || !GLOB.news_data.station_newspaper())
		return
	if(!dq_news_panel_cache)
		rel_set(src, nameof(dq_news_panel_cache), new /datum/news_panel(src, CHANNEL))
	else
		rel_set(dq_news_panel_cache, nameof(dq_news_panel_cache.channel), CHANNEL)
	if(!current_news_page && length(CHANNEL.messages))
		current_news_page = 1
	dq_news_panel_cache.tgui_interact(src)
	client.seen_news = 1


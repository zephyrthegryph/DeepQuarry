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

/datum/news_panel
	var/mob/new_player/host
	var/datum/feed_channel/channel

/datum/news_panel/New(mob/new_player/host_mob, datum/feed_channel/CHANNEL)
	rel_set(src, nameof(host), host_mob)
	rel_set(src, nameof(channel), CHANNEL)

DECLARE_UI_STATE(/datum/news_panel, GLOB.tgui_always_state)

DECLARE_UI(/datum/news_panel, "LatestNews", UI_TITLE("Latest News"))

/datum/news_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

UI_DATA_REPLACE(/datum/news_panel, "merge:ui_data_datum_news_panel{channel_name:text,page:bool,total:num,has_messages:bool,title:text,author:text,body:text}")

/// The computed part of /datum/news_panel's window data (declared on its UI_DATA row).
/datum/news_panel/proc/ui_data_datum_news_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/news_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!host || !channel)
		return FALSE
	return TRUE

UI_ACT(/datum/news_panel, "next", ui_act_next)
UI_ACT_PROC(/datum/news_panel, ui_act_next)
	if(!host.current_news_page || !channel.messages || host.current_news_page == channel.messages.len)
		return TRUE
	host.current_news_page++
	play_sfx(host.loc, SFX_PAGETURN)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/news_panel, "prev", ui_act_prev)
UI_ACT_PROC(/datum/news_panel, ui_act_prev)
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


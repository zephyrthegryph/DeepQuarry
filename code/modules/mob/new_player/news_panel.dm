// Latest News (station newspaper for new players) — structured TGUI.
// Image attachments (browse_rsc) are dropped in this view; the legacy panel
// served them inline but TGUI assets aren't wired for per-news-page images.

/mob/new_player
	var/datum/news_panel/dq_news_panel_cache

/datum/news_panel
	var/mob/new_player/host
	var/datum/feed_channel/channel

/datum/news_panel/New(mob/new_player/host_mob, datum/feed_channel/CHANNEL)
	host = host_mob
	channel = CHANNEL

/datum/news_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

DECLARE_UI(/datum/news_panel, "LatestNews", UI_TITLE("Latest News"))

/datum/news_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

/datum/news_panel/tgui_data(mob/user)
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
		dq_news_panel_cache = new(src, CHANNEL)
	else
		dq_news_panel_cache.channel = CHANNEL
	if(!current_news_page && length(CHANNEL.messages))
		current_news_page = 1
	dq_news_panel_cache.tgui_interact(src)
	client.seen_news = 1

DECLARE_REF(/mob/new_player, "dq_news_panel_cache", OWNED, null)
DECLARE_REF(/datum/news_panel, "host", BACK, "dq_news_panel_cache")
DECLARE_REF(/datum/news_panel, "channel", HELD, null)

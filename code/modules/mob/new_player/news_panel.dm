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

/datum/news_panel/Destroy(force, ...)
	if(host)
		host.dq_news_panel_cache = null
	host = null
	channel = null
	return ..()

/datum/news_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/news_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LatestNews", "Latest News")
		ui.open()

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

/datum/news_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !host || !channel)
		return
	switch(action)
		if("next")
			if(!host.current_news_page || !channel.messages || host.current_news_page == channel.messages.len)
				return TRUE
			host.current_news_page++
			playsound(host.loc, "pageturn", 50, 1)
			SStgui.update_uis(src)
			return TRUE
		if("prev")
			if(!host.current_news_page || !channel.messages || host.current_news_page <= 1)
				return TRUE
			host.current_news_page--
			playsound(host.loc, "pageturn", 50, 1)
			SStgui.update_uis(src)
			return TRUE

/mob/new_player/proc/show_latest_news(datum/feed_channel/CHANNEL)
	if(!GLOB.news_data || !GLOB.news_data.station_newspaper)
		return
	if(!dq_news_panel_cache)
		dq_news_panel_cache = new(src, CHANNEL)
	else
		dq_news_panel_cache.channel = CHANNEL
	if(!current_news_page && length(CHANNEL.messages))
		current_news_page = 1
	dq_news_panel_cache.tgui_interact(src)
	client.seen_news = 1

GLOBAL_DATUM_INIT(news_data, /datum/lore/news, new)

/datum/feed_network/New()
	CreateFeedChannel("Station Announcements", "NanoTrasen", 1, 1, "New Station Announcement Available")
	// CreateFeedChannel("Vir News Network", "Oculum Broadcast", 1, 1, "Updates from the Vir News Network!") // Removal

/datum/lore/news
	var/tmp/station_newspaper_handle
	var/datum/lore/codex/category/main_news/news_codex = new()
	var/newsindex

/datum/lore/news/New()
	..()
	om_after(src, 5 SECONDS, PROC_REF(find_station_newspaper)) //Give it a second or it gets fucky.
	om_after(src, 30 SECONDS, PROC_REF(fill_codex_news)) // Yes, again.
	if (!news_codex.newsindex)
		return
	else
		newsindex = news_codex.newsindex

/datum/lore/news/proc/fill_codex_news()
	if(!GLOB.news_network)
		log_runtime("Load: Could not find newscaster network.")
		return

	if(!station_newspaper())
		log_runtime("Load: Could not find news channel Vir News Network to populate news articles.")
		return

	//Feed the Lore Codex into the News Machine
	for(var/datum/lore/codex/child in news_codex.children)
		GLOB.news_network.SubmitArticle("[child.data]", "Oculum", "Vir News Network", null, 1, "", "[child.name]")

	return 1

/datum/lore/news/proc/find_station_newspaper()
	for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
		if(F.channel_name == "Vir News Network")
			station_newspaper_handle = om_handle(F)
			break

REF_OWNED(/datum/lore/news, "news_codex")

/// LC-refs: the station_newspaper this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/lore/news/proc/station_newspaper() as /datum/feed_channel
	return om_resolve(station_newspaper_handle)

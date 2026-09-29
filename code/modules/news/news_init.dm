GLOBAL_DATUM_INIT(news_data, /datum/lore/news, new)

/datum/feed_network/New()
	CreateFeedChannel("Station Announcements", "NanoTrasen", 1, 1, "New Station Announcement Available")
	// CreateFeedChannel("Vir News Network", "Oculum Broadcast", 1, 1, "Updates from the Vir News Network!") // Removal

/datum/lore/news
	var/tmp/datum/feed_channel/station_newspaper
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
	for(var/datum/lore/codex/child in news_codex.child_pages)
		GLOB.news_network.SubmitArticle("[child.data]", "Oculum", "Vir News Network", null, 1, "", "[child.name]")

	return 1

/datum/lore/news/proc/find_station_newspaper()
	for(var/datum/feed_channel/F in GLOB.news_network.network_channels)
		if(F.channel_name == "Vir News Network")
			rel_set(src, "station_newspaper", F)
			break


/// The station_newspaper this refers to (a relation view: null once that is deleted).
/datum/lore/news/proc/station_newspaper() as /datum/feed_channel
	return station_newspaper

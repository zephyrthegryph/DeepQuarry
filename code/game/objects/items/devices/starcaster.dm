/datum/category_item/catalogue/information/starfire_news
	desc = "A small news reporting agency based near Sif's New Reykjavik, the Starfire Report is somewhat infamous \
	for scrutinizing the actions of Trans-Stellar Corporations in the Vir system yet coming out on top in the legal \
	battles with inevitably follow. Aside from reporting, the agency is also known for inventing and manufacturing the \
	starcaster, a cheap device capable of accessing news articles from almost anywhere in the galaxy without need for \
	a stable exonet connection."
	value = CATALOGUER_REWARD_TRIVIAL

/obj/item/starcaster_news
	name = "\improper Starcaster"
	desc = "A device from the Starfire Report for reading the news and nothing else."
	icon = 'icons/obj/library.dmi'
	icon_state = "newscodex-open"
//	catalogue_data = list(/datum/category_item/catalogue/information/starfire_news) Commented out until I can figure out why this won't scan.

	var/datum/computer_file/data/news_article/loaded_article_owned //You must specify the variable this far to avoid compilation errors.
	var/show_archived = null

CAPABILITIES(/obj/item/starcaster_news)
	owns_one(nameof(loaded_article_owned), /datum/computer_file/data/news_article)
	op("read_news", in_hand(), then(PROC_REF(reader_selected)), opens_ui())
	interface("StarcasterCh")
	op("PRG_openarticle", ui_act("PRG_openarticle", arg("uid", num())), then(PROC_REF(ui_act_prg_openarticle)))
	op("PRG_reset", ui_act("PRG_reset"), then(PROC_REF(ui_act_prg_reset)))
	op("PRG_toggle_archived", ui_act("PRG_toggle_archived"), then(PROC_REF(ui_act_prg_toggle_archived)))



/obj/item/starcaster_news/proc/reader_selected(datum/act/op/A)
	A.actor.set_machine(src)
	return OP_OK

/// /obj/item/starcaster_news's window data.
/obj/item/starcaster_news/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/list/all_articles = list()
	data["showing_archived"] = show_archived
	data["article"] = null
	if(loaded_article()) 	// Viewing an article.
		data["article"] = list(
			"title" = loaded_article().filename,
			"cover" = loaded_article().cover,
			"content" = loaded_article().stored_data,
		)
	else										// Viewing list of articles
		for(var/datum/computer_file/data/news_article/F in GLOB.ntnet_global.available_news)
			if(!show_archived && F.archived)
				continue
			all_articles.Add(list(list(
				"name" = F.filename,
				"uid" = F.uid,
				"archived" = F.archived
			)))
	data["all_articles"] = all_articles

	return data

/obj/item/starcaster_news/proc/ui_act_prg_openarticle(datum/act/op/A, uid)
	. = TRUE
	if(loaded_article())
		return TRUE

	for(var/datum/computer_file/data/news_article/N in GLOB.ntnet_global.available_news)
		if(N.uid == uid)
			rel_set(src, nameof(/obj/item/starcaster_news::loaded_article_owned), N.clone())
			break

/obj/item/starcaster_news/proc/ui_act_prg_reset(datum/act/op/A)
	. = TRUE
	own_clear(src, nameof(/obj/item/starcaster_news::loaded_article_owned), OWN_DELETE) // our private clone

/obj/item/starcaster_news/proc/ui_act_prg_toggle_archived(datum/act/op/A)
	. = TRUE
	show_archived = !show_archived

/// Created for and owned by this holder; deleted with it.
/obj/item/starcaster_news/proc/loaded_article() as /datum/computer_file/data/news_article
	return loaded_article_owned

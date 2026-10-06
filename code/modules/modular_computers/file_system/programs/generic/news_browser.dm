/datum/computer_file/program/newsbrowser
	filename = "newsbrowser"
	filedesc = "NTNet/ExoNet News Browser"
	extended_desc = "This program may be used to view and download news articles from the network."
	program_icon_state = "generic"
	program_key_state = "generic_key"
	program_menu_icon = "contact"
	size = 4
	requires_ntnet = TRUE
	available_on_ntnet = TRUE
	usage_flags = PROGRAM_ALL

	var/datum/computer_file/data/news_article/loaded_article
	var/download_progress = 0
	var/download_netspeed = 0
	var/downloading = FALSE
	var/message = ""
	var/show_archived = FALSE

CAPABILITIES(/datum/computer_file/program/newsbrowser)
	op("PRG_reset", ui_act("PRG_reset"), then(PROC_REF(ui_act_prg_reset)))
	op("PRG_clearmessage", ui_act("PRG_clearmessage"), then(PROC_REF(ui_act_prg_clearmessage)))
	op("PRG_toggle_archived", ui_act("PRG_toggle_archived"), then(PROC_REF(ui_act_prg_toggle_archived)))
	owns_one(nameof(loaded_article), /datum/computer_file/data/news_article)
	interface("NtosNewsBrowser")
	op("PRG_openarticle", ui_act("PRG_openarticle", arg("uid", num())), then(PROC_REF(ui_act_prg_openarticle)))
	op("PRG_savearticle", ui_act("PRG_savearticle"), asks(/datum/prompt/text, fields = list("title" = "Save article", "question" = "Enter file name or leave blank to cancel:", "default" = computed(PROC_REF(article_default_name)))), then(PROC_REF(ui_act_prg_savearticle)))

/datum/computer_file/program/newsbrowser/process_tick()
	if(!downloading)
		return
	download_netspeed = 0
	// Speed defines are found in misc.dm
	switch(ntnet_status)
		if(1)
			download_netspeed = NTNETSPEED_LOWSIGNAL
		if(2)
			download_netspeed = NTNETSPEED_HIGHSIGNAL
		if(3)
			download_netspeed = NTNETSPEED_ETHERNET
	download_progress += download_netspeed
	if(download_progress >= loaded_article.size)
		downloading = 0
		requires_ntnet = 0 // Turn off NTNet requirement as we already loaded the file into local memory.
	SStgui.update_uis(src)

/datum/computer_file/program/newsbrowser/ui_data(datum/act/eval/A)
	var/list/data = get_header_data()
	data["message"] = message
	data["showing_archived"] = show_archived

	var/list/all_articles = list()
	data["download"] = null
	data["article"] = null
	if(loaded_article && !downloading) 	// Viewing an article.
		data["article"] = list(
			"title" = loaded_article.filename,
			"cover" = loaded_article.cover,
			"content" = loaded_article.stored_data,
		)
	else if(downloading)					// Downloading an article.
		data["download"] = list(
			"download_progress" = download_progress,
			"download_maxprogress" = loaded_article.size,
			"download_rate" = download_netspeed
		)
	else										// Viewing list of articles
		for(var/datum/computer_file/data/news_article/F in GLOB.ntnet_global.available_news)
			if(!show_archived && F.archived)
				continue
			all_articles.Add(list(list(
				"name" = F.filename,
				"size" = F.size,
				"uid" = F.uid,
				"archived" = F.archived
			)))
	data["all_articles"] = all_articles

	return data

/datum/computer_file/program/newsbrowser/kill_program()
	..()
	requires_ntnet = TRUE
	rel_clear(src, nameof(loaded_article))
	download_progress = 0
	downloading = FALSE
	show_archived = FALSE

/datum/computer_file/program/newsbrowser/proc/ui_act_prg_openarticle(datum/act/op/A, uid)
	. = TRUE
	if(downloading || loaded_article)
		return TRUE

	for(var/datum/computer_file/data/news_article/N in GLOB.ntnet_global.available_news)
		if(N.uid == uid)
			rel_set(src, nameof(/datum/computer_file/program/newsbrowser::loaded_article), N.clone())
			downloading = 1
			break

/datum/computer_file/program/newsbrowser/proc/ui_act_prg_reset(datum/act/op/A)

	downloading = 0
	download_progress = 0
	requires_ntnet = 1
	rel_clear(src, nameof(/datum/computer_file/program/newsbrowser::loaded_article))
	return OP_OK

/datum/computer_file/program/newsbrowser/proc/ui_act_prg_clearmessage(datum/act/op/A)

	message = ""
	return OP_OK

/datum/computer_file/program/newsbrowser/proc/article_default_name(datum/act/op/A)
	return loaded_article?.filename

/datum/computer_file/program/newsbrowser/proc/ui_act_prg_savearticle(datum/act/op/A)
	. = TRUE
	if(downloading || !loaded_article)
		return

	var/datum/prompt/P = A.answer
	var/savename = P?.value
	if(!savename)
		return TRUE
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return TRUE
	var/datum/computer_file/data/news_article/N = loaded_article.clone()
	N.filename = savename
	HDD.store_file(N)

/datum/computer_file/program/newsbrowser/proc/ui_act_prg_toggle_archived(datum/act/op/A)

	show_archived = !show_archived
	return OP_OK

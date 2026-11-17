// The StationWiki window: one shared window object; each reader's current article is a plain id kept per ckey. The index (every article's
// id, title, path and summary) is static data, sent once per open; ui_data sends only the article the reader is on. Back and forward are
// the page's own history: it asks for an article by id ("open"), and an open from outside (a reference book, a link elsewhere) lands in it.

GLOBAL_DATUM(station_wiki, /datum/station_wiki)

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/station_wiki)

/datum/station_wiki
	/// ckey -> the article id that reader is on.
	var/list/article_of

CAPABILITIES(/datum/station_wiki)
	interface("StationWiki", title = "Station Wiki", state = nameof(GLOB.tgui_always_state))
	ui_shape(index = any, article = any, requested = any, home = any)
	op("open", ui_act("open", arg("id", schema_text(256))), then(PROC_REF(ui_act_open)))

/// Opens the wiki for `user` on article `id` (the front page when null).
/proc/wiki_open(mob/user, id)
	if(!user?.client)
		return
	if(!GLOB.station_wiki)
		rel_set(GLOB, nameof(GLOB.station_wiki), new /datum/station_wiki)
	GLOB.station_wiki.show(user, id || WIKI_ID_HOME)

/datum/station_wiki/proc/show(mob/user, id)
	set_reader_article(user, id)
	tgui_interact(user)
	SStgui.update_user_uis(user, src)

/datum/station_wiki/proc/set_reader_article(mob/user, id)
	var/key = user?.ckey
	if(!key)
		return
	set_article_of_at(key, "[id]")
	if(GLOB.wiki_trace)
		log_world("WIKI: [key] reads [id]")

/datum/station_wiki/proc/reader_article(mob/user)
	return LAZYACCESS(article_of, user?.ckey) || WIKI_ID_HOME

/datum/station_wiki/ui_static_data(datum/act/eval/A)
	return list("index" = GLOBAL_TABLE_GET(wiki_index_rows_table), "home" = WIKI_ID_HOME)

/datum/station_wiki/ui_data(datum/act/eval/A)
	var/id = reader_article(A.actor)
	var/list/article = wiki_article(id)
	if(!article)
		return list("requested" = id, "article" = null)
	return list("requested" = id, "article" = list(
		"id" = article["id"],
		"title" = article["title"],
		"path" = article["path"],
		"summary" = article["summary"],
		"blocks" = article["blocks"],
	))

/datum/station_wiki/proc/ui_act_open(datum/act/op/A, id)
	set_reader_article(A.actor, id)
	SStgui.update_user_uis(A.actor, src)
	return OP_OK

/// The Status panel's quick row (tgui-panel/statpanel/menu.ts) runs this.
/client/verb/open_station_wiki()
	set name = "Station Wiki"
	set hidden = TRUE // the Status panel's Station Wiki entry
	set desc = "Opens the station wiki: every department's reference, guides and lore."
	wiki_open(mob, WIKI_ID_HOME)

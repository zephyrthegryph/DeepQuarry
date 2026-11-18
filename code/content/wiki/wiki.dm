// The station wiki: one in-game reference for every department, read in the StationWiki window (wiki_window.dm) from the Status panel's
// quick row (the "Station Wiki" command) or from a reference book.
//
// An article is a plain list, never a datum: id, title, path (its place in the index, "Medical/Conditions/Cardiac"), summary, and its body
// as a list of blocks. A catalogue or reagent article may also carry a sprite (wiki_set_sprite) or a colour swatch (wiki_set_swatch); the
// window shows it, with the body's first labelled facts, in an infobox card. Ids are stable strings ("med/cond/concussion", "chem/bicaridine"); any article links to any other by id.
//
// Where articles come from (all data, nothing per-department in the engine):
//   * Sources: GLOB.wiki_sources lists builder procs. Each is called once with the index and adds its articles with wiki_add(). A
//     generated source (medical, chemistry) reads the game's own data; its bodies are built on first read through `body_proc`.
//   * Authored pages: every /datum/wiki_page subtype with an `id` is an article; its `body` is wiki markup (below). A department adds
//     content by adding a subtype in its own folder, without touching the engine.
//
// Blocks (the window renders each kind; text fields take inline links):
//   p     list("k" = "p", "t" = text)                                   a paragraph
//   h     list("k" = "h", "t" = text)                                   a sub-heading
//   ul/ol list("k" = "ul"|"ol", "items" = list(text, ...))              a bullet or numbered list
//   note  list("k" = "note", "t" = text, "tone" = "good"|"bad"|...)     a callout box: good = tip, average = warning, bad = danger,
//                                                                       anything else = info
//   kv    list("k" = "kv", "rows" = list(list(label, text), ...))       labelled facts
//   links list("k" = "links", "t" = label, "items" = list(wiki_link(), ...))  a labelled row of links
//   table list("k" = "table", "head" = list(text, ...), "rows" = list(list(text, ...), ...))
//   tabs  list("k" = "tabs", "tabs" = list(list("name" = text, "blocks" = list(block, ...)), ...))
//
// Inline links in any text: [[id]] (shows the target's title) or [[id|label]]. wiki_link_ids() finds them; the link test resolves every one.
// In a DM string the brackets are escaped: "\[\[med/index|Medical]]". Markup (authored bodies, wiki_markup_blocks()): a blank line ends a paragraph; "## " a heading; "- " a bullet; "1. " a numbered step;
// "> " a note.
//
// Everything is built once per world: the index (wiki_index()) on first open, each body on first read (wiki_article()). The window sends
// the index once per open and the one article a reader is on, never the whole wiki. GLOB.wiki_trace logs every build and every read.

/// An authored article. Subtype it with an id, a title, a path and a body in wiki markup.
/datum/wiki_page
	/// The article id (unique). A type without one is a grouping type and is not an article.
	var/id
	var/title
	/// Its place in the index: "Engineering/Guides".
	var/path
	/// One line shown under the title and searched.
	var/summary
	/// The body, in wiki markup.
	var/body

/// Logs every article read and body build to the world log.
GLOBAL_VAR_INIT(wiki_trace, FALSE)

/// The builders of the wiki's articles, in index order. A department adds its source here.
GLOBAL_LIST_INIT(wiki_sources, list(
	GLOBAL_PROC_REF(wiki_source_authored),
	GLOBAL_PROC_REF(wiki_source_medical),
	GLOBAL_PROC_REF(wiki_source_chemistry),
	GLOBAL_PROC_REF(wiki_source_catalogue),
	GLOBAL_PROC_REF(wiki_source_station),
))

/// id -> article. Built once.
GLOBAL_TABLE(wiki_index_table, GLOBAL_PROC_REF(build_wiki_index))

/proc/wiki_index()
	return GLOBAL_TABLE_GET(wiki_index_table)

/proc/build_wiki_index()
	var/list/index = list()
	var/started = REALTIMEOFDAY
	for(var/source in GLOB.wiki_sources)
		var/before = length(index)
		call(source)(index)
		log_world("WIKI: source [source] added [length(index) - before] article(s)")
	log_world("WIKI: index built, [length(index)] article(s) in [REALTIMEOFDAY - started] ds")
	return index

/// The ids added twice, in the order they were refused (the duplicate-id test reads it).
GLOBAL_LIST_EMPTY(wiki_duplicate_ids)

/// Adds one article. `blocks` is its body, or null with `body_proc` (called with `body_key`) to build it on first read.
/proc/wiki_add(list/index, id, title, path, summary, list/blocks, body_proc, body_key)
	if(index[id])
		var/list/first = index[id]
		log_world("WIKI: duplicate article id [id] ([title]); the first one ([first["title"]]) is kept")
		GLOB.wiki_duplicate_ids += id
		return null
	var/list/article = list("id" = id, "title" = title, "path" = path, "summary" = summary, "blocks" = blocks, "body_proc" = body_proc, "body_key" = body_key)
	index[id] = article
	return article

/// The article with this id, its body built (once, then cached), or null. A new list: the index itself is never written.
/proc/wiki_article(id)
	var/list/article = wiki_index()[id]
	if(!islist(article))
		return null
	var/list/blocks = article["blocks"]
	if(isnull(blocks))
		var/started = REALTIMEOFDAY
		blocks = CACHED(wiki_bodies, id)
		if(GLOB.wiki_trace)
			log_world("WIKI: read [id] ([length(blocks)] block(s), [REALTIMEOFDAY - started] ds)")
	return list("id" = id, "title" = article["title"], "path" = article["path"], "summary" = article["summary"], "blocks" = blocks || list(),
		"icon" = article["icon"], "icon_state" = article["icon_state"], "swatch" = article["swatch"])

/// Gives an article a sprite (its infobox shows it): the type's own icon and state, read once when the index is built.
/proc/wiki_set_sprite(list/article, path)
	if(!article || !ispath(path, /atom))
		return
	var/atom/A = path
	if(!initial(A.icon))
		return
	article["icon"] = "[initial(A.icon)]"
	article["icon_state"] = initial(A.icon_state) || ""

/// Gives an article a colour swatch (a reagent's colour), shown in its infobox.
/proc/wiki_set_swatch(list/article, color)
	if(article && istext(color) && length(color))
		article["swatch"] = color

DECLARE_SHARED_CACHE(wiki_bodies, GLOBAL_PROC_REF(build_wiki_body), SC_NEVER)

/proc/build_wiki_body(id)
	var/list/article = wiki_index()[id]
	if(!article?["body_proc"])
		return list()
	var/list/blocks = call(article["body_proc"])(article["body_key"])
	return islist(blocks) ? blocks : list()

/// The window's index: list(id, title, path, summary) per article. Built once.
GLOBAL_TABLE(wiki_index_rows_table, GLOBAL_PROC_REF(build_wiki_index_rows))

/proc/build_wiki_index_rows()
	var/list/rows = list()
	var/list/index = wiki_index()
	for(var/id in index)
		var/list/article = index[id]
		rows += list(list(id, article["title"], article["path"], article["summary"] || ""))
	return rows

/// The title of an article, or null when there is none.
/proc/wiki_title(id)
	var/list/article = wiki_index()[id]
	return islist(article) ? article["title"] : null

// ---- block helpers ----

/proc/wiki_p(text)
	return list("k" = "p", "t" = text)

/proc/wiki_h(text)
	return list("k" = "h", "t" = text)

/proc/wiki_ul(list/items)
	return list("k" = "ul", "items" = items)

/proc/wiki_ol(list/items)
	return list("k" = "ol", "items" = items)

/proc/wiki_note(text, tone = "label")
	return list("k" = "note", "t" = text, "tone" = tone)

/proc/wiki_kv(list/rows)
	return list("k" = "kv", "rows" = rows)

/proc/wiki_links(label, list/items)
	return list("k" = "links", "t" = label, "items" = items)

/proc/wiki_table(list/head, list/rows)
	return list("k" = "table", "head" = head, "rows" = rows)

/proc/wiki_tab(name, list/blocks)
	return list("name" = name, "blocks" = blocks)

/proc/wiki_tabs(list/tabs)
	return list("k" = "tabs", "tabs" = tabs)

/// One link of a links block: the target id, its label, a short grey note and a colour (good, bad, average, grey); `sprite` (a type path)
/// shows that type's icon beside the label.
/proc/wiki_link(id, name, note, tone, sprite)
	var/list/link = list("id" = id, "name" = name, "note" = note, "tone" = tone)
	if(ispath(sprite, /atom))
		var/atom/A = sprite
		if(initial(A.icon))
			link["icon"] = "[initial(A.icon)]"
			link["icon_state"] = initial(A.icon_state) || ""
	return link

/// An inline link for text: [[id|label]].
/proc/wiki_ref(id, label)
	return label ? "\[\[[id]|[label]\]\]" : "\[\[[id]\]\]"

/// Inline links (id -> label), as an English list.
/proc/wiki_ref_list(list/labels_by_id)
	var/list/parts = list()
	for(var/id in labels_by_id)
		parts += wiki_ref(id, labels_by_id[id])
	return english_list(parts)

// ---- markup ----

/// Wiki markup to blocks (see the header).
/proc/wiki_markup_blocks(text)
	var/list/blocks = list()
	var/list/paragraph = list()
	var/list/items
	var/items_kind
	var/static/regex/numbered = regex(@"^\d+[.)]\s+")
	for(var/raw_line in splittext(text, "\n"))
		var/line = trimtext(raw_line)
		var/kind = null
		if(copytext(line, 1, 4) == "## ")
			kind = "h"
		else if(copytext(line, 1, 3) == "- ")
			kind = "ul"
		else if(copytext(line, 1, 3) == "> ")
			kind = "note"
		else if(numbered.Find(line))
			kind = "ol"
		if((!line || kind) && length(paragraph))
			blocks += list(wiki_p(jointext(paragraph, " ")))
			paragraph = list()
		if(items && kind != items_kind)
			blocks += list(list("k" = items_kind, "items" = items))
			items = null
		if(!line)
			continue
		switch(kind)
			if("h")
				blocks += list(wiki_h(copytext(line, 4)))
			if("note")
				blocks += list(wiki_note(copytext(line, 3)))
			if("ul")
				LAZYADD(items, copytext(line, 3))
				items_kind = "ul"
			if("ol")
				LAZYADD(items, replacetext(line, numbered, ""))
				items_kind = "ol"
			else
				paragraph += line
	if(length(paragraph))
		blocks += list(wiki_p(jointext(paragraph, " ")))
	if(items)
		blocks += list(list("k" = items_kind, "items" = items))
	return blocks

/// Every article id an inline link in `text` points to.
/proc/wiki_text_link_ids(text)
	. = list()
	if(!istext(text))
		return
	var/regex/link = regex(@"\[\[([^\]|]+)(\|[^\]]*)?\]\]", "g")
	while(link.Find(text))
		. += link.group[1]

/// Every article id a body links to: its links blocks and every inline link in its text, tabs included.
/proc/wiki_link_ids(list/blocks)
	. = list()
	for(var/list/block in blocks)
		. += wiki_text_link_ids(block["t"])
		for(var/item in block["items"])
			if(islist(item))
				var/list/link_item = item
				. += link_item["id"]
				. += wiki_text_link_ids(link_item["note"])
			else
				. += wiki_text_link_ids(item)
		for(var/list/row in block["rows"])
			for(var/cell in row)
				. += wiki_text_link_ids(cell)
		for(var/list/tab in block["tabs"])
			. += wiki_link_ids(tab["blocks"])

/// A body has something to read: a block with text, items, rows or tabs.
/proc/wiki_body_has_content(list/blocks)
	for(var/list/block in blocks)
		if(block["t"] || length(block["items"]) || length(block["rows"]) || length(block["tabs"]))
			return TRUE
	return FALSE

// ---- authored pages ----

/proc/wiki_source_authored(list/index)
	for(var/T in subtypesof(/datum/wiki_page))
		var/datum/wiki_page/page = T
		if(!initial(page.id))
			continue
		wiki_add(index, initial(page.id), initial(page.title), initial(page.path), initial(page.summary), null, GLOBAL_PROC_REF(wiki_authored_body), T)

/proc/wiki_authored_body(page_type)
	var/datum/wiki_page/page = page_type
	return wiki_markup_blocks(initial(page.body))

// Holds the various pages and implementations for codex books, so they can be used in more than just books.

/datum/codex_tree
	var/tmp/atom/movable/holder
	var/root_type = null
	var/datum/lore/codex/home = null // Top-most page.
	var/list/indexed_pages // Assoc list with search terms pointing to a ref of the page.  It's created on New().
	/// "[user]" -> /datum/codex_reader (owned): each reader's current page and history.
	var/list/readers

/datum/codex_tree/New(new_holder, new_root_type)
	rel_set(src, "holder", new_holder)
	root_type = new_root_type
	generate_pages()
	..()

/// One reader's cursor into the tree: their current page and the pages they visited, as
/// relation views (the pages belong to the tree's home).
/datum/codex_reader
	var/datum/lore/codex/page
	/// Visited pages, oldest first (a relation list; a revisited page moves to the end).
	var/list/history

/datum/codex_reader/proc/visit(datum/lore/codex/new_page, record_history)
	rel_set(src, "page", new_page)
	if(record_history && new_page)
		rel_remove(src, "history", new_page)
		rel_add(src, "history", new_page)

/// The reader state for `user`, made on first use.
/datum/codex_tree/proc/reader_of(mob/user) as /datum/codex_reader
	var/key = "[user]"
	var/datum/codex_reader/R = LAZYACCESS(readers, key)
	if(!R)
		R = own_put(src, "readers", key, new /datum/codex_reader)
	return R

/// `user`'s current page, or null.
/datum/codex_tree/proc/current_page_of(mob/user) as /datum/lore/codex
	var/datum/codex_reader/R = LAZYACCESS(readers, "[user]")
	return R?.page

/datum/codex_tree/proc/generate_pages()
	own_set(src, "home", new root_type(src)) // This will also generate the others.
	indexed_pages = home.index_page() // changed from current_page to home.

// Changes current_page to its parent, assuming one exists.
/datum/codex_tree/proc/go_to_parent(mob/user)
	var/datum/lore/codex/D = current_page_of(user)
	if(istype(D) && D.parent())
		reader_of(user).visit(D.parent(), FALSE)

// Changes current_page to a specific page or category.
/datum/codex_tree/proc/go_to_page(datum/lore/codex/new_page, dont_record_history = FALSE, mob/user)
	var/datum/lore/codex/D = current_page_of(user)
	if(new_page && istype(D)) // Make sure we're not going to a null page for whatever reason.
		reader_of(user).visit(new_page, !dont_record_history)

/datum/codex_tree/proc/quick_link(search_word, mob/user)
	for(var/word in indexed_pages)
		if(lowertext(search_word) == lowertext(word)) // Exact matches unfortunately limit our ability to perform SEOs.
			go_to_page(LAZYACCESS(indexed_pages, word), FALSE, user)
			return

/datum/codex_tree/proc/get_page_from_type(desired_type)
	for(var/word in indexed_pages)
		var/datum/lore/codex/C = LAZYACCESS(indexed_pages, word)
		if(C.type == desired_type)
			return C
	return null

// Returns to the last visited page, based on the history list.
/datum/codex_tree/proc/go_back(mob/user)
	var/datum/codex_reader/R = LAZYACCESS(readers, "[user]")
	var/datum/lore/codex/D = R?.page
	if(!LAZYLEN(R?.history) || !istype(D))
		return
	var/list/H = R.history
	if(length(H) > 1)
		if(H[length(H)] == D)
			rel_remove(R, "history", D) // This gets rid of the current page in the history.
			if(length(R.history) == 1)
				go_to_page(R.history[1], TRUE, user)
				return
		var/datum/lore/codex/previous = R.history[length(R.history)] // the previous page that we want to go to
		rel_remove(R, "history", previous)
		go_to_page(previous, TRUE, user)
	else
		go_to_page(H[length(H)], TRUE, user)

/datum/codex_tree/proc/get_tree_position(mob/user)
	var/datum/lore/codex/checked = current_page_of(user)
	if(istype(checked))
		var/output = ""
		output = span_bold("[checked.name]")
		while(checked.parent())
			output = "<a href='byond://?src=\ref[src];target=\ref[checked.parent()]'>[checked.parent().name]</a> \> [output]"
			checked = checked.parent()
		return output

/datum/codex_tree/proc/make_search_bar()
	var/html = {"
	<form id="submitForm" action="?">
	<input type = 'hidden' name = 'src' value = '\ref[src]'>
	<input type = 'hidden' name = 'action' value='search'>
	<label for = 'search_query'>Page Search: </label>
	<input type = 'text' name = 'search_query' id = 'search_query'>
	<input type = 'submit' value = 'Go'>
	</form>
	"}
	return html

/datum/codex_tree/proc/display(mob/user)
	if(!home)
		generate_pages()
	if(!user)
		return
	var/datum/lore/codex/D = current_page_of(user)
	if(!istype(D)) // Initialize the reader's page and history
		reader_of(user).visit(home, TRUE)
		D = current_page_of(user)
		if(!istype(D))
			log_runtime("Codex_tree failed to failed to load for [user].")
			return

	user << browse_rsc('html/browser/codex.css', "codex.css")

	var/dat
	dat =  "<head>"
	dat += "<title>[holder().name] ([D.name])</title>"
	dat += "<link rel='stylesheet' href='codex.css' />"
	dat += "</head>"

	dat += "<body>"
	dat += "[get_tree_position(user)]<br>"
	dat += "[make_search_bar()]<br>"
	dat += "<center>"
	dat += "<h2>[D.name]</h2>"
	dat += "<br>"
	if(D.data)
		dat += "[D.data]<br>"
	dat += "<br>"
	if(istype(D, /datum/lore/codex/category))
		dat += "<div class='button-group'>"
		var/datum/lore/codex/category/C = D
		for(var/datum/lore/codex/child in C.child_pages)
			dat += "<a href='byond://?src=\ref[src];target=\ref[child]' class='button'>[child.name]</a>"
		dat += "</div>"
	dat += "<hr>"
	var/datum/codex_reader/R = LAZYACCESS(readers, "[user]")
	if(LAZYLEN(R?.history))
		dat += "<br><a href='byond://?src=\ref[src];go_back=1'>\[Go Back\]</a>"
	if(D.parent())
		dat += "<br><a href='byond://?src=\ref[src];go_to_parent=1'>\[Go Up\]</a>"
	if(D != home)
		dat += "<br><a href='byond://?src=\ref[src];go_to_home=1'>\[Go To Home\]</a>"
	dat += "</center></body>"
	// structured TGUI AdminReport; byond:// links forwarded to host.
	dq_admin_report_html(user, "The Empress Protects", dat, src)

/datum/codex_tree/Topic(href, href_list)
	. = ..()
	if(.)
		return


	if(href_list["target"]) // Direct link, using a ref
		var/datum/lore/codex/new_page = locate(href_list["target"])
		go_to_page(new_page, FALSE, usr)
	else if(href_list["search_query"])
		quick_link(href_list["search_query"], usr)
	else if(href_list["go_to_parent"])
		go_to_parent(usr)
	else if(href_list["go_back"])
		go_back(usr)
	else if(href_list["go_to_home"])
		go_to_page(home, FALSE, usr)
	else if(href_list["quick_link"]) // Indirect link, using a (hopefully) indexed word.
		quick_link(href_list["quick_link"], usr)
	else if(href_list["close"])
		// close TGUI codex viewer
		SStgui.close_uis(src)
		return
	display(usr)


/// The holder this refers to (a relation view: null once that is deleted).
/datum/codex_tree/proc/holder() as /atom/movable
	return holder

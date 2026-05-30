// Holds the various pages and implementations for codex books, so they can be used in more than just books.

/datum/codex_tree
	var/atom/movable/holder = null
	var/root_type = null
	var/datum/lore/codex/home = null // Top-most page.
	var/list/current_page = list() // Current page or category to display to the user. // converted to list to track multiple players.
	var/list/indexed_pages = list() // Assoc list with search terms pointing to a ref of the page.  It's created on New().
	var/list/history = list() // List of pages we previously visited. // now a 2D list

/datum/codex_tree/New(new_holder, new_root_type)
	holder = new_holder
	root_type = new_root_type
	generate_pages()
	..()

/datum/codex_tree/proc/generate_pages()
	home = new root_type(src) // This will also generate the others.
	//current_page = home
	indexed_pages = home.index_page() // changed from current_page to home.

// Changes current_page to its parent, assuming one exists.
/datum/codex_tree/proc/go_to_parent(mob/user)
	var/datum/lore/codex/D = current_page["[user]"]
	if(istype(D) && D.parent)
		current_page["[user]"] = D.parent

// Changes current_page to a specific page or category.
/datum/codex_tree/proc/go_to_page(datum/lore/codex/new_page, dont_record_history = FALSE, mob/user)
	var/datum/lore/codex/D = current_page["[user]"]
	if(new_page && istype(D)) // Make sure we're not going to a null page for whatever reason.
		current_page["[user]"] = new_page
		if(!dont_record_history)
			var/list/H = history["[user]"]
			if(!H)
				H = list()
			H.Add(new_page)
			history["[user]"] = H

/datum/codex_tree/proc/quick_link(search_word, mob/user)
	for(var/word in indexed_pages)
		if(lowertext(search_word) == lowertext(word)) // Exact matches unfortunately limit our ability to perform SEOs.
			go_to_page(indexed_pages[word], FALSE, user)
			return

/datum/codex_tree/proc/get_page_from_type(desired_type)
	for(var/word in indexed_pages)
		var/datum/lore/codex/C = indexed_pages[word]
		if(C.type == desired_type)
			return C
	return null

// Returns to the last visited page, based on the history list.
/datum/codex_tree/proc/go_back(mob/user)
	var/list/H = history["[user]"]
	var/datum/lore/codex/D = current_page["[user]"]
	if(!LAZYLEN(H) || !istype(D))
		return
	if((H.len) > 1)
		if(H[H.len] == D)
			H.len-- // This gets rid of the current page in the history.
			history["[user]"] = H
			if(H.len == 1)
				go_to_page(H[H.len], TRUE, user)
				return
		go_to_page(pop(history["[user]"]), TRUE, user) // Where as this will get us the previous page that we want to go to.
	else
		go_to_page(H[H.len], TRUE, user)

/datum/codex_tree/proc/get_tree_position(mob/user)
	var/datum/lore/codex/checked = current_page["[user]"]
	if(istype(checked))
		var/output = ""
		output = span_bold("[checked.name]")
		while(checked.parent)
			output = "<a href='byond://?src=\ref[src];target=\ref[checked.parent]'>[checked.parent.name]</a> \> [output]"
			checked = checked.parent
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

// DQEdit Start — TGUI migration. display() now opens CodexTree.tsx; Topic
// dispatch moves to tgui_act. Page/history state stays per-user as before.
/datum/codex_tree/proc/display(mob/user)
	if(!home)
		generate_pages()
	if(!user)
		return
	var/datum/lore/codex/D = current_page["[user]"]
	if(!istype(D))
		current_page["[user]"] = home
		D = current_page["[user]"]
		if(!istype(D))
			log_runtime("Codex_tree failed to load for [user].")
			return
		var/list/H_init = list()
		H_init.Add(home)
		history["[user]"] = H_init
	tgui_interact(user)

/datum/codex_tree/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/codex_tree/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CodexTree", holder?.name || "Codex")
		ui.open()

/datum/codex_tree/tgui_data(mob/user)
	var/list/data = list()
	data["holder_name"] = holder?.name || ""
	var/datum/lore/codex/D = current_page["[user]"]
	if(!istype(D))
		D = home
	data["page_name"] = D ? D.name : ""
	data["page_data"] = D?.data || ""
	var/list/crumbs = list()
	var/datum/lore/codex/walker = D
	while(walker)
		crumbs.Insert(1, null)
		crumbs[1] = list("ref" = "\ref[walker]", "name" = walker.name)
		walker = walker.parent
	data["crumbs"] = crumbs
	var/list/kids = list()
	data["is_category"] = istype(D, /datum/lore/codex/category)
	if(data["is_category"])
		var/datum/lore/codex/category/C = D
		for(var/datum/lore/codex/child in C.children)
			kids += list(list("ref" = "\ref[child]", "name" = child.name))
	data["children"] = kids
	var/list/H = history["[user]"]
	data["can_go_back"] = LAZYLEN(H) > 0
	data["can_go_up"] = !!(D?.parent)
	data["can_go_home"] = D != home
	return data

/datum/codex_tree/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("target")
			var/datum/lore/codex/new_page = locate(params["ref"])
			go_to_page(new_page, FALSE, usr)
			return TRUE
		if("search")
			quick_link(params["query"], usr)
			return TRUE
		if("go_up")
			go_to_parent(usr)
			return TRUE
		if("go_back")
			go_back(usr)
			return TRUE
		if("go_home")
			go_to_page(home, FALSE, usr)
			return TRUE
// DQEdit End

// Holds the various pages and implementations for codex books, so they can be used in more than just books.

/datum/codex_tree
	var/tmp/atom/movable/holder
	var/root_type = null
	var/datum/lore/codex/home = null // Top-most page.
	var/list/indexed_pages // Assoc list with search terms pointing to a ref of the page.  It's created on New().
	/// "[user]" -> /datum/codex_reader (owned): each reader's current page and history.
	var/list/readers

CAPABILITIES(/datum/codex_tree)
	ref_one(nameof(holder), /atom/movable)
	owns_one(nameof(home), /datum/lore/codex)
	owns_many(nameof(readers))
	interface("CodexReader", title = "The Empress Protects")
	op("target", ui_act("target", arg("page", int(1))), needs(req(PROC_REF(req_page))), then(PROC_REF(ui_act_target)))
	op("quick_link", ui_act("quick_link", arg("term", schema_text(MAX_NAME_LEN))), then(PROC_REF(ui_act_quick_link)))
	op("go_to_parent", ui_act("go_to_parent"), then(PROC_REF(ui_act_go_to_parent)))
	op("go_back", ui_act("go_back"), then(PROC_REF(ui_act_go_back)))
	op("go_to_home", ui_act("go_to_home"), then(PROC_REF(ui_act_go_to_home)))
	op("close", ui_act("close"), then(PROC_REF(ui_act_close)))

/datum/codex_tree/New(new_holder, new_root_type)
	rel_set(src, nameof(holder), new_holder)
	root_type = new_root_type
	generate_pages()
	..()

/// One reader's cursor into the tree: their current page and the pages they visited, as
/// relation views (the pages belong to the tree's home).
/datum/codex_reader
	var/datum/lore/codex/page
	/// Visited pages, oldest first (a relation list; a revisited page moves to the end).
	var/list/history

CAPABILITIES(/datum/codex_reader)
	ref_one(nameof(page), /datum/lore/codex)
	ref_many(nameof(history))

/datum/codex_reader/proc/visit(datum/lore/codex/new_page, record_history)
	rel_set(src, nameof(page), new_page)
	if(record_history && new_page)
		rel_remove(src, nameof(history), new_page)
		rel_add(src, nameof(history), new_page)

/// The reader state for `user`, made on first use.
/datum/codex_tree/proc/reader_of(mob/user) as /datum/codex_reader
	var/key = "[user]"
	var/datum/codex_reader/R = LAZYACCESS(readers, key)
	if(!R)
		R = rel_add(src, nameof(readers), new /datum/codex_reader, key)
	return R

/// `user`'s current page, or null.
/datum/codex_tree/proc/current_page_of(mob/user) as /datum/lore/codex
	var/datum/codex_reader/R = LAZYACCESS(readers, "[user]")
	return R?.page

/datum/codex_tree/proc/generate_pages()
	rel_set(src, nameof(home), new root_type(src)) // This will also generate the others.
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
			rel_remove(R, nameof(R.history), D) // This gets rid of the current page in the history.
			if(length(R.history) == 1)
				go_to_page(R.history[1], TRUE, user)
				return
		var/datum/lore/codex/previous = R.history[length(R.history)] // the previous page that we want to go to
		rel_remove(R, nameof(R.history), previous)
		go_to_page(previous, TRUE, user)
	else
		go_to_page(H[length(H)], TRUE, user)

/// Every page of the tree in a fixed order (the home page first, then each category's pages in turn): a page's place in it is the id the window uses.
/datum/codex_tree/proc/pages_in_order()
	var/list/out = list()
	if(!home)
		return out
	var/list/queue = list(home)
	while(length(queue))
		var/datum/lore/codex/D = queue[length(queue)]
		queue.len--
		out += D
		if(istype(D, /datum/lore/codex/category))
			var/datum/lore/codex/category/C = D
			for(var/i in length(C.child_pages) to 1 step -1)
				queue += C.child_pages[i]
	return out

/// Opens the reader's window on their current page (the home page the first time).
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
	tgui_interact(user)

/// /datum/codex_tree's window data: the reader's page, the way up from it and the pages under it.
/datum/codex_tree/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/mob/user = A.actor
	var/datum/lore/codex/D = current_page_of(user)
	if(!istype(D))
		return data
	var/list/order = pages_in_order()
	var/list/trail = list()
	var/datum/lore/codex/up = D.parent()
	while(up)
		trail += list(list("name" = up.name, "id" = order.Find(up)))
		up = up.parent()
	// The way up was walked from the page to the home page; it reads the other way.
	var/list/trail_down = list()
	for(var/i in length(trail) to 1 step -1)
		trail_down += list(trail[i])
	var/list/children = list()
	if(istype(D, /datum/lore/codex/category))
		var/datum/lore/codex/category/C = D
		for(var/datum/lore/codex/child in C.child_pages)
			children += list(list("name" = child.name, "id" = order.Find(child)))
	var/datum/codex_reader/R = LAZYACCESS(readers, "[user]")
	data["page_name"] = D.name
	data["page_html"] = D.data
	data["trail"] = trail_down
	data["children"] = children
	data["can_back"] = !!LAZYLEN(R?.history)
	data["can_up"] = !!D.parent()
	data["can_home"] = D != home
	return data

/// Requirement: the button names a page of this codex (a page of another codex is not).
/datum/codex_tree/proc/req_page(datum/act/op/A)
	var/id = A.args ? A.args["page"] : null
	return isnum(id) && LAZYACCESS(pages_in_order(), id) ? null : MSG(req_silent)

/datum/codex_tree/proc/ui_act_target(datum/act/op/A, page)
	go_to_page(LAZYACCESS(pages_in_order(), page), FALSE, A.actor)
	SStgui.update_uis(src)
	return OP_OK

/datum/codex_tree/proc/ui_act_quick_link(datum/act/op/A, term)
	quick_link(term, A.actor)
	SStgui.update_uis(src)
	return OP_OK

/datum/codex_tree/proc/ui_act_go_to_parent(datum/act/op/A)
	go_to_parent(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/datum/codex_tree/proc/ui_act_go_back(datum/act/op/A)
	go_back(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/datum/codex_tree/proc/ui_act_go_to_home(datum/act/op/A)
	go_to_page(home, FALSE, A.actor)
	SStgui.update_uis(src)
	return OP_OK

/datum/codex_tree/proc/ui_act_close(datum/act/op/A)
	SStgui.close_uis(src)
	return OP_OK


/// The holder this refers to (a relation view: null once that is deleted).
/datum/codex_tree/proc/holder() as /atom/movable
	return holder

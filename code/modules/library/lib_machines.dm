/* Library Machines
 *
 * Contains:
 *		Borrowbook datum
 *		Library Public Computer
 *		Library Computer
 *		Library Scanner
 *		Book Binder
 */

/*
 * Borrowbook datum
 */
/datum/borrowbook // Datum used to keep track of who has borrowed what when and for how long.
	var/bookname
	var/mobname
	var/getdate
	var/duedate

/*
 * Library Public Computer
 */
/obj/machinery/librarypubliccomp
	name = "visitor computer"
	icon = 'icons/obj/library.dmi'
	icon_state = "computer"
	anchored = TRUE
	density = TRUE
	var/screenstate = 0
	var/title
	var/category = "Any"
	var/author
	var/SQLquery
	// cached search results (list of assoc lists) for TGUI.
	var/list/last_results = null

// TGUI migration. attack_hand opens LibraryVisitor.tsx;
// filter prompts and search execution move to tgui_act.
/obj/machinery/librarypubliccomp/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/librarypubliccomp_open_ui,
	)
	..()

/datum/interaction/machine_hand/ungated/librarypubliccomp_open_ui
	id = "librarypubliccomp_open_ui"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/librarypubliccomp/proc/interaction_open_ui_impl

/obj/machinery/librarypubliccomp/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/obj/machinery/librarypubliccomp/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LibraryVisitor", "Library Visitor")
		ui.open()

/obj/machinery/librarypubliccomp/tgui_data(mob/user)
	var/list/data = list()
	data["screenstate"] = screenstate
	data["title"] = title || ""
	data["category"] = category || "Any"
	data["author"] = author || ""
	data["has_db"] = SSdbcore.IsConnected()
	data["has_query"] = !!SQLquery
	data["results"] = last_results || list()
	return data

/obj/machinery/librarypubliccomp/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	switch(action)
		if("settitle")
			var/newtitle = act_ask(usr, action, params, ui, "k79", /datum/om/prompt/text, message = "Enter a title to search for:")
			if(isnull(newtitle))
				return
			if(newtitle)
				title = newtitle
			return TRUE
		if("setcategory")
			var/newcategory = act_ask(usr, action, params, ui, "k84", /datum/om/prompt/choice, message = "Choose a category to search for:", title = "Category", choices = list("Any", "Fiction", "Non-Fiction", "Adult", "Reference", "Religion"))
			if(isnull(newcategory))
				return
			if(!newcategory)
				newcategory = "Any"
			category = newcategory
			return TRUE
		if("setauthor")
			var/newauthor = act_ask(usr, action, params, ui, "k90", /datum/om/prompt/text, message = "Enter an author to search for:")
			if(isnull(newauthor))
				return
			if(newauthor)
				author = newauthor
			return TRUE
		if("search")
			last_results = list()
			if(SSdbcore.IsConnected())
				// category == "Any" means no category filter; both branches use
				// LIKE parameters so user-supplied title/author cannot inject SQL.
				// om_io: the results fill in when they arrive.
				if(category == "Any")
					om_sql_view(src, "search",
						"SELECT author, title, category, id FROM library WHERE author LIKE :author_pat AND title LIKE :title_pat",
						list("author_pat" = "%[author]%", "title_pat" = "%[title]%"),
						PROC_REF(sql_rows_arrived)
					)
				else
					om_sql_view(src, "search",
						"SELECT author, title, category, id FROM library WHERE author LIKE :author_pat AND title LIKE :title_pat AND category = :category",
						list("author_pat" = "%[author]%", "title_pat" = "%[title]%", "category" = category),
						PROC_REF(sql_rows_arrived)
					)
			SQLquery = null // cleared after search — no longer holds interpolated SQL
			screenstate = 1
			add_fingerprint(usr)
			return TRUE
		if("back")
			screenstate = 0
			return TRUE


/obj/machinery/librarypubliccomp/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = om_sql_view_rows(result, error, key, src)
	last_results = list()
	for(var/list/row as anything in rows)
		last_results += list(list(
			"author" = row[1],
			"title" = row[2],
			"category" = row[3],
			"id" = "[row[4]]",
		))
	SStgui.update_uis(src)

/*
 * Library Computer
 */
// TODO: Make this an actual /obj/machinery/computer that can be crafted from circuit boards and such
// It is August 22nd, 2012... This TODO has already been here for months.. I wonder how long it'll last before someone does something about it. // Nov 2019. Nope.
/obj/machinery/librarycomp
	name = "Check-In/Out Computer"
	desc = "Print books from the archives! (You aren't quite sure how they're printed by it, though.)"
	icon = 'icons/obj/library.dmi'
	icon_state = "computer"
	anchored = TRUE
	density = TRUE
	var/arcanecheckout = 0
	var/screenstate = 0 // 0 - Main Menu, 1 - Inventory, 2 - Checked Out, 3 - Check Out a Book
	var/sortby = "author"
	var/buffer_book
	var/buffer_mob
	var/upload_category = "Fiction"
	/// Check-out records (owned /datum/borrowbook)
	var/list/checkouts
	/// Books in the general inventory (a relation list)
	var/list/inventory
	var/checkoutperiod = 5 // In minutes
	var/tmp/obj/machinery/libraryscanner/scanner	// Book scanner that will be used when uploading books to the Archive

	/// Printing a bible or a book: at most one per few seconds.
	COOLDOWN_DECLARE(print_cooldown)

	var/static/list/all_books

	var/static/list/base_genre_books

	// TGUI: TRUE when the admin ghost view is active. Toggles the
	// External Archive table to show Delete buttons.
	var/is_admin_view = FALSE
	/// The External Archive's rows (refresh_external(): they arrive after it is asked).
	var/list/external_rows

/obj/machinery/librarycomp/Initialize(mapload)
	. = ..()

	if(!base_genre_books || !base_genre_books.len)
		base_genre_books = list(
			/obj/item/book/custom_library/fiction,
			/obj/item/book/custom_library/nonfiction,
			/obj/item/book/custom_library/reference,
			/obj/item/book/custom_library/religious,
			/obj/item/book/bundle/custom_library/fiction,
			/obj/item/book/bundle/custom_library/nonfiction,
			/obj/item/book/bundle/custom_library/reference,
			/obj/item/book/bundle/custom_library/religious
			)

	if(!all_books || !all_books.len)
		all_books = list()

		for(var/path in subtypesof(/obj/item/book/codex/lore))
			var/obj/item/book/C = new path(null)
			own_put(src, "all_books", C.name, C)

		for(var/path in subtypesof(/obj/item/book/custom_library) - base_genre_books)
			var/obj/item/book/B = new path(null)
			own_put(src, "all_books", B.title, B)

		for(var/path in subtypesof(/obj/item/book/bundle/custom_library) - base_genre_books)
			var/obj/item/book/M = new path(null)
			own_put(src, "all_books", M.title, M)

// TGUI migration. attack_hand and attack_ghost open
// LibraryComp.tsx. The big browse-rendered switch and Topic dispatcher
// move to tgui_data + tgui_act.
/obj/machinery/librarycomp/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_OBSERVER("Admin view", PROC_REF(librarycomp_ghost_admin_view)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_item/librarycomp_link_scanner,
		/datum/interaction/machine_hand/ungated/librarycomp_open_ui,
	)
	..()

/datum/interaction/machine_item/librarycomp_link_scanner
	id = "librarycomp_link_scanner"
	name = "Link scanner"
	held_type = /obj/item/barcodescanner
	effect = /obj/machinery/librarycomp/proc/interaction_link_scanner

/obj/machinery/librarycomp/proc/interaction_link_scanner(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/barcodescanner/scanner = held
	rel_set(scanner, "computer", src)
	to_chat(user, "[scanner]'s associated machine has been set to [src].")
	for(var/mob/V in hearers(src))
		V.show_message("[src] lets out a low, short blip.", 2)
	return TRUE

/datum/interaction/machine_hand/ungated/librarycomp_open_ui
	id = "librarycomp_open_ui"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/librarycomp/proc/interaction_open_ui_impl

/obj/machinery/librarycomp/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	is_admin_view = FALSE
	tgui_interact(user)
	return TRUE

/obj/machinery/librarycomp/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LibraryComp", "Book Inventory Management")
		ui.open()

/obj/machinery/librarycomp/tgui_state(mob/user)
	if(is_admin_view)
		return GLOB.tgui_always_state
	return ..()

/// Fetches the External Archive listing (om_io); tgui_data shows it when it arrives.
/obj/machinery/librarycomp/proc/refresh_external()
	if(!SSdbcore.IsConnected())
		return
	// sortby is mapped to a fixed column literal at the query site, so ORDER BY
	// can never be injected even if the whitelist in tgui_act is ever bypassed.
	om_sql_view(src, "external", "SELECT id, author, title, category FROM library ORDER BY [safe_sortby_column()]", PROC_REF(sql_rows_arrived))

/obj/machinery/librarycomp/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = om_sql_view_rows(result, error, key, src)
	external_rows = rows
	SStgui.update_uis(src)

/// Maps the stored sortby value to a fixed, known-safe SQL column literal.
/// Defense-in-depth: even if a future writer sets `sortby` without the whitelist
/// in the "sort" tgui_act branch, ORDER BY can never become injectable.
/obj/machinery/librarycomp/proc/safe_sortby_column()
	switch(sortby)
		if("title")
			return "title"
		if("category")
			return "category"
		else
			return "author"

/obj/machinery/librarycomp/tgui_data(mob/user)
	var/list/data = list()
	data["screenstate"] = screenstate
	data["emagged"] = !!emagged
	data["is_admin"] = !!is_admin_view
	data["buffer_book"] = buffer_book || ""
	data["buffer_mob"] = buffer_mob || ""
	data["checkout_period"] = checkoutperiod
	data["world_time_min"] = world.time / 600
	data["sort_by"] = sortby
	data["upload_category"] = upload_category
	data["has_db"] = SSdbcore.IsConnected()
	// Ensure a connected scanner is auto-discovered like the legacy UI did.
	if(!scanner())
		for(var/obj/machinery/libraryscanner/S in range(9))
			rel_set(src, "scanner", S)
			break
	data["has_scanner"] = !!scanner()
	if(scanner()?.cache())
		data["scanner_cache"] = list(
			"name" = scanner().cache().name,
			"author" = scanner().cache().author || "",
		)
	else
		data["scanner_cache"] = null
	var/list/inv = list()
	for(var/obj/item/book/b in inventory)
		inv += list(list("ref" = "\ref[b]", "name" = b.name))
	data["inventory"] = inv
	var/list/cos = list()
	for(var/datum/borrowbook/b in checkouts)
		var/timetaken = round((world.time - b.getdate) / 600)
		var/raw_due = (b.duedate - world.time) / 600
		var/overdue = (raw_due <= 0)
		cos += list(list(
			"ref" = "\ref[b]",
			"bookname" = b.bookname,
			"mobname" = b.mobname,
			"taken_min" = timetaken,
			"due_min" = round(raw_due),
			"overdue" = overdue,
		))
	data["checkouts"] = cos
	var/list/internal = list()
	if(screenstate == 4 && all_books?.len)
		for(var/name in all_books)
			var/obj/item/book/mb = all_books[name]
			internal += list(list(
				"path" = "[mb.type]",
				"name" = mb.name,
				"author" = mb.author || "",
				"category" = mb.libcategory || "",
			))
	data["internal_archive"] = internal
	var/list/external = list()
	if(screenstate == 8 || is_admin_view)
		for(var/list/row as anything in external_rows)
			external += list(list(
				"id" = "[row[1]]",
				"author" = row[2],
				"title" = row[3],
				"category" = row[4],
			))
	data["external_archive"] = external
	return data

/obj/machinery/librarycomp/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	switch(action)
		if("switchscreen")
			screenstate = text2num(params["screen"])
			if(screenstate == 8)
				refresh_external()
			return TRUE
		if("print_bible")
			if(COOLDOWN_FINISHED(src, print_cooldown))
				new /obj/item/storage/bible(src.loc)
				COOLDOWN_START(src, print_cooldown, 6 SECONDS)
			else
				for(var/mob/V in hearers(src))
					V.show_message(span_infoplain(span_bold("[src]") + "'s monitor flashes, \"Bible printer currently unavailable, please wait a moment.\""))
			return TRUE
		if("arccheckout")
			if(emagged)
				arcanecheckout = 1
				if(arcanecheckout)
					new /obj/item/book/tome(src.loc)
					to_chat(usr, span_warning("Your sanity barely endures the seconds spent in the vault's browsing window. The only thing to remind you of this when you stop browsing is a dusty old tome sitting on the desk. You don't really remember printing it."))
					usr.visible_message(span_infoplain(span_bold("\The [usr]") + " stares at the blank screen for a few moments, [usr.p_their()] expression frozen in fear. When [usr.p_they()] finally awaken from it, [usr.p_they()] look a lot older."), 2)
					arcanecheckout = 0
			screenstate = 0
			return TRUE
		if("increasetime")
			checkoutperiod += 1
			return TRUE
		if("decreasetime")
			checkoutperiod -= 1
			if(checkoutperiod < 1)
				checkoutperiod = 1
			return TRUE
		if("editbook")
			var/_answer_k357 = act_ask(usr, action, params, ui, "k357", /datum/om/prompt/text, message = "Enter the book's title:", encode = FALSE)
			if(isnull(_answer_k357))
				return
			buffer_book = sanitizeSafe(_answer_k357)
			return TRUE
		if("editmob")
			var/_answer_k360 = act_ask(usr, action, params, ui, "k360", /datum/om/prompt/text, message = "Enter the recipient's name:", max_length = MAX_NAME_LEN)
			if(isnull(_answer_k360))
				return
			buffer_mob = _answer_k360
			return TRUE
		if("checkout")
			var/datum/borrowbook/b = new
			b.bookname = sanitizeSafe(buffer_book)
			b.mobname = sanitize(buffer_mob)
			b.getdate = world.time
			b.duedate = world.time + (checkoutperiod * 600)
			own_add(src, "checkouts", b)
			return TRUE
		if("checkin")
			var/datum/borrowbook/b = locate(params["ref"])
			if(b)
				own_remove(src, "checkouts", b)
			return TRUE
		if("delbook")
			var/obj/item/book/b = locate(params["ref"])
			if(b)
				rel_remove(src, "inventory", b)
			return TRUE
		if("setauthor")
			var/newauthor = act_ask(usr, action, params, ui, "k381", /datum/om/prompt/text, message = "Enter the author's name:")
			if(isnull(newauthor))
				return
			if(newauthor && scanner()?.cache())
				scanner().cache().author = newauthor
			return TRUE
		if("setcategory")
			var/newcategory = act_ask(usr, action, params, ui, "k386", /datum/om/prompt/choice, message = "Choose a category:", title = "Category", choices = list("Fiction", "Non-Fiction", "Adult", "Reference", "Religion"))
			if(isnull(newcategory))
				return
			if(newcategory)
				upload_category = newcategory
			return TRUE
		if("upload")
			if(!scanner()?.cache())
				return TRUE
			var/choice = act_ask(usr, action, params, ui, "k393", /datum/om/prompt/choice/alert, message = "Are you certain you wish to upload this title to the Archive?", title = "Confirmation", choices = list("Confirm", "Abort"))
			if(isnull(choice))
				return
			if(choice != "Confirm")
				return TRUE
			if(scanner().cache().unique)
				tgui_alert_async(usr, "This book has been rejected from the database. Aborting!")
				return TRUE
			if(!SSdbcore.IsConnected())
				tgui_alert_async(usr, "Connection to Archive has been severed. Aborting.")
				return TRUE
			// om_io: the uploader hears back when the archive answers.
			om_io(src, /datum/om/io/sql,
				"INSERT INTO library (author, title, content, category) VALUES (:author, :title, :content, :category)",
				list("author" = scanner().cache().author, "title" = scanner().cache().name, "content" = scanner().cache().dat, "category" = upload_category),
				PROC_REF(upload_done), usr.ckey, "[usr.name]/[usr.key] has uploaded the book titled [scanner().cache().name], [length(scanner().cache().dat)] signs")
			return TRUE
		if("targetid")
			var/raw_id = params["id"]
			var/numeric_id = text2num(raw_id)
			// Validate that the id is a positive integer before querying.
			if(!isnum(numeric_id) || numeric_id <= 0 || round(numeric_id) != numeric_id)
				return TRUE
			if(!SSdbcore.IsConnected())
				tgui_alert_async(usr, "Connection to Archive has been severed. Aborting.")
				return TRUE
			if(!COOLDOWN_FINISHED(src, print_cooldown))
				for(var/mob/V in hearers(src))
					V.show_message(span_infoplain(span_bold("[src]") + "'s monitor flashes, \"Printer unavailable. Please allow a short time before attempting to print.\""))
				return TRUE
			COOLDOWN_START(src, print_cooldown, 6)
			om_io(src, /datum/om/io/sql,
				"SELECT id, author, title, content FROM library WHERE id = :id",
				list("id" = numeric_id),
				PROC_REF(print_book_arrived))
			return TRUE
		if("delid")
			if(!check_rights(R_ADMIN))
				return TRUE
			var/raw_id = params["id"]
			var/numeric_id = text2num(raw_id)
			// Validate that the id is a positive integer before deleting.
			if(!isnum(numeric_id) || numeric_id <= 0 || round(numeric_id) != numeric_id)
				return TRUE
			if(!SSdbcore.IsConnected())
				tgui_alert_async(usr, "Connection to Archive has been severed. Aborting.")
				return TRUE
			om_sql_write("DELETE FROM library WHERE id = :id", list("id" = numeric_id))
			log_admin("[usr.key] has deleted library book id=[numeric_id]")
			refresh_external()
			return TRUE
		if("orderbyid")
			var/orderid = act_ask(usr, action, params, ui, "k468", /datum/om/prompt/number, message = "Enter your order:")
			if(isnull(orderid))
				return
			if(orderid && isnum(orderid))
				tgui_act("targetid", list("id" = "[orderid]"), ui, state)
			return TRUE
		if("sort")
			var/field = params["field"]
			if(field in list("author", "title", "category"))
				sortby = field
				refresh_external()
			return TRUE
		if("hardprint")
			var/newpath = text2path(params["path"])
			if(!ispath(newpath, /obj/item/book))
				return TRUE
			var/obj/item/book/NewBook = new newpath(get_turf(src))
			NewBook.name = "Book: [NewBook.name]"
			return TRUE

/// om_io() callback: tells the uploader how the upload went.
/obj/machinery/librarycomp/proc/upload_done(list/result, error, uploader_ckey, log_line)
	var/client/C = GLOB.directory[uploader_ckey]
	if(error)
		if(C)
			to_chat(C, error)
		return
	log_game(log_line)
	if(C)
		tgui_alert_async(C.mob, "Upload Complete.")

/// om_io() callback: prints the ordered book, if the archive had it.
/obj/machinery/librarycomp/proc/print_book_arrived(list/result, error)
	var/list/rows = result?["rows"]
	if(!length(rows))
		return
	var/list/row = rows[1]
	var/book_title = row[3]
	var/obj/item/book/B = new(src.loc)
	B.name = "Book: [book_title]"
	B.title = book_title
	B.author = row[2]
	B.dat = row[4]
	B.icon_state = "book[rand(1,16)]"
	B.item_state = B.icon_state
	visible_message("[src]'s printer hums as it produces a completely bound book. How did it do that?")

// admin ghost view routes to LibraryComp.tsx with is_admin_view
// set; non-admin ghosts fall through to default handling.
/// Old attack_ghost: admins get the admin view; other ghosts the default.
/obj/machinery/librarycomp/proc/librarycomp_ghost_admin_view(mob/user, obj/item/held, datum/interaction/interaction)
	if(!check_rights(R_ADMIN, show_msg = FALSE))
		return FALSE
	user.set_machine(src)
	is_admin_view = TRUE
	screenstate = 8
	refresh_external()
	tgui_interact(user)
	return TRUE

/obj/machinery/librarycomp/emag_act(remaining_charges, mob/user)
	if (src.density && !src.emagged)
		src.emagged = 1
		return 1

/*
 * Library Scanner
 */
/obj/machinery/libraryscanner
	name = "scanner"
	desc = "A scanner for scanning in books and papers."
	icon = 'icons/obj/library.dmi'
	icon_state = "bigscanner"
	anchored = TRUE
	density = TRUE
	var/tmp/obj/item/book/cache	// Last scanned book

/obj/machinery/libraryscanner/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/libraryscanner_insert_book,
		/datum/interaction/machine_hand/ungated/libraryscanner_open_ui,
	)
	..()

/datum/interaction/machine_item/libraryscanner_insert_book
	id = "libraryscanner_insert_book"
	name = "Insert book"
	held_type = /obj/item/book
	effect = /obj/machinery/libraryscanner/proc/interaction_insert_book

/obj/machinery/libraryscanner/proc/interaction_insert_book(mob/user, obj/item/held, datum/interaction/interaction)
	user.drop_item()
	held.forceMove(src)
	return TRUE

// TGUI migration. attack_hand opens LibraryScanner.tsx;
// scan/clear/eject move to tgui_act.
/datum/interaction/machine_hand/ungated/libraryscanner_open_ui
	id = "libraryscanner_open_ui"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/libraryscanner/proc/interaction_open_ui_impl

/obj/machinery/libraryscanner/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/obj/machinery/libraryscanner/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LibraryScanner", "Scanner")
		ui.open()

/obj/machinery/libraryscanner/tgui_data(mob/user)
	var/list/data = list()
	data["has_cache"] = !!cache()
	data["cache_name"] = cache() ? cache().name : ""
	var/has_book = FALSE
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/book/B in contents) // ALLOW(latent): materialized above
		has_book = TRUE
		break
	data["has_book"] = has_book
	return data

/obj/machinery/libraryscanner/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	switch(action)
		if("scan")
			latent_materialize_all() // a walk needs real things (C5)
			for(var/obj/item/book/B in contents) // ALLOW(latent): materialized above
				rel_set(src, "cache", B)
				break
			add_fingerprint(usr)
			return TRUE
		if("clear")
			rel_clear(src, "cache")
			return TRUE
		if("eject")
			latent_materialize_all() // a walk needs real things (C5)
			for(var/obj/item/book/B in contents) // ALLOW(latent): materialized above
				B.forceMove(src.loc)
			return TRUE


/*
 * Book binder
 */
/obj/machinery/bookbinder
	name = "Book Binder"
	desc = "Bundles up a stack of inserted paper into a convenient book format."
	icon = 'icons/obj/library.dmi'
	icon_state = "binder"
	anchored = TRUE
	density = TRUE

/obj/machinery/bookbinder/Initialize(mapload)
	. = ..()
	make_climbable()

/obj/machinery/bookbinder/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/bookbinder_bind,
	)
	..()

/datum/interaction/machine_item/bookbinder_bind
	id = "bookbinder_bind"
	name = "Bind"
	held_type = list(/obj/item/paper, /obj/item/paper_bundle)
	effect = /obj/machinery/bookbinder/proc/interaction_bind

/obj/machinery/bookbinder/proc/interaction_bind(mob/user, obj/item/held, datum/interaction/interaction)
	if(istype(held, /obj/item/paper))
		user.drop_item()
		held.forceMove(src)
		user.visible_message("[user] loads some paper into [src].", "You load some paper into [src].")
		src.visible_message("[src] begins to hum as it warms up its printing drums.")
		om_after(src, rand(200,400), PROC_REF(bind_paper), held)
	else
		user.drop_item()
		held.forceMove(src)
		user.visible_message("[user] loads some paper into [src].", "You load some paper into [src].")
		src.visible_message("[src] begins to hum as it warms up its printing drums.")
		om_after(src, rand(300,500), PROC_REF(bind_bundle), held)
	return TRUE

/obj/machinery/bookbinder/proc/bind_paper(obj/item/paper/source_paper)
	src.visible_message("[src] whirs as it prints and binds a new book.")
	var/obj/item/book/b = new(src.loc)
	b.dat = source_paper.info
	b.name = "Print Job #" + "[rand(100, 999)]"
	b.icon_state = "book[rand(1,7)]"
	qdel(source_paper)

/obj/machinery/bookbinder/proc/bind_bundle(obj/item/paper_bundle/source_bundle)
	src.visible_message("[src] whirs as it prints and binds a new book.")
	var/obj/item/book/bundle/b = new(src.loc)
	b.pages = source_bundle.pages
	for(var/obj/item/paper/P in contents_of(source_bundle))
		P.forceMove(b)
	for(var/obj/item/photo/P in contents_of(source_bundle))
		P.forceMove(b)
	b.name = "Print Job #" + "[rand(100, 999)]"
	b.icon_state = "book[rand(1,7)]"
	qdel(source_bundle)

/// Book scanner that will be used when uploading books to the Archive (a relation view: null once that is deleted).
/obj/machinery/librarycomp/proc/scanner() as /obj/machinery/libraryscanner
	return scanner

/// Last scanned book (a relation view: null once that is deleted).
/obj/machinery/libraryscanner/proc/cache() as /obj/item/book
	return cache

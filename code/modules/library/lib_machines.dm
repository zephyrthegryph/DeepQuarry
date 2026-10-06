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
	EXPIRY_DECLARE(getdate)
	EXPIRY_DECLARE(duedate)

/*
 * Library Public Computer
 */
CAPABILITIES(/obj/machinery/librarypubliccomp)
	op("search", ui_act(), then(PROC_REF(ui_act_search)))
	op("back", ui_act(), then(PROC_REF(ui_act_back)))
	interface("LibraryVisitor", title = "Library Visitor")
	without("ui_open")
	op("settitle", ui_act("settitle"), asks(/datum/prompt/text/library_search_text, fields = list("question" = "Enter a title to search for:"), step = "value"), then(PROC_REF(ui_act_settitle)))
	op("setcategory", ui_act("setcategory"), asks(/datum/prompt/choice/library_search_category, fields = list("question" = "Choose a category to search for:", "title" = "Category"), step = "value"), then(PROC_REF(ui_act_setcategory)))
	op("setauthor", ui_act("setauthor"), asks(/datum/prompt/text/library_search_text, fields = list("question" = "Enter an author to search for:"), step = "value"), then(PROC_REF(ui_act_setauthor)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

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

/obj/machinery/librarypubliccomp/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/obj/machinery/librarypubliccomp/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["screenstate"] = screenstate
	var/list/merged_1 = ui_data_obj_machinery_librarypubliccomp(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/librarypubliccomp's window data.
/obj/machinery/librarypubliccomp/proc/ui_data_obj_machinery_librarypubliccomp(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["title"] = title || ""
	data["category"] = category || "Any"
	data["author"] = author || ""
	data["has_db"] = SSdbcore.IsConnected()
	data["has_query"] = !!SQLquery
	data["results"] = last_results || list()
	return data

/obj/machinery/librarypubliccomp/proc/ui_act_settitle(datum/act/op/A)
	apply_search_answer("settitle", A.step_value("value"))
	return TRUE

/obj/machinery/librarypubliccomp/proc/ui_act_setcategory(datum/act/op/A)
	apply_search_answer("setcategory", A.step_value("value"))
	return TRUE

/obj/machinery/librarypubliccomp/proc/ui_act_setauthor(datum/act/op/A)
	apply_search_answer("setauthor", A.step_value("value"))
	return TRUE

/obj/machinery/librarypubliccomp/proc/ui_act_search(datum/act/op/A)
	var/mob/user = A.actor
	last_results = list()
	if(SSdbcore.IsConnected())
		// category == "Any" means no category filter; both branches use
		// LIKE parameters so user-supplied title/author cannot inject SQL.
		// io_job: the results fill in when they arrive.
		if(category == "Any")
			sql_view(src, "search",
				"SELECT author, title, category, id FROM library WHERE author LIKE :author_pat AND title LIKE :title_pat",
				list("author_pat" = "%[author]%", "title_pat" = "%[title]%"),
				PROC_REF(sql_rows_arrived)
			)
		else
			sql_view(src, "search",
				"SELECT author, title, category, id FROM library WHERE author LIKE :author_pat AND title LIKE :title_pat AND category = :category",
				list("author_pat" = "%[author]%", "title_pat" = "%[title]%", "category" = category),
				PROC_REF(sql_rows_arrived)
			)
	SQLquery = null // cleared after search — no longer holds interpolated SQL
	screenstate = 1
	add_fingerprint(user)
	return OP_OK

/obj/machinery/librarypubliccomp/proc/ui_act_back(datum/act/op/A)
	screenstate = 0
	return OP_OK

/obj/machinery/librarypubliccomp/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = sql_view_rows(result, error, key, src)
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

CAPABILITIES(/obj/machinery/librarycomp)
	owns_many(nameof(checkouts))
	op("print_bible", ui_act(), then(PROC_REF(ui_act_print_bible)))
	op("arccheckout", ui_act(), then(PROC_REF(ui_act_arccheckout)))
	op("increasetime", ui_act(), then(PROC_REF(ui_act_increasetime)))
	op("decreasetime", ui_act(), then(PROC_REF(ui_act_decreasetime)))
	op("checkout", ui_act(), then(PROC_REF(ui_act_checkout)))
	interface("LibraryComp", title = "Book Inventory Management")
	without("ui_open")
	op("switchscreen", ui_act("switchscreen", arg("screen", num())), then(PROC_REF(ui_act_switchscreen)))
	op("editbook", ui_act("editbook"), asks(/datum/prompt/text/library_catalogue/book, fields = list("question" = "Enter the book's title:"), step = "value"), then(PROC_REF(ui_act_editbook)))
	op("editmob", ui_act("editmob"), asks(/datum/prompt/text/library_catalogue/recipient, fields = list("question" = "Enter the recipient's name:"), step = "value"), then(PROC_REF(ui_act_editmob)))
	op("checkin", ui_act("checkin", arg("ref", schema_ref(/datum/borrowbook))), then(PROC_REF(ui_act_checkin)))
	op("delbook", ui_act("delbook", arg("ref", schema_ref(/obj/item/book))), then(PROC_REF(ui_act_delbook)))
	op("setauthor", ui_act("setauthor"), asks(/datum/prompt/text/library_catalogue/author, fields = list("question" = "Enter the author's name:"), step = "value"), then(PROC_REF(ui_act_setauthor)))
	op("setcategory", ui_act("setcategory"), asks(/datum/prompt/choice/library_catalogue_category, fields = list("question" = "Choose a category:", "title" = "Category"), step = "value"), then(PROC_REF(ui_act_setcategory)))
	op("upload", ui_act("upload"), asks(/datum/prompt/choice/library_upload, step = "confirm"), then(PROC_REF(ui_act_upload)))
	op("targetid", ui_act("targetid", arg("id", num())), then(PROC_REF(ui_act_targetid)))
	op("delid", ui_act("delid", arg("id", num())), then(PROC_REF(ui_act_delid)))
	op("orderbyid", ui_act("orderbyid"), asks(/datum/prompt/number/library_order_id, step = "id"), then(PROC_REF(ui_act_orderbyid)))
	op("sort", ui_act("sort", arg("field", schema_text(4096))), then(PROC_REF(ui_act_sort)))
	op("hardprint", ui_act("hardprint", arg("path", schema_path(/datum))), then(PROC_REF(ui_act_hardprint)))

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

	if(!length(all_books))
		// A static archive of plain data rows (name -> row), read from the type defaults: no book is
		// instantiated and no library computer holds book instances.
		all_books = list()
		for(var/path in subtypesof(/obj/item/book/codex/lore))
			var/obj/item/book/C = path
			all_books[initial(C.name)] = library_archive_row(path)

		for(var/path in subtypesof(/obj/item/book/custom_library) - base_genre_books)
			var/obj/item/book/B = path
			all_books[initial(B.title)] = library_archive_row(path)

		for(var/path in subtypesof(/obj/item/book/bundle/custom_library) - base_genre_books)
			var/obj/item/book/M = path
			all_books[initial(M.title)] = library_archive_row(path)

/// One internal-archive row for the UI: plain data from the book type's defaults.
/obj/machinery/librarycomp/proc/library_archive_row(book_path)
	var/obj/item/book/template = book_path
	return list(
		"path" = "[book_path]",
		"name" = initial(template.name),
		"author" = initial(template.author) || "",
		"category" = initial(template.libcategory) || "",
	)

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
	rel_set(scanner, nameof(scanner.computer), src)
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

/obj/machinery/librarycomp/tgui_state(mob/user)
	if(is_admin_view)
		return GLOB.tgui_always_state
	return ..()

/// Fetches the External Archive listing (io_job); tgui_data shows it when it arrives.
/obj/machinery/librarycomp/proc/refresh_external()
	if(!SSdbcore.IsConnected())
		return
	// sortby is mapped to a fixed column literal at the query site, so ORDER BY
	// can never be injected even if the whitelist in tgui_act is ever bypassed.
	sql_view(src, "external", "SELECT id, author, title, category FROM library ORDER BY [safe_sortby_column()]", PROC_REF(sql_rows_arrived))

/obj/machinery/librarycomp/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = sql_view_rows(result, error, key, src)
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

/obj/machinery/librarycomp/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["screenstate"] = screenstate
	data["checkout_period"] = checkoutperiod
	data["sort_by"] = sortby
	data["upload_category"] = upload_category
	var/list/merged_1 = ui_data_obj_machinery_librarycomp(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/librarycomp's window data.
/obj/machinery/librarycomp/proc/ui_data_obj_machinery_librarycomp(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["emagged"] = !!emagged
	data["is_admin"] = !!is_admin_view
	data["buffer_book"] = buffer_book || ""
	data["buffer_mob"] = buffer_mob || ""
	data["world_time_min"] = world.time / 600
	data["has_db"] = SSdbcore.IsConnected()
	// Ensure a connected scanner is auto-discovered like the legacy UI did.
	if(!scanner())
		for(var/obj/machinery/libraryscanner/S in range(9))
			rel_set(src, nameof(scanner), S)
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
	if(screenstate == 4 && length(all_books))
		for(var/name in all_books)
			internal += list(all_books[name])
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

/obj/machinery/librarycomp/proc/ui_act_switchscreen(datum/act/op/A, screen)
	screenstate = screen
	if(screenstate == 8)
		refresh_external()
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_print_bible(datum/act/op/A)
	if(COOLDOWN_FINISHED(src, print_cooldown))
		new /obj/item/storage/bible(src.loc)
		COOLDOWN_START(src, print_cooldown, 6 SECONDS)
	else
		for(var/mob/V in hearers(src))
			V.show_message(span_infoplain(span_bold("[src]") + "'s monitor flashes, \"Bible printer currently unavailable, please wait a moment.\""))
	return OP_OK

/obj/machinery/librarycomp/proc/ui_act_arccheckout(datum/act/op/A)
	var/mob/user = A.actor
	if(emagged)
		arcanecheckout = 1
		if(arcanecheckout)
			new /obj/item/book/tome(src.loc)
			to_chat(user, span_warning("Your sanity barely endures the seconds spent in the vault's browsing window. The only thing to remind you of this when you stop browsing is a dusty old tome sitting on the desk. You don't really remember printing it."))
			act_message(user, null, MSG_SELF(2), \
				MSG_OTHERS(span_infoplain(span_bold("%U%") + " stares at the blank screen for a few moments, %THEIR% expression frozen in fear. When %THEY% finally awaken from it, %THEY% look a lot older.")))
			arcanecheckout = 0
	screenstate = 0
	return OP_OK

/obj/machinery/librarycomp/proc/ui_act_increasetime(datum/act/op/A)
	checkoutperiod += 1
	return OP_OK

/obj/machinery/librarycomp/proc/ui_act_decreasetime(datum/act/op/A)
	checkoutperiod -= 1
	if(checkoutperiod < 1)
		checkoutperiod = 1
	return OP_OK

/obj/machinery/librarycomp/proc/ui_act_editbook(datum/act/op/A)
	apply_catalogue_answer("editbook", A.step_value("value"))
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_editmob(datum/act/op/A)
	apply_catalogue_answer("editmob", A.step_value("value"))
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_checkout(datum/act/op/A)
	var/datum/borrowbook/b = new
	b.bookname = sanitizeSafe(buffer_book)
	b.mobname = sanitize(buffer_mob)
	EXPIRY_STAMP(b, getdate, CLOCK_WORLD)
	EXPIRY_SET(b, duedate, (checkoutperiod * 600), CLOCK_WORLD)
	rel_add(src, nameof(/obj/machinery/librarycomp::checkouts), b)
	return OP_OK

/obj/machinery/librarycomp/proc/ui_act_checkin(datum/act/op/A, ref)
	var/datum/borrowbook/b = ref
	if(b)
		own_remove(src, nameof(/obj/machinery/librarycomp::checkouts), b)
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_delbook(datum/act/op/A, ref)
	var/obj/item/book/b = ref
	if(b)
		rel_remove(src, nameof(/obj/machinery/librarycomp::inventory), b)
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_setauthor(datum/act/op/A)
	apply_catalogue_answer("setauthor", A.step_value("value"))
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_setcategory(datum/act/op/A)
	apply_catalogue_answer("setcategory", A.step_value("value"))
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_upload(datum/act/op/A)
	return library_upload_stage(A.actor, A.step_value("confirm"))

/obj/machinery/librarycomp/proc/library_upload_stage(mob/user, choice)
	if(!scanner()?.cache())
		return TRUE
	if(choice != "Confirm")
		return TRUE
	if(scanner().cache().unique)
		tgui_alert_async(user, "This book has been rejected from the database. Aborting!")
		return TRUE
	if(!SSdbcore.IsConnected())
		tgui_alert_async(user, "Connection to Archive has been severed. Aborting.")
		return TRUE
	// io_job: the uploader hears back when the archive answers.
	io_job(src, /datum/io_backend/sql,
		"INSERT INTO library (author, title, content, category) VALUES (:author, :title, :content, :category)",
		list("author" = scanner().cache().author, "title" = scanner().cache().name, "content" = scanner().cache().dat, "category" = upload_category),
		PROC_REF(upload_done), user.ckey, "[user.name]/[user.key] has uploaded the book titled [scanner().cache().name], [length(scanner().cache().dat)] signs")
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_targetid(datum/act/op/A, id)
	var/mob/user = A.actor
	return order_library_id(user, id)

/obj/machinery/librarycomp/proc/order_library_id(mob/user, numeric_id)
	// Validate that the id is a positive integer before querying.
	if(!isnum(numeric_id) || numeric_id <= 0 || round(numeric_id) != numeric_id)
		return TRUE
	if(!SSdbcore.IsConnected())
		tgui_alert_async(user, "Connection to Archive has been severed. Aborting.")
		return TRUE
	if(!COOLDOWN_FINISHED(src, print_cooldown))
		for(var/mob/V in hearers(src))
			V.show_message(span_infoplain(span_bold("[src]") + "'s monitor flashes, \"Printer unavailable. Please allow a short time before attempting to print.\""))
		return TRUE
	COOLDOWN_START(src, print_cooldown, 0.6 SECONDS)
	io_job(src, /datum/io_backend/sql,
		"SELECT id, author, title, content FROM library WHERE id = :id",
		list("id" = numeric_id),
		PROC_REF(print_book_arrived))
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_delid(datum/act/op/A, id)
	var/mob/user = A.actor
	if(!admin_require(A.actor?.client, R_ADMIN, "ui_act_delid", TRUE))
		return TRUE
	var/numeric_id = id
	// Validate that the id is a positive integer before deleting.
	if(!isnum(numeric_id) || numeric_id <= 0 || round(numeric_id) != numeric_id)
		return TRUE
	if(!SSdbcore.IsConnected())
		tgui_alert_async(user, "Connection to Archive has been severed. Aborting.")
		return TRUE
	sql_write("DELETE FROM library WHERE id = :id", list("id" = numeric_id))
	log_admin("[user.key] has deleted library book id=[numeric_id]")
	refresh_external()
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_orderbyid(datum/act/op/A)
	var/mob/user = A.actor
	var/orderid = A.step_value("id")
	if(isnum(orderid))
		order_library_id(user, orderid)
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_sort(datum/act/op/A, field_arg)
	var/field = field_arg
	if(field in list("author", "title", "category"))
		sortby = field
		refresh_external()
	return TRUE

/obj/machinery/librarycomp/proc/ui_act_hardprint(datum/act/op/A, path)
	var/newpath = path
	if(!ispath(newpath, /obj/item/book))
		return TRUE
	var/obj/item/book/NewBook = new newpath(get_turf(src))
	NewBook.name = "Book: [NewBook.name]"
	return TRUE

/// io_job() callback: tells the uploader how the upload went.
/obj/machinery/librarycomp/proc/upload_done(list/result, error, uploader_ckey, log_line)
	var/client/C = GLOB.directory[uploader_ckey]
	if(error)
		if(C)
			to_chat(C, error)
		return
	log_game(log_line)
	if(C)
		tgui_alert_async(C.mob, "Upload Complete.")

/// io_job() callback: prints the ordered book, if the archive had it.
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
	if(!admin_require(user.client, R_ADMIN, "librarycomp_ghost_admin_view", FALSE))
		return FALSE
	user.set_machine(src)
	is_admin_view = TRUE
	screenstate = 8
	refresh_external()
	tgui_interact(user)
	return TRUE

DECLARE_EMAG_REPEATABLE(/obj/machinery/librarycomp, PROC_REF(on_emag), null)
/obj/machinery/librarycomp/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if (src.density && !src.emagged)
		set_emagged(1)
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

/obj/machinery/libraryscanner/proc/interaction_insert_book(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	user.drop_item()
	held.forceMove(src)
	return TRUE

// TGUI migration. attack_hand opens LibraryScanner.tsx;
// scan/clear/eject move to tgui_act.
/obj/machinery/libraryscanner/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/libraryscanner)
	interface("LibraryScanner", title = "Scanner")
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("clear", ui_act("clear"), then(PROC_REF(ui_act_clear)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("insert_book", item(/obj/item/book), priority(OP_PRIORITY_DEFAULT - 1), label("Insert book"), then(PROC_REF(interaction_insert_book)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/// /obj/machinery/libraryscanner's window data.
/obj/machinery/libraryscanner/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["has_cache"] = !!cache()
	data["cache_name"] = cache() ? cache().name : ""
	var/has_book = FALSE
	FOR_REAL_CONTENTS(var/obj/item/book/B, src)
		has_book = TRUE
		break
	data["has_book"] = has_book
	return data

/obj/machinery/libraryscanner/proc/ui_act_scan(datum/act/op/A)
	var/mob/user = A.actor
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/book/B in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		rel_set(src, nameof(/datum/om/edge::cache), B)
		break
	add_fingerprint(user)
	return TRUE

/obj/machinery/libraryscanner/proc/ui_act_clear(datum/act/op/A)
	rel_clear(src, nameof(/datum/om/edge::cache))
	return TRUE

/obj/machinery/libraryscanner/proc/ui_act_eject(datum/act/op/A)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/book/B in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
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

CAPABILITIES(/obj/machinery/bookbinder)
	climb()
	op("bind", inputs(item(/obj/item/paper), item(/obj/item/paper_bundle)), priority(OP_PRIORITY_DEFAULT - 1), label("Bind"), then(PROC_REF(interaction_bind)))

/obj/machinery/bookbinder/proc/interaction_bind(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held, /obj/item/paper))
		user.drop_item()
		held.forceMove(src)
		act_message(user, src, MSG_SELF("You load some paper into %T%."), MSG_OTHERS("%U% loads some paper into %T%."))
		src.visible_message("[src] begins to hum as it warms up its printing drums.")
		after(src, rand(20 SECONDS, 40 SECONDS), PROC_REF(bind_paper), with = list(held))
	else
		user.drop_item()
		held.forceMove(src)
		act_message(user, src, MSG_SELF("You load some paper into %T%."), MSG_OTHERS("%U% loads some paper into %T%."))
		src.visible_message("[src] begins to hum as it warms up its printing drums.")
		after(src, rand(30 SECONDS, 50 SECONDS), PROC_REF(bind_bundle), with = list(held))
	return OP_OK

/obj/machinery/bookbinder/proc/bind_paper(obj/item/paper/source_paper)
	src.visible_message("[src] whirs as it prints and binds a new book.")
	var/obj/item/book/b = new(src.loc)
	b.dat = source_paper.info
	b.name = "Print Job #" + "[rand(100, 999)]"
	b.icon_state = "book[rand(1,7)]"
	consumed(source_paper, src)

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
	consumed(source_bundle, src)

/// Book scanner that will be used when uploading books to the Archive (a relation view: null once that is deleted).
/obj/machinery/librarycomp/proc/scanner() as /obj/machinery/libraryscanner
	return scanner

/// Last scanned book (a relation view: null once that is deleted).
/obj/machinery/libraryscanner/proc/cache() as /obj/item/book
	return cache

/obj/machinery/librarycomp/proc/apply_catalogue_answer(selected_action, value)
	switch(selected_action)
		if("editbook")
			buffer_book = sanitizeSafe(value)
		if("editmob")
			buffer_mob = value
		if("setauthor")
			if(value && scanner()?.cache())
				scanner().cache().author = value
		if("setcategory")
			if(value)
				upload_category = value

/datum/prompt/text/library_catalogue
	timeout = 0

/datum/prompt/text/library_catalogue/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/library_catalogue/book
	encode = FALSE

/datum/prompt/text/library_catalogue/recipient
	max_len = MAX_NAME_LEN
	name_text = TRUE

/datum/prompt/text/library_catalogue/recipient/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/text/library_catalogue/author

/datum/prompt/choice/library_catalogue_category
	choices = list("Fiction", "Non-Fiction", "Adult", "Reference", "Religion")
	timeout = 0

/obj/machinery/librarypubliccomp/proc/apply_search_answer(selected_action, value)
	switch(selected_action)
		if("settitle")
			if(value)
				title = value
		if("setauthor")
			if(value)
				author = value
		if("setcategory")
			category = value || "Any"

/datum/prompt/text/library_search_text
	timeout = 0

/datum/prompt/text/library_search_text/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/library_search_category
	choices = list("Any", "Fiction", "Non-Fiction", "Adult", "Reference", "Religion")
	timeout = 0

/datum/prompt/choice/library_upload
	question = "Are you certain you wish to upload this title to the Archive?"
	title = "Confirmation"
	choices = list("Confirm", "Abort")
	buttons = TRUE
	timeout = 0

/datum/prompt/number/library_order_id
	question = "Enter your order:"
	timeout = 0

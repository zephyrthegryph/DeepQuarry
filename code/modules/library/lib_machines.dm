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
/obj/machinery/librarypubliccomp/attack_hand(mob/user)
	user.set_machine(src)
	tgui_interact(user)

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

/obj/machinery/librarypubliccomp/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("settitle")
			var/newtitle = tgui_input_text(usr, "Enter a title to search for:", max_length = MAX_MESSAGE_LEN)
			if(newtitle)
				title = newtitle
			return TRUE
		if("setcategory")
			var/newcategory = tgui_input_list(usr, "Choose a category to search for:", "Category", list("Any", "Fiction", "Non-Fiction", "Adult", "Reference", "Religion"))
			if(!newcategory)
				newcategory = "Any"
			category = newcategory
			return TRUE
		if("setauthor")
			var/newauthor = tgui_input_text(usr, "Enter an author to search for:", max_length = MAX_MESSAGE_LEN)
			if(newauthor)
				author = newauthor
			return TRUE
		if("search")
			last_results = list()
			if(SSdbcore.IsConnected())
				var/datum/db_query/query
				// category == "Any" means no category filter; both branches use
				// LIKE parameters so user-supplied title/author cannot inject SQL.
				if(category == "Any")
					query = SSdbcore.NewQuery(
						"SELECT author, title, category, id FROM library WHERE author LIKE :author_pat AND title LIKE :title_pat",
						list("author_pat" = "%[author]%", "title_pat" = "%[title]%")
					)
				else
					query = SSdbcore.NewQuery(
						"SELECT author, title, category, id FROM library WHERE author LIKE :author_pat AND title LIKE :title_pat AND category = :category",
						list("author_pat" = "%[author]%", "title_pat" = "%[title]%", "category" = category)
					)
				query.Execute()
				while(query.NextRow())
					last_results += list(list(
						"author" = query.item[1],
						"title" = query.item[2],
						"category" = query.item[3],
						"id" = "[query.item[4]]",
					))
				qdel(query)
			SQLquery = null // cleared after search — no longer holds interpolated SQL
			screenstate = 1
			add_fingerprint(usr)
			return TRUE
		if("back")
			screenstate = 0
			return TRUE


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
	var/list/checkouts = list()
	var/list/inventory = list()
	var/checkoutperiod = 5 // In minutes
	var/obj/machinery/libraryscanner/scanner // Book scanner that will be used when uploading books to the Archive

	var/bibledelay = 0 // LOL NO SPAM (1 minute delay) -- Doohl

	var/static/list/all_books

	var/static/list/base_genre_books

	// TGUI: TRUE when the admin ghost view is active. Toggles the
	// External Archive table to show Delete buttons.
	var/is_admin_view = FALSE

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
			all_books[C.name] = C

		for(var/path in subtypesof(/obj/item/book/custom_library) - base_genre_books)
			var/obj/item/book/B = new path(null)
			all_books[B.title] = B

		for(var/path in subtypesof(/obj/item/book/bundle/custom_library) - base_genre_books)
			var/obj/item/book/M = new path(null)
			all_books[M.title] = M

// TGUI migration. attack_hand and attack_ghost open
// LibraryComp.tsx. The big browse-rendered switch and Topic dispatcher
// move to tgui_data + tgui_act. The legacy attack_hand body below is
// retained only for reference and is unreachable.
/obj/machinery/librarycomp/attack_hand(mob/user)
	user.set_machine(src)
	is_admin_view = FALSE
	tgui_interact(user)

/obj/machinery/librarycomp/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LibraryComp", "Book Inventory Management")
		ui.open()

/obj/machinery/librarycomp/tgui_state(mob/user)
	if(is_admin_view)
		return GLOB.tgui_always_state
	return ..()

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
	if(!scanner)
		for(var/obj/machinery/libraryscanner/S in range(9))
			scanner = S
			break
	data["has_scanner"] = !!scanner
	if(scanner?.cache)
		data["scanner_cache"] = list(
			"name" = scanner.cache.name,
			"author" = scanner.cache.author || "",
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
	if((screenstate == 8 || is_admin_view) && SSdbcore.IsConnected())
		// sortby is mapped to a fixed column literal at the query site, so ORDER BY
		// can never be injected even if the whitelist in tgui_act is ever bypassed.
		var/datum/db_query/query = SSdbcore.NewQuery("SELECT id, author, title, category FROM library ORDER BY [safe_sortby_column()]")
		query.Execute()
		while(query.NextRow())
			external += list(list(
				"id" = "[query.item[1]]",
				"author" = query.item[2],
				"title" = query.item[3],
				"category" = query.item[4],
			))
		qdel(query)
	data["external_archive"] = external
	return data

/obj/machinery/librarycomp/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("switchscreen")
			screenstate = text2num(params["screen"])
			return TRUE
		if("print_bible")
			if(!bibledelay)
				new /obj/item/storage/bible(src.loc)
				bibledelay = 1
				spawn(60)
					bibledelay = 0
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
			buffer_book = sanitizeSafe(tgui_input_text(usr, "Enter the book's title:", encode = FALSE))
			return TRUE
		if("editmob")
			buffer_mob = tgui_input_text(usr, "Enter the recipient's name:", null, null, MAX_NAME_LEN)
			return TRUE
		if("checkout")
			var/datum/borrowbook/b = new
			b.bookname = sanitizeSafe(buffer_book)
			b.mobname = sanitize(buffer_mob)
			b.getdate = world.time
			b.duedate = world.time + (checkoutperiod * 600)
			checkouts.Add(b)
			return TRUE
		if("checkin")
			var/datum/borrowbook/b = locate(params["ref"])
			if(b)
				checkouts.Remove(b)
			return TRUE
		if("delbook")
			var/obj/item/book/b = locate(params["ref"])
			if(b)
				inventory.Remove(b)
			return TRUE
		if("setauthor")
			var/newauthor = tgui_input_text(usr, "Enter the author's name:", "", "", MAX_MESSAGE_LEN)
			if(newauthor && scanner?.cache)
				scanner.cache.author = newauthor
			return TRUE
		if("setcategory")
			var/newcategory = tgui_input_list(usr, "Choose a category:", "Category", list("Fiction", "Non-Fiction", "Adult", "Reference", "Religion"))
			if(newcategory)
				upload_category = newcategory
			return TRUE
		if("upload")
			if(!scanner?.cache)
				return TRUE
			var/choice = tgui_alert(usr, "Are you certain you wish to upload this title to the Archive?", "Confirmation", list("Confirm", "Abort"))
			if(choice != "Confirm")
				return TRUE
			if(scanner.cache.unique)
				tgui_alert_async(usr, "This book has been rejected from the database. Aborting!")
				return TRUE
			if(!SSdbcore.IsConnected())
				tgui_alert_async(usr, "Connection to Archive has been severed. Aborting.")
				return TRUE
			var/datum/db_query/query = SSdbcore.NewQuery(
				"INSERT INTO library (author, title, content, category) VALUES (:author, :title, :content, :category)",
				list("author" = scanner.cache.author, "title" = scanner.cache.name, "content" = scanner.cache.dat, "category" = upload_category)
			)
			if(!query.Execute())
				to_chat(usr, query.ErrorMsg())
			else
				log_game("[usr.name]/[usr.key] has uploaded the book titled [scanner.cache.name], [length(scanner.cache.dat)] signs")
				tgui_alert_async(usr, "Upload Complete.")
			qdel(query)
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
			if(bibledelay)
				for(var/mob/V in hearers(src))
					V.show_message(span_infoplain(span_bold("[src]") + "'s monitor flashes, \"Printer unavailable. Please allow a short time before attempting to print.\""))
				return TRUE
			bibledelay = 1
			spawn(6)
				bibledelay = 0
			var/datum/db_query/query = SSdbcore.NewQuery(
				"SELECT id, author, title, content FROM library WHERE id = :id",
				list("id" = numeric_id)
			)
			query.Execute()
			while(query.NextRow())
				var/book_author = query.item[2]
				var/book_title = query.item[3]
				var/content = query.item[4]
				var/obj/item/book/B = new(src.loc)
				B.name = "Book: [book_title]"
				B.title = book_title
				B.author = book_author
				B.dat = content
				B.icon_state = "book[rand(1,16)]"
				B.item_state = B.icon_state
				visible_message("[src]'s printer hums as it produces a completely bound book. How did it do that?")
				break
			qdel(query)
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
			var/datum/db_query/query = SSdbcore.NewQuery(
				"DELETE FROM library WHERE id = :id",
				list("id" = numeric_id)
			)
			query.Execute()
			log_admin("[usr.key] has deleted library book id=[numeric_id]")
			qdel(query)
			return TRUE
		if("orderbyid")
			var/orderid = tgui_input_number(usr, "Enter your order:")
			if(orderid && isnum(orderid))
				tgui_act("targetid", list("id" = "[orderid]"))
			return TRUE
		if("sort")
			var/field = params["field"]
			if(field in list("author", "title", "category"))
				sortby = field
			return TRUE
		if("hardprint")
			var/newpath = text2path(params["path"])
			if(!ispath(newpath, /obj/item/book))
				return TRUE
			var/obj/item/book/NewBook = new newpath(get_turf(src))
			NewBook.name = "Book: [NewBook.name]"
			return TRUE

// admin ghost view routes to LibraryComp.tsx with is_admin_view
// set; non-admin ghosts fall through to default handling.
/obj/machinery/librarycomp/attack_ghost(mob/user)
	if(!check_rights(R_ADMIN, show_msg = FALSE))
		return ..()
	user.set_machine(src)
	is_admin_view = TRUE
	screenstate = 8
	tgui_interact(user)

/obj/machinery/librarycomp/emag_act(remaining_charges, mob/user)
	if (src.density && !src.emagged)
		src.emagged = 1
		return 1

/obj/machinery/librarycomp/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/barcodescanner))
		var/obj/item/barcodescanner/scanner = W
		scanner.computer = src
		to_chat(user, "[scanner]'s associated machine has been set to [src].")
		for (var/mob/V in hearers(src))
			V.show_message("[src] lets out a low, short blip.", 2)
	else
		..()

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
	var/obj/item/book/cache		// Last scanned book

/obj/machinery/libraryscanner/attackby(obj/O, mob/user)
	if(istype(O, /obj/item/book))
		user.drop_item()
		O.loc = src

// TGUI migration. attack_hand opens LibraryScanner.tsx;
// scan/clear/eject move to tgui_act.
/obj/machinery/libraryscanner/attack_hand(mob/user)
	user.set_machine(src)
	tgui_interact(user)

/obj/machinery/libraryscanner/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LibraryScanner", "Scanner")
		ui.open()

/obj/machinery/libraryscanner/tgui_data(mob/user)
	var/list/data = list()
	data["has_cache"] = !!cache
	data["cache_name"] = cache ? cache.name : ""
	var/has_book = FALSE
	for(var/obj/item/book/B in contents)
		has_book = TRUE
		break
	data["has_book"] = has_book
	return data

/obj/machinery/libraryscanner/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("scan")
			for(var/obj/item/book/B in contents)
				cache = B
				break
			add_fingerprint(usr)
			return TRUE
		if("clear")
			cache = null
			return TRUE
		if("eject")
			for(var/obj/item/book/B in contents)
				B.loc = src.loc
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
	AddElement(/datum/element/climbable)

/obj/machinery/bookbinder/attackby(obj/O as obj, mob/user as mob)
	if(istype(O, /obj/item/paper) || istype(O, /obj/item/paper_bundle))
		if(istype(O, /obj/item/paper))
			user.drop_item()
			O.loc = src
			user.visible_message("[user] loads some paper into [src].", "You load some paper into [src].")
			src.visible_message("[src] begins to hum as it warms up its printing drums.")
			sleep(rand(200,400))
			src.visible_message("[src] whirs as it prints and binds a new book.")
			var/obj/item/book/b = new(src.loc)
			var/obj/item/paper/source_paper = O
			b.dat = source_paper.info
			b.name = "Print Job #" + "[rand(100, 999)]"
			b.icon_state = "book[rand(1,7)]"
			qdel(O)
		else
			user.drop_item()
			O.loc = src
			user.visible_message("[user] loads some paper into [src].", "You load some paper into [src].")
			src.visible_message("[src] begins to hum as it warms up its printing drums.")
			sleep(rand(300,500))
			src.visible_message("[src] whirs as it prints and binds a new book.")
			var/obj/item/book/bundle/b = new(src.loc)
			var/obj/item/paper_bundle/source_bundle = O
			b.pages = source_bundle.pages
			for(var/obj/item/paper/P in O.contents)
				P.forceMove(b)
			for(var/obj/item/photo/P in O.contents)
				P.forceMove(b)
			b.name = "Print Job #" + "[rand(100, 999)]"
			b.icon_state = "book[rand(1,7)]"
			qdel(O)
	else
		..()

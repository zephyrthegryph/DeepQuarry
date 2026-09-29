/* Library Items
 *
 * Contains:
 *		Bookcase
 *		Book
 *		Barcode Scanner
 */


/*
 * Bookcase
 */

/obj/structure/bookcase
	name = "bookcase"
	desc = "A set of wooden shelves, perfect for placing books on."
	icon = 'icons/obj/library.dmi'
	icon_state = "book-0"
	anchored = TRUE
	density = TRUE
	opacity = 1

/obj/structure/bookcase/Initialize(mapload)
	. = ..()
	for(var/obj/item/I in contents_of(loc))
		if(istype(I, /obj/item/book))
			I.forceMove(src)
	update_icon()
	make_climbable()

/// Old attackby.
/obj/structure/bookcase/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/book))
		user.drop_item()
		O.forceMove(src)
		update_icon()
	else if(istype(O, /obj/item/pen))
		var/_answer_k37 = rerun_ask(user, "k37", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "What would you like to title this bookshelf?", max_length = MAX_NAME_LEN, encode = FALSE)
		if(isnull(_answer_k37))
			return TRUE
		var/newname = sanitizeSafe(_answer_k37, MAX_NAME_LEN)
		if(!newname)
			return INTERACTION_HANDLED_PASS
		else
			name = ("bookcase ([newname])")
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/structure/bookcase/wrench_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 100, 1)
	to_chat(user, anchored ? span_notice("You unfasten \the [src] from the floor.") : span_notice("You secure \the [src] to the floor."))
	set_anchored(!anchored)
	return ITEM_INTERACT_SUCCESS

/obj/structure/bookcase/screwdriver_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 2.5 SECONDS, volume = 75, message_self = "You begin dismantling \the [src].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/bookcase/proc/screwdriver_act_tool_done(mob/user)
	to_chat(user, span_notice("You dismantle \the [src]."))
	new /obj/item/stack/material/wood(get_turf(src), 3)
	for(var/obj/item/book/book in contents)
		book.forceMove(get_turf(src))
	qdel(src)
	return ITEM_INTERACT_SUCCESS

DECLARE_INTERACTIONS(/obj/structure/bookcase, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/structure/bookcase/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(contents_count(src))
		var/obj/item/book/choice = rerun_ask(user, "k65", PROC_REF(interaction_hand), args, /datum/om/prompt/choice, message = "Which book would you like to remove from the shelf?", title = "Book Selection", choices = contents)
		if(isnull(choice))
			return TRUE
		if(choice)
			if(!user.canmove || user.stat || user.restrained() || !in_range(loc, user))
				return TRUE
			if(ishuman(user))
				if(!user.get_active_hand())
					user.put_in_hands(choice)
			else
				choice.forceMove(get_turf(src))
			update_icon()
	return TRUE

/obj/structure/bookcase/explosion_contents_severity(severity)
	return severity

/obj/structure/bookcase/atom_destruction(damage_flag)
	for(var/obj/item/book/b in contents)
		b.forceMove(loc)
	return ..()

/obj/structure/bookcase/update_icon()
	if(contents_count(src) < 5)
		icon_state = "book-[contents.len]"
	else
		icon_state = "book-5"

/*
Book Cart
*/

/obj/structure/bookcase/bookcart
	name = "book cart"
	icon = 'icons/obj/library.dmi'
	icon_state = "bookcart-0"
	anchored = FALSE
	opacity = 0

EXTEND_INTERACTIONS(/obj/structure/bookcase/bookcart, INTERACT_ITEM(null, PROC_REF(bookcart_interaction_item)))

/// Old attackby.
/obj/structure/bookcase/bookcart/proc/bookcart_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/book))
		user.drop_item()
		O.forceMove(src)
		update_icon()
	else
		return INTERACTION_HANDLED_PASS
	return INTERACTION_HANDLED_PASS

/obj/structure/bookcase/bookcart/update_icon()
	if(contents_count(src) < 5)
		icon_state = "bookcart-[contents.len]"
	else
		icon_state = "bookcart-5"

/*
Book Cart End
*/

/obj/structure/bookcase/manuals/medical
	name = "Medical Manuals bookcase"

/obj/structure/bookcase/manuals/medical/Initialize(mapload)
	new /obj/item/book/manual/medical_cloning(src)
	new /obj/item/book/manual/wiki/medical_diagnostics_manual(src)
	new /obj/item/book/manual/wiki/medical_diagnostics_manual(src)
	new /obj/item/book/manual/wiki/medical_diagnostics_manual(src)
	. = ..()


/obj/structure/bookcase/manuals/engineering
	name = "Engineering Manuals bookcase"

/obj/structure/bookcase/manuals/engineering/Initialize(mapload)
	new /obj/item/book/manual/wiki/engineering_construction(src)
	new /obj/item/book/manual/engineering_particle_accelerator(src)
	new /obj/item/book/manual/wiki/engineering_hacking(src)
	new /obj/item/book/manual/wiki/engineering_guide(src)
	new /obj/item/book/manual/atmospipes(src)
	new /obj/item/book/manual/engineering_singularity_safety(src)
	new /obj/item/book/manual/evaguide(src)
	. = ..()

/obj/structure/bookcase/manuals/research_and_development
	name = "R&D Manuals bookcase"

/obj/structure/bookcase/manuals/research_and_development/Initialize(mapload)
	new /obj/item/book/manual/research_and_development(src)
	. = ..()


/*
 * Book
 */
/obj/item/book
	name = "book"
	icon = 'icons/obj/library.dmi'
	icon_state ="book"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_books.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_books.dmi'
		)
	item_state = "book"
	throw_speed = 1
	throw_range = 5
	flags = NOCONDUCT
	w_class = ITEMSIZE_NORMAL		 //upped to three because books are, y'know, pretty big. (and you could hide them inside eachother recursively forever)
	attack_verb = list("bashed", "whacked", "educated")
	var/dat			 // Actual page content
	var/due_date = 0 // Game time in 1/10th seconds
	var/author		 // Who wrote the thing, can be changed by pen or PC. It is not automatically assigned
	var/libcategory = "Miscellaneous"	// The library category this book sits in. "Fiction", "Non-Fiction", "Adult", "Reference", "Religion"
	var/unique = 0   // 0 - Normal book, 1 - Should not be treated as normal book, unable to be copied, unable to be modified
	var/title		 // The real name of the book.
	var/carved = 0	 // Has the book been hollowed out for use as a secret storage item?
	var/tmp/store_handle	//What's in the book?
	var/occult_tier = 0 //If the book is an occult book or not and how strong it is. Used for attack_self
	///Var for attack_self chain
	var/special_handling = FALSE
	drop_sound = 'sound/items/drop/book.ogg'
	pickup_sound = 'sound/items/pickup/book.ogg'
	resistance_flags = FLAMMABLE

/// Old attack_self: read the book. Occult and specially handled books leave it to their own self-use.
/obj/item/book/proc/interaction_read(mob/user, obj/item/held, datum/interaction/interaction)
	if(occult_tier)
		return FALSE
	if(special_handling)
		return FALSE
	if(carved)
		if(store())
			to_chat(user, span_notice("[store()] falls out of [title]!"))
			store().forceMove(get_turf(src.loc))
			store_handle = null
			return TRUE
		else
			to_chat(user, span_notice("The pages of [title] have been cut out!"))
			return TRUE
	if(dat)
		display_content(user)
		user.visible_message("[user] opens a book titled \"[src.title]\" and begins reading intently.")
		playsound(src, 'sound/bureaucracy/bookopen.ogg', 50, 1)
		// onclose() was for the legacy "book" browse() window
		// that no longer exists (books are TGUI now).
		playsound(src, 'sound/bureaucracy/bookclose.ogg', 50, 1)
	else
		to_chat(user, "This book is completely blank!")
	return TRUE

// TGUI migration. display_content now opens Book.tsx,
// which renders the book's HTML content with a "Penned by [author]"
// preamble.
/obj/item/book/proc/display_content(mob/living/user)
	tgui_interact(user)

/obj/item/book/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Book", title || name)
		ui.open()

/obj/item/book/tgui_data(mob/user)
	var/list/data = list()
	data["title"] = title || name
	data["author"] = author || ""
	data["content"] = dat || ""
	return data

DECLARE_INTERACTIONS(/obj/item/book, \
	INTERACT_SELF("Read", PROC_REF(interaction_read)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attackby.
/obj/item/book/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(carved)
		if(!store())
			if(W.w_class < ITEMSIZE_LARGE)
				user.drop_item()
				W.forceMove(src)
				store_handle = om_handle(W)
				to_chat(user, span_notice("You put [W] in [title]."))
				return INTERACTION_HANDLED_PASS
			else
				to_chat(user, span_notice("[W] won't fit in [title]."))
				return INTERACTION_HANDLED_PASS
		else
			to_chat(user, span_notice("There's already something in [title]!"))
			return INTERACTION_HANDLED_PASS
	if(istype(W, /obj/item/pen))
		if(unique)
			to_chat(user, "These pages don't seem to take the ink well. Looks like you can't modify it.")
			return INTERACTION_HANDLED_PASS
		var/choice = rerun_ask(user, "k248", PROC_REF(interaction_item), args, /datum/om/prompt/choice, message = "What would you like to change?", title = "Change What?", choices = list("Title", "Contents", "Author", "Cancel"))
		if(isnull(choice))
			return TRUE
		switch(choice)
			if("Title")
				var/_answer_k251 = rerun_ask(user, "k251", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Write a new title:", encode = FALSE)
				if(isnull(_answer_k251))
					return TRUE
				var/newtitle = reject_bad_text(sanitizeSafe(_answer_k251))
				if(!newtitle)
					to_chat(user, "The title is invalid.")
					return INTERACTION_HANDLED_PASS
				else
					src.name = newtitle
					src.title = newtitle
			if("Contents")
				var/content = rerun_ask(user, "k259", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Write your book's contents (HTML NOT allowed):", max_length = MAX_BOOK_MESSAGE_LEN, multiline = TRUE)
				if(isnull(content))
					return TRUE
				if(!content)
					to_chat(user, "The content is invalid.")
					return INTERACTION_HANDLED_PASS
				else
					src.dat += content
			if("Author")
				var/newauthor = rerun_ask(user, "k266", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Write the author's name:", max_length = MAX_LNAME_LEN)
				if(isnull(newauthor))
					return TRUE
				if(!newauthor)
					to_chat(user, "The name is invalid.")
					return INTERACTION_HANDLED_PASS
				else
					src.author = newauthor
			else
				return INTERACTION_HANDLED_PASS
	else if(istype(W, /obj/item/barcodescanner))
		var/obj/item/barcodescanner/scanner = W
		if(!scanner.computer())
			to_chat(user, "[W]'s screen flashes: 'No associated computer found!'")
		else
			switch(scanner.mode)
				if(0)
					scanner.book_handle = om_handle(src)
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer.'")
				if(1)
					scanner.book_handle = om_handle(src)
					scanner.computer().buffer_book = src.name
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Book title stored in associated computer buffer.'")
				if(2)
					scanner.book_handle = om_handle(src)
					for(var/datum/borrowbook/b in scanner.computer().checkouts)
						if(b.bookname == src.name)
							LAZYREMOVE(scanner.computer().checkouts, b)
							to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Book has been checked in.'")
							return INTERACTION_HANDLED_PASS
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. No active check-out record found for current title.'")
				if(3)
					scanner.book_handle = om_handle(src)
					for(var/obj/item/book in scanner.computer().inventory)
						if(book == src)
							to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Title already present in inventory, aborting to avoid duplicate entry.'")
							return INTERACTION_HANDLED_PASS
					LAZYADD(scanner.computer().inventory, src)
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Title added to general inventory.'")
	else if(istype(W, /obj/item/material/knife))
		return carve_pages(user)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/book/wirecutter_act(mob/user, obj/item/tool)
	return carve_pages(user) ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING

/obj/item/book/proc/carve_pages(mob/user)
	if(carved)
		return FALSE
	to_chat(user, span_notice("You begin to carve out [title]."))
	om_task_timed(user, 3 SECONDS, src, src, PROC_REF(carve_done), list(user))
	return TRUE

/obj/item/book/proc/carve_done(mob/user)
	if(carved)
		return
	to_chat(user, span_notice("You carve out the pages from [title]! You didn't want to read it anyway."))
	playsound(src, 'sound/bureaucracy/papercrumple.ogg', 50, 1)
	new /obj/item/shreddedp(get_turf(src))
	carved = TRUE

/obj/item/book/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(user.zone_sel.selecting == O_EYES)
		user.visible_message(span_notice("You open up the book and show it to [M]."), \
			span_notice(" [user] opens up a book and shows it to [M]."))
		display_content(M)
		user.setClickCooldown(DEFAULT_QUICK_COOLDOWN) //to prevent spam
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

/*
* Book Bundle (Multi-page book)
*/

/obj/item/book/bundle
	var/page = 1 //current page
	// ALLOW(instance_list): d: a bundle holds pages
	var/list/pages = list() //the contents of each page
	special_handling = TRUE

// TGUI migration. show_content now opens BookBundle.tsx;
// Topic page-flip moves to tgui_act. Photo image embedding via
// browse_rsc is not yet wired through TGUI assets.
/obj/item/book/bundle/proc/show_content(mob/user)
	tgui_interact(user)

EXTEND_INTERACTIONS(/obj/item/book/bundle, INTERACT_USE("Read", PROC_REF(interaction_read_bundle)))

/// Old attack_self.
/obj/item/book/bundle/proc/interaction_read_bundle(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	update_icon()
	tgui_interact(user)

/obj/item/book/bundle/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BookBundle", name)
		ui.open()

/obj/item/book/bundle/tgui_data(mob/user)
	var/list/data = list()
	data["page"] = page
	data["total_pages"] = pages.len
	data["scribble"] = ""
	if(pages.len)
		var/obj/item/W = pages[page]
		if(istype(W, /obj/item/paper))
			var/obj/item/paper/P = W
			data["page_name"] = P.name
			data["page_kind"] = "paper"
			var/info = (ishuman(user) || isobserver(user) || issilicon(user)) ? P.info : stars(P.info)
			data["page_info"] = "[info][P.stamps]"
		else if(istype(W, /obj/item/photo))
			var/obj/item/photo/P = W
			data["page_name"] = P.name
			data["page_kind"] = "photo"
			data["page_info"] = ""
			data["scribble"] = P.scribble || ""
		else if(!isnull(pages[page]))
			data["page_name"] = "Page [page]"
			data["page_kind"] = "text"
			var/text = pages[page]
			data["page_info"] = (ishuman(user) || isobserver(user) || issilicon(user)) ? "[text]" : stars("[text]")
		else
			data["page_name"] = "Page [page]"
			data["page_kind"] = "text"
			data["page_info"] = ""
	else
		data["page_name"] = name
		data["page_kind"] = "text"
		data["page_info"] = ""
	return data

/obj/item/book/bundle/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(!((is_in_holder(src, usr)) || (istype(src.loc, /obj/item/folder) && (is_in_holder(src.loc, usr)))))
		to_chat(usr, span_notice("You need to hold it in your hands!"))
		return TRUE
	usr.set_machine(src)
	switch(action)
		if("next_page")
			if(page != pages.len)
				page++
				playsound(src, "pageturn", 50, 1)
			return TRUE
		if("prev_page")
			if(page > 1)
				page--
				playsound(src, "pageturn", 50, 1)
			return TRUE

/*
 * Barcode Scanner
 */
/obj/item/barcodescanner
	name = "barcode scanner"
	icon = 'icons/obj/library.dmi'
	icon_state ="scanner"
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	var/tmp/computer_handle	// Associated computer - Modes 1 to 3 use this
	var/tmp/book_handle	//  Currently scanned book
	var/mode = 0 					// 0 - Scan only, 1 - Scan and Set Buffer, 2 - Scan and Attempt to Check In, 3 - Scan and Attempt to Add to Inventory

DECLARE_INTERACTIONS(/obj/item/barcodescanner, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/barcodescanner/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	mode += 1
	if(mode > 3)
		mode = 0
	to_chat(user, "[src] Status Display:")
	var/modedesc
	switch(mode)
		if(0)
			modedesc = "Scan book to local buffer."
		if(1)
			modedesc = "Scan book to local buffer and set associated computer buffer to match."
		if(2)
			modedesc = "Scan book to local buffer, attempt to check in scanned book."
		if(3)
			modedesc = "Scan book to local buffer, attempt to add book to general inventory."
		else
			modedesc = "ERROR"
	to_chat(user, " - Mode [mode] : [modedesc]")
	if(src.computer())
		to_chat(user, span_green("Computer has been associated with this unit."))
	else
		to_chat(user, span_red("No associated computer found. Only local scans will function properly."))
	to_chat(user, "\n")
	return TRUE

/// LC-refs: What's in the book? -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/book/proc/store() as /obj/item
	return om_resolve(store_handle)

/// LC-refs: Associated computer - Modes 1 to 3 use this -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/barcodescanner/proc/computer() as /obj/machinery/librarycomp
	return om_resolve(computer_handle)

/// LC-refs: Currently scanned book -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/barcodescanner/proc/book() as /obj/item/book
	return om_resolve(book_handle)

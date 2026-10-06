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

CAPABILITIES(/obj/structure/bookcase)
	blast_contents()
	climb()
	op("take_book", hand(), ungated(),
		asks(/datum/prompt/choice, fields = list("question" = "Which book would you like to remove from the shelf?", "title" = "Book Selection", "choices" = computed(PROC_REF(shelved_books)), "timeout" = 0), step = "k65", when = PROC_REF(has_books)),
		then(PROC_REF(interaction_hand)))
	op("shelve", item(/obj/item/book), then(PROC_REF(shelve_book)))
	op("title_shelf", item(/obj/item/pen),
		asks(/datum/prompt/text, fields = list("question" = "What would you like to title this bookshelf?", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "k37"),
		then(PROC_REF(title_shelf)))

// ALLOW(init/INSTANCE_STATE): gathers the books the map placed on its tile
/obj/structure/bookcase/Initialize(mapload)
	. = ..()
	for(var/obj/item/I in contents_of(loc))
		if(istype(I, /obj/item/book))
			I.forceMove(src)

/// Old attackby: a book goes on the shelf (the click goes on).
/obj/structure/bookcase/proc/shelve_book(datum/act/op/A)
	var/mob/user = A.actor
	user.drop_item()
	A.held.forceMove(src)
	return OP_PASS

/// Old attackby: a pen names the shelf with the answered title (the click goes on).
/obj/structure/bookcase/proc/title_shelf(datum/act/op/A)
	var/newname = sanitizeSafe(A.step_value("k37"), MAX_NAME_LEN)
	if(newname)
		name = ("bookcase ([newname])")
	return OP_PASS

/obj/structure/bookcase/wrench_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 100, 1)
	to_chat(user, anchored ? span_notice("You unfasten \the [src] from the floor.") : span_notice("You secure \the [src] to the floor."))
	set_anchored(!anchored)
	return ITEM_INTERACT_SUCCESS

/obj/structure/bookcase/screwdriver_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 2.5 SECONDS, volume = 75, start_self = "You begin dismantling \the [src].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/bookcase/proc/screwdriver_act_tool_done(mob/user)
	to_chat(user, span_notice("You dismantle \the [src]."))
	new /obj/item/stack/material/wood(get_turf(src), 3)
	for(var/obj/item/book/book in contents)
		book.forceMove(get_turf(src))
	consume(src, user)
	return ITEM_INTERACT_SUCCESS

/// The question is asked only while there are books on the shelf.
/obj/structure/bookcase/proc/has_books(datum/act/op/A)
	return length(contents) > 0 // ALLOW(reads, spatial): the shelf's books are read when it is reached into, never cached; a plain count of its own contents

/obj/structure/bookcase/proc/shelved_books(datum/act/op/A)
	return contents_of(src)

/// Old attack_hand: take the picked book.
/obj/structure/bookcase/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/book/choice = A.step_value("k65")
	if(choice)
		if(choice.loc == src)
			if(!user.canmove || user.stat || user.restrained() || !in_range(loc, user))
				return TRUE
			if(ishuman(user))
				if(!user.get_active_hand())
					user.put_in_hands(choice)
			else
				choice.forceMove(get_turf(src))
	return TRUE

/obj/structure/bookcase/atom_destruction(damage_flag)
	for(var/obj/item/book/b in contents)
		b.forceMove(loc)
	return ..()

/obj/structure/bookcase/proc/appearance_books()
	return min(contents_count(src), 5)

/// The look (the draw sweep: from its template).
/obj/structure/bookcase/draw(datum/look/look)
	..()
	look.state("book-[appearance_books()]")

/*
Book Cart
*/

/obj/structure/bookcase/bookcart
	name = "book cart"
	icon = 'icons/obj/library.dmi'
	icon_state = "bookcart-0"
	anchored = FALSE
	opacity = 0

CAPABILITIES(/obj/structure/bookcase/bookcart)
	op("bookcart_interaction_item", item(/obj/item), then(PROC_REF(bookcart_interaction_item)))

/// Old attackby.
/obj/structure/bookcase/bookcart/proc/bookcart_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/book))
		user.drop_item()
		O.forceMove(src)
	else
		return OP_PASS
	return OP_PASS

/// The look (the draw sweep: from its template).
/obj/structure/bookcase/bookcart/draw(datum/look/look)
	..()
	look.state("bookcart-[appearance_books()]")

/*
Book Cart End
*/

/obj/structure/bookcase/manuals/medical
	name = "Medical Manuals bookcase"

CAPABILITIES(/obj/structure/bookcase/manuals/medical)
	initial_contents(/obj/item/book/manual/medical_cloning)
	initial_contents(/obj/item/book/manual/wiki/medical_diagnostics_manual, count = 3)

/obj/structure/bookcase/manuals/engineering
	name = "Engineering Manuals bookcase"

CAPABILITIES(/obj/structure/bookcase/manuals/engineering)
	initial_contents(/obj/item/book/manual/wiki/engineering_construction)
	initial_contents(/obj/item/book/manual/engineering_particle_accelerator)
	initial_contents(/obj/item/book/manual/wiki/engineering_hacking)
	initial_contents(/obj/item/book/manual/wiki/engineering_guide)
	initial_contents(/obj/item/book/manual/atmospipes)
	initial_contents(/obj/item/book/manual/engineering_singularity_safety)
	initial_contents(/obj/item/book/manual/evaguide)

/obj/structure/bookcase/manuals/research_and_development
	name = "R&D Manuals bookcase"

CAPABILITIES(/obj/structure/bookcase/manuals/research_and_development)
	initial_contents(/obj/item/book/manual/research_and_development)

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
	var/tmp/obj/item/store	//What's in the book?
	var/occult_tier = 0 //If the book is an occult book or not and how strong it is. Used for attack_self
	///Var for attack_self chain
	var/special_handling = FALSE
	drop_sound = SFX_ITEMS_DROP_BOOK
	pickup_sound = SFX_ITEMS_PICKUP_BOOK
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
			rel_clear(src, nameof(store))
			return TRUE
		else
			to_chat(user, span_notice("The pages of [title] have been cut out!"))
			return TRUE
	if(dat)
		display_content(user)
		act_message(user, null, others = "%U% opens a book titled \"[src.title]\" and begins reading intently.")
		play_sfx(src, SFX_BUREAUCRACY_BOOKOPEN)
		// onclose() was for the legacy "book" browse() window
		// that no longer exists (books are TGUI now).
		play_sfx(src, SFX_BUREAUCRACY_BOOKCLOSE)
	else
		to_chat(user, "This book is completely blank!")
	return TRUE

// TGUI migration. display_content now opens Book.tsx,
// which renders the book's HTML content with a "Penned by [author]"
// preamble.
/obj/item/book/proc/display_content(mob/living/user)
	tgui_interact(user)

CAPABILITIES(/obj/item/book)
	interface("Book")
	without("ui_open")
	ui_shape(title = bool(), author = bool(), content = bool())

/// The guard every window button of the family asks first (a subtype overrides it).
/obj/item/book/proc/ui_gate(datum/act/op/A)
	return TRUE

/obj/item/book/ui_title(mob/user)
	return title || name

/// /obj/item/book's window data.
/obj/item/book/ui_data(datum/act/eval/A)
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
				rel_set(src, nameof(store), W)
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
					rel_set(scanner, nameof(scanner.book), src)
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer.'")
				if(1)
					rel_set(scanner, nameof(scanner.book), src)
					scanner.computer().buffer_book = src.name
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Book title stored in associated computer buffer.'")
				if(2)
					rel_set(scanner, nameof(scanner.book), src)
					for(var/datum/borrowbook/b in scanner.computer().checkouts)
						if(b.bookname == src.name)
							own_remove(scanner.computer(), nameof(/obj/machinery/librarycomp::checkouts), b)
							to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Book has been checked in.'")
							return INTERACTION_HANDLED_PASS
					to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. No active check-out record found for current title.'")
				if(3)
					rel_set(scanner, nameof(scanner.book), src)
					for(var/obj/item/book in scanner.computer().inventory)
						if(book == src)
							to_chat(user, "[W]'s screen flashes: 'Book stored in buffer. Title already present in inventory, aborting to avoid duplicate entry.'")
							return INTERACTION_HANDLED_PASS
					rel_add(scanner.computer(), nameof(/obj/machinery/librarycomp::inventory), src)
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
	play_sfx(src, SFX_BUREAUCRACY_PAPERCRUMPLE)
	new /obj/item/shreddedp(get_turf(src))
	carved = TRUE

/obj/item/book/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(user.zone_sel.selecting == O_EYES)
		act_message(user, M, MSG_SELF(span_notice(" %U% opens up a book and shows it to %T%.")), \
			MSG_OTHERS(span_notice("You open up the book and show it to %T%.")))
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

CAPABILITIES(/obj/item/book/bundle)
	op("read_bundle", in_hand(), label("Read"), then(PROC_REF(interaction_read_bundle)))
	interface("BookBundle")
	without("ui_open")
	op("next_page", ui_act("next_page"), then(PROC_REF(ui_act_next_page)))
	op("prev_page", ui_act("prev_page"), then(PROC_REF(ui_act_prev_page)))

/// Old attack_self.
/obj/item/book/bundle/proc/interaction_read_bundle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	tgui_interact(user)

/obj/item/book/bundle/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["page"] = page
	var/list/merged_1 = ui_data_obj_item_book_bundle(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/book/bundle's window data.
/obj/item/book/bundle/proc/ui_data_obj_item_book_bundle(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
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

/obj/item/book/bundle/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!..())
		return FALSE
	if(!((is_in_holder(src, user)) || (istype(src.loc, /obj/item/folder) && (is_in_holder(src.loc, user)))))
		to_chat(user, span_notice("You need to hold it in your hands!"))
		return FALSE
	user.set_machine(src)
	return TRUE

/obj/item/book/bundle/proc/ui_act_next_page(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(page != pages.len)
		page++
		play_sfx(src, SFX_PAGETURN)
	return TRUE

/obj/item/book/bundle/proc/ui_act_prev_page(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(page > 1)
		page--
		play_sfx(src, SFX_PAGETURN)
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
	var/tmp/obj/machinery/librarycomp/computer	// Associated computer - Modes 1 to 3 use this
	var/tmp/obj/item/book/book	//  Currently scanned book
	var/mode = 0 					// 0 - Scan only, 1 - Scan and Set Buffer, 2 - Scan and Attempt to Check In, 3 - Scan and Attempt to Add to Inventory

CAPABILITIES(/obj/item/barcodescanner)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/barcodescanner/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
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

/// What's in the book? (a relation view: null once that is deleted).
/obj/item/book/proc/store() as /obj/item
	return store

/// Associated computer - Modes 1 to 3 use this (a relation view: null once that is deleted).
/obj/item/barcodescanner/proc/computer() as /obj/machinery/librarycomp
	return computer

/// Currently scanned book (a relation view: null once that is deleted).
/obj/item/barcodescanner/proc/book() as /obj/item/book
	return book

/obj/item/clipboard
	name = "clipboard"
	desc = "Used to clip paper to, for an on-the-go writing board."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "clipboard"
	item_state = "clipboard"
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	throw_speed = 3
	throw_range = 10
	var/obj/item/pen/haspen		//The stored pen.
	var/obj/item/toppaper	//The topmost piece of paper.
	slot_flags = SLOT_BELT

/obj/item/clipboard/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/clipboard/MouseDrop(obj/over_object as obj) //Quick clipboard fix. -Agouri
	if(ishuman(usr))
		var/mob/M = usr
		if(!(istype(over_object, /atom/movable/screen) ))
			return ..()

		if(!M.restrained() && !M.stat)
			switch(over_object.name)
				if("r_hand")
					M.unEquip(src)
					M.put_in_r_hand(src)
				if("l_hand")
					M.unEquip(src)
					M.put_in_l_hand(src)

			add_fingerprint(usr)
			return

/obj/item/clipboard/update_icon()
	cut_overlays()
	if(toppaper)
		add_overlay(toppaper.icon_state)
		add_overlay(toppaper.overlays)
	if(haspen)
		add_overlay("clipboard_pen")
	add_overlay("clipboard_over")
	return

/obj/item/clipboard/attackby(obj/item/W, mob/user)

	if(istype(W, /obj/item/paper) || istype(W, /obj/item/photo))
		user.drop_item()
		W.loc = src
		if(istype(W, /obj/item/paper))
			toppaper = W
		to_chat(user, span_notice("You clip the [W] onto \the [src]."))
		update_icon()

	else if(istype(toppaper) && istype(W, /obj/item/pen))
		toppaper.attackby(W, user)
		update_icon()

	return

/obj/item/clipboard/afterattack(turf/T as turf, mob/user)
	for(var/obj/item/paper/P in T)
		P.loc = src
		toppaper = P
		update_icon()
		to_chat(user, span_notice("You clip the [P] onto \the [src]."))

// TGUI migration. attack_self opens Clipboard.tsx; the
// Topic pen/write/remove/rename/read/look actions move to tgui_act.
// Reading a paper/photo chains to that item's TGUI viewer
// (Paper.tsx / Photo.tsx).
/obj/item/clipboard/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	add_fingerprint(user)
	tgui_interact(user)

/obj/item/clipboard/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Clipboard", "Clipboard")
		ui.open()

/obj/item/clipboard/tgui_data(mob/user)
	var/list/data = list()
	data["has_pen"] = !!haspen
	var/list/items = list()
	// Top paper first so React can render it at the head of the list.
	if(toppaper)
		items += list(list(
			"ref" = "\ref[toppaper]",
			"name" = toppaper.name,
			"kind" = "paper",
			"is_top" = TRUE,
		))
	for(var/obj/item/paper/P in src)
		if(P == toppaper)
			continue
		items += list(list(
			"ref" = "\ref[P]",
			"name" = P.name,
			"kind" = "paper",
			"is_top" = FALSE,
		))
	for(var/obj/item/photo/Ph in src)
		items += list(list(
			"ref" = "\ref[Ph]",
			"name" = Ph.name,
			"kind" = "photo",
			"is_top" = FALSE,
		))
	data["items"] = items
	return data

/obj/item/clipboard/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(usr.stat || usr.restrained() || loc != usr)
		return TRUE
	switch(action)
		if("remove_pen")
			if(haspen && haspen.loc == src)
				haspen.loc = usr.loc
				usr.put_in_hands(haspen)
				haspen = null
				update_icon()
			return TRUE
		if("add_pen")
			if(!haspen)
				var/obj/item/pen/W = usr.get_active_hand()
				if(istype(W, /obj/item/pen))
					usr.drop_item()
					W.loc = src
					haspen = W
					to_chat(usr, span_notice("You slot the pen into \the [src]."))
					update_icon()
			return TRUE
	var/obj/item/O = locate(params["ref"])
	if(!O || O.loc != src)
		return TRUE
	switch(action)
		if("write")
			if(O == toppaper && istype(O, /obj/item/paper))
				var/obj/item/I = usr.get_active_hand()
				if(istype(I, /obj/item/pen))
					O.attackby(I, usr)
			return TRUE
		if("remove")
			if(istype(O, /obj/item/paper) || istype(O, /obj/item/photo))
				O.loc = usr.loc
				usr.put_in_hands(O)
				if(O == toppaper)
					toppaper = locate(/obj/item/paper) in src
				update_icon()
			return TRUE
		if("rename")
			if(istype(O, /obj/item/paper))
				var/obj/item/paper/p = O
				p.rename()
			else if(istype(O, /obj/item/photo))
				var/obj/item/photo/ph = O
				ph.rename()
			return TRUE
		if("open")
			switch(params["kind"])
				if("paper")
					var/obj/item/paper/p = O
					p.show_content(usr)
				if("photo")
					var/obj/item/photo/ph = O
					ph.show(usr)
			return TRUE

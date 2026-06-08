/obj/item/folder
	name = "folder"
	desc = "A folder."
	icon = 'icons/obj/bureaucracy.dmi' // Continues using new folder sprite, contrary to YW
	icon_state = "folder"
	w_class = ITEMSIZE_SMALL
	pressure_resistance = 2
	drop_sound = 'sound/items/drop/paper.ogg'
	pickup_sound = 'sound/items/pickup/paper.ogg'
	slot_flags = SLOT_BELT | SLOT_HOLSTER

/obj/item/folder/blue
	desc = "A blue folder."
	icon_state = "folder_blue"

/obj/item/folder/red
	desc = "A red folder."
	icon_state = "folder_red"

/obj/item/folder/yellow
	desc = "A yellow folder."
	icon_state = "folder_yellow"

/obj/item/folder/white
	desc = "A white folder."
	icon_state = "folder_white"

/obj/item/folder/blue_captain
	desc = "A blue folder with " + JOB_SITE_MANAGER + " markings."
	icon_state = "folder_captain"

/obj/item/folder/blue_hop
	desc = "A blue folder with HoP markings."
	icon_state = "folder_hop"

/obj/item/folder/white_cmo
	desc = "A white folder with CMO markings."
	icon_state = "folder_cmo"

/obj/item/folder/white_rd
	desc = "A white folder with RD markings."
	icon_state = "folder_rd"

/obj/item/folder/white_rd/Initialize(mapload)
	. = ..()
	//add some memos
	var/obj/item/paper/P = new()
	P.name = "Memo RE: proper analysis procedure"
	P.info = "<br>We keep test dummies in pens here for a reason"
	src.contents += P
	update_icon()

/obj/item/folder/yellow_ce
	desc = "A yellow folder with CE markings."
	icon_state = "folder_ce"

/obj/item/folder/red_hos
	desc = "A red folder with HoS markings."
	icon_state = "folder_hos"

/obj/item/folder/update_icon()
	cut_overlays()
	if(contents.len)
		add_overlay("folder_paper")
	return

/obj/item/folder/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/paper) || istype(W, /obj/item/photo) || istype(W, /obj/item/paper_bundle))
		user.drop_item()
		W.loc = src
		to_chat(user, span_notice("You put the [W] into \the [src]."))
		update_icon()
	else if(istype(W, /obj/item/pen))
		var/n_name = sanitizeSafe(tgui_input_text(user, "What would you like to label the folder?", "Folder Labelling", null, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(in_range(user, src) && user.stat == 0)
			name = "folder[(n_name ? text("- '[n_name]'") : null)]"
	return

/obj/item/folder/afterattack(turf/T as turf, mob/user as mob)
	for(var/obj/item/paper/P in T)
		P.loc = src
		update_icon()
		to_chat(user, span_notice("You tuck the [P] into \the [src]."))

// TGUI migration. attack_self opens Folder.tsx; the Topic
// remove/rename/read/look/browse actions move to tgui_act. Reading a
// paper/photo chains to that item's TGUI viewer (Paper.tsx / Photo.tsx).
/obj/item/folder/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	add_fingerprint(user)
	tgui_interact(user)

/obj/item/folder/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Folder", name)
		ui.open()

/obj/item/folder/tgui_data(mob/user)
	var/list/data = list()
	data["folder_name"] = name
	var/list/items = list()
	for(var/obj/item/paper/P in src)
		items += list(list("ref" = "\ref[P]", "name" = P.name, "kind" = "paper"))
	for(var/obj/item/photo/Ph in src)
		items += list(list("ref" = "\ref[Ph]", "name" = Ph.name, "kind" = "photo"))
	for(var/obj/item/paper_bundle/Pb in src)
		items += list(list("ref" = "\ref[Pb]", "name" = Pb.name, "kind" = "bundle"))
	data["items"] = items
	return data

/obj/item/folder/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(usr.stat || usr.restrained())
		return TRUE
	if(loc != usr)
		return TRUE
	var/obj/item/O = locate(params["ref"])
	if(!O || O.loc != src)
		return TRUE
	switch(action)
		if("remove")
			O.loc = usr.loc
			usr.put_in_hands(O)
			update_icon()
			return TRUE
		if("rename")
			if(istype(O, /obj/item/paper))
				var/obj/item/paper/p = O
				p.rename()
			else if(istype(O, /obj/item/photo))
				var/obj/item/photo/ph = O
				ph.rename()
			else if(istype(O, /obj/item/paper_bundle))
				var/obj/item/paper_bundle/pb = O
				pb.rename()
			return TRUE
		if("open")
			switch(params["kind"])
				if("paper")
					var/obj/item/paper/p = O
					p.show_content(usr)
				if("photo")
					var/obj/item/photo/ph = O
					ph.show(usr)
				if("bundle")
					var/obj/item/paper_bundle/pb = O
					pb.attack_self(usr)
			return TRUE

//########################################################################################################################
//###################################### NEWSPAPER! ######################################################################
//########################################################################################################################

/obj/item/newspaper
	name = "newspaper"
	desc = "An issue of The Griffon, the newspaper circulating aboard most stations."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "newspaper"
	w_class = ITEMSIZE_SMALL	//Let's make it fit in trashbags!
	attack_verb = list("bapped")
	var/screen = 0
	var/pages = 0
	var/curr_page = 0
	var/list/datum/feed_channel/news_content = list()
	var/datum/feed_message/important_message = null
	var/scribble=""
	var/scribble_page = null
	drop_sound = 'sound/items/drop/wrapper.ogg'
	pickup_sound = 'sound/items/pickup/wrapper.ogg'
	resistance_flags = FLAMMABLE

// DQEdit Start — TGUI migration. The 3-screen browse() pager becomes a
// single TGUI window with all channels/messages shipped in one payload
// and curr_page driving the view. Photo embedding (browse_rsc) is not
// yet wired through TGUI assets, so message photos are omitted.
/obj/item/newspaper/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(!ishuman(user))
		to_chat(user, span_infoplain("The paper is full of intelligible symbols!"))
		return
	tgui_interact(user)

/obj/item/newspaper/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Newspaper", "The Griffon")
		ui.open()

/obj/item/newspaper/tgui_data(mob/user)
	var/list/data = list()
	data["company_name"] = using_map.company_name
	data["curr_page"] = curr_page
	data["scribble_page"] = isnum(scribble_page) ? scribble_page : -1
	data["scribble"] = scribble || ""
	var/list/chs = list()
	pages = 0
	for(var/datum/feed_channel/NP in news_content)
		pages++
		var/list/msgs = list()
		if(!NP.censored)
			for(var/datum/feed_message/M in NP.messages)
				msgs += list(list(
					"title" = M.title,
					"body" = M.body,
					"author" = M.author,
					"message_type" = M.message_type,
				))
		chs += list(list(
			"name" = NP.channel_name,
			"author" = NP.author,
			"censored" = !!NP.censored,
			"messages" = msgs,
		))
	data["channels"] = chs
	if(important_message)
		data["wanted"] = list(
			"author" = important_message.author,
			"body" = important_message.body,
		)
	else
		data["wanted"] = null
	return data

/obj/item/newspaper/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("next_page")
			if(curr_page == pages + 1)
				return TRUE
			if(curr_page == pages)
				screen = 2
			else if(curr_page == 0)
				screen = 1
			curr_page++
			playsound(src, "pageturn", 50, 1)
			return TRUE
		if("prev_page")
			if(curr_page == 0)
				return TRUE
			if(curr_page == 1)
				screen = 0
			else if(curr_page == pages + 1)
				screen = 1
			curr_page--
			playsound(src, "pageturn", 50, 1)
			return TRUE
// DQEdit End

/obj/item/newspaper/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/pen))
		if(scribble_page == curr_page)
			to_chat(user, span_blue("There's already a scribble in this page... You wouldn't want to make things too cluttered, would you?"))
		else
			var/s = tgui_input_text(user, "Write something", "Newspaper", "", MAX_MESSAGE_LEN)
			if(!s)
				return
			if(!in_range(src, user) && src.loc != user)
				return
			scribble_page = curr_page
			scribble = s
			attack_self(user)
		return

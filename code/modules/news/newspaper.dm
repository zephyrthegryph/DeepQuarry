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
	/// The news network's channels at print time (relation list: the network owns them, the paper only reads them).
	var/list/datum/feed_channel/news_content
	var/tmp/datum/feed_message/important_message
	var/scribble=""
	var/scribble_page = null
	drop_sound = SFX_ITEMS_DROP_WRAPPER
	pickup_sound = SFX_ITEMS_PICKUP_WRAPPER
	resistance_flags = FLAMMABLE

// TGUI migration. The 3-screen browse() pager becomes a
// single TGUI window with all channels/messages shipped in one payload
// and curr_page driving the view. Photo embedding (browse_rsc) is not
// yet wired through TGUI assets, so message photos are omitted.
DECLARE_INTERACTIONS(/obj/item/newspaper, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/newspaper/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user))
		to_chat(user, span_infoplain("The paper is full of intelligible symbols!"))
		return TRUE
	tgui_interact(user)
	return TRUE

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
	if(important_message())
		data["wanted"] = list(
			"author" = important_message().author,
			"body" = important_message().body,
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
			play_sfx(src, SFX_PAGETURN)
			return TRUE
		if("prev_page")
			if(curr_page == 0)
				return TRUE
			if(curr_page == 1)
				screen = 0
			else if(curr_page == pages + 1)
				screen = 1
			curr_page--
			play_sfx(src, SFX_PAGETURN)
			return TRUE

/// Old attackby.
/obj/item/newspaper/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/pen))
		if(scribble_page == curr_page)
			to_chat(user, span_blue("There's already a scribble in this page... You wouldn't want to make things too cluttered, would you?"))
		else
			var/s = rerun_ask(user, "k108", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Write something", title = "Newspaper")
			if(isnull(s))
				return TRUE
			if(!s)
				return INTERACTION_HANDLED_PASS
			if(!in_range(src, user) && src.loc != user)
				return INTERACTION_HANDLED_PASS
			scribble_page = curr_page
			scribble = s
			attack_self(user)
		return INTERACTION_HANDLED_PASS
	return INTERACTION_HANDLED_PASS

/// The important_message this refers to (a relation view: null once that is deleted).
/obj/item/newspaper/proc/important_message() as /datum/feed_message
	return important_message

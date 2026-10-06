// Holowarrant viewer — structured TGUI panel for arrest/search warrants.

CAPABILITIES(/obj/item/holowarrant)
	interface("Holowarrant", title = "Holographic Warrant", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	ui_shape(loaded = bool(), kind = schema_text(), name = schema_text(), charges = schema_text(), auth = schema_text(), jurisdiction = schema_text(), station = schema_text())
	ref_one(nameof(active), /datum/data/record/warrant)
	// hit yourself with it: pick a warrant to load (the loaded one is dropped first)
	op("load", in_hand(),
		asks(/datum/prompt/choice, fields = list("title" = "Warrant Selection", "question" = "Which warrant would you like to load?", "choices" = computed(PROC_REF(warrant_names)), "timeout" = 0), when = PROC_REF(warrants_exist)),
		then(PROC_REF(warrant_chosen)))
	// an ID with the Head of Security's access authorizes the loaded warrant, after a yes
	op("authorize", item(/obj/item), when(nameof(active)),
		asks(/datum/prompt/yes_no, fields = list("title" = "Warrant authorization", "question" = "Would you like to authorize this warrant?", "timeout" = 0), when = PROC_REF(authorizing_card)),
		then(PROC_REF(authorize_answered)))

/// /obj/item/holowarrant's window data.
/obj/item/holowarrant/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!active())
		data["loaded"] = FALSE
		return data
	data["loaded"] = TRUE
	data["kind"] = "[active().fields["arrestsearch"]]"
	data["name"] = "[active().fields["namewarrant"]]"
	data["charges"] = "[active().fields["charges"]]"
	data["auth"] = "[active().fields["auth"]]"
	data["jurisdiction"] = "[using_map.boss_name]"
	data["station"] = "[using_map.station_name]"
	return data

/obj/item/holowarrant/proc/show_content(mob/user)
	if(!active())
		return
	tgui_interact(user)

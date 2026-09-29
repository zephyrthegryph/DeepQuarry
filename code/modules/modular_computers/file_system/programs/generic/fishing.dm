/datum/computer_file/program/fishing
	filename = "fishingminigame"
	filedesc = "Fishy Fishy 905"
	program_icon_state = "arcade"
	extended_desc = "A little fishing minigame for when you're really bored."
	size = 3
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	tgui_id = "NtosFishing"
	usage_flags = PROGRAM_ALL

/datum/computer_file/program/fishing/tgui_data(mob/user)
	return get_header_data()

/datum/computer_file/program/fishing/tgui_act(action, list/params)
	. = ..()
	if(.)
		return

	switch(action)
		if("lose")
			play_sfx(computer(), SFX_ARCADE_LOSE)
			. = TRUE
		if("win")
			play_sfx(computer(), SFX_ARCADE_WIN)
			. = TRUE

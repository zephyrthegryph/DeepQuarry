// Eye Buddy / Bodycam — structured TGUI panel.

// ---- TV camera ------------------------------------------------------------

/obj/item/tvcamera/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/item/tvcamera/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "EyeBuddy", "Eye Buddy")
		ui.open()

/obj/item/tvcamera/tgui_data(mob/user)
	var/list/data = list()
	data["channel"] = channel ? channel : "unidentified broadcast"
	data["video_on"] = !!camera.status
	data["audio_on"] = !!radio.broadcasting
	data["showing_name"] = (camera.status && showing_name) ? showing_name : null
	data["frequency"] = "[format_frequency(radio.frequency)] ([get_frequency_name(radio.frequency)])"
	return data

/obj/item/tvcamera/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("set_channel")
			Topic("channel=1", list("channel" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_video")
			Topic("video=1", list("video" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_audio")
			Topic("sound=1", list("sound" = "1"))
			SStgui.update_uis(src)
			return TRUE

/obj/item/tvcamera/proc/show_ui(mob/user)
	tgui_interact(user)

// ---- Bodycam --------------------------------------------------------------

/obj/item/clothing/accessory/bodycam/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/item/clothing/accessory/bodycam/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "EyeBuddy", "Eye Buddy")
		ui.open()

/obj/item/clothing/accessory/bodycam/tgui_data(mob/user)
	var/list/data = list()
	data["channel"] = channel ? channel : "unidentified broadcast"
	data["video_on"] = !!bcamera.status
	data["audio_on"] = !!bradio.broadcasting
	data["showing_name"] = (bcamera.status && showing_name) ? showing_name : null
	data["frequency"] = "[format_frequency(bradio.frequency)] ([get_frequency_name(bradio.frequency)])"
	return data

/obj/item/clothing/accessory/bodycam/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("set_channel")
			Topic("channel=1", list("channel" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_video")
			Topic("video=1", list("video" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_audio")
			Topic("sound=1", list("sound" = "1"))
			SStgui.update_uis(src)
			return TRUE

/obj/item/clothing/accessory/bodycam/proc/show_bodycam_ui(mob/user)
	tgui_interact(user)

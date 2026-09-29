// Eye Buddy / Bodycam — structured TGUI panel.

// ---- TV camera ------------------------------------------------------------

/obj/item/tvcamera/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/item/tvcamera, "EyeBuddy", UI_TITLE("Eye Buddy"))

/obj/item/tvcamera/tgui_data(mob/user)
	var/list/data = list()
	data["channel"] = channel ? channel : "unidentified broadcast"
	data["video_on"] = !!camera.status
	data["audio_on"] = !!radio.broadcasting
	data["showing_name"] = (camera.status && showing_name) ? showing_name : null
	data["frequency"] = "[format_frequency(radio.frequency)] ([get_frequency_name(radio.frequency)])"
	return data

UI_ACT(/obj/item/tvcamera, "set_channel", ui_act_set_channel)
UI_ACT_PROC(/obj/item/tvcamera, ui_act_set_channel)
	camera_set_channel(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/tvcamera, "toggle_video", ui_act_toggle_video)
UI_ACT_PROC(/obj/item/tvcamera, ui_act_toggle_video)
	camera_toggle_video(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/tvcamera, "toggle_audio", ui_act_toggle_audio)
UI_ACT_PROC(/obj/item/tvcamera, ui_act_toggle_audio)
	camera_toggle_audio(ui.user)
	SStgui.update_uis(src)
	return TRUE

/obj/item/tvcamera/proc/show_ui(mob/user)
	tgui_interact(user)

// ---- Bodycam --------------------------------------------------------------

/obj/item/clothing/accessory/bodycam/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/item/clothing/accessory/bodycam, "EyeBuddy", UI_TITLE("Eye Buddy"))

/obj/item/clothing/accessory/bodycam/tgui_data(mob/user)
	var/list/data = list()
	data["channel"] = channel ? channel : "unidentified broadcast"
	data["video_on"] = !!bcamera.status
	data["audio_on"] = !!bradio.broadcasting
	data["showing_name"] = (bcamera.status && showing_name) ? showing_name : null
	data["frequency"] = "[format_frequency(bradio.frequency)] ([get_frequency_name(bradio.frequency)])"
	return data

UI_ACT(/obj/item/clothing/accessory/bodycam, "set_channel", ui_act_set_channel)
UI_ACT_PROC(/obj/item/clothing/accessory/bodycam, ui_act_set_channel)
	camera_set_channel(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/clothing/accessory/bodycam, "toggle_video", ui_act_toggle_video)
UI_ACT_PROC(/obj/item/clothing/accessory/bodycam, ui_act_toggle_video)
	camera_toggle_video(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/clothing/accessory/bodycam, "toggle_audio", ui_act_toggle_audio)
UI_ACT_PROC(/obj/item/clothing/accessory/bodycam, ui_act_toggle_audio)
	camera_toggle_audio(ui.user)
	SStgui.update_uis(src)
	return TRUE

/obj/item/clothing/accessory/bodycam/proc/show_bodycam_ui(mob/user)
	tgui_interact(user)

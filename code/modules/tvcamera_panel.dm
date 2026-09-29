// Eye Buddy / Bodycam — structured TGUI panel.

// ---- TV camera ------------------------------------------------------------

DECLARE_UI_STATE(/obj/item/tvcamera, GLOB.tgui_default_state)

DECLARE_UI(/obj/item/tvcamera, "EyeBuddy", UI_TITLE("Eye Buddy"))

UI_DATA_REPLACE(/obj/item/tvcamera, "merge:ui_data_obj_item_tvcamera{channel:unknown,video_on:bool,audio_on:bool,showing_name:unknown,frequency:text}")

/// The computed part of /obj/item/tvcamera's window data (declared on its UI_DATA row).
/obj/item/tvcamera/proc/ui_data_obj_item_tvcamera(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

DECLARE_UI_STATE(/obj/item/clothing/accessory/bodycam, GLOB.tgui_default_state)

DECLARE_UI(/obj/item/clothing/accessory/bodycam, "EyeBuddy", UI_TITLE("Eye Buddy"))

UI_DATA_REPLACE(/obj/item/clothing/accessory/bodycam, "merge:ui_data_obj_item_clothing_accessory_bodycam{channel:unknown,video_on:bool,audio_on:bool,showing_name:unknown,frequency:text}")

/// The computed part of /obj/item/clothing/accessory/bodycam's window data (declared on its UI_DATA row).
/obj/item/clothing/accessory/bodycam/proc/ui_data_obj_item_clothing_accessory_bodycam(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

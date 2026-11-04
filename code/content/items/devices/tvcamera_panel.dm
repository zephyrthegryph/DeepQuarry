// Eye Buddy / Bodycam — structured TGUI panel.

// ---- TV camera ------------------------------------------------------------

/// /obj/item/tvcamera's window data.
/obj/item/tvcamera/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["channel"] = channel ? channel : "unidentified broadcast"
	data["video_on"] = !!camera.status
	data["audio_on"] = !!radio.broadcasting
	data["showing_name"] = (camera.status && showing_name) ? showing_name : null
	data["frequency"] = "[format_frequency(radio.frequency)] ([get_frequency_name(radio.frequency)])"
	return data

/obj/item/tvcamera/proc/ui_act_set_channel(datum/act/op/A)
	var/mob/user = A.actor
	camera_set_channel(user)
	SStgui.update_uis(src)
	return TRUE

/obj/item/tvcamera/proc/ui_act_toggle_video(datum/act/op/A)
	var/mob/user = A.actor
	camera_toggle_video(user)
	SStgui.update_uis(src)
	return OP_OK

/obj/item/tvcamera/proc/ui_act_toggle_audio(datum/act/op/A)
	var/mob/user = A.actor
	camera_toggle_audio(user)
	SStgui.update_uis(src)
	return OP_OK

/obj/item/tvcamera/proc/show_ui(mob/user)
	tgui_interact(user)

// ---- Bodycam --------------------------------------------------------------

/// /obj/item/clothing/accessory/bodycam's window data.
/obj/item/clothing/accessory/bodycam/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["channel"] = channel ? channel : "unidentified broadcast"
	data["video_on"] = !!bcamera.status
	data["audio_on"] = !!bradio.broadcasting
	data["showing_name"] = (bcamera.status && showing_name) ? showing_name : null
	data["frequency"] = "[format_frequency(bradio.frequency)] ([get_frequency_name(bradio.frequency)])"
	return data

/obj/item/clothing/accessory/bodycam/proc/ui_act_set_channel(datum/act/op/A)
	var/mob/user = A.actor
	camera_set_channel(user)
	SStgui.update_uis(src)
	return TRUE

/obj/item/clothing/accessory/bodycam/proc/ui_act_toggle_video(datum/act/op/A)
	var/mob/user = A.actor
	camera_toggle_video(user)
	SStgui.update_uis(src)
	return OP_OK

/obj/item/clothing/accessory/bodycam/proc/ui_act_toggle_audio(datum/act/op/A)
	var/mob/user = A.actor
	camera_toggle_audio(user)
	SStgui.update_uis(src)
	return OP_OK

/obj/item/clothing/accessory/bodycam/proc/show_bodycam_ui(mob/user)
	tgui_interact(user)

/world/presentation_flush()
	return ui_push_flush()

/datum/presentation_refresh_windows()
	return ui_push_mark(src)

/datum/presentation_modal_data()
	return tgui_modal_data(src)

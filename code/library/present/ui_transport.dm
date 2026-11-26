/world/presentation_flush()
	return ui_push_flush()

/datum/presentation_refresh_windows()
	return ui_push_mark(src)

/datum/presentation_refresh_static()
	for(var/datum/tgui/window as anything in open_tguis)
		log_tgui(window.user, "static data changed: full update", src_object = src)
		window.send_full_update()

/datum/presentation_modal_data()
	return tgui_modal_data(src)

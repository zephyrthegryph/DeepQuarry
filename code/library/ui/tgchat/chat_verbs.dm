/client/verb/export_chat()
	set hidden = TRUE // the Menu page
	set name = "Export Chatlog"
	set desc = "Allows to trigger the chat export"

	tgui_panel.window.send_message("saveToDiskCommand")
